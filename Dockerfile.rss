FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY rss.js ./

CMD ["node", "rss.js"]
