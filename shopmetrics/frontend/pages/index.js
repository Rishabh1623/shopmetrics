import { useState, useEffect } from 'react'
import Head from 'next/head'
import styles from '../styles/Home.module.css'

export default function Home() {
  const [products, setProducts] = useState([])
  const [cart, setCart] = useState([])
  const [loading, setLoading] = useState(true)

  // Fetch products on load
  useEffect(() => {
    fetchProducts()
  }, [])

  const fetchProducts = async () => {
    try {
      // Mock products for demo
      const mockProducts = [
        { id: 1, name: 'Laptop Pro', price: 1299, image: '💻', category: 'Electronics' },
        { id: 2, name: 'Wireless Mouse', price: 29, image: '🖱️', category: 'Electronics' },
        { id: 3, name: 'Mechanical Keyboard', price: 89, image: '⌨️', category: 'Electronics' },
        { id: 4, name: 'USB-C Hub', price: 49, image: '🔌', category: 'Accessories' },
        { id: 5, name: 'Webcam HD', price: 79, image: '📷', category: 'Electronics' },
        { id: 6, name: 'Headphones', price: 199, image: '🎧', category: 'Audio' },
        { id: 7, name: 'Monitor 27"', price: 399, image: '🖥️', category: 'Electronics' },
        { id: 8, name: 'Desk Lamp', price: 39, image: '💡', category: 'Accessories' },
      ]
      setProducts(mockProducts)
      setLoading(false)
    } catch (error) {
      console.error('Error fetching products:', error)
      setLoading(false)
    }
  }

  const addToCart = (product) => {
    setCart([...cart, product])
    alert(`${product.name} added to cart!`)
  }

  const getTotalPrice = () => {
    return cart.reduce((total, item) => total + item.price, 0)
  }

  return (
    <div className={styles.container}>
      <Head>
        <title>ShopMetrics - E-Commerce Platform</title>
        <meta name="description" content="ShopMetrics E-Commerce Platform" />
      </Head>

      {/* Header */}
      <header className={styles.header}>
        <div className={styles.logo}>
          <h1>🛒 ShopMetrics</h1>
        </div>
        <nav className={styles.nav}>
          <a href="/">Home</a>
          <a href="#products">Products</a>
          <a href="#cart">Cart ({cart.length})</a>
        </nav>
      </header>

      {/* Hero Section */}
      <section className={styles.hero}>
        <h2>Welcome to ShopMetrics</h2>
        <p>Your one-stop shop for quality products</p>
        <div className={styles.stats}>
          <div className={styles.stat}>
            <span className={styles.statNumber}>1000+</span>
            <span className={styles.statLabel}>Products</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statNumber}>50K+</span>
            <span className={styles.statLabel}>Customers</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statNumber}>99%</span>
            <span className={styles.statLabel}>Satisfaction</span>
          </div>
        </div>
      </section>

      {/* Products Section */}
      <section id="products" className={styles.productsSection}>
        <h2>Featured Products</h2>
        {loading ? (
          <p>Loading products...</p>
        ) : (
          <div className={styles.productsGrid}>
            {products.map((product) => (
              <div key={product.id} className={styles.productCard}>
                <div className={styles.productImage}>{product.image}</div>
                <h3>{product.name}</h3>
                <p className={styles.category}>{product.category}</p>
                <p className={styles.price}>${product.price}</p>
                <button 
                  className={styles.addButton}
                  onClick={() => addToCart(product)}
                >
                  Add to Cart
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Cart Section */}
      <section id="cart" className={styles.cartSection}>
        <h2>Shopping Cart</h2>
        {cart.length === 0 ? (
          <p>Your cart is empty</p>
        ) : (
          <div className={styles.cart}>
            <div className={styles.cartItems}>
              {cart.map((item, index) => (
                <div key={index} className={styles.cartItem}>
                  <span>{item.image} {item.name}</span>
                  <span>${item.price}</span>
                </div>
              ))}
            </div>
            <div className={styles.cartTotal}>
              <strong>Total: ${getTotalPrice()}</strong>
              <button className={styles.checkoutButton}>
                Proceed to Checkout
              </button>
            </div>
          </div>
        )}
      </section>

      {/* Footer */}
      <footer className={styles.footer}>
        <p>© 2024 ShopMetrics - Monitored by Prometheus & Grafana</p>
        <p>
          <a href="http://localhost:3000" target="_blank">Grafana</a> | 
          <a href="http://localhost:9090" target="_blank">Prometheus</a>
        </p>
      </footer>
    </div>
  )
}
