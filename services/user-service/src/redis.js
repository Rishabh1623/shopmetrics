const redis = require('redis');
const logger = require('./utils/logger');

const client = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

client.on('error', (err) => {
  logger.error('Redis error:', err);
});

client.on('connect', () => {
  logger.info('Redis connected');
});

// Connect to Redis
(async () => {
  try {
    await client.connect();
  } catch (err) {
    logger.error('Failed to connect to Redis:', err);
  }
})();

module.exports = client;
