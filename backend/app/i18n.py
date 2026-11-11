"""Превод на съобщенията за грешки, които сървърът връща на приложението.

Текстовете в кода са на български. Когато клиентът поиска английски
(HTTP заглавка Accept-Language: en или поле "lang" в WebSocket), съобщението
се превежда по този речник. Непознатите текстове се връщат без промяна.
"""

EN = {
    "Невалиден или изтекъл токен": "Invalid or expired token",
    "Само администратор може да извърши това действие": "Only an administrator can perform this action",
    "Зоната не е намерена": "Zone not found",
    "Стандартът не е намерен": "Standard not found",
    "Трябва да остане поне един стандарт": "At least one standard must remain",
    "Потребителят не е намерен": "User not found",
    "Не можете да премахнете собствените си администраторски права": "You cannot remove your own administrator rights",
    "Потребителското име или имейлът вече са заети": "The username or email is already taken",
    "Грешно потребителско име или парола": "Wrong username or password",
    "Имейлът вече се използва от друг акаунт": "The email is already used by another account",
    "Текущата парола е грешна": "The current password is wrong",
    "Новата парола трябва да е различна от текущата": "The new password must be different from the current one",
    "Грешна парола": "Wrong password",
    "Микрофонът в момента се използва от измерване": "The microphone is currently used by a measurement",
    "Микрофонът в момента се използва от друго измерване или калибровка":
        "The microphone is currently used by another measurement or calibration",
    "Калибровката не е намерена": "Calibration not found",
    "Калибровката вече е приложена или отхвърлена": "The calibration has already been applied or rejected",
    "Устройството не е намерено": "Device not found",
    "Вече имате устройство с този сериен номер": "You already have a device with this serial number",
    "Началото на периода трябва да е преди края му": "The start of the period must be before its end",
    "Измерването не е намерено": "Measurement not found",
    "Няма WAV запис за това измерване": "There is no WAV recording for this measurement",
    "Някое от измерванията още не е приключило": "One of the measurements has not finished yet",
    "Сертификатът не е намерен": "Certificate not found",
    "Паролата трябва да съдържа поне една буква и една цифра": "The password must contain at least one letter and one digit",
    "Минималната честота трябва да е по-малка от максималната": "The minimum frequency must be lower than the maximum",
    "Показателите не трябва да се повтарят": "Indicators must not repeat",
    "Полюсните честоти трябва да са положителни и във възходящ ред": "Pole frequencies must be positive and ascending",
}

# Съобщения с променлива част след двоеточието.
EN_PREFIX = {
    "Невалидни показатели: ": "Invalid indicators: ",
    "Непознат честотен филтър: ": "Unknown frequency weighting: ",
    "Непознат времеви филтър: ": "Unknown time weighting: ",
    "Микрофонът не може да бъде отворен: ": "The microphone cannot be opened: ",
}


def is_english(lang: str | None) -> bool:
    return (lang or "").strip().lower().startswith("en")


def translate(text: str, lang: str | None) -> str:
    if not is_english(lang) or not isinstance(text, str):
        return text
    # Грешките от валидацията на Pydantic идват с префикс "Value error, ".
    head = ""
    if text.startswith("Value error, "):
        head, text = "Value error, ", text[len("Value error, "):]
    if text in EN:
        return head + EN[text]
    for bg, en in EN_PREFIX.items():
        if text.startswith(bg):
            return head + en + text[len(bg):]
    return head + text
