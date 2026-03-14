// index.js
const express = require('express');
const { Pool } = require('pg');
const path = require('path');

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public'), { index: false }));

const pool = new Pool({
  host:     process.env.DB_HOST,
  database: process.env.DB_NAME || 'appdb',
  user:     process.env.DB_USER || 'appuser',
  password: process.env.DB_PASSWORD,
  port:     5432,
  ssl: { rejectUnauthorized: false }
});

// Health check (no DB required)
app.get('/healthz', (req, res) => res.json({ status: 'healthy', timestamp: new Date() }));

// DB test
app.get('/db-check', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW()');
    res.json({ connected: true, time: result.rows[0].now });
  } catch (err) {
    res.status(500).json({ connected: false, error: err.message });
  }
});

app.get('/', (req, res) => res.json({ message: 'Hello AWS UG AI/ML USER GROUP!', env: process.env.ENV || 'local' }));

// Serve frontend for any non-API route
app.get('/ui', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(3000, '0.0.0.0', () => console.log('Server listening on port 3000'));