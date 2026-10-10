// HTTP server used by Docker Compose, on a laptop and on the EC2 server.
// Turns plain HTTP requests into Lambda function URL events so the exact same
// handler runs everywhere. With DYNAMODB_ENDPOINT set (local development) it talks to
// DynamoDB Local and creates the table; without it, it uses the real table in AWS.

import http from 'node:http';
import { CreateTableCommand, DescribeTableCommand, ResourceNotFoundException } from '@aws-sdk/client-dynamodb';
import { handler, client, tableName } from './handler.js';

const PORT = Number(process.env.PORT || 3000);

async function ensureTable(attempt = 1) {
  try {
    await client.send(new DescribeTableCommand({ TableName: tableName }));
    return;
  } catch (err) {
    if (!(err instanceof ResourceNotFoundException)) {
      if (attempt >= 30) throw err;
      await new Promise((r) => setTimeout(r, 1000));
      return ensureTable(attempt + 1);
    }
  }
  await client.send(
    new CreateTableCommand({
      TableName: tableName,
      BillingMode: 'PAY_PER_REQUEST',
      AttributeDefinitions: [{ AttributeName: 'id', AttributeType: 'S' }],
      KeySchema: [{ AttributeName: 'id', KeyType: 'HASH' }],
    }),
  );
  console.log(`created local table ${tableName}`);
}

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', async () => {
    const url = new URL(req.url, 'http://localhost');
    const event = {
      rawPath: url.pathname,
      rawQueryString: url.search.slice(1),
      headers: req.headers,
      requestContext: { http: { method: req.method } },
      body: Buffer.concat(chunks).toString('utf8'),
      isBase64Encoded: false,
    };
    try {
      const out = await handler(event);
      res.writeHead(out.statusCode, out.headers);
      res.end(out.body);
    } catch (err) {
      console.error(err);
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'Internal error' }));
    }
  });
});

// Only DynamoDB Local needs its table created. In AWS, Terraform owns the table.
if (process.env.DYNAMODB_ENDPOINT) await ensureTable();
server.listen(PORT, () => console.log(`feedback api listening on :${PORT}, table ${tableName}`));
