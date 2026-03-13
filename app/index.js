// index.js
const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

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

app.get('/', (req, res) => res.json({ message: 'Hello from the cloud!', env: process.env.ENV || 'local' }));

app.listen(3000, '0.0.0.0', () => console.log('Server listening on port 3000'));