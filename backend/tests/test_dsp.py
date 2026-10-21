import numpy as np
import pytest

from app.audio import indicators, octave
from app.audio.meter import LevelMeter, MeterConfig
from app.audio.weighting import analog_response_db, design_weighting
from scipy import signal

FS = 48000

# Таблица 3 от IEC 61672-1:2013 - номинални стойности (dB) и допуски за клас 1.
IEC_TABLE = [
    # f, A, C, допуск +, допуск -
    (31.5, -39.4, -3.0, 1.5, 1.5),
    (63, -26.2, -0.8, 1.0, 1.0),
    (125, -16.1, -0.2, 1.0, 1.0),
    (250, -8.6, 0.0, 1.0, 1.0),
    (500, -3.2, 0.0, 1.0, 1.0),
    (1000, 0.0, 0.0, 0.7, 0.7),
    (2000, 1.2, -0.2, 1.0, 1.0),
    (4000, 1.0, -0.8, 1.0, 1.0),
    (8000, -1.1, -3.0, 1.5, 2.5),
    (12500, -4.3, -6.2, 2.0, 5.0),
    (16000, -6.6, -8.5, 2.5, 16.0),
]


@pytest.mark.parametrize("weighting,col", [("A", 1), ("C", 2)])
def test_analog_weighting_matches_iec_table(weighting, col):
    # Стойностите в таблицата са изчислени за точните честоти с база 10 (31.5 -> 31.62 Hz).
    nominal = np.array([row[0] for row in IEC_TABLE])
    freqs = 1000 * octave.G ** (np.round(3 * np.log(nominal / 1000) / np.log(octave.G)) / 3)
    expected = np.array([row[col] for row in IEC_TABLE])
    assert np.allclose(analog_response_db(weighting, freqs), expected, atol=0.1)


@pytest.mark.parametrize("weighting,col", [("A", 1), ("C", 2)])
def test_digital_weighting_within_class1_tolerance(weighting, col):
    sos = design_weighting(weighting, FS)
    for f, *vals, tol_plus, tol_minus in IEC_TABLE:
        _, h = signal.sosfreqz(sos, worN=[f], fs=FS)
        db = 20 * np.log10(abs(h[0]))
        nominal = vals[col - 1]
        assert nominal - tol_minus <= db <= nominal + tol_plus, (weighting, f, db)


def _sine(freq, amplitude, seconds):
    t = np.arange(int(FS * seconds)) / FS
    return amplitude * np.sin(2 * np.pi * freq * t)


def _run(meter, x, block=4800):
    frame = None
    for i in range(0, len(x), block):
        frame = meter.process(x[i:i + block])
    return frame


def test_calibrated_1khz_tone_reads_94_db():
    # Микрофон с чувствителност -18 dBFS: тон 94 dB SPL има RMS 10^(-18/20).
    sens = -18.0
    amp = np.sqrt(2) * 10 ** (sens / 20)
    meter = LevelMeter(MeterConfig(FS, 94 - sens, 20, 20000, "1/3"))
    levels = _run(meter, _sine(1000, amp, 3))["levels"]
    for code in ("LAF", "LAS", "LAeq", "LCF", "LZF", "LZeq"):
        assert levels[code] == pytest.approx(94.0, abs=0.1), code


def test_a_weighting_attenuates_100hz():
    meter = LevelMeter(MeterConfig(FS, 94, 20, 20000, "off"))
    levels = _run(meter, _sine(100, np.sqrt(2), 3))["levels"]
    assert levels["LZeq"] == pytest.approx(94.0, abs=0.2)
    assert levels["LAeq"] == pytest.approx(94.0 - 19.1, abs=0.3)


def test_fast_responds_faster_than_slow_and_max_min():
    meter = LevelMeter(MeterConfig(FS, 94, 20, 20000, "off"))
    x = np.concatenate([_sine(1000, np.sqrt(2) * 0.01, 2), _sine(1000, np.sqrt(2), 0.5)])
    levels = _run(meter, x)["levels"]
    # След 0.5 s на +40 dB: F е почти установен, S все още изостава.
    assert levels["LAF"] > 93.5
    assert levels["LAS"] < levels["LAF"] - 1
    assert levels["LAFmax"] == pytest.approx(94.0, abs=0.2)
    assert levels["LAFmin"] == pytest.approx(54.0, abs=0.5)


def test_impulse_holds_peak():
    meter = LevelMeter(MeterConfig(FS, 94, 20, 20000, "off"))
    x = np.concatenate([_sine(1000, np.sqrt(2), 0.5), np.zeros(int(FS * 0.5))])
    levels = _run(meter, x)["levels"]
    # 0.5 s след изключване: спад ~2.9 dB при I, много по-голям при F.
    assert levels["LAI"] == pytest.approx(94 - 10 * np.log10(np.e) * 0.5 / 1.5, abs=0.3)
    assert levels["LAF"] < 80


def test_third_octave_band_of_tone():
    meter = LevelMeter(MeterConfig(FS, 94, 20, 20000, "1/3"))
    bands = _run(meter, _sine(1000, np.sqrt(2), 2))["bands"]
    i = bands["centers"].index(1000)
    assert bands["levels"][i] == pytest.approx(94.0, abs=0.5)
    assert bands["levels"][i - 2] < 60 and bands["levels"][i + 2] < 60
    assert bands["centers"][0] == 20 and bands["centers"][-1] == 20000


def test_octave_band_centers():
    centers = [octave.nominal(c) for c in octave.band_centers(1, 20, 20000)]
    assert centers == [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]


def test_indicator_codes():
    assert indicators.is_valid("LAF")
    assert indicators.is_valid("LZSmax")
    assert indicators.is_valid("LCeq")
    assert not indicators.is_valid("LAeqmax")
    assert not indicators.is_valid("LBF")
    assert indicators.display_name("LZSmax") == "LZ,S,max"
    assert all(indicators.is_valid(c) for c in indicators.all_indicators())
