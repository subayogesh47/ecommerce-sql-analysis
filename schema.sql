-- =====================================================
-- E-commerce Sales Analysis | Database: MySQL 8+
-- File 1 of 3: Schema (tables, keys, indexes)
-- =====================================================

DROP DATABASE IF EXISTS ecommerce_db;
CREATE DATABASE ecommerce_db;
USE ecommerce_db;

CREATE TABLE customers (
    customer_id   INT AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    email         VARCHAR(150) NOT NULL UNIQUE,
    city          VARCHAR(50),
    signup_date   DATE NOT NULL
);

CREATE TABLE products (
    product_id    INT AUTO_INCREMENT PRIMARY KEY,
    product_name  VARCHAR(100) NOT NULL,
    category      VARCHAR(50)  NOT NULL,
    price         DECIMAL(10,2) NOT NULL CHECK (price > 0)
);

CREATE TABLE orders (
    order_id      INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   INT NOT NULL,
    order_date    DATE NOT NULL,
    status        ENUM('Delivered','Shipped','Cancelled','Returned') NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id      INT NOT NULL,
    product_id    INT NOT NULL,
    quantity      INT NOT NULL CHECK (quantity > 0),
    unit_price    DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE TABLE payments (
    payment_id    INT AUTO_INCREMENT PRIMARY KEY,
    order_id      INT NOT NULL,
    method        VARCHAR(20) NOT NULL,
    amount        DECIMAL(12,2) NOT NULL,
    payment_date  DATE NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

-- Indexes on join columns
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_items_order     ON order_items(order_id);
CREATE INDEX idx_items_product   ON order_items(product_id);
CREATE INDEX idx_payments_order  ON payments(order_id);
