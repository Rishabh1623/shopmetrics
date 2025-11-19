const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { register, collectDefaultMetrics } = require('prom-client');
const logger = require('./utils/logger');
const metrics = require('./utils/metrics');
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const profileRoutes = require('./routes/profiles');
const { errorHandler } = require('./middleware/errorHandler');
const { authenticateToken } = require('./middleware/auth');

// Collect default metrics
collectDefaultMetrics({ register });

const app = express();
const PORT = process.env.PORT || 8083;

// Security middleware
app.use(helmet());
app.use(cors());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP'
});
app.use('/api/', limiter);

// Body parsing
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging and metrics
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    
    metrics.httpRequestsTotal.labels(
      req.method,
      req.route?.path || req.path,
      res.statusCode
    ).inc();
    
    metrics.httpRequestDuration.labels(
      req.method,
      req.route?.path || req.path
    ).observe(duration);
  });
  
  next();
});

// Health checks
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'user-service' });
});

app.get('/ready', async (req, res) => {
  try {
    // Check database connection
    const db = require('./db');
    await db.query('SELECT 1');
    
    // Check Redis connection
    const redis = require('./redis');
    await redis.ping();
    
    res.json({ status: 'ready' });
  } catch (error) {
    logger.error('Readiness check failed:', error);
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/users', authenticateToken, userRoutes);
app.use('/api/profiles', authenticateToken, profileRoutes);

// Error handling
app.use(errorHandler);

// Start server
app.listen(PORT, () => {
  logger.info(`User Service listening on port ${PORT}`);
});

module.exports = app;
