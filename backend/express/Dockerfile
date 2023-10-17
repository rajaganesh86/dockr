FROM node:alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install
COPY . .
EXPOSE 8082
CMD ["node", "index.js"] # replace with your actual file
