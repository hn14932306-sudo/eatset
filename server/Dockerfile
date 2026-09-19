FROM node:22-alpine
WORKDIR /app
COPY package.json *.mjs ./
RUN mkdir /data && chown node:node /data
USER node
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 DB_PATH=/data/usage.sqlite
EXPOSE 8787
CMD ["node", "index.mjs"]
