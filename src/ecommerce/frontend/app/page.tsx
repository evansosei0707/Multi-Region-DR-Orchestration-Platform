'use client';

import { useEffect, useState } from 'react';
import axios from 'axios';
import Link from 'next/link';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

interface Product {
    id: number;
    name: string;
    description: string;
    price: number;
    image_url: string;
    stock: number;
}

export default function Home() {
    const [products, setProducts] = useState<Product[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [region, setRegion] = useState('');
    const [cart, setCart] = useState<{ [key: number]: number }>({});

    useEffect(() => {
        fetchProducts();
    }, []);

    const fetchProducts = async () => {
        try {
            const response = await axios.get(`${API_URL}/api/products`);
            setProducts(response.data.products);
            setRegion(response.data.region);
            setLoading(false);
        } catch (err) {
            setError('Failed to load products. Please try again later.');
            setLoading(false);
        }
    };

    const addToCart = (productId: number) => {
        setCart(prev => ({
            ...prev,
            [productId]: (prev[productId] || 0) + 1
        }));
    };

    const getCartCount = () => {
        return Object.values(cart).reduce((sum, qty) => sum + qty, 0);
    };

    if (loading) {
        return (
            <div className="min-h-screen flex items-center justify-center">
                <div className="text-2xl">Loading...</div>
            </div>
        );
    }

    if (error) {
        return (
            <div className="min-h-screen flex items-center justify-center">
                <div className="text-red-500 text-xl">{error}</div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
            {/* Header */}
            <header className="bg-white shadow-md sticky top-0 z-10">
                <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
                    <div className="flex justify-between items-center">
                        <div>
                            <h1 className="text-3xl font-bold text-indigo-600">DR E-commerce</h1>
                            <p className="text-sm text-gray-500">Serving from: {region || 'unknown'}</p>
                        </div>
                        {getCartCount() > 0 && (
                            <Link href="/checkout" className="relative">
                                <div className="bg-indigo-600 text-white px-6 py-3 rounded-lg hover:bg-indigo-700 transition">
                                    🛒 Cart ({getCartCount()})
                                </div>
                            </Link>
                        )}
                    </div>
                </div>
            </header>

            {/* Products Grid */}
            <main className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
                <h2 className="text-2xl font-bold text-gray-800 mb-6">Our Products</h2>

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
                    {products.map((product) => (
                        <div key={product.id} className="bg-white rounded-xl shadow-lg overflow-hidden hover:shadow-2xl transition-shadow duration-300">
                            <div className="aspect-square bg-gray-200 flex items-center justify-center">
                                <img
                                    src={product.image_url}
                                    alt={product.name}
                                    className="w-full h-full object-cover"
                                />
                            </div>

                            <div className="p-4">
                                <h3 className="font-bold text-lg text-gray-800 mb-2">{product.name}</h3>
                                <p className="text-gray-600 text-sm mb-3 line-clamp-2">{product.description}</p>

                                <div className="flex justify-between items-center mb-3">
                                    <span className="text-2xl font-bold text-indigo-600">${product.price}</span>
                                    <span className="text-sm text-gray-500">{product.stock} in stock</span>
                                </div>

                                <button
                                    onClick={() => addToCart(product.id)}
                                    disabled={product.stock === 0}
                                    className="w-full bg-indigo-600 text-white py-2 px-4 rounded-lg hover:bg-indigo-700 disabled:bg-gray-300 disabled:cursor-not-allowed transition"
                                >
                                    {product.stock > 0 ? 'Add to Cart' : 'Out of Stock'}
                                </button>

                                {cart[product.id] > 0 && (
                                    <div className="mt-2 text-center text-sm text-green-600 font-semibold">
                                        {cart[product.id]} in cart
                                    </div>
                                )}
                            </div>
                        </div>
                    ))}
                </div>
            </main>

            {/* Footer */}
            <footer className="bg-gray-800 text-white mt-12 py-6">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
                    <p>Multi-Region DR E-commerce Platform</p>
                    <p className="text-sm text-gray-400 mt-2">Active Region: {region}</p>
                </div>
            </footer>
        </div>
    );
}
