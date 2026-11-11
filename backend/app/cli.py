"""Команди за администриране от терминала.

    python -m app.cli make-admin <потребителско име>    # дава администраторски права
    python -m app.cli remove-admin <потребителско име>  # прави го обикновен потребител

Първият администратор се създава оттук; след това администраторите могат да
управляват ролите и от приложението.
"""

import sys

from sqlalchemy import select

from app import models  # noqa: F401
from app.database import Base, SessionLocal, add_missing_columns, engine
from app.models import User


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0] not in ("make-admin", "remove-admin"):
        print(__doc__)
        return 1
    Base.metadata.create_all(bind=engine)
    add_missing_columns()
    command, username = argv
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.username == username))
        if user is None:
            print(f"Няма потребител „{username}“")
            return 1
        user.role = "admin" if command == "make-admin" else "user"
        db.commit()
        print(f"{username}: {'администратор' if user.role == 'admin' else 'обикновен потребител'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
