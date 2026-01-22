import os
import json
import psycopg2
import boto3

def get_db_credentials():
    """Get database credentials from Secrets Manager"""
    AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
    secret_name = os.environ.get('DB_SECRET')
    
    secrets_client = boto3.client('secretsmanager', region_name=AWS_REGION)
    
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return secret
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        raise

def init_database():
    """Initialize database schema and seed data"""
    creds = get_db_credentials()
    
    conn = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password'],
        port=creds.get('port', 5432)
    )
    
    cur = conn.cursor()
    
    # Create tables
    cur.execute('''
        CREATE TABLE IF NOT EXISTS products (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            description TEXT,
            price DECIMAL(10, 2) NOT NULL,
            image_url VARCHAR(500),
            stock INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ''')
    
    cur.execute('''
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            total DECIMAL(10, 2) NOT NULL,
            status VARCHAR(50) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ''')
    
    cur.execute('''
        CREATE TABLE IF NOT EXISTS order_items (
            id SERIAL PRIMARY KEY,
            order_id INTEGER REFERENCES orders(id),
            product_id INTEGER REFERENCES products(id),
            quantity INTEGER NOT NULL,
            price DECIMAL(10, 2) NOT NULL
        );
    ''')
    
    # Seed initial products if table is empty
    cur.execute('SELECT COUNT(*) FROM products')
    count = cur.fetchone()[0]
    
    if count == 0:
        print("Seeding initial products...")
        products = [
            ('Wireless Headphones', 'Premium noise-canceling headphones', 89.99, 'https://via.placeholder.com/300x300?text=Headphones', 50),
            ('Smart Watch', 'Fitness tracker with heart rate monitor', 199.99, 'https://via.placeholder.com/300x300?text=Smart+Watch', 30),
            ('Laptop Stand', 'Ergonomic aluminum laptop stand', 45.99, 'https://via.placeholder.com/300x300?text=Laptop+Stand', 75),
            ('USB-C Hub', '7-in-1 USB-C multiport adapter', 39.99, 'https://via.placeholder.com/300x300?text=USB-C+Hub', 100),
            ('Mechanical Keyboard', 'RGB backlit gaming keyboard', 129.99, 'https://via.placeholder.com/300x300?text=Keyboard', 40),
            ('Wireless Mouse', 'Ergonomic wireless mouse', 29.99, 'https://via.placeholder.com/300x300?text=Mouse', 80),
            ('Webcam HD', '1080p HD webcam with microphone', 69.99, 'https://via.placeholder.com/300x300?text=Webcam', 60),
            ('Phone Case', 'Protective silicone phone case', 14.99, 'https://via.placeholder.com/300x300?text=Phone+Case', 200),
        ]
        
        cur.executemany('''
            INSERT INTO products (name, description, price, image_url, stock)
            VALUES (%s, %s, %s, %s, %s)
        ''', products)
        print(f"Inserted {len(products)} products")
    
    conn.commit()
    cur.close()
    conn.close()
    print("Database initialized successfully!")

if __name__ == '__main__':
    init_database()
