-- Initialize E-commerce Database
-- Run this script against your RDS PostgreSQL database

-- Create tables
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    image_url VARCHAR(500),
    stock INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    total DECIMAL(10, 2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    price DECIMAL(10, 2) NOT NULL
);

-- Seed initial products
INSERT INTO products (name, description, price, image_url, stock) VALUES
('Wireless Headphones', 'Premium noise-canceling headphones', 89.99, 'https://via.placeholder.com/300x300?text=Headphones', 50),
('Smart Watch', 'Fitness tracker with heart rate monitor', 199.99, 'https://via.placeholder.com/300x300?text=Smart+Watch', 30),
('Laptop Stand', 'Ergonomic aluminum laptop stand', 45.99, 'https://via.placeholder.com/300x300?text=Laptop+Stand', 75),
('USB-C Hub', '7-in-1 USB-C multiport adapter', 39.99, 'https://via.placeholder.com/300x300?text=USB-C+Hub', 100),
('Mechanical Keyboard', 'RGB backlit gaming keyboard', 129.99, 'https://via.placeholder.com/300x300?text=Keyboard', 40),
('Wireless Mouse', 'Ergonomic wireless mouse', 29.99, 'https://via.placeholder.com/300x300?text=Mouse', 80),
('Webcam HD', '1080p HD webcam with microphone', 69.99, 'https://via.placeholder.com/300x300?text=Webcam', 60),
('Phone Case', 'Protective silicone phone case', 14.99, 'https://via.placeholder.com/300x300?text=Phone+Case', 200)
ON CONFLICT DO NOTHING;

-- Verify
SELECT 'Database initialized successfully!' AS status;
SELECT COUNT(*) AS product_count FROM products;
