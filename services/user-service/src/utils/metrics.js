const { Counter, Histogram, Gauge } = require('prom-client');

// HTTP metrics
const httpRequestsTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'path', 'status']
});

const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'path'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5]
});

// User metrics
const userRegistrationsTotal = new Counter({
  name: 'user_registrations_total',
  help: 'Total number of user registrations'
});

const userLoginsTotal = new Counter({
  name: 'user_logins_total',
  help: 'Total number of user login attempts',
  labelNames: ['status']
});

const userSessionsActive = new Gauge({
  name: 'user_sessions_active',
  help: 'Number of active user sessions'
});

const passwordResetRequestsTotal = new Counter({
  name: 'password_reset_requests_total',
  help: 'Total number of password reset requests'
});

// Database metrics
const dbConnectionPoolActive = new Gauge({
  name: 'database_connection_pool_active',
  help: 'Number of active database connections'
});

const dbConnectionPoolMax = new Gauge({
  name: 'database_connection_pool_max',
  help: 'Maximum number of database connections'
});

const dbQueryDuration = new Histogram({
  name: 'database_query_duration_seconds',
  help: 'Database query duration in seconds',
  labelNames: ['query_type'],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1]
});

module.exports = {
  httpRequestsTotal,
  httpRequestDuration,
  userRegistrationsTotal,
  userLoginsTotal,
  userSessionsActive,
  passwordResetRequestsTotal,
  dbConnectionPoolActive,
  dbConnectionPoolMax,
  dbQueryDuration
};
