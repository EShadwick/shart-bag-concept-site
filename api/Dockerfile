# Image for the feedback API, used by local development and by the EC2 server.
# Node 24 matches the nodejs24.x Lambda runtime used in AWS.
ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-alpine

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src ./src

ENV NODE_ENV=production PORT=3000
USER node
EXPOSE 3000

HEALTHCHECK --interval=5s --timeout=3s --retries=10 \
  CMD node -e "fetch('http://localhost:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/local-server.js"]
