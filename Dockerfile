# Build Stage
FROM node:20-alpine AS build

WORKDIR /app

# Copy package files first to optimize build caching
COPY package.json package-lock.json ./

# Install dependencies
RUN npm ci

# Copy the rest of the codebase
COPY . .

# Build the project (compiles TypeScript and bundles via Vite)
RUN npm run build

# Production Stage
FROM nginx:stable-alpine

# Copy build output from build stage to Nginx server directory
COPY --from=build /app/dist /usr/share/nginx/html

# Copy our custom Nginx config for routing and compression
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
