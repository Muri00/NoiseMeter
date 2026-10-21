from collections.abc import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)

if engine.dialect.name == "sqlite":
    # SQLite (само за тестове) по подразбиране не проверява външните ключове и ON DELETE CASCADE.
    @event.listens_for(engine, "connect")
    def _enable_foreign_keys(conn, _):
        conn.execute("PRAGMA foreign_keys=ON")

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Iterator[Session]:
    """FastAPI зависимост: отваря сесия към базата за времето на една заявка."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def add_missing_columns() -> None:
    """Добавя нови колони към вече създадени таблици (create_all създава само липсващи таблици).

    Покрива само добавяне на колони, които допускат NULL - това е достатъчно за
    разширяването на схемата между етапите, без отделен инструмент за миграции.
    """
    from sqlalchemy import inspect, text

    inspector = inspect(engine)
    with engine.begin() as conn:
        for table in Base.metadata.sorted_tables:
            if not inspector.has_table(table.name):
                continue
            existing = {c["name"] for c in inspector.get_columns(table.name)}
            for column in table.columns:
                if column.name in existing or not column.nullable:
                    continue
                col_type = column.type.compile(dialect=engine.dialect)
                conn.execute(text(f"ALTER TABLE {table.name} ADD COLUMN {column.name} {col_type} NULL"))
