from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from pydantic import BaseModel, validator
from typing import List, Optional
from datetime import datetime
from decimal import Decimal
import asyncpg
import aioredis
import boto3
import json
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'path', 'status']
)

http_request_duration = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration',
    ['method', 'path']
)

orders_created_total = Counter(
    'orders_created_total',
    'Total orders created',
    ['status']
)

orders_completed_total = Counter(
    'orders_completed_total',
    'Total orders completed'
)

orders_cancelled_total = Counter(
    'orders_cancelled_total',
    'Total orders cancelled'
)

order_value_total = Counter(
    'order_value_total',
    'Total order value',
    ['currency']
)

order_processing_duration = Histogram(
    'order_processing_duration_seconds',
    'Order processing duration'
)

cart_created_total = Counter(
    'cart_created_total',
    'Total carts created'
)

cart_abandoned_total = Counter(
    'cart_abandoned_total',
    'Total carts abandoned'
)

db_connection_pool_active = Gauge(
    'database_connection_pool_active',
    'Active database connections'
)

db_connection_pool_max = Gauge(
    'database_connection_pool_max',
    'Maximum database connections'
)

# FastAPI app
app = FastAPI(title="ShopMetrics Order Service", version="1.0.0")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection pool
db_pool = None
redis_client = None
sqs_client = None

# Pydantic models
class CartItem(BaseModel):
    product_id: str
    quantity: int
    price: Decimal

    @validator('quantity')
    def quantity_must_be_positive(cls, v):
        if v <= 0:
            raise ValueError('Quantity must be positive')
        return v

class CreateCartRequest(BaseModel):
    user_id: str
    items: List[CartItem]

class CreateOrderRequest(BaseModel):
    user_id: str
    cart_id: str
    shipping_address_id: str
    billing_address_id: str
    payment_method_id: str

class OrderResponse(BaseModel):
    id: str
    user_id: str
    status: str
    total: Decimal
    currency: str
    created_at: datetime
    items: List[dict]

# Startup/Shutdown events
@app.on_event("startup")
async def startup():
    global db_pool, redis_client, sqs_client
    
    # Database connection
    database_url = os.getenv('DATABASE_URL', 'postgresql://user:password@localhost:5432/orders')
    db_pool = await asyncpg.create_pool(
        database_url,
        min_size=5,
        max_size=20
    )
    db_connection_pool_max.set(20)
    logger.info("Database pool created")
    
    # Redis connection
    redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379')
    redis_client = await aioredis.from_url(redis_url)
    logger.info("Redis connected")
    
    # SQS client
    sqs_client = boto3.client('sqs', region_name=os.getenv('AWS_REGION', 'us-east-1'))
    logger.info("SQS client initialized")

@app.on_event("shutdown")
async def shutdown():
    if db_pool:
        await db_pool.close()
    if redis_client:
        await redis_client.close()

# Middleware for metrics
@app.middleware("http")
async def metrics_middleware(request, call_next):
    import time
    start_time = time.time()
    
    response = await call_next(request)
    
    duration = time.time() - start_time
    http_requests_total.labels(
        method=request.method,
        path=request.url.path,
        status=response.status_code
    ).inc()
    http_request_duration.labels(
        method=request.method,
        path=request.url.path
    ).observe(duration)
    
    return response

# Health checks
@app.get("/health")
async def health():
    return {"status": "healthy", "service": "order-service"}

@app.get("/ready")
async def ready():
    try:
        # Check database
        async with db_pool.acquire() as conn:
            await conn.fetchval('SELECT 1')
        
        # Check Redis
        await redis_client.ping()
        
        return {"status": "ready"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail="Service not ready")

@app.get("/metrics")
async def metrics():
    from starlette.responses import Response
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

# Cart endpoints
@app.post("/api/cart", status_code=status.HTTP_201_CREATED)
async def create_cart(cart_request: CreateCartRequest):
    try:
        async with db_pool.acquire() as conn:
            # Create cart
            cart_id = await conn.fetchval(
                """
                INSERT INTO cart (user_id, created_at, expires_at)
                VALUES ($1, NOW(), NOW() + INTERVAL '24 hours')
                RETURNING id
                """,
                cart_request.user_id
            )
            
            # Add items
            for item in cart_request.items:
                await conn.execute(
                    """
                    INSERT INTO cart_items (cart_id, product_id, quantity, price)
                    VALUES ($1, $2, $3, $4)
                    """,
                    cart_id, item.product_id, item.quantity, item.price
                )
            
            cart_created_total.inc()
            logger.info(f"Cart created: {cart_id}")
            
            return {"cart_id": cart_id, "message": "Cart created successfully"}
    
    except Exception as e:
        logger.error(f"Error creating cart: {e}")
        raise HTTPException(status_code=500, detail="Failed to create cart")

@app.get("/api/cart/{cart_id}")
async def get_cart(cart_id: str):
    try:
        # Try cache first
        cached = await redis_client.get(f"cart:{cart_id}")
        if cached:
            return json.loads(cached)
        
        async with db_pool.acquire() as conn:
            # Get cart
            cart = await conn.fetchrow(
                "SELECT * FROM cart WHERE id = $1",
                cart_id
            )
            
            if not cart:
                raise HTTPException(status_code=404, detail="Cart not found")
            
            # Get items
            items = await conn.fetch(
                """
                SELECT ci.*, p.name, p.image_url
                FROM cart_items ci
                JOIN products p ON ci.product_id = p.id
                WHERE ci.cart_id = $1
                """,
                cart_id
            )
            
            result = {
                "id": str(cart['id']),
                "user_id": str(cart['user_id']),
                "items": [dict(item) for item in items],
                "created_at": cart['created_at'].isoformat()
            }
            
            # Cache result
            await redis_client.setex(
                f"cart:{cart_id}",
                300,  # 5 minutes
                json.dumps(result, default=str)
            )
            
            return result
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching cart: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch cart")

# Order endpoints
@app.post("/api/orders", status_code=status.HTTP_201_CREATED)
async def create_order(order_request: CreateOrderRequest):
    import time
    start_time = time.time()
    
    try:
        async with db_pool.acquire() as conn:
            async with conn.transaction():
                # Get cart items
                cart_items = await conn.fetch(
                    "SELECT * FROM cart_items WHERE cart_id = $1",
                    order_request.cart_id
                )
                
                if not cart_items:
                    raise HTTPException(status_code=404, detail="Cart is empty")
                
                # Calculate total
                total = sum(item['quantity'] * item['price'] for item in cart_items)
                
                # Create order
                order_id = await conn.fetchval(
                    """
                    INSERT INTO orders (user_id, status, total, currency, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, NOW(), NOW())
                    RETURNING id
                    """,
                    order_request.user_id, 'pending', total, 'USD'
                )
                
                # Create order items
                for item in cart_items:
                    await conn.execute(
                        """
                        INSERT INTO order_items (order_id, product_id, quantity, price)
                        VALUES ($1, $2, $3, $4)
                        """,
                        order_id, item['product_id'], item['quantity'], item['price']
                    )
                
                # Clear cart
                await conn.execute("DELETE FROM cart_items WHERE cart_id = $1", order_request.cart_id)
                await conn.execute("DELETE FROM cart WHERE id = $1", order_request.cart_id)
                
                # Publish order created event to SQS
                queue_url = os.getenv('ORDER_QUEUE_URL')
                if queue_url:
                    sqs_client.send_message(
                        QueueUrl=queue_url,
                        MessageBody=json.dumps({
                            'event': 'OrderCreated',
                            'order_id': str(order_id),
                            'user_id': order_request.user_id,
                            'total': float(total),
                            'payment_method_id': order_request.payment_method_id
                        })
                    )
                
                # Track metrics
                orders_created_total.labels(status='pending').inc()
                order_value_total.labels(currency='USD').inc(float(total))
                order_processing_duration.observe(time.time() - start_time)
                
                logger.info(f"Order created: {order_id}")
                
                return {
                    "order_id": str(order_id),
                    "status": "pending",
                    "total": float(total),
                    "message": "Order created successfully"
                }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating order: {e}")
        raise HTTPException(status_code=500, detail="Failed to create order")

@app.get("/api/orders/{order_id}", response_model=OrderResponse)
async def get_order(order_id: str):
    try:
        async with db_pool.acquire() as conn:
            # Get order
            order = await conn.fetchrow(
                "SELECT * FROM orders WHERE id = $1",
                order_id
            )
            
            if not order:
                raise HTTPException(status_code=404, detail="Order not found")
            
            # Get order items
            items = await conn.fetch(
                """
                SELECT oi.*, p.name, p.image_url
                FROM order_items oi
                JOIN products p ON oi.product_id = p.id
                WHERE oi.order_id = $1
                """,
                order_id
            )
            
            return OrderResponse(
                id=str(order['id']),
                user_id=str(order['user_id']),
                status=order['status'],
                total=order['total'],
                currency=order['currency'],
                created_at=order['created_at'],
                items=[dict(item) for item in items]
            )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching order: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch order")

@app.get("/api/orders/user/{user_id}")
async def get_user_orders(user_id: str, limit: int = 10, offset: int = 0):
    try:
        async with db_pool.acquire() as conn:
            orders = await conn.fetch(
                """
                SELECT id, status, total, currency, created_at
                FROM orders
                WHERE user_id = $1
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                """,
                user_id, limit, offset
            )
            
            return [dict(order) for order in orders]
    
    except Exception as e:
        logger.error(f"Error fetching user orders: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch orders")

@app.patch("/api/orders/{order_id}/status")
async def update_order_status(order_id: str, status: str):
    try:
        async with db_pool.acquire() as conn:
            result = await conn.execute(
                "UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2",
                status, order_id
            )
            
            if result == "UPDATE 0":
                raise HTTPException(status_code=404, detail="Order not found")
            
            # Track metrics
            if status == 'completed':
                orders_completed_total.inc()
            elif status == 'cancelled':
                orders_cancelled_total.inc()
            
            logger.info(f"Order {order_id} status updated to {status}")
            
            return {"message": "Order status updated successfully"}
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating order status: {e}")
        raise HTTPException(status_code=500, detail="Failed to update order status")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8082)
