FROM haproxy:1.7-alpine

RUN apk add --no-cache \
       bash \
       coreutils \
       sed \
       gawk \
       rsyslog

ENV RSYSLOG=y

COPY render_cfg.sh         /
COPY docker-entrypoint.sh  /
COPY rsyslogd.conf         /etc/rsyslogd.conf

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/etc/haproxy.cfg"]
