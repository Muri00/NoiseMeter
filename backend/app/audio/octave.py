"""Октавни (1/1) и терцоктавни (1/3) ленти с база 10 според IEC 61260-1."""

import numpy as np

G = 10 ** (3 / 10)  # октавно отношение (база 10)
F_REF = 1000.0


def band_centers(fraction: int, f_min: float, f_max: float) -> np.ndarray:
    """Точни средни честоти на лентите, чиито средни честоти са в [f_min, f_max].

    fraction: 1 за октави, 3 за терцоктави.
    Допускът от 3% е, за да влязат номиналните граници (напр. 20 Hz е точно 19.95 Hz).
    """
    xs = np.arange(-60, 61)
    centers = F_REF * G ** (xs / fraction)
    return centers[(centers >= f_min * 0.97) & (centers <= f_max * 1.03)]


def band_edges(centers: np.ndarray, fraction: int) -> tuple[np.ndarray, np.ndarray]:
    half = G ** (1 / (2 * fraction))
    return centers / half, centers * half


_NOMINAL_THIRD = [1.0, 1.25, 1.6, 2.0, 2.5, 3.15, 4.0, 5.0, 6.3, 8.0]


def nominal(center: float) -> float:
    """Номинална (закръглена) честота за етикет, напр. 1995.3 -> 2000."""
    exp = np.floor(np.log10(center))
    mant = center / 10**exp
    best = min(_NOMINAL_THIRD + [10.0], key=lambda n: abs(np.log(mant / n)))
    return float(round(best * 10**exp, 2))


class BandAnalyzer:
    """Изчислява нивата в лентите от последните `window` секунди сигнал чрез FFT.

    FFT прозорец от 1 s дава разделителна способност 1 Hz, което е достатъчно за
    терцоктавите от 25 Hz нагоре; под тази честота лентите са по-тесни от няколко
    отчета и стойностите са ориентировъчни.
    """

    def __init__(self, fraction: int, f_min: float, f_max: float, fs: float, window_s: float = 1.0):
        self.fs = fs
        self.n = int(round(window_s * fs))
        self.buffer = np.zeros(0)
        self.centers = band_centers(fraction, f_min, min(f_max, 0.5 * fs))
        lower, upper = band_edges(self.centers, fraction)
        freqs = np.fft.rfftfreq(self.n, d=1 / fs)
        # Матрица лента x честотен отчет: кои отчети попадат в коя лента.
        self.mask = (freqs[None, :] >= lower[:, None]) & (freqs[None, :] < upper[:, None])
        self.window = np.hanning(self.n)
        self.window_power = np.sum(self.window**2)

    def push(self, x: np.ndarray) -> None:
        self.buffer = np.concatenate([self.buffer, x])[-self.n:]

    def mean_squares(self) -> np.ndarray | None:
        """Средноквадратична стойност във всяка лента или None, ако още няма достатъчно данни."""
        if len(self.buffer) < self.n or len(self.centers) == 0:
            return None
        spec = np.abs(np.fft.rfft(self.buffer * self.window)) ** 2
        # Скалиране така, че сумата по всички отчети да е средният квадрат на сигнала.
        spec[1:-1] *= 2
        spec /= self.n * self.window_power
        return self.mask @ spec
