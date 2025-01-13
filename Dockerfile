FROM joseluisq/static-web-server:2.34.0 AS static-web-server

FROM alpine:3.21.2

LABEL org.opencontainers.image.title=blocky-list-updater
LABEL org.opencontainers.image.description="Download and watch source lists for blocky DNS."
LABEL org.opencontainers.image.vendor="Shizun Ge"
LABEL org.opencontainers.image.licenses=GPLv3

RUN mkdir -p /src
RUN mkdir -p /web
RUN mkdir -p /web/watch
RUN mkdir -p /web/downloaded
RUN mkdir -p /sources

RUN apk add --update --no-cache curl tzdata inotify-tools

COPY --from=static-web-server /static-web-server /usr/local/bin/

WORKDIR /src
COPY src/* /src

ENTRYPOINT ["/src/entrypoint.sh"]

