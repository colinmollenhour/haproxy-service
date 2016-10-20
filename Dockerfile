FROM haproxy:1.6-alpine

RUN apk add --update bash && \
    apk add coreutils && \
    apk add sed && \
    apk add gawk && \
    rm -rf /var/cache/apk/*

COPY render_cfg.sh /
COPY docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/etc/haproxy.cfg"]
