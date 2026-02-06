# Use Node.js LTS version
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Install tsx for running TypeScript directly
RUN npm install -g tsx

# Copy application code
COPY index.ts ./

# Set up non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs

# Run the TypeScript script
CMD ["npx", "tsx", "index.ts"]
