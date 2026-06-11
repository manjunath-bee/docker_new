# FROM node:20.18.3-alpine3.21 AS builder
# WORKDIR /opt/backend
# COPY package.json ./
# COPY *.js ./
# RUN npm install


# FROM node:20.18.3-alpine3.21
# RUN addgroup -S expense && adduser -S expense -G expense && \
#     mkdir /opt/backend && \
#     chown -R expense:expense /opt/backend
# WORKDIR /opt/backend
# COPY --from=builder /opt/backend /opt/backend
# ENV DB_HOST="mysql"
# USER expense
# CMD ["node", "index.js"]


-------------

FROM node:20.18.3-alpine3.21
RUN addgroup -S expense && adduser -S expense -G expense
RUN mkdir /opt/backend
RUN chown -R expense:expense /opt/backend
WORKDIR /opt/backend
COPY package.json ./
COPY *.js ./
RUN npm install
#ENV DB_HOST="mysql"
ENV DB_HOST="mysql"
USER expense
CMD ["node", "index.js"]