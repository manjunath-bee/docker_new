FROM node:20.18.3-alpine3.21
WORKDIR /opt/backend
COPY package.json .
COPY *.js .
RUN npm install
#ENV DB_HOST="mysql"
ENV DB_HOST="mysql"
CMD ["node", "index.js"]
