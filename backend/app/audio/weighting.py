"""Честотни (A, C, Z) и времеви (F, S, I) филтри според IEC 61672-1:2013 и ANSI S1.4.

Честотните филтри се получават от аналоговите прототипи в стандарта (IEC 61672-1,
приложение E) чрез билинейна трансформация. Усилването е нормирано на 0 dB при 1 kHz.
"""

import numpy as np
from scipy import signal

# Полюсни честоти от IEC 61672-1, приложение E (Hz).
F1 = 20.598997
F2 = 107.65265
F3 = 737.86223
F4 = 12194.217

# Времеви константи (s).
TAU_FAST = 0.125
TAU_SLOW = 1.0
TAU_IMPULSE_RISE = 0.035
TAU_IMPULSE_DECAY = 1.5  # ANSI S1.4: детектор на пик с експоненциален спад


def _analog_zpk(weighting: str):
    w1, w2, w3, w4 = (2 * np.pi * f for f in (F1, F2, F3, F4))
    if weighting == "A":
        return [0.0] * 4, [-w1, -w1, -w2, -w3, -w4, -w4]
    if weighting == "C":
        return [0.0] * 2, [-w1, -w1, -w4, -w4]
    raise ValueError(f"Непознат честотен филтър: {weighting}")


def design_weighting(weighting: str, fs: float) -> np.ndarray | None:
    """Връща SOS коефициенти на цифровия филтър или None за Z (без тегловност)."""
    if weighting == "Z":
        return None
    z, p = _analog_zpk(weighting)
    # Нормиране на аналоговия прототип към 0 dB при 1 kHz.
    _, h = signal.freqs_zpk(z, p, 1.0, worN=[2 * np.pi * 1000.0])
    k = 1.0 / abs(h[0])
    zd, pd, kd = signal.bilinear_zpk(z, p, k, fs)
    sos = signal.zpk2sos(zd, pd, kd)
    # Билинейната трансформация леко променя усилването при 1 kHz - коригираме го.
    _, hd = signal.sosfreqz(sos, worN=[1000.0], fs=fs)
    sos[0, :3] /= abs(hd[0])
    return sos


def analog_response_db(weighting: str, freqs: np.ndarray) -> np.ndarray:
    """Теоретична характеристика на филтъра в dB (за проверка и за графики)."""
    freqs = np.asarray(freqs, dtype=float)
    if weighting == "Z":
        return np.zeros_like(freqs)
    z, p = _analog_zpk(weighting)
    _, h = signal.freqs_zpk(z, p, 1.0, worN=2 * np.pi * np.append(freqs, 1000.0))
    db = 20 * np.log10(np.abs(h))
    return db[:-1] - db[-1]


def design_bandpass(f_min: float, f_max: float, fs: float) -> np.ndarray | None:
    """Ограничава сигнала до измервателния интервал (Бътъруърт 4-ти ред).

    Връща None, ако интервалът обхваща целия звуков диапазон, който може да се
    представи при тази честота на дискретизация.
    """
    nyquist_limit = 0.45 * fs
    highpass = f_min > 3.0
    lowpass = f_max < nyquist_limit
    if highpass and lowpass:
        return signal.butter(4, [f_min, f_max], btype="bandpass", fs=fs, output="sos")
    if highpass:
        return signal.butter(4, f_min, btype="highpass", fs=fs, output="sos")
    if lowpass:
        return signal.butter(4, f_max, btype="lowpass", fs=fs, output="sos")
    return None


class SosFilter:
    """SOS филтър, който пази състоянието си между последователни блокове."""

    def __init__(self, sos: np.ndarray | None):
        self.sos = sos
        self.zi = None if sos is None else np.zeros((sos.shape[0], 2))

    def __call__(self, x: np.ndarray) -> np.ndarray:
        if self.sos is None:
            return x
        y, self.zi = signal.sosfilt(self.sos, x, zi=self.zi)
        return y


class ExponentialAverager:
    """Експоненциално осредняване на квадрата на сигнала (времеви филтри F и S)."""

    def __init__(self, tau: float, fs: float):
        self.alpha = 1.0 - np.exp(-1.0 / (tau * fs))
        self.state: float | None = None

    def __call__(self, x2: np.ndarray) -> np.ndarray:
        if self.state is None:
            # Започваме от средната стойност на първия блок, за да няма
            # преходен процес от нула (иначе Lmin в началото е -inf).
            self.state = float(np.mean(x2))
        b, a = [self.alpha], [1.0, -(1.0 - self.alpha)]
        zi = [(1.0 - self.alpha) * self.state]
        y, _ = signal.lfilter(b, a, x2, zi=zi)
        self.state = float(y[-1])
        return y


class ImpulseAverager:
    """Времеви филтър I: нарастване с 35 ms и детектор на пик със спад 1.5 s (ANSI S1.4)."""

    def __init__(self, fs: float):
        self.rise = ExponentialAverager(TAU_IMPULSE_RISE, fs)
        self.decay = np.exp(-1.0 / (TAU_IMPULSE_DECAY * fs))
        self.peak: float | None = None

    def __call__(self, x2: np.ndarray) -> np.ndarray:
        y = self.rise(x2)
        if self.peak is None:
            self.peak = float(y[0])
        # z[n] = max(y[n], d*z[n-1]) във векторна форма:
        # z[n] = d^n * max(d*z[-1], max_{k<=n} y[k]*d^-k)
        k = np.arange(len(y))
        dk = self.decay ** k
        running = np.maximum.accumulate(y / dk)
        z = dk * np.maximum(running, self.decay * self.peak)
        self.peak = float(z[-1])
        return z


def make_time_weighting(tw: str, fs: float):
    if tw == "F":
        return ExponentialAverager(TAU_FAST, fs)
    if tw == "S":
        return ExponentialAverager(TAU_SLOW, fs)
    if tw == "I":
        return ImpulseAverager(fs)
    raise ValueError(f"Непознат времеви филтър: {tw}")
