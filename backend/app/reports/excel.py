"""Експорт в Excel (изискване 7).

Задължителни полета: време, № обект (микрофон), измерени стойности, референтни
стойности и дали измерването е в границите. Референтната стойност е нормата за
периода (ден/вечер/нощ) по Наредба № 6, зададена за мястото на измерването.
"""

import io

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

from app.audio import indicators as indicator_codes
from app.reports import norms

# Excel има ограничение от ~1 милион реда; оставяме резерв.
MAX_DATA_ROWS = 500_000

_HEADER_FONT = Font(bold=True, color="FFFFFF")
_HEADER_FILL = PatternFill("solid", fgColor="3F51B5")
_OK_FILL = PatternFill("solid", fgColor="C8E6C9")
_BAD_FILL = PatternFill("solid", fgColor="FFCDD2")
_DATE_FMT = "dd.mm.yyyy hh:mm:ss"


def device_label(info: dict) -> str:
    return f"{info['brand']} {info['model']}, S/N {info['serial_number']}"


def _local(ts):
    # Excel не поддържа часови зони - записваме местното време без зона.
    return norms.to_local(ts).replace(tzinfo=None)


def _yes_no(ok: bool | None) -> str:
    return "" if ok is None else ("Да" if ok else "Не")


def _header(ws, titles: list[str]) -> None:
    ws.append(titles)
    for cell in ws[ws.max_row]:
        cell.font = _HEADER_FONT
        cell.fill = _HEADER_FILL
        cell.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
    ws.freeze_panes = f"A{ws.max_row + 1}"  # ws.cell() би създал празен ред


def _fit_columns(ws, widths: dict[int, int] | None = None, default: int = 13) -> None:
    for i in range(1, ws.max_column + 1):
        ws.column_dimensions[get_column_letter(i)].width = (widths or {}).get(i, default)


def _mark(cell, ok: bool | None) -> None:
    if ok is not None:
        cell.fill = _OK_FILL if ok else _BAD_FILL


def build_workbook(items: list[tuple], indicators: list[str], title: str) -> bytes:
    """items: списък от (Measurement, frames), подредени по време."""
    wb = Workbook()

    # --- Лист 1: обобщение по измервания и периоди ---
    ws = wb.active
    ws.title = "Измервания"
    ws.append([title])
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    summary_codes = [c for c in indicators if c != "LAeq"]
    _header(ws, [
        "№ измерване", "Начало", "Край", "Точка / място", "Източник / режим", "№ обект (микрофон)",
        "Период", "Измерено LAeq, dB(A)", "Референтна стойност (норма), dB(A)", "В границите",
    ] + [f"{indicator_codes.display_name(c)}, dB" for c in summary_codes])

    for m, frames in items:
        per_period = norms.period_levels(frames, m.period)
        if not per_period:
            per_period = {"": {"laeq": m.summary.get("LAeq") if m.summary else None,
                               "start": m.started_at, "end": m.ended_at or m.started_at}}
        for period, p in per_period.items():
            norm = norms.norm_for(m, period) if period else None
            ok = norms.within_limit(p["laeq"], norm)
            ws.append([
                m.id, _local(p["start"]), _local(p["end"]), norms.place_label(m), m.source or "",
                device_label(m.device_info), norms.PERIOD_NAMES.get(period, ""),
                p["laeq"], norm, _yes_no(ok),
            ] + [(m.summary or {}).get(c) for c in summary_codes])
            row = ws[ws.max_row]
            row[1].number_format = row[2].number_format = _DATE_FMT
            # Измереното ниво и „В границите“: зелено - в норма, червено - превишение.
            _mark(row[7], ok)
            _mark(row[9], ok)
    _fit_columns(ws, {2: 19, 3: 19, 4: 22, 5: 20, 6: 30, 8: 14, 9: 16, 10: 11})

    # --- Лист 2: данни по секунди ---
    ws = wb.create_sheet("Данни по секунди")
    codes = ["LAeq"] + [c for c in indicators if c != "LAeq"]
    _header(ws, [
        "Време", "№ обект (микрофон)", "Точка / място", "№ измерване", "Период",
    ] + [
        f"{indicator_codes.display_name(c)}{',1s' if c.endswith('eq') else ''}, dB" for c in codes
    ] + ["Референтна стойност (норма), dB(A)", "В границите"])
    rows = 0
    for m, frames in items:
        label = device_label(m.device_info)
        for f in frames:
            if rows >= MAX_DATA_ROWS:
                break
            period = norms.frame_period(m, f.ts)
            norm = norms.norm_for(m, period)
            ok = norms.within_limit(f.leq_a, norm)
            ws.append([
                _local(f.ts), label, norms.place_label(m), m.id, norms.PERIOD_NAMES[period],
            ] + [f.levels.get(c) for c in codes] + [norm, _yes_no(ok)])
            row = ws[ws.max_row]
            row[0].number_format = _DATE_FMT
            _mark(row[5], ok)  # LA,eq за секундата
            _mark(row[-1], ok)
            rows += 1
    if rows >= MAX_DATA_ROWS:
        ws.append([f"Показани са първите {MAX_DATA_ROWS} секунди. Изберете по-кратък период за пълните данни."])
    _fit_columns(ws, {1: 19, 2: 30, 3: 20})

    # --- Лист 3: входни устройства и калибровка ---
    ws = wb.create_sheet("Устройства")
    _header(ws, [
        "№ измерване", "Марка", "Модел", "Сериен №", "Чувствителност, dBFS при 94 dB",
        "Работна лента, Hz", "Калибровъчна корекция, dB", "Дата на калибровка (UTC)",
        "Измервателен интервал, Hz", "Октавни ленти", "WAV запис",
    ])
    for m, _ in items:
        d = m.device_info
        ws.append([
            m.id, d["brand"], d["model"], d["serial_number"], d["sensitivity_dbfs"],
            f"{d['freq_min_hz']:g}-{d['freq_max_hz']:g}", d.get("calibration_offset_db"),
            (d.get("calibration_date") or "")[:19].replace("T", " "),
            f"{m.f_min_hz:g}-{m.f_max_hz:g}", m.band_mode, "Да" if m.wav_path else "Не",
        ])
    _fit_columns(ws, {4: 16, 5: 16, 8: 19, 9: 16})

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()
