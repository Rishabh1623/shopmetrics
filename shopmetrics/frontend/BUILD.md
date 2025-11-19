# Frontend Build Instructions

## Quick Build & Deploy

### Option 1: Build Docker Image Locally

```bash
cd shopmetrics/frontend

# Build Docker image
docker build -t shopmetrics/frontend:latest .

# Test locally
docker run -p 3000:3000 shopmetrics/frontend:latest

# Access: http://localhost:3000
```

### Option 2: Deploy to Kubernetes Directly

```bash
# Deploy to Kubernetes
kubectl apply -f deployment.yaml

# Port forward to access
kubectl port-forward -n shopmetrics svc/frontend 8080:80

# Access: http://localhost:8080
```

## What You'll See

A beautiful e-commerce website with:
- 🏠 Homepage with hero section
- 🛍️ Product catalog (8 demo products)
- 🛒 Shopping cart functionality
- 📊 Stats display
- 💳 Checkout button
- 📱 Responsive design

## Features

- ✅ Modern UI with gradient design
- ✅ Product grid layout
- ✅ Add to cart functionality
- ✅ Cart total calculation
- ✅ Responsive (mobile-friendly)
- ✅ Links to Grafana & Prometheus

## Tech Stack

- **Framework:** Next.js 14
- **Language:** React 18
- **Styling:** CSS Modules
- **Port:** 3000

## Development

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start
```

## Customization

Edit these files to customize:
- `pages/index.js` - Main page content
- `styles/Home.module.css` - Styling
- `styles/globals.css` - Global styles

## Integration with Backend

The frontend is configured to connect to backend services:
- Product Service: http://product-service:8081
- Order Service: http://order-service:8082
- User Service: http://user-service:8083
- Payment Service: http://payment-service:8084

These are automatically resolved within the Kubernetes cluster.
