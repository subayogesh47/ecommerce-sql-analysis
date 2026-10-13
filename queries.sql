-- =====================================================
-- File 3 of 3: Business questions and analysis queries
-- =====================================================
USE ecommerce_db;

-- ---------- SECTION 1: KPIs and JOINs ----------

-- Q1. What are total revenue, delivered orders and average order value?
SELECT COUNT(DISTINCT o.order_id)  AS delivered_orders,
       ROUND(SUM(p.amount), 2)     AS total_revenue,
       ROUND(AVG(p.amount), 2)     AS avg_order_value
FROM orders o
JOIN payments p ON p.order_id = o.order_id
WHERE o.status = 'Delivered';

-- Q2. What share of orders end up cancelled or returned?
SELECT status,
       COUNT(*) AS orders,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders
FROM orders
GROUP BY status
ORDER BY orders DESC;

-- Q3. Which cities generate the most revenue?
SELECT c.city,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(p.amount), 2)    AS revenue
FROM customers c
JOIN orders o   ON o.customer_id = c.customer_id
JOIN payments p ON p.order_id = o.order_id
WHERE o.status = 'Delivered'
GROUP BY c.city
ORDER BY revenue DESC;

-- Q4. Which customers never placed an order? (LEFT JOIN + NULL check)
SELECT c.customer_id, c.name, c.signup_date
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

-- Q5. Which payment methods are most popular?
SELECT method,
       COUNT(*) AS payments,
       ROUND(SUM(amount), 2) AS total_amount,
       ROUND(100 * SUM(amount) / SUM(SUM(amount)) OVER (), 2) AS pct_of_revenue
FROM payments
GROUP BY method
ORDER BY total_amount DESC;

-- ---------- SECTION 2: CTEs and window functions ----------

-- Q6. Monthly revenue with month-over-month growth (CTE + LAG)
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS ym,
           SUM(p.amount) AS revenue
    FROM orders o
    JOIN payments p ON p.order_id = o.order_id
    WHERE o.status = 'Delivered'
    GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
)
SELECT ym,
       ROUND(revenue, 2) AS revenue,
       ROUND(LAG(revenue) OVER (ORDER BY ym), 2) AS prev_month,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY ym))
                 / LAG(revenue) OVER (ORDER BY ym), 2) AS mom_growth_pct
FROM monthly
ORDER BY ym;

-- Q7. Cumulative (running total) revenue by month
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS ym,
           SUM(p.amount) AS revenue
    FROM orders o
    JOIN payments p ON p.order_id = o.order_id
    WHERE o.status = 'Delivered'
    GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
)
SELECT ym,
       ROUND(revenue, 2) AS revenue,
       ROUND(SUM(revenue) OVER (ORDER BY ym), 2) AS running_total
FROM monthly
ORDER BY ym;

-- Q8. Top 3 products in each category by revenue (RANK + PARTITION BY)
WITH product_rev AS (
    SELECT pr.category,
           pr.product_name,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM order_items oi
    JOIN orders o    ON o.order_id = oi.order_id
    JOIN products pr ON pr.product_id = oi.product_id
    WHERE o.status = 'Delivered'
    GROUP BY pr.category, pr.product_name
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk
    FROM product_rev
)
SELECT category, product_name, ROUND(revenue, 2) AS revenue, rnk
FROM ranked
WHERE rnk <= 3
ORDER BY category, rnk;

-- Q9. Top 10 customers by lifetime spend
SELECT c.customer_id,
       c.name,
       c.city,
       ROUND(SUM(p.amount), 2) AS lifetime_spend,
       DENSE_RANK() OVER (ORDER BY SUM(p.amount) DESC) AS spend_rank
FROM customers c
JOIN orders o   ON o.customer_id = c.customer_id
JOIN payments p ON p.order_id = o.order_id
WHERE o.status = 'Delivered'
GROUP BY c.customer_id, c.name, c.city
ORDER BY spend_rank
LIMIT 10;

-- Q10. Days between consecutive orders per customer (LAG)
SELECT customer_id,
       order_id,
       order_date,
       DATEDIFF(order_date,
                LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date)
       ) AS days_since_prev_order
FROM orders
WHERE status <> 'Cancelled'
ORDER BY customer_id, order_date
LIMIT 30;

-- Q11. Which day of the week gets the most orders?
SELECT DAYNAME(order_date) AS weekday,
       COUNT(*) AS orders
FROM orders
GROUP BY DAYNAME(order_date), DAYOFWEEK(order_date)
ORDER BY DAYOFWEEK(order_date);

-- ---------- SECTION 3: Customer analytics ----------

-- Q12. New vs repeat customers
WITH order_counts AS (
    SELECT customer_id, COUNT(*) AS total_orders
    FROM orders
    WHERE status <> 'Cancelled'
    GROUP BY customer_id
)
SELECT CASE WHEN total_orders = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM order_counts
GROUP BY customer_type;

-- Q13. Cohort retention: of customers who first ordered in month X,
--      what % ordered again N months later?
WITH first_order AS (
    SELECT customer_id,
           DATE_SUB(MIN(order_date), INTERVAL DAYOFMONTH(MIN(order_date)) - 1 DAY) AS cohort_month
    FROM orders
    WHERE status <> 'Cancelled'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT o.customer_id,
           f.cohort_month,
           TIMESTAMPDIFF(MONTH, f.cohort_month,
               DATE_SUB(o.order_date, INTERVAL DAYOFMONTH(o.order_date) - 1 DAY)) AS month_number
    FROM orders o
    JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.status <> 'Cancelled'
),
cohort_counts AS (
    SELECT cohort_month, month_number, COUNT(*) AS customers
    FROM activity
    GROUP BY cohort_month, month_number
)
SELECT cohort_month,
       month_number,
       customers,
       ROUND(100 * customers /
             FIRST_VALUE(customers) OVER (PARTITION BY cohort_month ORDER BY month_number), 1
       ) AS retention_pct
FROM cohort_counts
ORDER BY cohort_month, month_number;

-- Q14. RFM segmentation (Recency, Frequency, Monetary) using NTILE
WITH rfm_base AS (
    SELECT o.customer_id,
           DATEDIFF((SELECT MAX(order_date) FROM orders), MAX(o.order_date)) AS recency_days,
           COUNT(DISTINCT o.order_id) AS frequency,
           SUM(p.amount) AS monetary
    FROM orders o
    JOIN payments p ON p.order_id = o.order_id
    WHERE o.status = 'Delivered'
    GROUP BY o.customer_id
),
scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(4) OVER (ORDER BY frequency)         AS f_score,
           NTILE(4) OVER (ORDER BY monetary)          AS m_score
    FROM rfm_base
)
SELECT customer_id, recency_days, frequency, ROUND(monetary, 2) AS monetary,
       r_score, f_score, m_score,
       CASE
           WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champion'
           WHEN r_score >= 3                                   THEN 'Active'
           WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
           ELSE 'Needs Attention'
       END AS segment
FROM scored
ORDER BY monetary DESC;

-- ---------- SECTION 4: Views and stored procedure ----------

-- A reusable view: one row per order with customer and amount
CREATE OR REPLACE VIEW vw_order_summary AS
SELECT o.order_id, o.order_date, o.status,
       c.customer_id, c.name AS customer_name, c.city,
       COALESCE(p.amount, 0) AS amount,
       p.method AS payment_method
FROM orders o
JOIN customers c     ON c.customer_id = o.customer_id
LEFT JOIN payments p ON p.order_id = o.order_id;

SELECT * FROM vw_order_summary LIMIT 10;

-- Stored procedure: summary for a single customer
-- (If you run this in a plain .sql file via the mysql client, keep the DELIMITER lines)
DROP PROCEDURE IF EXISTS sp_customer_summary;
DELIMITER //
CREATE PROCEDURE sp_customer_summary(IN p_customer_id INT)
BEGIN
    SELECT c.customer_id, c.name, c.city,
           COUNT(DISTINCT o.order_id)  AS total_orders,
           COALESCE(SUM(p.amount), 0)  AS total_spent
    FROM customers c
    LEFT JOIN orders o   ON o.customer_id = c.customer_id
    LEFT JOIN payments p ON p.order_id = o.order_id
    WHERE c.customer_id = p_customer_id
    GROUP BY c.customer_id, c.name, c.city;
END //
DELIMITER ;

CALL sp_customer_summary(5);

-- ---------- SECTION 5: Query optimization ----------

-- BEFORE: full table scan (look at "type" = ALL and "rows" in the output)
EXPLAIN SELECT * FROM orders
WHERE order_date BETWEEN '2024-09-01' AND '2024-09-30';

-- Add an index (run once; it errors if the index already exists)
CREATE INDEX idx_orders_date ON orders(order_date);

-- AFTER: index range scan (type = range, far fewer rows examined)
EXPLAIN SELECT * FROM orders
WHERE order_date BETWEEN '2024-09-01' AND '2024-09-30';
