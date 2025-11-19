/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  env: {
    PRODUCT_SERVICE_URL: process.env.PRODUCT_SERVICE_URL || 'http://product-service:8081',
    ORDER_SERVICE_URL: process.env.ORDER_SERVICE_URL || 'http://order-service:8082',
    USER_SERVICE_URL: process.env.USER_SERVICE_URL || 'http://user-service:8083',
    PAYMENT_SERVICE_URL: process.env.PAYMENT_SERVICE_URL || 'http://payment-service:8084',
  },
}

module.exports = nextConfig
