"""PDF сертификат (протокол) от измерване на шум (изискване 8).

Структурата следва протоколите на акредитираните органи за контрол: данни за
организацията, нормативни актове, таблица с резултатите по точки и периоди
(измерена стойност и норма), заключение, забележки, технически средства и
подписи. Стойностите над нормата се отбелязват с удебелен шрифт.
"""

import io
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.reports.norms import PERIOD_NAMES, PERIODS

_FONTS = Path(__file__).parent / "fonts"
pdfmetrics.registerFont(TTFont("DejaVu", str(_FONTS / "DejaVuSans.ttf")))
pdfmetrics.registerFont(TTFont("DejaVu-Bold", str(_FONTS / "DejaVuSans-Bold.ttf")))

_BASE = ParagraphStyle("base", fontName="DejaVu", fontSize=9, leading=12)
_SMALL = ParagraphStyle("small", parent=_BASE, fontSize=7.5, leading=9.5)
_CELL = ParagraphStyle("cell", parent=_BASE, fontSize=8.5, leading=10.5)
_CELL_C = ParagraphStyle("cellc", parent=_CELL, alignment=TA_CENTER)
_HEAD_C = ParagraphStyle("headc", parent=_CELL_C, fontSize=7.5, leading=9)
_ORG = ParagraphStyle("org", parent=_BASE, fontName="DejaVu-Bold", fontSize=13, leading=16, alignment=TA_CENTER)
_CENTER_SMALL = ParagraphStyle("cs", parent=_SMALL, alignment=TA_CENTER)
_TITLE = ParagraphStyle("title", parent=_BASE, fontName="DejaVu-Bold", fontSize=12, leading=15, alignment=TA_CENTER)
_SECTION = ParagraphStyle("section", parent=_BASE, fontName="DejaVu-Bold", fontSize=10, leading=13, spaceBefore=8, spaceAfter=3)


def _esc(text: str) -> str:
    return (text or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\n", "<br/>")


def _num(v) -> str:
    return "–" if v is None else f"{v:.2f}".replace(".", ",")


def _norm(v) -> str:
    return "–" if v is None else f"{v:g}"


_DISCLAIMER = ("Резултатите се отнасят само за измерените обекти, на мястото и по времето на измерването.",
               "Сертификатът не може да се възпроизвежда частично без съгласието на издателя.")


class _NumberedCanvas(canvas.Canvas):
    """Добавя "Страница N от M" - общият брой страници е известен чак накрая."""

    def __init__(self, *args, footer_left: str = "", **kwargs):
        super().__init__(*args, **kwargs)
        self._pages = []
        self._footer_left = footer_left

    def showPage(self):
        self._pages.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        total = len(self._pages)
        for state in self._pages:
            self.__dict__.update(state)
            self.setFont("DejaVu", 7.5)
            self.setStrokeColor(colors.grey)
            self.setFont("DejaVu", 6.5)
            self.drawCentredString(A4[0] / 2, 19 * mm, _DISCLAIMER[0])
            self.drawCentredString(A4[0] / 2, 16 * mm, _DISCLAIMER[1])
            self.setFont("DejaVu", 7.5)
            self.line(15 * mm, 14 * mm, A4[0] - 15 * mm, 14 * mm)
            self.drawString(15 * mm, 10 * mm, self._footer_left)
            self.drawRightString(A4[0] - 15 * mm, 10 * mm, f"Страница {self._pageNumber} от {total}")
            super().showPage()
        super().save()


def _results_table(rows: list[dict]) -> Table:
    header1 = [Paragraph("№ по ред", _CELL_C), Paragraph("Източник / режим / място на измерване (точка №)", _CELL_C),
               Paragraph("ЕКВИВАЛЕНТНО НИВО НА ШУМ, dB(A)", _CELL_C), "", "", "", "", ""]
    header2 = ["", ""] + sum(([Paragraph(PERIOD_NAMES[p], _CELL_C), ""] for p in PERIODS), [])
    header3 = ["", ""] + [Paragraph(t, _HEAD_C) for _ in PERIODS for t in ("Измерена стойност", "Норма")]
    data = [header1, header2, header3]
    style = [
        ("FONTNAME", (0, 0), (-1, -1), "DejaVu"),
        ("FONTSIZE", (0, 0), (-1, -1), 8.5),
        ("GRID", (0, 0), (-1, -1), 0.6, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ALIGN", (2, 3), (-1, -1), "CENTER"),
        ("ALIGN", (0, 3), (0, -1), "CENTER"),
        ("SPAN", (0, 0), (0, 2)), ("SPAN", (1, 0), (1, 2)), ("SPAN", (2, 0), (7, 0)),
        ("SPAN", (2, 1), (3, 1)), ("SPAN", (4, 1), (5, 1)), ("SPAN", (6, 1), (7, 1)),
        ("BACKGROUND", (0, 0), (-1, 2), colors.Color(0.93, 0.93, 0.93)),
    ]
    for i, row in enumerate(rows):
        r = len(data)
        cells = [str(row["no"]), Paragraph(
            f"<b>{_esc(row['point'])}</b>"
            + (f"<br/>{_esc(row['source'])}" if row.get("source") else "")
            + f"<br/><font size=7>{_esc(row['time'])}</font>", _CELL)]
        for c, p in enumerate(PERIODS):
            v = row["values"].get(p) or {}
            cells += [_num(v.get("value")), _norm(v.get("norm"))]
            if v.get("ok") is False:
                # Превишение на нормата - удебелено и в червено, както в образеца.
                col = 2 + 2 * c
                style += [("FONTNAME", (col, r), (col, r), "DejaVu-Bold"), ("TEXTCOLOR", (col, r), (col, r), colors.red)]
        style.append(("FONTNAME", (3, r), (3, r), "DejaVu-Bold"))
        style.append(("FONTNAME", (5, r), (5, r), "DejaVu-Bold"))
        style.append(("FONTNAME", (7, r), (7, r), "DejaVu-Bold"))
        data.append(cells)

    widths = [12 * mm, 51 * mm] + [25 * mm, 14 * mm] * 3
    table = Table(data, colWidths=widths, repeatRows=3)
    table.setStyle(TableStyle(style))
    return table


def conclusion(rows: list[dict]) -> str:
    exceeded = [
        f"{r['point']} ({PERIOD_NAMES[p].lower()}: {_num(v['value'])} dB(A) при норма {_norm(v['norm'])} dB(A))"
        for r in rows for p in PERIODS
        if (v := r["values"].get(p)) and v.get("ok") is False
    ]
    no_norm = any(v.get("norm") is None for r in rows for v in r["values"].values())
    if exceeded:
        return "Установено е превишение на граничните стойности в: " + "; ".join(exceeded) + "."
    if no_norm:
        return ("Няма установено превишение на зададените гранични стойности. "
                "За част от измерванията не е зададена норма.")
    return "Всички измерени стойности са в границите на нормите."


def render_pdf(data: dict) -> bytes:
    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm, topMargin=12 * mm, bottomMargin=25 * mm,
        title=f"Сертификат № {data['number']}", author=data["organization"].get("name") or "",
    )
    org = data["organization"]
    story = []

    # Заглавна част
    story.append(Paragraph(_esc(org.get("name") or "Орган за измерване на шум"), _ORG))
    if org.get("address"):
        story.append(Paragraph(_esc(org["address"]), _CENTER_SMALL))
    if org.get("accreditation"):
        story.append(Paragraph(_esc(org["accreditation"]), _CENTER_SMALL))
    story.append(Spacer(1, 2 * mm))
    story.append(Table([[""]], colWidths=[180 * mm], style=[("LINEABOVE", (0, 0), (-1, -1), 1.2, colors.black)]))
    story.append(Spacer(1, 3 * mm))
    story.append(Paragraph(f"СЕРТИФИКАТ ЗА ИЗМЕРВАНЕ НА ШУМ № {_esc(data['number'])}", _TITLE))
    story.append(Paragraph(f"от {_esc(data['issued_date'])}", ParagraphStyle("d", parent=_BASE, alignment=TA_CENTER)))
    if data.get("title"):
        story.append(Paragraph(_esc(data["title"]), ParagraphStyle("t2", parent=_BASE, alignment=TA_CENTER)))

    # 1. Нормативни актове
    story.append(Paragraph("1. Нормативни актове:", _SECTION))
    story.append(Paragraph("<b>Методи за измерване</b>", _BASE))
    for m in data["methods"]:
        story.append(Paragraph(f"&nbsp;&nbsp;&nbsp;– {_esc(m)}", _BASE))
    story.append(Paragraph("<b>Нормативни изисквания</b>", _BASE))
    for n in data["normative"]:
        story.append(Paragraph(f"&nbsp;&nbsp;&nbsp;– {_esc(n)}", _BASE))

    # 2. Резултати
    story.append(Paragraph("2. Резултати от измерването:", _SECTION))
    story.append(_results_table(data["rows"]))

    # 3-6
    story.append(Paragraph("3. Заключение:", _SECTION))
    story.append(Paragraph(_esc(data["conclusion"]), _BASE))
    story.append(Paragraph("4. Забележки:", _SECTION))
    story.append(Paragraph(_esc(data.get("remarks") or "Няма."), _BASE))
    story.append(Paragraph("5. Технически средства за измерване:", _SECTION))
    for e in data["equipment"]:
        story.append(Paragraph(f"&nbsp;&nbsp;&nbsp;– {_esc(e)}", _BASE))

    signatures = [Paragraph("6. Извършил(и) измерването:", _SECTION)]
    sig_rows = []
    for i, name in enumerate(data["performed_by"], 1):
        sig_rows.append([Paragraph(f"{i}. ........................................<br/><font size=7>({_esc(name)})</font>", _BASE),
                         Paragraph("Подпис: ...................................", _BASE)])
    signatures.append(Table(sig_rows, colWidths=[90 * mm, 90 * mm], style=[("TOPPADDING", (0, 0), (-1, -1), 10)]))
    story.append(KeepTogether(signatures))

    footer = f"Сертификат № {data['number']} / {data['issued_date']}"
    doc.build(story, canvasmaker=lambda *a, **k: _NumberedCanvas(*a, footer_left=footer, **k))
    return buf.getvalue()
