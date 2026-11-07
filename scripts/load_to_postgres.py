from pathlib import Path
import os

import psycopg
from dotenv import load_dotenv


# ---------------------------------------------------------
# Project paths
# ---------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data" / "processed"

load_dotenv(PROJECT_ROOT / ".env")


# ---------------------------------------------------------
# PostgreSQL connection
# ---------------------------------------------------------

connection_params = {
    "host": os.getenv("DB_HOST"),
    "port": os.getenv("DB_PORT"),
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
}


# ---------------------------------------------------------
# Tables must be loaded in this order because sales contains
# foreign keys referencing the other tables.
# ---------------------------------------------------------

tables = [
    ("customers", DATA_DIR / "customers_clean.csv"),
    ("products", DATA_DIR / "products_clean.csv"),
    ("stores", DATA_DIR / "stores_clean.csv"),
    ("exchange_rates", DATA_DIR / "exchange_rates_clean.csv"),
    ("sales", DATA_DIR / "sales_clean.csv"),
]


def load_csv(cursor, table_name, csv_path):
    print(f"Loading {table_name}...")

    with csv_path.open("r", encoding="utf-8") as file:
        with cursor.copy(
            f"COPY {table_name} FROM STDIN WITH (FORMAT CSV, HEADER TRUE)"
        ) as copy:
            while data := file.read(1024 * 1024):
                copy.write(data)

    print(f"Loaded {table_name}.")


def main():
    with psycopg.connect(**connection_params) as connection:
        with connection.cursor() as cursor:

            # Allows the script to be rerun without creating duplicates.
            cursor.execute(
                """
                TRUNCATE TABLE
                    sales,
                    exchange_rates,
                    products,
                    customers,
                    stores
                CASCADE;
                """
            )

            for table_name, csv_path in tables:
                load_csv(cursor, table_name, csv_path)

        connection.commit()

    print("\nAll tables loaded successfully.")


if __name__ == "__main__":
    main()