FROM joseluisq/static-web-server:2.41.0 AS static-web-server

FROM alpine:3.23.3

LABEL org.opencontainers.image.title=blocky-list-updater
LABEL org.opencontainers.image.description="Download and watch source lists for blocky DNS."
LABEL org.opencontainers.image.vendor="Shizun Ge"
LABEL org.opencontainers.image.licenses=GPLv3

RUN mkdir -p /src
RUN mkdir -p /web
RUN mkdir -p /web/watch
RUN mkdir -p /web/downloaded
RUN mkdir -p /sources

# Add sed and gawk because they are faster than the busybox ones.
RUN apk add --update --no-cache curl tzdata inotify-tools sed gawk

COPY --from=static-web-server /static-web-server /usr/local/bin/

WORKDIR /src
COPY src/* /src

ENTRYPOINT ["/src/entrypoint.sh"]

