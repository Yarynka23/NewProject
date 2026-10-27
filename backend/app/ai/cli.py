import sys
import json
from datetime import date
from app.ai.agenda import parse_agenda

def main():
    if len(sys.argv) < 2:
        print("Помилка: не передано текст для парсингу.")
        print("Використання: python -m app.ai.cli \"текст зустрічі\"")
        sys.exit(1)

    text = sys.argv[1]
    today = date.today()
    tz = "Europe/Kyiv"

    try:
        agenda, usage = parse_agenda(text, today, tz)

        print("--- Згенерований JSON ---")
        # model_dump(mode="json") перетворює дати та інші типи Pydantic у базові типи
        print(json.dumps(agenda.model_dump(mode="json"), indent=2, ensure_ascii=False))

        print("\n--- Використання токенів ---")
        print(usage)

    except Exception as e:
        print(f"Помилка парсингу: {e}")

if __name__ == "__main__":
    main()
