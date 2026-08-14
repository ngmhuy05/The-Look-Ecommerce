SELECT
    traffic_source,
    COUNT (*) AS num_sessions
FROM TLEcom_users_temp
GROUP BY traffic_source
;

CREATE INDEX idx_inv_product_time
    ON TLEcom_inventory_events_temp (product_id, created_date_clean, sold_date_clean);

CREATE INDEX idx_events_session_seq
    ON TLEcom_events_temp (session_id, sequence_number)
    INCLUDE (event_type, uri, created_date_clean, traffic_source, browser);


-- 1.1 Tổng quan: sessions, users, conversion rate theo traffic_source
WITH session_summary AS (
    SELECT 
        session_id,
        user_id_fix AS user_id,
        traffic_source,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart
    FROM TLEcom_events_temp 
    GROUP BY session_id, user_id_fix, traffic_source
)
SELECT
    traffic_source,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT user_id) AS total_users,
    SUM(has_cart) AS sessions_with_cart,
    SUM(has_purchase) AS sessions_with_purchase,
    CAST(SUM(has_cart) AS FLOAT) / NULLIF(COUNT(DISTINCT session_id),0) AS session_to_cart_rate,
    CAST(SUM(has_purchase) AS FLOAT) / NULLIF(SUM(has_cart),0) AS cart_to_purchase_rate,
    CAST(SUM(has_purchase) AS FLOAT) / NULLIF(COUNT(DISTINCT session_id),0) AS conversion_rate
FROM session_summary
GROUP BY traffic_source
ORDER BY total_sessions DESC;


-- 1.2 Doanh thu & AOV theo traffic_source (traffic_source lấy từ users_clean)
SELECT
    t3.traffic_source,
    COUNT(DISTINCT t1.order_id) AS total_orders,
    COUNT(DISTINCT t1.user_id) AS total_buyers,
    SUM(t2.sale_price) AS total_revenue,
    SUM(t2.sale_price) / NULLIF(COUNT(DISTINCT t1.order_id),0) AS aov
FROM TLEcom_orders_temp t1
LEFT JOIN TLEcom_order_items_temp t2 ON t2.order_id = t1.order_id
LEFT JOIN TLEcom_users_temp t3 ON t3.id = t1.user_id
WHERE t1.status NOT IN ('Cancelled','Returned')
GROUP BY t3.traffic_source
ORDER BY total_revenue DESC;


-- Xu hướng 1.2: revenue, AOV theo tháng & traffic_source (users_clean)
WITH monthly_revenue AS (
    SELECT
        DATEFROMPARTS(YEAR(t1.created_date_clean), MONTH(t1.created_date_clean), 1) AS year_month,
        YEAR(t1.created_date_clean) AS year,
        MONTH(t1.created_date_clean) AS month,
        t3.traffic_source,
        t1.order_id,
        t1.user_id,
        t2.sale_price
    FROM TLEcom_orders_temp t1
    JOIN TLEcom_order_items_temp t2 ON t2.order_id = t1.order_id
    JOIN TLEcom_users_temp t3 ON t3.id = t1.user_id
    WHERE t1.status NOT IN ('Cancelled','Returned')
)
SELECT
    year_month,
    year,
    month,
    traffic_source,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT user_id) AS total_buyers,
    SUM(sale_price) AS total_revenue,
    SUM(sale_price) / NULLIF(COUNT(DISTINCT order_id),0) AS aov
FROM monthly_revenue
GROUP BY year_month, year, month, traffic_source
ORDER BY year_month, traffic_source;


-- 1.3 Xu hướng theo tháng theo traffic_source (đánh giá kênh nào tăng trưởng bền vững)
SELECT
    DATEFROMPARTS(YEAR(created_date_clean), MONTH(created_date_clean), 1) AS year_month,
    YEAR(created_date_clean) AS year,
    MONTH(created_date_clean) AS month,
    traffic_source,
    COUNT(DISTINCT session_id) AS sessions,
    COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN session_id END) AS purchase_sessions
FROM TLEcom_events_temp 
GROUP BY
    DATEFROMPARTS(YEAR(created_date_clean), MONTH(created_date_clean), 1),
    YEAR(created_date_clean),
    MONTH(created_date_clean),
    traffic_source
ORDER BY year_month, sessions DESC
;


-- Kiểm tra: đơn 1 và đơn 2 của cùng user cách nhau bao lâu?
WITH order_ranked AS (
    SELECT
        o.user_id,
        o.order_id,
        o.created_date_clean,
        ROW_NUMBER() OVER (PARTITION BY o.user_id ORDER BY o.created_date_clean) AS order_rank
    FROM TLEcom_orders_temp o
    WHERE o.status NOT IN ('Cancelled','Returned')
), test AS(
    SELECT
        *,
        LAG(created_date_clean) OVER (PARTITION BY user_id ORDER BY created_date_clean) AS prev_order_date,
        DATEDIFF(SECOND, LAG(created_date_clean) OVER (PARTITION BY user_id ORDER BY created_date_clean), created_date_clean) AS gap_seconds
    FROM order_ranked
) 
SELECT
    CASE 
        WHEN gap_seconds < 60 THEN '< 1 minute'
        WHEN gap_seconds < 3600 THEN '1 minute - 1 hour'
        WHEN gap_seconds < 86400 THEN '1 hour - 1 day'
        ELSE '> 1 day'
    END AS gap_bucket,
    COUNT(*) AS num_order_pairs,
    COUNT(DISTINCT user_id) AS num_distinct_users
FROM test
WHERE prev_order_date IS NOT NULL
GROUP BY 
    CASE 
        WHEN gap_seconds < 60 THEN '< 1 minute'
        WHEN gap_seconds < 3600 THEN '1 minute - 1 hour'
        WHEN gap_seconds < 86400 THEN '1 hour - 1 day'
        ELSE '> 1 day'
    END
ORDER BY num_order_pairs DESC;


-- 1.4 Repeat purchase rate & avg orders/buyer theo traffic_source (nguồn traffic gốc của user)
-- repeat_rate đã loại các cặp đơn bị tách kỹ thuật (< 1 phút)
WITH order_ranked AS (
    SELECT
        o.user_id,
        o.order_id,
        o.created_date_clean,
        LAG(o.created_date_clean) OVER (PARTITION BY o.user_id ORDER BY o.created_date_clean) AS prev_order_date
    FROM TLEcom_orders_temp o
    WHERE o.status NOT IN ('Cancelled','Returned')
),
valid_orders AS (
    -- giữ đơn đầu tiên của mỗi user, và các đơn sau đó cách đơn liền trước >= 60s
    SELECT user_id, order_id, created_date_clean
    FROM order_ranked
    WHERE prev_order_date IS NULL 
       OR DATEDIFF(SECOND, prev_order_date, created_date_clean) >= 60
),
user_orders AS (
    SELECT user_id, COUNT(*) AS num_orders
    FROM valid_orders
    GROUP BY user_id
)
SELECT
    u.traffic_source,
    COUNT(DISTINCT uo.user_id) AS total_buyers,
    SUM(CASE WHEN uo.num_orders >= 2 THEN 1 ELSE 0 END) AS repeat_buyers,
    CAST(SUM(CASE WHEN uo.num_orders >= 2 THEN 1 ELSE 0 END) AS FLOAT)
        / NULLIF(COUNT(DISTINCT uo.user_id),0) AS repeat_rate
FROM user_orders uo
JOIN TLEcom_users_temp u ON u.id = uo.user_id
GROUP BY u.traffic_source
ORDER BY repeat_rate DESC;







-- 2.2 Funnel theo traffic_source (tìm điểm nghẽn theo kênh)
WITH session_funnel AS (
    SELECT
        session_id,
        traffic_source,
        MAX(CASE WHEN event_type = 'product' THEN 1 ELSE 0 END) AS step_product,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS step_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS step_purchase
    FROM TLEcom_events_temp
    GROUP BY session_id, traffic_source
)
SELECT
    traffic_source,
    SUM(step_product) AS product_view_sessions,
    SUM(step_cart) AS cart_sessions,
    SUM(step_purchase) AS purchase_sessions,
    CAST(SUM(step_cart) AS FLOAT)/NULLIF(SUM(step_product),0) AS product_to_cart_rate,
    CAST(SUM(step_purchase) AS FLOAT)/NULLIF(SUM(step_cart),0) AS cart_to_purchase_rate
FROM session_funnel
GROUP BY traffic_source
ORDER BY purchase_sessions DESC;

-- 2.3 Funnel theo browser (điểm nghẽn kỹ thuật/UX)
WITH session_funnel AS (
    SELECT
        session_id,
        browser,
        MAX(CASE WHEN event_type = 'product' THEN 1 ELSE 0 END) AS step_product,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS step_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS step_purchase
    FROM TLEcom_events_temp
    GROUP BY session_id, browser
)
SELECT
    browser,
    SUM(step_product) AS product_view_sessions,
    SUM(step_cart) AS cart_sessions,
    SUM(step_purchase) AS purchase_sessions,
    CAST(SUM(step_cart) AS FLOAT)/NULLIF(SUM(step_product),0) AS product_to_cart_rate,
    CAST(SUM(step_purchase) AS FLOAT)/NULLIF(SUM(step_cart),0) AS cart_to_purchase_rate
FROM session_funnel
GROUP BY browser
ORDER BY product_view_sessions DESC;


WITH session_funnel AS (
    SELECT 
        session_id,
        MAX(CASE WHEN event_type = 'product' THEN 1 ELSE 0 END) AS step_product,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS step_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS step_purchase
    FROM TLEcom_events_temp
    GROUP BY session_id
)
SELECT
    SUM(step_product) AS product_view_sessions,
    SUM(step_cart) AS cart_sessions,
    SUM(step_purchase) AS purchase_sessions,
    SUM(step_product) - SUM(step_cart) AS drop_before_cart,
    SUM(step_cart) - SUM(step_purchase) AS drop_after_cart,
    CAST(SUM(step_cart) AS FLOAT) / NULLIF(SUM(step_product),0) AS product_to_cart_rate,
    CAST(SUM(step_purchase) AS FLOAT) / NULLIF(SUM(step_cart),0) AS cart_to_purchase_rate
FROM session_funnel;

-- 3.1 Session có cart nhưng không purchase
WITH session_status AS (
    SELECT
        session_id,
        user_id_fix AS user_id,
        traffic_source,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM TLEcom_events_temp
    GROUP BY session_id, user_id_fix, traffic_source
)
SELECT * INTO #abandoned_sessions
FROM session_status
WHERE has_cart = 1 AND has_purchase = 0;

SELECT COUNT(*) AS total_abandoned_sessions FROM #abandoned_sessions;



--- Abandonment rate theo stock_status
-- BƯỚC 1 + 2: Forward-fill product_id đúng cách
WITH events_raw AS (
    SELECT
        session_id,
        event_type,
        sequence_number,
        created_date_clean,
        product_id_raw
    FROM TLEcom_events_temp 
    WHERE event_type IN ('product','cart')
),
grouped AS (
    SELECT
        *,
        SUM(CASE WHEN product_id_raw IS NOT NULL THEN 1 ELSE 0 END)
            OVER (PARTITION BY session_id ORDER BY sequence_number
                  ROWS UNBOUNDED PRECEDING) AS grp
    FROM events_raw
),
forward_filled AS (
    SELECT
        session_id,
        event_type,
        created_date_clean,
        MAX(product_id_raw) OVER (PARTITION BY session_id, grp) AS product_id
    FROM grouped
)
SELECT session_id, created_date_clean AS cart_time, product_id
INTO TLEcom_cart_product_map
FROM forward_filled
WHERE event_type = 'cart'
  AND product_id IS NOT NULL;


SELECT TOP 1000 * FROM TLEcom_cart_product_map;

-- BƯỚC 3: Running stock level bằng SUM() cộng dồn
WITH inventory_timeline AS (
    SELECT product_id, created_date_clean AS t, 1 AS delta
    FROM TLEcom_inventory_events_temp
    WHERE created_date_clean IS NOT NULL

    UNION ALL

    SELECT product_id, sold_date_clean AS t, -1 AS delta
    FROM TLEcom_inventory_events_temp
    WHERE sold_date_clean IS NOT NULL
)
SELECT
    product_id,
    t,
    SUM(delta) OVER (PARTITION BY product_id ORDER BY t
                     ROWS UNBOUNDED PRECEDING) AS stock_level
INTO TLEcom_stock_timeline
FROM inventory_timeline;

SELECT TOP 1000 * FROM TLEcom_stock_timeline;


-- BƯỚC 4: OUTER APPLY tra đúng stock_level tại cart_time
SELECT
    cpm.session_id,
    cpm.product_id,
    cpm.cart_time,
    CASE WHEN ISNULL(s.stock_level, 0) > 0 THEN 'In stock' ELSE 'Out of stock' END AS stock_status
INTO TLEcom_stock_check
FROM TLEcom_cart_product_map cpm
OUTER APPLY (
    SELECT TOP 1 st.stock_level
    FROM TLEcom_stock_timeline st
    WHERE st.product_id = cpm.product_id
      AND st.t <= cpm.cart_time
    ORDER BY st.t DESC
) s;

SELECT TOP 1000 * FROM TLEcom_stock_check;

-- KẾT QUẢ CUỐI: abandonment rate theo stock_status
SELECT
    sc.stock_status,
    COUNT(*) AS total_carts,
    SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS abandoned_carts,
    CAST(SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*),0) AS abandonment_rate
FROM TLEcom_stock_check sc
JOIN (
    SELECT session_id, MAX(CASE WHEN event_type='purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM TLEcom_events_temp
    GROUP BY session_id
) sp ON sp.session_id = sc.session_id
GROUP BY sc.stock_status;


-- Abandonment theo stock_status x category
SELECT
    sc.stock_status,
    pr.category,
    COUNT(*) AS times_added_to_cart,
    SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS abandoned_count,
    CAST(SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*),0) AS abandonment_rate
FROM TLEcom_stock_check sc
JOIN TLEcom_products pr ON pr.id = sc.product_id
JOIN (
    SELECT session_id, MAX(CASE WHEN event_type='purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM TLEcom_events_temp GROUP BY session_id
) sp ON sp.session_id = sc.session_id
GROUP BY sc.stock_status, pr.category
ORDER BY sc.stock_status, abandonment_rate DESC;

-- Revenue at risk do out-of-stock (theo category, lọc sample nhỏ)
SELECT
    pr.category,
    COUNT(*) AS abandoned_oos_events,
    SUM(pr.retail_price) AS revenue_at_risk,
    AVG(pr.retail_price) AS avg_item_price
FROM TLEcom_stock_check sc
JOIN (
    SELECT session_id, MAX(CASE WHEN event_type='purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM TLEcom_events_temp GROUP BY session_id
) sp ON sp.session_id = sc.session_id
JOIN TLEcom_products pr ON pr.id = sc.product_id
WHERE sc.stock_status = 'Out of stock' AND sp.has_purchase = 0
GROUP BY pr.category
HAVING COUNT(*) >= 200
ORDER BY revenue_at_risk DESC;


WITH session_traffic AS (
    SELECT
        session_id,
        MAX(traffic_source) AS traffic_source
    FROM TLEcom_events_temp
    GROUP BY session_id
)
SELECT
    st.traffic_source,
    COUNT(*) AS times_added_to_cart,
    SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS abandoned_count,
    CAST(SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*),0) AS abandonment_rate
FROM TLEcom_stock_check sc
JOIN session_traffic st ON st.session_id = sc.session_id
JOIN (
    SELECT session_id, MAX(CASE WHEN event_type='purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM TLEcom_events_temp GROUP BY session_id
) sp ON sp.session_id = sc.session_id
GROUP BY st.traffic_source
ORDER BY abandonment_rate DESC;


-- 3.3 Cart abandonment theo price tier (góc nhìn: sản phẩm giá cao có bị bỏ giỏ nhiều hơn không)
SELECT
    CASE
        WHEN pr.retail_price < 25 THEN '1. < $25'
        WHEN pr.retail_price < 50 THEN '2. $25 - $50'
        WHEN pr.retail_price < 100 THEN '3. $50 - $100'
        ELSE '4. >= $100'
    END AS price_tier,
    COUNT(*) AS times_added_to_cart,
    SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS abandoned_count,
    CAST(SUM(CASE WHEN sp.has_purchase = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*),0) AS abandonment_rate
FROM TLEcom_stock_check sc
JOIN TLEcom_products pr ON pr.id = sc.product_id
JOIN (
    SELECT session_id, MAX(CASE WHEN event_type='purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM TLEcom_events_temp GROUP BY session_id
) sp ON sp.session_id = sc.session_id
GROUP BY
    CASE
        WHEN pr.retail_price < 25 THEN '1. < $25'
        WHEN pr.retail_price < 50 THEN '2. $25 - $50'
        WHEN pr.retail_price < 100 THEN '3. $50 - $100'
        ELSE '4. >= $100'
    END
ORDER BY price_tier;


-- 3.4 Product→cart rate theo category (góc nhìn: category nào bị xem nhiều nhưng ít add-to-cart)
WITH product_view_events AS (
    SELECT
        session_id,
        product_id_raw AS product_id,
        sequence_number
    FROM TLEcom_events_temp
    WHERE event_type = 'product' AND product_id_raw IS NOT NULL
),
session_category_view AS (
    SELECT DISTINCT
        pv.session_id,
        pr.category
    FROM product_view_events pv
    JOIN TLEcom_products pr ON pr.id = pv.product_id
),
session_category_cart AS (
    SELECT DISTINCT
        cpm.session_id,
        pr.category
    FROM TLEcom_cart_product_map cpm
    JOIN TLEcom_products pr ON pr.id = cpm.product_id
)
SELECT
    scv.category,
    COUNT(DISTINCT scv.session_id) AS product_view_sessions,
    COUNT(DISTINCT scc.session_id) AS cart_sessions,
    CAST(COUNT(DISTINCT scc.session_id) AS FLOAT) / NULLIF(COUNT(DISTINCT scv.session_id),0) AS product_to_cart_rate
FROM session_category_view scv
LEFT JOIN session_category_cart scc
    ON scc.session_id = scv.session_id AND scc.category = scv.category
GROUP BY scv.category
ORDER BY product_to_cart_rate ASC;


