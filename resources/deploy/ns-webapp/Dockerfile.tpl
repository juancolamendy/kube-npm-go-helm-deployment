FROM mhart/alpine-node:12
MAINTAINER JC

RUN mkdir -p /app
WORKDIR /app
COPY . .
RUN apk add --no-cache git && rm -fr node_modules && npm install && npm run build

EXPOSE {{PORT}}

CMD ["npm", "run", "start"]
