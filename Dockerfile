FROM haproxy:2.6-alpine

USER root

RUN apk add --no-cache \
       bash \
       coreutils \
       gawk \
       sed \
       socat \
    ;

COPY render_cfg.sh         /
COPY docker-entrypoint.sh  /

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/etc/haproxy.cfg"]
