FROM mashape/kong-enterprise:dev-master

RUN rm -rf /usr/local/share/lua/5.1/kong

COPY ./kong /usr/local/share/lua/5.1/kong

EXPOSE 8002
