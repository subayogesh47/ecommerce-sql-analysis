-- =====================================================
-- File 2 of 3: Sample data (generated with recursive CTEs)
-- Run AFTER schema.sql
-- Data is pseudo-random but repeatable (CRC32 hash of the row number),
-- with skewed distributions so the analysis looks realistic:
-- a few heavy buyers, many one-time buyers, popular vs niche products.
-- =====================================================
USE ecommerce_db;

-- 150 customers, signing up between Jan 2024 and Mar 2025
INSERT INTO customers (name, email, city, signup_date)
WITH RECURSIVE seq AS (
    SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 150
)
SELECT CONCAT(
           ELT(1 + MOD(n, 10), 'Aarav','Priya','Rohan','Ananya','Karthik','Meera','Vikram','Sneha','Arjun','Divya'),
           ' ',
           ELT(1 + MOD(n * 3 + FLOOR(n / 10), 10), 'Iyer','Sharma','Reddy','Nair','Patel','Singh','Das','Menon','Gupta','Rao')
       ),
       CONCAT('customer', n, '@example.com'),
       ELT(1 + FLOOR(6 * POW((CRC32(CONCAT('s200_', n)) / 4294967296), 1.3)),
           'Chennai','Bengaluru','Mumbai','Delhi','Hyderabad','Pune'),
       DATE_ADD('2024-01-01', INTERVAL FLOOR((CRC32(CONCAT('s100_', n)) / 4294967296) * 456) DAY)
FROM seq;

-- 12 products
INSERT INTO products (product_name, category, price) VALUES
('Wireless Earbuds',   'Electronics', 2499.00),
('Smart Watch',        'Electronics', 4999.00),
('Bluetooth Speaker',  'Electronics', 1799.00),
('Power Bank',         'Electronics',  999.00),
('Running Shoes',      'Fashion',     3199.00),
('Denim Jacket',       'Fashion',     2199.00),
('Backpack',           'Fashion',     1499.00),
('Coffee Maker',       'Home',        3499.00),
('Table Lamp',         'Home',         799.00),
('Bedsheet Set',       'Home',        1299.00),
('SQL Mastery Book',   'Books',        499.00),
('Data Analytics Book','Books',        699.00);

-- 600 orders from Jun 2024 to May 2025 (12 full months).
-- Customer choice is skewed: low customer_ids order far more often.
-- Order date is never earlier than the customer's signup date.
INSERT INTO orders (customer_id, order_date, status)
WITH RECURSIVE seq AS (
    SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 600
),
base AS (
    SELECT n, 1 + FLOOR(150 * POW((CRC32(CONCAT('s5000_', n)) / 4294967296), 1.8)) AS cid
    FROM seq
)
SELECT b.cid AS customer_id,
       DATE_ADD(GREATEST(c.signup_date, DATE '2024-06-01'),
                INTERVAL FLOOR((CRC32(CONCAT('s9000_', b.n)) / 4294967296) *
                    (DATEDIFF(DATE '2025-05-31', GREATEST(c.signup_date, DATE '2024-06-01')) + 1)) DAY
       ) AS order_date,
       CASE WHEN (CRC32(CONCAT('s7000_', b.n)) / 4294967296) < 0.72 THEN 'Delivered'
            WHEN (CRC32(CONCAT('s7000_', b.n)) / 4294967296) < 0.82 THEN 'Shipped'
            WHEN (CRC32(CONCAT('s7000_', b.n)) / 4294967296) < 0.90 THEN 'Cancelled'
            ELSE 'Returned' END AS status
FROM base b
JOIN customers c ON c.customer_id = b.cid
ORDER BY order_date, b.n;

-- Every order gets a first item (popular products are picked more often)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT t.order_id, p.product_id, 1 + FLOOR((CRC32(CONCAT('s21000_', t.order_id)) / 4294967296) * 3), p.price
FROM (
    SELECT order_id, 1 + FLOOR(12 * POW((CRC32(CONCAT('s20000_', order_id)) / 4294967296), 1.5)) AS pid
    FROM orders
) t
JOIN products p ON p.product_id = t.pid;

-- About half of the orders get a second, different item
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT t.order_id, p.product_id, 1 + FLOOR((CRC32(CONCAT('s24000_', t.order_id)) / 4294967296) * 2), p.price
FROM (
    SELECT order_id,
           1 + MOD(1 + FLOOR(12 * POW((CRC32(CONCAT('s20000_', order_id)) / 4294967296), 1.5))
                     + FLOOR((CRC32(CONCAT('s22000_', order_id)) / 4294967296) * 11), 12) AS pid
    FROM orders
    WHERE (CRC32(CONCAT('s23000_', order_id)) / 4294967296) < 0.5
) t
JOIN products p ON p.product_id = t.pid;

-- Payments for every non-cancelled order, with a weighted payment mix
INSERT INTO payments (order_id, method, amount, payment_date)
SELECT o.order_id,
       CASE WHEN (CRC32(CONCAT('s30000_', o.order_id)) / 4294967296) < 0.40 THEN 'UPI'
            WHEN (CRC32(CONCAT('s30000_', o.order_id)) / 4294967296) < 0.65 THEN 'Credit Card'
            WHEN (CRC32(CONCAT('s30000_', o.order_id)) / 4294967296) < 0.85 THEN 'Debit Card'
            ELSE 'COD' END,
       SUM(oi.quantity * oi.unit_price),
       o.order_date
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status <> 'Cancelled'
GROUP BY o.order_id, o.order_date;

-- Quick sanity check
SELECT (SELECT COUNT(*) FROM customers)   AS customers,
       (SELECT COUNT(*) FROM products)    AS products,
       (SELECT COUNT(*) FROM orders)      AS orders,
       (SELECT COUNT(*) FROM order_items) AS order_items,
       (SELECT COUNT(*) FROM payments)    AS payments;
