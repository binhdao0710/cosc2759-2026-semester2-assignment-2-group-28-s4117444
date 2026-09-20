FROM node:24
WORKDIR /app
# Dependencies
COPY package*.json .
RUN npm install
# App
COPY . .
CMD [ "npm", "run", "start" ]