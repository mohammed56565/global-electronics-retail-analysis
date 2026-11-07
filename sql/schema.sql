-- =========================================================
-- Global Electronics Retail Analysis
-- PostgreSQL Database Schema
-- =========================================================
-- Drop dependent analytical view first.
DROP VIEW IF EXISTS sales_enriched;

-- Drop tables in dependency order so the script can be rerun.
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS exchange_rates;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS stores;


-- =========================================================
-- CUSTOMERS
-- =========================================================

CREATE TABLE customers (
    customer_key      INTEGER PRIMARY KEY,
    gender            VARCHAR(10) NOT NULL,
    name              VARCHAR(150) NOT NULL,
    city              VARCHAR(150) NOT NULL,
    state_code VARCHAR(100) NOT NULL,
    state             VARCHAR(150) NOT NULL,
    zip_code          VARCHAR(20) NOT NULL,
    country           VARCHAR(100) NOT NULL,
    continent         VARCHAR(100) NOT NULL,
    birthday          DATE NOT NULL
);


-- =========================================================
-- PRODUCTS
-- =========================================================

CREATE TABLE products (
    product_key       INTEGER PRIMARY KEY,
    product_name      VARCHAR(255) NOT NULL,
    brand             VARCHAR(150) NOT NULL,
    color             VARCHAR(100) NOT NULL,
    unit_cost_usd     NUMERIC(12, 2) NOT NULL,
    unit_price_usd    NUMERIC(12, 2) NOT NULL,
    subcategory_key   INTEGER NOT NULL,
    subcategory       VARCHAR(150) NOT NULL,
    category_key      INTEGER NOT NULL,
    category          VARCHAR(150) NOT NULL,

    CONSTRAINT chk_product_cost_positive
        CHECK (unit_cost_usd >= 0),

    CONSTRAINT chk_product_price_positive
        CHECK (unit_price_usd > 0),

    CONSTRAINT chk_price_not_below_cost
        CHECK (unit_price_usd >= unit_cost_usd)
);


-- =========================================================
-- STORES
-- =========================================================

CREATE TABLE stores (
    store_key         INTEGER PRIMARY KEY,
    country           VARCHAR(100) NOT NULL,
    state             VARCHAR(150) NOT NULL,
    square_meters     NUMERIC(10, 2),
    open_date         DATE NOT NULL,

    CONSTRAINT chk_store_area_positive
        CHECK (
            square_meters IS NULL
            OR square_meters > 0
        )
);


-- =========================================================
-- EXCHANGE RATES
-- =========================================================

CREATE TABLE exchange_rates (
    rate_date         DATE NOT NULL,
    currency          CHAR(3) NOT NULL,
    exchange_rate     NUMERIC(12, 6) NOT NULL,

    CONSTRAINT pk_exchange_rates
        PRIMARY KEY (rate_date, currency),

    CONSTRAINT chk_exchange_rate_positive
        CHECK (exchange_rate > 0)
);


-- =========================================================
-- SALES
-- =========================================================

CREATE TABLE sales (
    order_number      INTEGER NOT NULL,
    line_item         INTEGER NOT NULL,
    order_date        DATE NOT NULL,
    delivery_date     DATE,
    customer_key      INTEGER NOT NULL,
    store_key         INTEGER NOT NULL,
    product_key       INTEGER NOT NULL,
    quantity          INTEGER NOT NULL,
    currency_code     CHAR(3) NOT NULL,

    CONSTRAINT pk_sales
        PRIMARY KEY (order_number, line_item),

    CONSTRAINT fk_sales_customer
        FOREIGN KEY (customer_key)
        REFERENCES customers(customer_key),

    CONSTRAINT fk_sales_store
        FOREIGN KEY (store_key)
        REFERENCES stores(store_key),

    CONSTRAINT fk_sales_product
        FOREIGN KEY (product_key)
        REFERENCES products(product_key),

    CONSTRAINT fk_sales_exchange_rate
        FOREIGN KEY (order_date, currency_code)
        REFERENCES exchange_rates(rate_date, currency),

    CONSTRAINT chk_sales_quantity
        CHECK (quantity > 0),

    CONSTRAINT chk_delivery_date
        CHECK (
            delivery_date IS NULL
            OR delivery_date >= order_date
        )
);


-- =========================================================
-- INDEXES
-- =========================================================

CREATE INDEX idx_sales_order_date
    ON sales(order_date);

CREATE INDEX idx_sales_customer_key
    ON sales(customer_key);

CREATE INDEX idx_sales_product_key
    ON sales(product_key);

CREATE INDEX idx_sales_store_key
    ON sales(store_key);

CREATE INDEX idx_sales_currency_date
    ON sales(order_date, currency_code);