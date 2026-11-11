"""Показатели на шумомера (изискване 3.9).

Кодът на показател следва означенията от IEC 61672-1 / ANSI S1.4, без запетаята:
    L  <честотен филтър A|C|Z>  <времеви филтър F|S|I | eq>  [max|min]
Примери: LAF, LAS, LAeq, LCF, LZSmax, LAFmin.
Еквивалентното ниво (eq) няма max/min вариант.
"""

import re

FREQUENCY_WEIGHTINGS = ("A", "C", "Z")
TIME_WEIGHTINGS = ("F", "S", "I")

_PATTERN = re.compile(r"^L([ACZ])(F|S|I|eq)(max|min)?$")

MIN_INDICATORS = 5
DEFAULT_INDICATORS = ["LAF", "LAS", "LAeq", "LCF", "LZSmax"]


# Ниво без честотен и без времеви филтър (средноквадратично за блок от 100 ms) и неговите max/min.
UNWEIGHTED = ["Lp", "Lpmax", "Lpmin"]


def all_indicators() -> list[str]:
    codes = list(UNWEIGHTED)
    for fw in FREQUENCY_WEIGHTINGS:
        for tw in TIME_WEIGHTINGS:
            codes += [f"L{fw}{tw}", f"L{fw}{tw}max", f"L{fw}{tw}min"]
        codes.append(f"L{fw}eq")
    return codes


def is_valid(code: str) -> bool:
    if code in UNWEIGHTED:
        return True
    m = _PATTERN.match(code)
    return m is not None and not (m.group(2) == "eq" and m.group(3))


def display_name(code: str) -> str:
    """LAFmax -> LA,F,max (запис по стандарта)."""
    if code in UNWEIGHTED:
        return {"Lp": "Lp", "Lpmax": "Lp,max", "Lpmin": "Lp,min"}[code]
    m = _PATTERN.match(code)
    if not m:
        return code
    parts = [f"L{m.group(1)}", m.group(2)] + ([m.group(3)] if m.group(3) else [])
    return ",".join(parts)
