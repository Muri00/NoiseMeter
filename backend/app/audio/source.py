"""Източници на аудио: USB микрофон (sounddevice) или симулатор за разработка без микрофон."""

import asyncio
import time
from collections.abc import AsyncIterator

import numpy as np
from scipy import signal

from app.config import settings


class AudioSourceError(RuntimeError):
    pass


# Има един физически микрофон, затова измерване и калибровка не могат да вървят едновременно.
microphone_lock = asyncio.Lock()


async def microphone_blocks(fs: int, block_size: int) -> AsyncIterator[np.ndarray]:
    """Чете блокове от входното устройство. Записът се спира при изход от генератора."""
    import sounddevice as sd  # импорт тук, за да работят тестовете и без PortAudio

    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[np.ndarray] = asyncio.Queue(maxsize=50)

    def callback(indata, frames, time_info, status):
        block = indata[:, 0].copy()
        loop.call_soon_threadsafe(_put_nowait, queue, block)

    device = settings.audio_device or None
    if device is not None and device.isdigit():
        device = int(device)
    try:
        stream = sd.InputStream(
            samplerate=fs, blocksize=block_size, channels=1, dtype="float32",
            device=device, callback=callback,
        )
        stream.start()
    except Exception as e:
        raise AudioSourceError(f"Микрофонът не може да бъде отворен: {e}") from e

    try:
        while True:
            yield await queue.get()
    finally:
        stream.stop()
        stream.close()


def _put_nowait(queue: asyncio.Queue, block: np.ndarray) -> None:
    # Ако клиентът не смогва, изпускаме най-стария блок, вместо да блокираме аудио нишката.
    if queue.full():
        queue.get_nowait()
    queue.put_nowait(block)


async def simulated_blocks(fs: int, block_size: int) -> AsyncIterator[np.ndarray]:
    """Розов шум (~60 dB SPL при UMIK-1) + тон 1 kHz, който се включва и изключва на всеки 3 s."""
    rng = np.random.default_rng()
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    zi = np.zeros(3)
    n = 0
    start = time.monotonic()
    calibrator = settings.simulator_signal == "calibrator"
    while True:
        noise, zi = signal.lfilter(b, a, rng.standard_normal(block_size), zi=zi)
        t = (n + np.arange(block_size)) / fs
        if calibrator:
            # 94 dB SPL при -18 dBFS, малко над номинала - като реален микрофон.
            block = np.sqrt(2) * 10 ** (-17.6 / 20) * np.sin(2 * np.pi * 1000 * t) + 1e-4 * noise
        else:
            tone_on = (t // 3) % 2 == 1
            block = 0.01 * noise + 0.02 * np.sin(2 * np.pi * 1000 * t) * tone_on
        n += block_size
        # Подаваме блоковете в реално време.
        delay = start + n / fs - time.monotonic()
        if delay > 0:
            await asyncio.sleep(delay)
        yield block.astype(np.float32)


def audio_blocks(fs: int, block_size: int) -> AsyncIterator[np.ndarray]:
    if settings.audio_source == "simulator":
        return simulated_blocks(fs, block_size)
    return microphone_blocks(fs, block_size)
