import os
import json
from flask import Flask, jsonify, request
from flask_cors import CORS
import psycopg2
from psycopg2.extras import RealDictCursor
import boto3
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Get AWS region from environment
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
REGION_TYPE = os.environ.get('REGION_TYPE', 'primary')
S3_BUCKET = os.environ.get('S3_BUCKET', '')

# Get database credentials from Secrets Manager
def get_db_credentials():
    secrets_client = boto3.client('secretsmanager', region_name=AWS_REGION)
    secret_name = os.environ.get('DB_SECRET')
    
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return secret
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        return None

# Database connection
def get_db_connection():
    creds = get_db_credentials()
    if not creds:
        return None
    
    try:
        conn = psycopg2.connect(
            host=creds['host'],
            database=creds['dbname'],
            user=creds['username'],
            password=creds['password'],
            port=creds.get('port', 5432)
        )
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        return None

# Health check endpoint
@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint for ALB target group"""
    db_status = 'healthy'
    
    # Test database connection
    try:
        conn = get_db_connection()
        if conn:
            conn.close()
        else:
            db_status = 'unhealthy'
    except:
        db_status = 'unhealthy'
    
    return jsonify({
        'status': 'healthy' if db_status == 'healthy' else 'degraded',
        'region': AWS_REGION,
        'region_type': REGION_TYPE,
        'database': db_status,
        'timestamp': datetime.utcnow().isoformat()
    }), 200 if db_status == 'healthy' else 503

# Get all products
@app.route('/api/products', methods=['GET'])
def get_products():
    """Get all products from database"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('''
            SELECT id, name, description, price, image_url, stock
            FROM products
            WHERE stock > 0
            ORDER BY name
        ''')
        products = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({
            'products': products,
            'region': AWS_REGION,
            'region_type': REGION_TYPE
        }), 200
    except Exception as e:
        print(f"Error fetching products: {e}")
        return jsonify({'error': str(e)}), 500

# Get product by ID
@app.route('/api/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    """Get a single product by ID"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('''
            SELECT id, name, description, price, image_url, stock
            FROM products
            WHERE id = %s
        ''', (product_id,))
        product = cur.fetchone()
        cur.close()
        conn.close()
        
        if product:
            return jsonify({
                'product': product,
                'region': AWS_REGION
            }), 200
        else:
            return jsonify({'error': 'Product not found'}), 404
    except Exception as e:
        print(f"Error fetching product: {e}")
        return jsonify({'error': str(e)}), 500

# Add item to cart (session-based for simplicity)
@app.route('/api/cart', methods=['POST'])
def add_to_cart():
    """Add item to cart"""
    data = request.get_json()
    
    if not data or 'product_id' not in data or 'quantity' not in data:
        return jsonify({'error': 'Missing product_id or quantity'}), 400
    
    # For simplicity, we'll just validate the product exists
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT stock FROM products WHERE id = %s', (data['product_id'],))
        product = cur.fetchone()
        cur.close()
        conn.close()
        
        if not product:
            return jsonify({'error': 'Product not found'}), 404
        
        if product['stock'] < data['quantity']:
            return jsonify({'error': 'Insufficient stock'}), 400
        
        return jsonify({
            'message': 'Item added to cart',
            'product_id': data['product_id'],
            'quantity': data['quantity']
        }), 200
    except Exception as e:
        print(f"Error adding to cart: {e}")
        return jsonify({'error': str(e)}), 500

# Create order
@app.route('/api/orders', methods=['POST'])
def create_order():
    """Create a new order"""
    data = request.get_json()
    
    if not data or 'items' not in data:
        return jsonify({'error': 'Missing items in request'}), 400
    
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Calculate total
        total = 0
        for item in data['items']:
            cur.execute('SELECT price, stock FROM products WHERE id = %s', (item['product_id'],))
            product = cur.fetchone()
            if not product:
                cur.close()
                conn.close()
                return jsonify({'error': f'Product {item["product_id"]} not found'}), 404
            
            if product['stock'] < item['quantity']:
                cur.close()
                conn.close()
                return jsonify({'error': f'Insufficient stock for product {item["product_id"]}'}), 400
            
            total += product['price'] * item['quantity']
        
        # Create order
        cur.execute('''
            INSERT INTO orders (total, status, created_at)
            VALUES (%s, %s, %s)
            RETURNING id
        ''', (total, 'pending', datetime.utcnow()))
        order_id = cur.fetchone()['id']
        
        # Add order items and update stock
        for item in data['items']:
            cur.execute('''
                INSERT INTO order_items (order_id, product_id, quantity, price)
                SELECT %s, %s, %s, price FROM products WHERE id = %s
            ''', (order_id, item['product_id'], item['quantity'], item['product_id']))
            
            cur.execute('''
                UPDATE products SET stock = stock - %s WHERE id = %s
            ''', (item['quantity'], item['product_id']))
        
        conn.commit()
        cur.close()
        conn.close()
        
        return jsonify({
            'message': 'Order created successfully',
            'order_id': order_id,
            'total': float(total),
            'region': AWS_REGION
        }), 201
    except Exception as e:
        print(f"Error creating order: {e}")
        if conn:
            conn.rollback()
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # Run on port 8080 for ECS
    app.run(host='0.0.0.0', port=8080, debug=False)
