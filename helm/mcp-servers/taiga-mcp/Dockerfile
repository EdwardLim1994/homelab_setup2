# ponytail: no maintained Taiga MCP image exists (checked before writing
# this) — thin custom server, see server.js. Built+pushed by
# terraform/internal/mcp-servers.tf's null_resource, same pattern
# terraform/internal/taiga.tf uses for the taiga-back-oidc image.
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY server.js .
EXPOSE 8300
CMD ["node", "server.js"]
