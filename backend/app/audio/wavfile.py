"""Записване на WAV файл блок по блок, с метаданни за входното устройство.

Форматът е 32-битов IEEE float, моно: стойностите от микрофона се записват без
загуба на точност (необработени данни, изискване 4). Данните за устройството се
записват в стандартния LIST/INFO блок на WAV файла (вижда се в Audacity, foobar2000,
Windows Explorer -> Properties -> Details и др.).
"""

import struct
from pathlib import Path

import numpy as np

_FORMAT_IEEE_FLOAT = 3


class WavWriter:
    def __init__(self, path: Path, sample_rate: int, info: dict[str, str]):
        self.path = path
        self.sample_rate = sample_rate
        self.data_bytes = 0
        self._file = open(path, "wb")
        self._write_header(info)

    def _write_header(self, info: dict[str, str]) -> None:
        f = self._file
        f.write(b"RIFF\x00\x00\x00\x00WAVE")
        # fmt блок: IEEE float, 1 канал, 32 бита.
        block_align = 4
        f.write(b"fmt " + struct.pack(
            "<IHHIIHH", 16, _FORMAT_IEEE_FLOAT, 1, self.sample_rate,
            self.sample_rate * block_align, block_align, 32,
        ))
        # LIST/INFO блок с метаданните.
        if info:
            body = b"INFO"
            for key, value in info.items():
                data = value.encode("utf-8") + b"\x00"
                if len(data) % 2:
                    data += b"\x00"
                body += key.encode("ascii") + struct.pack("<I", len(data)) + data
            f.write(b"LIST" + struct.pack("<I", len(body)) + body)
        f.write(b"data\x00\x00\x00\x00")
        self._data_size_pos = f.tell() - 4

    def write(self, block: np.ndarray) -> None:
        data = np.asarray(block, dtype="<f4").tobytes()
        self._file.write(data)
        self.data_bytes += len(data)

    def close(self) -> None:
        if self._file.closed:
            return
        f = self._file
        end = f.tell()
        f.seek(self._data_size_pos)
        f.write(struct.pack("<I", self.data_bytes))
        f.seek(4)
        f.write(struct.pack("<I", end - 8))
        f.close()
