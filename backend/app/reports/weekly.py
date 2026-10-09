import csv
import io
import os
import asyncio
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlalchemy.orm import selectinload

# ВАЖЛИВО: Переконайся, що імпорт відповідає твоїй структурі.
# Якщо models.py лежить у папці backend/app/, залишай так:
from app.models import Meeting

async def _get_report_data(week: str):
    # Беремо URL бази з оточення (Lambda та Docker автоматично його підставлять)
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        raise RuntimeError("DATABASE_URL environment variable is missing")

    # Створюємо підключення
    engine = create_async_engine(db_url)
    AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

    # Парсимо ISO-тиждень (наприклад "2026-W40") у дати
    # %G - ISO рік, %V - ISO тиждень, %u - день тижня (1 = Понеділок)
    this_monday = datetime.strptime(f"{week}-1", "%G-W%V-%u").replace(tzinfo=timezone.utc)
    next_monday = this_monday + timedelta(days=7)
    last_monday = this_monday - timedelta(days=7)

    async with AsyncSessionLocal() as session:
        # Запит на цей тиждень (разом з учасниками через selectinload)
        result_this = await session.execute(
            select(Meeting)
            .options(selectinload(Meeting.participants))
            .where(Meeting.starts_at >= this_monday, Meeting.starts_at < next_monday)
        )
        this_week_meetings = result_this.scalars().all()

        # Запит на минулий тиждень (тільки для статистики, учасники не потрібні)
        result_last = await session.execute(
            select(Meeting)
            .where(Meeting.starts_at >= last_monday, Meeting.starts_at < this_monday)
        )
        last_week_meetings = result_last.scalars().all()

    await engine.dispose()
    return this_week_meetings, last_week_meetings


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""

    # Виконуємо асинхронні запити
    this_week_meetings, last_week_meetings = asyncio.run(_get_report_data(week))

    # --- 1. Підрахунок метрик ---
    def calc_stats(meetings):
        count = len(meetings)
        hours = sum((m.ends_at - m.starts_at).total_seconds() / 3600.0 for m in meetings)
        return count, hours

    this_count, this_hours = calc_stats(this_week_meetings)
    last_count, last_hours = calc_stats(last_week_meetings)

    count_diff = this_count - last_count
    hours_diff = this_hours - last_hours

    # --- 2. 5 найдовших зустрічей ---
    this_week_meetings_sorted = sorted(
        this_week_meetings,
        key=lambda m: (m.ends_at - m.starts_at).total_seconds(),
        reverse=True
    )
    longest_5 = this_week_meetings_sorted[:5]

    # --- 3. Формуємо CSV ---
    output = io.StringIO()
    writer = csv.writer(output)

    writer.writerow(["Metric", "This Week", "Last Week", "Change"])
    writer.writerow(["Meetings Count", this_count, last_count, count_diff])
    writer.writerow(["Total Duration (hours)", f"{this_hours:.2f}", f"{last_hours:.2f}", f"{hours_diff:.2f}"])

    writer.writerow([]) # Порожній рядок

    writer.writerow(["Top 5 Longest Meetings This Week"])
    writer.writerow(["Title", "Start Time", "Duration (hours)", "Participants Count"])

    for m in longest_5:
        duration_hrs = (m.ends_at - m.starts_at).total_seconds() / 3600.0
        start_str = m.starts_at.strftime("%Y-%m-%d %H:%M")
        writer.writerow([m.title, start_str, f"{duration_hrs:.2f}", len(m.participants)])

    # Повертаємо як байти
    return output.getvalue().encode("utf-8")
def previous_iso_week(today: datetime | None = None) -> str:
    """Return the ISO week string (e.g. '2026-W40') for the previous week."""
    if today is None:
        today = datetime.now(timezone.utc)
    # Віднімаємо 7 днів від поточної дати
    prev = today - timedelta(days=7)
    iso_year, iso_week, _ = prev.isocalendar()
    return f"{iso_year}-W{iso_week:02d}"
