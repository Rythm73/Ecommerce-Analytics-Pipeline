import os
from pathlib import Path
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

# --- Configuration ---
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
DATA_DIR = Path(__file__).resolve().parent.parent / "data"

engine = create_engine(DATABASE_URL)

print(f"Connecting to database.......")
print(f"Reading CSVs from: {DATA_DIR}")

def load_csv_to_raw(file_name: str, table_name: str, dtypes: dict = None, date_columns: list = None):
    """Load a single CSV from the data folder into the raw schema."""
    file_path = DATA_DIR / file_name
    print(f"\nLoading {file_name} -> raw.{table_name}")

    df = pd.read_csv(file_path, dtype=dtypes, parse_dates=date_columns)
    print(f"  Read {len(df):,} rows from CSV")

    df.to_sql(table_name, engine, schema="raw", if_exists="replace", index=False)
    print(f"  Loaded into raw.{table_name}")

# --- Table configurations ---
TABLES = [
    {
        "file_name": "olist_customers_dataset.csv",
        "table_name": "customers",
        "dtypes": {
            "customer_id": str,
            "customer_unique_id": str,
            "customer_zip_code_prefix": str,
            "customer_city": str,
            "customer_state": str,
        },
        "date_columns": None,
    },
    {
        "file_name": "olist_geolocation_dataset.csv",
        "table_name": "geolocation",
        "dtypes": {
            "geolocation_zip_code_prefix": str,
            "geolocation_lat": float,
            "geolocation_lng": float,
            "geolocation_city": str,
            "geolocation_state": str,
        },
        "date_columns": None,
    },
    {
        "file_name": "olist_order_items_dataset.csv",
        "table_name": "order_items",
        "dtypes": {
            "order_id": str,
            "order_item_id": str,
            "product_id": str,
            "seller_id": str,
            "price": float,
            "freight_value": float,
        },
        "date_columns": ["shipping_limit_date"],
    },
    {
        "file_name": "olist_order_payments_dataset.csv",
        "table_name": "order_payments",
        "dtypes": {
            "order_id": str,
            "payment_sequential": int,
            "payment_type": str,
            "payment_installments": int,
            "payment_value": float,
        },
        "date_columns": None,
    },
    {
        "file_name": "olist_order_reviews_dataset.csv",
        "table_name": "order_reviews",
        "dtypes": {
            "review_id": str,
            "order_id": str,
            "review_score": int,
            "review_comment_title": str,
            "review_comment_message": str,
        },
        "date_columns": ["review_creation_date", "review_answer_timestamp"],
    },
    {
        "file_name": "olist_orders_dataset.csv",
        "table_name": "orders",
        "dtypes": {
            "order_id": str,
            "customer_id": str,
            "order_status": str,
        },
        "date_columns": [
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
        ],
    },
    {
        "file_name": "olist_products_dataset.csv",
        "table_name": "products",
        "dtypes": {
            "product_id": str,
            "product_category_name": str,
            "product_name_lenght": float,
            "product_description_lenght": float,
            "product_photos_qty": float,
            "product_weight_g": float,
            "product_length_cm": float,
            "product_height_cm": float,
            "product_width_cm": float,
        },
        "date_columns": None,
    },
    {
        "file_name": "olist_sellers_dataset.csv",
        "table_name": "sellers",
        "dtypes": {
            "seller_id": str,
            "seller_zip_code_prefix": str,
            "seller_city": str,
            "seller_state": str,
        },
        "date_columns": None,
    },
    {
        "file_name": "product_category_name_translation.csv",
        "table_name": "product_category_name_translation",
        "dtypes": {
            "product_category_name": str,
            "product_category_name_english": str,
        },
        "date_columns": None,
    },
]


# --- Load all tables ---
for config in TABLES:
    load_csv_to_raw(**config)

print("\nAll tables loaded.")