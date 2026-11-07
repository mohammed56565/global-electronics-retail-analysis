-- =========================================================
-- Global Electronics Retail Sales & Profitability Analysis
-- PostgreSQL Business Analysis
-- =========================================================
--
-- Dataset:
-- Global Electronics Retailers
--
-- Sales period:
-- 2016-01-01 to 2021-02-20
--
-- Important:
-- 2021 is a partial year and should not be directly compared
-- with complete calendar years.
--
-- Core financial metrics:
-- Revenue = Quantity * Unit Price USD
-- Cost    = Quantity * Unit Cost USD
-- Profit  = Revenue - Cost
--
-- Product prices and costs are already expressed in USD.
-- Exchange rates are therefore not used to calculate the
-- primary USD revenue and profit metrics.
-- =========================================================
-- =========================================================
-- DATABASE VALIDATION
-- =========================================================

SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM customers

UNION ALL

SELECT 'products', COUNT(*)
FROM products

UNION ALL

SELECT 'stores', COUNT(*)
FROM stores

UNION ALL
SELECT 'exchange_rates', COUNT(*)
FROM exchange_rates

UNION ALL

SELECT 'sales', COUNT(*)
FROM sales;

-- =========================================================
-- ANALYTICAL VIEW
-- =========================================================
--
-- This view combines the relational tables and calculates
-- reusable financial and analytical fields.
--
-- The original normalized PostgreSQL tables remain unchanged.
-- =========================================================

CREATE OR REPLACE VIEW sales_enriched AS

SELECT
    s.order_number,
    s.line_item,
    s.order_date,
    s.delivery_date,
    s.customer_key,
    s.store_key,
    s.product_key,
    s.quantity,
    s.currency_code,

    -- Product attributes
    p.product_name,
    p.brand,
    p.subcategory,
    p.category,
    p.unit_cost_usd,
    p.unit_price_usd,

    -- Customer attributes
    c.gender,
    c.city AS customer_city,
    c.state AS customer_state,
    c.country AS customer_country,
    c.continent,
    c.birthday,

    -- Store attributes
    st.country AS store_country,
    st.state AS store_state,
    st.square_meters,
    st.open_date AS store_open_date,

    -- Exchange rate retained for optional FX analysis
    er.exchange_rate,

    -- Financial metrics
    s.quantity * p.unit_price_usd AS revenue_usd,

    s.quantity * p.unit_cost_usd AS cost_usd,

    s.quantity *
        (p.unit_price_usd - p.unit_cost_usd)
        AS profit_usd,

    -- Sales channel
    CASE
        WHEN s.store_key = 0 THEN 'Online'
        ELSE 'Physical Store'
    END AS sales_channel,

    -- Customer age at the time of purchase
    EXTRACT(
        YEAR FROM AGE(s.order_date, c.birthday)
    )::INTEGER AS customer_age,

    -- Delivery duration
    CASE
        WHEN s.delivery_date IS NOT NULL
        THEN s.delivery_date - s.order_date
	END AS delivery_days,

c.name AS customer_name

FROM sales AS s

JOIN products AS p
    ON s.product_key = p.product_key

JOIN customers AS c
    ON s.customer_key = c.customer_key

JOIN stores AS st
    ON s.store_key = st.store_key

JOIN exchange_rates AS er
    ON s.order_date = er.rate_date
   AND s.currency_code = er.currency;


SELECT COUNT(*) AS enriched_rows
FROM sales_enriched;


SELECT *
FROM sales_enriched
LIMIT 10;



-- =========================================================
-- BUSINESS QUESTION 1
-- How have revenue, profit, and order volume changed over time?
-- =========================================================


WITH yearly_performance AS (

    SELECT
        EXTRACT(YEAR FROM order_date)::INTEGER AS year,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold

    FROM sales_enriched

    GROUP BY
        EXTRACT(YEAR FROM order_date)
)

SELECT
    year,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd

FROM yearly_performance

ORDER BY year;



-- Year-over-year performance using window functions

WITH yearly_performance AS (

    SELECT
        EXTRACT(YEAR FROM order_date)::INTEGER AS year,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders

    FROM sales_enriched

    GROUP BY
        EXTRACT(YEAR FROM order_date)
),



yearly_with_previous AS (

    SELECT
        year,
        revenue_usd,
        profit_usd,
        orders,

        LAG(revenue_usd)
            OVER (ORDER BY year)
            AS previous_year_revenue,

        LAG(profit_usd)
            OVER (ORDER BY year)
            AS previous_year_profit,

        LAG(orders)
            OVER (ORDER BY year)
            AS previous_year_orders

    FROM yearly_performance
)




SELECT
    year,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(
        100 *
        (revenue_usd - previous_year_revenue)
        / NULLIF(previous_year_revenue, 0),
        2
    ) AS revenue_yoy_pct,

    ROUND(profit_usd, 2) AS profit_usd,

    ROUND(
        100 *
        (profit_usd - previous_year_profit)
        / NULLIF(previous_year_profit, 0),
        2
    ) AS profit_yoy_pct,

    orders,

    ROUND(
        100.0 *
        (orders - previous_year_orders)
        / NULLIF(previous_year_orders, 0),
        2
    ) AS orders_yoy_pct

FROM yearly_with_previous
WHERE year <= 2020
ORDER BY year;

-- =========================================================
-- BUSINESS QUESTION 2
-- Which categories and subcategories generate the most
-- revenue and profit?
-- =========================================================


WITH category_performance AS (

    SELECT
        category,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold

    FROM sales_enriched

    GROUP BY category
)



SELECT
    category,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM category_performance

ORDER BY revenue_usd DESC;

-- Top-performing subcategories

WITH subcategory_performance AS (

    SELECT
        category,
        subcategory,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold

    FROM sales_enriched

    GROUP BY
        category,
        subcategory
)


SELECT
    category,
    subcategory,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM subcategory_performance

ORDER BY revenue_usd DESC;


-- Rank subcategories within each category

WITH subcategory_performance AS (

    SELECT
        category,
        subcategory,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd

    FROM sales_enriched

    GROUP BY
        category,
        subcategory
)

SELECT
    category,
    subcategory,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    RANK() OVER (
        PARTITION BY category
        ORDER BY revenue_usd DESC
    ) AS rank_within_category

FROM subcategory_performance

ORDER BY
    category,
    rank_within_category;

-- =========================================================
-- BUSINESS QUESTION 3
-- Which brands and products generate the most revenue
-- and profit?
-- =========================================================


WITH brand_performance AS (

    SELECT
        brand,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold

    FROM sales_enriched

    GROUP BY brand
)

SELECT
    brand,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM brand_performance

ORDER BY revenue_usd DESC;



-- Top-performing products

WITH product_performance AS (

    SELECT
        product_key,
        product_name,
        brand,
        category,
        subcategory,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold

    FROM sales_enriched

    GROUP BY
        product_key,
        product_name,
        brand,
        category,
        subcategory
)

SELECT
    product_key,
    product_name,
    brand,
    category,
    subcategory,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM product_performance

ORDER BY revenue_usd DESC

LIMIT 20;



-- Rank products within each brand

WITH product_performance AS (

    SELECT
        product_key,
        product_name,
        brand,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd

    FROM sales_enriched

    GROUP BY
        product_key,
        product_name,
        brand
),

ranked_products AS (

    SELECT
        brand,
        product_key,
        product_name,
        revenue_usd,
        profit_usd,

        RANK() OVER (
            PARTITION BY brand
            ORDER BY revenue_usd DESC
        ) AS rank_within_brand

    FROM product_performance
)

SELECT
    brand,
    product_key,
    product_name,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    rank_within_brand

FROM ranked_products

WHERE rank_within_brand <= 3

ORDER BY
    brand,
    rank_within_brand;

-- =========================================================
-- BUSINESS QUESTION 4
-- Which countries and geographic markets generate the
-- highest revenue and profit?
-- =========================================================


WITH country_performance AS (

    SELECT
        customer_country AS country,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

        COUNT(DISTINCT customer_key) AS customers

    FROM sales_enriched

    GROUP BY customer_country
)

SELECT
    country,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    customers,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd,

    ROUND(
        revenue_usd / NULLIF(customers, 0),
        2
    ) AS revenue_per_customer_usd,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM country_performance

ORDER BY revenue_usd DESC;


WITH continent_performance AS (

    SELECT
        continent,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        COUNT(DISTINCT customer_key) AS customers

    FROM sales_enriched

    GROUP BY continent
)

SELECT
    continent,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    customers,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM continent_performance

ORDER BY revenue_usd DESC;


WITH country_performance AS (

    SELECT
        continent,
        customer_country AS country,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd

    FROM sales_enriched

    GROUP BY
        continent,
        customer_country
),

ranked_countries AS (

    SELECT
        continent,
        country,
        revenue_usd,
        profit_usd,

        RANK() OVER (
            PARTITION BY continent
            ORDER BY revenue_usd DESC
        ) AS rank_within_continent

    FROM country_performance
)

SELECT
    continent,
    country,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    rank_within_continent

FROM ranked_countries

ORDER BY
    continent,
    rank_within_continent;


-- =========================================================
-- BUSINESS QUESTION 5
-- Which physical stores perform best and worst, and is
-- store size associated with sales performance?
-- =========================================================



WITH store_performance AS (

    SELECT
        store_key,
        store_country,
        store_state,
        square_meters,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

        COUNT(DISTINCT customer_key) AS customers

    FROM sales_enriched

    WHERE store_key <> 0

    GROUP BY
        store_key,
        store_country,
        store_state,
        square_meters
)

SELECT
    store_key,
    store_country,
    store_state,
    square_meters,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,
    units_sold,
    customers,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM store_performance

ORDER BY revenue_usd DESC;


SELECT
    st.store_key,
    st.country,
    st.state,
    st.square_meters,
    st.open_date

FROM stores AS st

LEFT JOIN sales AS s
    ON st.store_key = s.store_key

WHERE st.store_key <> 0
  AND s.store_key IS NULL

ORDER BY
    st.country,
    st.state;


WITH store_performance AS (

    SELECT
        store_key,
        store_country,
        store_state,
        square_meters,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold

    FROM sales_enriched

    WHERE store_key <> 0

    GROUP BY
        store_key,
        store_country,
        store_state,
        square_meters
)

SELECT
    store_key,
    store_country,
    store_state,
    square_meters,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(
        revenue_usd / NULLIF(square_meters, 0),
        2
    ) AS revenue_per_square_meter,

    ROUND(
        profit_usd / NULLIF(square_meters, 0),
        2
    ) AS profit_per_square_meter,

    RANK() OVER (
        ORDER BY
            revenue_usd / NULLIF(square_meters, 0) DESC
    ) AS efficiency_rank

FROM store_performance

WHERE square_meters IS NOT NULL

ORDER BY efficiency_rank;


WITH store_performance AS (

    SELECT
        store_key,
        square_meters,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold

    FROM sales_enriched

    WHERE store_key <> 0

    GROUP BY
        store_key,
        square_meters
)

SELECT
    ROUND(
        CORR(square_meters, revenue_usd)::NUMERIC,
        3
    ) AS size_revenue_correlation,

    ROUND(
        CORR(square_meters, profit_usd)::NUMERIC,
        3
    ) AS size_profit_correlation,

    ROUND(
        CORR(square_meters, orders)::NUMERIC,
        3
    ) AS size_orders_correlation,

    ROUND(
        CORR(square_meters, units_sold)::NUMERIC,
        3
    ) AS size_units_correlation

FROM store_performance

WHERE square_meters IS NOT NULL;



-- =========================================================
-- BUSINESS QUESTION 6
-- How does online sales performance compare with
-- physical-store performance?
-- =========================================================


WITH channel_performance AS (

    SELECT
        sales_channel,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

        COUNT(DISTINCT customer_key) AS customers

    FROM sales_enriched

    GROUP BY sales_channel
)

SELECT
    sales_channel,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    customers,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd,

    ROUND(
        units_sold::NUMERIC / NULLIF(orders, 0),
        2
    ) AS units_per_order,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct,

    ROUND(
        100.0 * orders
        / SUM(orders) OVER (),
        2
    ) AS order_share_pct

FROM channel_performance

ORDER BY revenue_usd DESC;



-- Online revenue share by year

WITH yearly_channel AS (

    SELECT
        EXTRACT(YEAR FROM order_date)::INTEGER AS year,
        sales_channel,

        SUM(revenue_usd) AS revenue_usd

    FROM sales_enriched

    GROUP BY
        EXTRACT(YEAR FROM order_date),
        sales_channel
),

yearly_totals AS (

    SELECT
        year,
        sales_channel,
        revenue_usd,

        SUM(revenue_usd)
            OVER (PARTITION BY year)
            AS total_year_revenue

    FROM yearly_channel
)

SELECT
    year,

    ROUND(
        MAX(
            CASE
                WHEN sales_channel = 'Online'
                THEN revenue_usd
            END
        ),
        2
    ) AS online_revenue_usd,

    ROUND(
        100 *
        MAX(
            CASE
                WHEN sales_channel = 'Online'
                THEN revenue_usd
            END
        )
        /
        MAX(total_year_revenue),
        2
    ) AS online_revenue_share_pct

FROM yearly_totals

GROUP BY year

ORDER BY year;


-- Online delivery performance at order level

WITH online_orders AS (

    SELECT
        order_number,

        MIN(order_date) AS order_date,

        MAX(delivery_date) AS delivery_date,

        MAX(delivery_date) - MIN(order_date)
            AS delivery_days

    FROM sales_enriched

    WHERE sales_channel = 'Online'

    GROUP BY order_number
)

SELECT
    EXTRACT(YEAR FROM order_date)::INTEGER AS year,

    COUNT(*) AS online_orders,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY delivery_days)
        AS median_delivery_days,

    MIN(delivery_days) AS minimum_delivery_days,

    MAX(delivery_days) AS maximum_delivery_days

FROM online_orders

GROUP BY
    EXTRACT(YEAR FROM order_date)

ORDER BY year;



WITH online_orders AS (

    SELECT
        order_number,

        MAX(delivery_date) - MIN(order_date)
            AS delivery_days

    FROM sales_enriched

    WHERE sales_channel = 'Online'

    GROUP BY order_number
)

SELECT
    COUNT(*) AS online_orders,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY delivery_days)
        AS median_delivery_days,

    MIN(delivery_days) AS minimum_delivery_days,

    MAX(delivery_days) AS maximum_delivery_days

FROM online_orders;




-- =========================================================
-- BUSINESS QUESTION 7
-- Which customers generate the most value, and how
-- concentrated is revenue among high-value customers?
-- =========================================================


WITH customer_performance AS (

    SELECT
        customer_key,

        MAX(customer_country) AS country,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

	    MIN(order_date) AS first_purchase_date,

	    MAX(order_date) AS last_purchase_date,

        MAX(customer_name) AS customer_name


    FROM sales_enriched

    GROUP BY customer_key
)

SELECT
    customer_key,
	customer_name,
    country,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    first_purchase_date,
    last_purchase_date,

    RANK() OVER (
        ORDER BY revenue_usd DESC
    ) AS revenue_rank

FROM customer_performance

ORDER BY revenue_usd DESC

LIMIT 20;



WITH customer_performance AS (

    SELECT
        customer_key,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders

    FROM sales_enriched

    GROUP BY customer_key
),

customer_segments AS (

    SELECT
        customer_key,
        revenue_usd,
        profit_usd,
        orders,

        CASE
            WHEN orders > 1 THEN 'Repeat Customer'
            ELSE 'One-time Customer'
        END AS customer_type

    FROM customer_performance
)

SELECT
    customer_type,

    COUNT(*) AS customers,

    SUM(orders) AS orders,

    ROUND(
        SUM(revenue_usd),
        2
    ) AS revenue_usd,

    ROUND(
        SUM(profit_usd),
        2
    ) AS profit_usd,

    ROUND(
        100 * SUM(revenue_usd)
        / SUM(SUM(revenue_usd)) OVER (),
        2
    ) AS revenue_share_pct

FROM customer_segments

GROUP BY customer_type

ORDER BY revenue_usd DESC;



WITH customer_performance AS (

    SELECT
        customer_key,

        SUM(revenue_usd) AS revenue_usd

    FROM sales_enriched

    GROUP BY customer_key
),

ranked_customers AS (

    SELECT
        customer_key,
        revenue_usd,

        ROW_NUMBER() OVER (
            ORDER BY revenue_usd DESC
        ) AS revenue_rank,

        COUNT(*) OVER () AS total_customers

    FROM customer_performance
)

SELECT
    MAX(total_customers) AS active_customers,

    CEIL(
        MAX(total_customers) * 0.10
    )::INTEGER AS top_10_pct_customers,

    ROUND(
        SUM(revenue_usd)
        FILTER (
            WHERE revenue_rank <=
                CEIL(total_customers * 0.10)
        ),
        2
    ) AS top_10_pct_revenue_usd,

    ROUND(
        100 *
        SUM(revenue_usd)
        FILTER (
            WHERE revenue_rank <=
                CEIL(total_customers * 0.10)
        )
        /
        SUM(revenue_usd),
        2
    ) AS top_10_pct_revenue_share

FROM ranked_customers;



WITH customer_performance AS (

    SELECT
        customer_key,

        COUNT(DISTINCT order_number) AS orders

    FROM sales_enriched

    GROUP BY customer_key
)

SELECT
    orders AS number_of_orders,

    COUNT(*) AS customers

FROM customer_performance

GROUP BY orders

ORDER BY orders;


-- =========================================================
-- BUSINESS QUESTION 8
-- How does purchasing behavior differ across customer
-- age groups and gender?
-- =========================================================


WITH demographic_sales AS (

    SELECT
        *,

CASE
    WHEN customer_age < 25 THEN 'Under 25'
    WHEN customer_age BETWEEN 25 AND 34 THEN '25-34'
    WHEN customer_age BETWEEN 35 AND 44 THEN '35-44'
    WHEN customer_age BETWEEN 45 AND 54 THEN '45-54'
    WHEN customer_age BETWEEN 55 AND 64 THEN '55-64'
    WHEN customer_age >= 65 THEN '65+'
    ELSE 'Unknown'
      END AS age_group
    FROM sales_enriched
),

age_performance AS (

    SELECT
        age_group,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

        COUNT(DISTINCT customer_key) AS customers

    FROM demographic_sales

    GROUP BY age_group
)

SELECT
    age_group,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    customers,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd,

    ROUND(
        revenue_usd / NULLIF(customers, 0),
        2
    ) AS revenue_per_customer_usd,

    ROUND(
        units_sold::NUMERIC / NULLIF(orders, 0),
        2
    ) AS units_per_order

FROM age_performance

ORDER BY
    CASE age_group
        WHEN 'Under 25' THEN 1
        WHEN '25-34' THEN 2
        WHEN '35-44' THEN 3
        WHEN '45-54' THEN 4
        WHEN '55-64' THEN 5
        WHEN '65+' THEN 6
    END;



WITH gender_performance AS (

    SELECT
        gender,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

        COUNT(DISTINCT customer_key) AS customers

    FROM sales_enriched

    GROUP BY gender
)

SELECT
    gender,

    ROUND(revenue_usd, 2) AS revenue_usd,

    ROUND(profit_usd, 2) AS profit_usd,

    orders,

    units_sold,

    customers,

    ROUND(
        100 * profit_usd / NULLIF(revenue_usd, 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd,

    ROUND(
        revenue_usd / NULLIF(customers, 0),
        2
    ) AS revenue_per_customer_usd,

    ROUND(
        units_sold::NUMERIC / NULLIF(orders, 0),
        2
    ) AS units_per_order,

    ROUND(
        100 * revenue_usd
        / SUM(revenue_usd) OVER (),
        2
    ) AS revenue_share_pct

FROM gender_performance

ORDER BY revenue_usd DESC;


WITH demographic_sales AS (

    SELECT
        *,

        CASE
            WHEN customer_age < 25 THEN 'Under 25'
            WHEN customer_age BETWEEN 25 AND 34 THEN '25-34'
            WHEN customer_age BETWEEN 35 AND 44 THEN '35-44'
            WHEN customer_age BETWEEN 45 AND 54 THEN '45-54'
            WHEN customer_age BETWEEN 55 AND 64 THEN '55-64'
			WHEN customer_age >= 65 THEN '65+'
            ELSE 'Unknown'
            END AS age_group
    FROM sales_enriched
),

age_gender_performance AS (

    SELECT
        age_group,
        gender,

        SUM(revenue_usd) AS revenue_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

        COUNT(DISTINCT customer_key) AS customers

    FROM demographic_sales

    GROUP BY
        age_group,
        gender
)

SELECT
    age_group,
    gender,

    ROUND(revenue_usd, 2) AS revenue_usd,

    orders,

    units_sold,

    customers,

    ROUND(
        revenue_usd / NULLIF(orders, 0),
        2
    ) AS average_order_value_usd,

    ROUND(
        revenue_usd / NULLIF(customers, 0),
        2
    ) AS revenue_per_customer_usd

FROM age_gender_performance

ORDER BY
    CASE age_group
        WHEN 'Under 25' THEN 1
        WHEN '25-34' THEN 2
        WHEN '35-44' THEN 3
        WHEN '45-54' THEN 4
        WHEN '55-64' THEN 5
        WHEN '65+' THEN 6
    END,
    gender;




-- =========================================================
-- BUSINESS QUESTION 9
-- Are there seasonal patterns in sales and order activity?
-- =========================================================


WITH monthly_performance AS (

    SELECT
        EXTRACT(MONTH FROM order_date)::INTEGER AS month_number,

        TO_CHAR(order_date, 'FMMonth') AS month_name,

        SUM(revenue_usd) AS revenue_usd,

        SUM(profit_usd) AS profit_usd,

        COUNT(DISTINCT order_number) AS orders,

        SUM(quantity) AS units_sold,

        COUNT(
            DISTINCT EXTRACT(YEAR FROM order_date)
        ) AS years_included

    FROM sales_enriched

    WHERE EXTRACT(YEAR FROM order_date)
          BETWEEN 2016 AND 2020

    GROUP BY
        EXTRACT(MONTH FROM order_date),
        TO_CHAR(order_date, 'FMMonth')
)

SELECT
    month_number,
    month_name,

    ROUND(
        revenue_usd / years_included,
        2
    ) AS average_annual_revenue_usd,

    ROUND(
        profit_usd / years_included,
        2
    ) AS average_annual_profit_usd,

    ROUND(
        orders::NUMERIC / years_included,
        2
    ) AS average_annual_orders,

    ROUND(
        units_sold::NUMERIC / years_included,
        2
    ) AS average_annual_units,

    RANK() OVER (
        ORDER BY revenue_usd / years_included DESC
    ) AS revenue_rank

FROM monthly_performance

ORDER BY month_number;



-- Monthly revenue pattern by year

SELECT
    EXTRACT(YEAR FROM order_date)::INTEGER AS year,

    EXTRACT(MONTH FROM order_date)::INTEGER AS month_number,

    TO_CHAR(order_date, 'FMMonth') AS month_name,

    ROUND(
        SUM(revenue_usd),
        2
    ) AS revenue_usd,

    COUNT(DISTINCT order_number) AS orders

FROM sales_enriched

WHERE EXTRACT(YEAR FROM order_date)
      BETWEEN 2016 AND 2020

GROUP BY
    EXTRACT(YEAR FROM order_date),
    EXTRACT(MONTH FROM order_date),
    TO_CHAR(order_date, 'FMMonth')

ORDER BY
    year,
    month_number;




WITH monthly_performance AS (

    SELECT
        EXTRACT(MONTH FROM order_date)::INTEGER AS month_number,

        TO_CHAR(order_date, 'FMMonth') AS month_name,

        SUM(revenue_usd)
        /
        COUNT(
            DISTINCT EXTRACT(YEAR FROM order_date)
        ) AS average_revenue_usd

    FROM sales_enriched

    WHERE EXTRACT(YEAR FROM order_date)
          BETWEEN 2016 AND 2020

    GROUP BY
        EXTRACT(MONTH FROM order_date),
        TO_CHAR(order_date, 'FMMonth')
)

SELECT
    month_name,

    ROUND(
        average_revenue_usd,
        2
    ) AS average_revenue_usd,

    RANK() OVER (
        ORDER BY average_revenue_usd DESC
    ) AS strongest_month_rank,

    RANK() OVER (
        ORDER BY average_revenue_usd
    ) AS weakest_month_rank

FROM monthly_performance

ORDER BY average_revenue_usd DESC;