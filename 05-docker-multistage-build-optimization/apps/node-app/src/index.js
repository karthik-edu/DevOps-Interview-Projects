const express = require('express');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Node.js multi-stage build!',
    hostname: os.hostname(),
    nodeVersion: process.version,
    user: process.env.USER || 'unknown',
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT} as uid=${process.getuid()}`);
});
