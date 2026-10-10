// AWS Lambda entry point: wires the request handler to DynamoDB.
// Lambda runtime: nodejs24.x, handler "src/handler.handler".

import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { createHandler } from './app.js';

const tableName = process.env.TABLE_NAME;
const client = new DynamoDBClient({
  region: process.env.AWS_REGION,
  ...(process.env.DYNAMODB_ENDPOINT ? { endpoint: process.env.DYNAMODB_ENDPOINT } : {}),
});

export function toDynamoItem(item) {
  return {
    id: { S: item.id },
    createdAt: { S: item.createdAt },
    expiresAt: { N: String(item.expiresAt) },
    name: { S: item.name },
    favoriteBag: { S: item.favoriteBag },
    favoriteCharm: { S: item.favoriteCharm },
    wouldBuy: { S: item.wouldBuy },
    comments: { S: item.comments },
  };
}

export async function saveFeedback(item) {
  if (!tableName) throw new Error('TABLE_NAME is not set');
  await client.send(
    new PutItemCommand({
      TableName: tableName,
      Item: toDynamoItem(item),
      ConditionExpression: 'attribute_not_exists(id)',
    }),
  );
}

export const handler = createHandler({ saveFeedback });
export { client, tableName };
