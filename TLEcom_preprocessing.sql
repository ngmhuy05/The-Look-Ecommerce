--- events ---
SELECT
    *,
    TRY_CAST(user_id AS INT) AS user_id_fix,
    TRY_CAST(REPLACE(created_at, ' UTC', '') AS DATETIME2) AS created_date_clean,
    CASE WHEN event_type = 'product'
             THEN TRY_CAST(SUBSTRING(uri, 10, LEN(uri)) AS BIGINT)
        END AS product_id_raw
INTO dbo.TLEcom_events_temp
FROM TLEcom_events
;

SELECT * FROM dbo.TLEcom_events_temp;
DROP TABLE dbo.TLEcom_events_temp;


--- inventory_events ---
SELECT
    *,
    TRY_CAST(REPLACE(created_at, ' UTC', '') AS DATETIME2) AS created_date_clean,
    TRY_CAST(REPLACE(sold_at, ' UTC', '') AS DATETIME2) AS sold_date_clean
-- INTO dbo.TLEcom_inventory_events_temp
FROM TLEcom_inventory_events;

SELECT * FROM dbo.TLEcom_inventory_events_temp
DROP TABLE dbo.TLEcom_inventory_events_temp;


--- orders ---
SELECT
    *,
    TRY_CAST(REPLACE(created_at, ' UTC', '') AS DATETIME2) AS created_date_clean,
    TRY_CAST(REPLACE(returned_at, ' UTC', '') AS DATETIME2) AS returned_date_clean,
    TRY_CAST(REPLACE(shipped_at, ' UTC', '') AS DATETIME2) AS shipped_date_clean,
    TRY_CAST(REPLACE(delivered_at, ' UTC', '') AS DATETIME2) AS delivered_date_clean
-- INTO dbo.TLEcom_orders_temp
FROM TLEcom_orders;

SELECT * FROM dbo.TLEcom_orders_temp
WHERE returned_date_clean IS NULL;
DROP TABLE dbo.TLEcom_orders_temp;

--- order_items ---
SELECT
    t1.*,
    CASE
        WHEN TRY_CAST(REPLACE(t1.created_at, ' UTC', '') AS DATETIME2) > TRY_CAST(REPLACE(t1.shipped_at, ' UTC', '') AS DATETIME2)
        THEN (SELECT TRY_CAST(REPLACE(t2.created_at, ' UTC', '') AS DATETIME2) FROM TLEcom_orders t2 WHERE t2.order_id = t1.order_id)
        ELSE TRY_CAST(REPLACE(t1.created_at, ' UTC', '') AS DATETIME2)
    END AS created_date_fix,
    TRY_CAST(REPLACE(t1.shipped_at, ' UTC', '') AS DATETIME2) AS shipped_date_fix,
    TRY_CAST(REPLACE(t1.delivered_at, ' UTC', '') AS DATETIME2) AS delivered_date_fix,
    TRY_CAST(REPLACE(t1.returned_at, ' UTC', '') AS DATETIME2) AS returned_date_fix
INTO dbo.TLEcom_order_items_temp
FROM TLEcom_order_items t1
LEFT JOIN TLEcom_orders t2 ON t1.order_id = t2.order_id;

SELECT * FROM dbo.TLEcom_order_items_temp;
DROP TABLE dbo.TLEcom_order_items_temp;


--- users ---
WITH duplicate_emails AS (
    SELECT
        *,
        TRY_CAST(REPLACE(created_at, ' UTC', '') AS DATETIME2) AS created_date_clean,
        CASE 
            WHEN COUNT(*) OVER (PARTITION BY email) > 1 THEN 1 
            ELSE 0 
        END AS is_duplicate_account,
        ROW_NUMBER() OVER (
            PARTITION BY email 
            ORDER BY TRY_CAST(REPLACE(created_at, ' UTC', '') AS DATETIME2) DESC
        ) AS row_num_per_email
    FROM TLEcom_users
)

SELECT * INTO dbo.TLEcom_users_temp
FROM duplicate_emails
WHERE row_num_per_email = 1
;

SELECT TOP 1000 * FROM dbo.TLEcom_users_temp;
DROP TABLE dbo.TLEcom_users_temp;


SELECT * FROM TLEcom_events_temp;
SELECT * FROM TLEcom_inventory_events_temp;
SELECT * FROM TLEcom_orders_temp;
SELECT * FROM TLEcom_order_items_temp;
SELECT * FROM TLEcom_users_temp;
