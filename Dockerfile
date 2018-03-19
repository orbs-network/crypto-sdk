FROM node:9-slim

VOLUME [ "/opt/orbs/logs", "/opt/orbs/db" ]

# TODO: move to later stage, use cache for ts compiler & top level software

ADD package.json yarn.lock .yarnrc docker/bootstrap-*.sh /opt/orbs/

WORKDIR /opt/orbs

RUN ./docker/bootstrap-sdk.sh
RUN ./docker/bootstrap-server.sh

RUN yarn config list && \
    yarn global add typescript@2.7.1 tslint@5.9.1 && \
    yarn install && yarn cache clean

ADD . /opt/orbs

RUN yarn run build && yarn cache clean

CMD echo
