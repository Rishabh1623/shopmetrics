const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const Joi = require('joi');
const db = require('../db');
const redis = require('../redis');
const logger = require('../utils/logger');
const metrics = require('../utils/metrics');

const router = express.Router();

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';
const JWT_EXPIRES_IN = '15m';
const REFRESH_TOKEN_EXPIRES_IN = 7 * 24 * 60 * 60; // 7 days in seconds

// Validation schemas
const registerSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().min(8).required(),
  firstName: Joi.string().required(),
  lastName: Joi.string().required()
});

const loginSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().required()
});

// Register new user
router.post('/register', async (req, res) => {
  try {
    const { error, value } = registerSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { email, password, firstName, lastName } = value;

    // Check if user exists
    const existingUser = await db.query(
      'SELECT id FROM users WHERE email = $1',
      [email]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: 'User already exists' });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Create user
    const result = await db.query(
      `INSERT INTO users (email, password_hash, created_at, updated_at)
       VALUES ($1, $2, NOW(), NOW())
       RETURNING id, email, created_at`,
      [email, passwordHash]
    );

    const user = result.rows[0];

    // Create profile
    await db.query(
      `INSERT INTO profiles (user_id, first_name, last_name)
       VALUES ($1, $2, $3)`,
      [user.id, firstName, lastName]
    );

    // Track metric
    metrics.userRegistrationsTotal.inc();

    logger.info(`User registered: ${user.id}`);

    res.status(201).json({
      message: 'User registered successfully',
      userId: user.id
    });
  } catch (error) {
    logger.error('Registration error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Login
router.post('/login', async (req, res) => {
  try {
    const { error, value } = loginSchema.validate(req.body);
    if (error) {
      metrics.userLoginsTotal.labels('failed').inc();
      return res.status(400).json({ error: error.details[0].message });
    }

    const { email, password } = value;

    // Get user
    const result = await db.query(
      'SELECT id, email, password_hash FROM users WHERE email = $1',
      [email]
    );

    if (result.rows.length === 0) {
      metrics.userLoginsTotal.labels('failed').inc();
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];

    // Verify password
    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      metrics.userLoginsTotal.labels('failed').inc();
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Generate tokens
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    );

    const refreshToken = jwt.sign(
      { userId: user.id, type: 'refresh' },
      JWT_SECRET,
      { expiresIn: `${REFRESH_TOKEN_EXPIRES_IN}s` }
    );

    // Store refresh token in Redis
    await redis.setEx(
      `refresh_token:${user.id}`,
      REFRESH_TOKEN_EXPIRES_IN,
      refreshToken
    );

    // Store session
    await redis.setEx(
      `session:${user.id}`,
      REFRESH_TOKEN_EXPIRES_IN,
      JSON.stringify({ userId: user.id, email: user.email })
    );

    // Track metrics
    metrics.userLoginsTotal.labels('success').inc();
    metrics.userSessionsActive.inc();

    logger.info(`User logged in: ${user.id}`);

    res.json({
      accessToken,
      refreshToken,
      expiresIn: JWT_EXPIRES_IN,
      user: {
        id: user.id,
        email: user.email
      }
    });
  } catch (error) {
    logger.error('Login error:', error);
    metrics.userLoginsTotal.labels('error').inc();
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Refresh token
router.post('/refresh', async (req, res) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      return res.status(400).json({ error: 'Refresh token required' });
    }

    // Verify refresh token
    const decoded = jwt.verify(refreshToken, JWT_SECRET);

    if (decoded.type !== 'refresh') {
      return res.status(401).json({ error: 'Invalid token type' });
    }

    // Check if token exists in Redis
    const storedToken = await redis.get(`refresh_token:${decoded.userId}`);
    if (storedToken !== refreshToken) {
      return res.status(401).json({ error: 'Invalid refresh token' });
    }

    // Get user
    const result = await db.query(
      'SELECT id, email FROM users WHERE id = $1',
      [decoded.userId]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'User not found' });
    }

    const user = result.rows[0];

    // Generate new access token
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    );

    res.json({
      accessToken,
      expiresIn: JWT_EXPIRES_IN
    });
  } catch (error) {
    logger.error('Token refresh error:', error);
    res.status(401).json({ error: 'Invalid refresh token' });
  }
});

// Logout
router.post('/logout', async (req, res) => {
  try {
    const token = req.headers.authorization?.split(' ')[1];
    
    if (token) {
      const decoded = jwt.verify(token, JWT_SECRET);
      
      // Remove refresh token and session
      await redis.del(`refresh_token:${decoded.userId}`);
      await redis.del(`session:${decoded.userId}`);
      
      // Track metric
      metrics.userSessionsActive.dec();
      
      logger.info(`User logged out: ${decoded.userId}`);
    }

    res.json({ message: 'Logged out successfully' });
  } catch (error) {
    logger.error('Logout error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Password reset request
router.post('/password-reset-request', async (req, res) => {
  try {
    const { email } = req.body;

    const result = await db.query(
      'SELECT id FROM users WHERE email = $1',
      [email]
    );

    if (result.rows.length > 0) {
      const user = result.rows[0];
      
      // Generate reset token
      const resetToken = jwt.sign(
        { userId: user.id, type: 'reset' },
        JWT_SECRET,
        { expiresIn: '1h' }
      );

      // Store reset token in Redis
      await redis.setEx(
        `reset_token:${user.id}`,
        3600, // 1 hour
        resetToken
      );

      // Track metric
      metrics.passwordResetRequestsTotal.inc();

      // TODO: Send email with reset link
      logger.info(`Password reset requested: ${user.id}`);
    }

    // Always return success to prevent email enumeration
    res.json({ message: 'If the email exists, a reset link has been sent' });
  } catch (error) {
    logger.error('Password reset request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
