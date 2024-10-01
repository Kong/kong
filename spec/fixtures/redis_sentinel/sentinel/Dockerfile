FROM redis:7.4

ARG MASTER_IP
ARG MASTER_PORT
ARG SENTINEL_PORT

COPY --chown=redis:redis sentinel_template.conf /etc/redis/sentinel.conf

RUN sed -i "s/\$SENTINEL_PORT/${SENTINEL_PORT}/g" /etc/redis/sentinel.conf
RUN sed -i "s/\$MASTER_IP/${MASTER_IP}/g" /etc/redis/sentinel.conf
RUN sed -i "s/\$MASTER_PORT/${MASTER_PORT}/g" /etc/redis/sentinel.conf

CMD redis-server "/etc/redis/sentinel.conf" --sentinel
