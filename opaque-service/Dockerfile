FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
ENV OPAQUE_SERVICE_PORT=8092
EXPOSE 8092
CMD ["node", "server.js"]
