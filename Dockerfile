# Kong
#
# VERSION       0.1-preview

# use the Openresty base image provided by Mashape
FROM mashape/docker-openresty
MAINTAINER Marco Palladino, marco@mashape.com

ENV KONG_VERSION 0.1-preview

# download Kong
RUN wget https://github.com/Mashape/kong/archive/$KONG_VERSION.tar.gz && tar xzf $KONG_VERSION.tar.gz

# install Kong
RUN cd kong-$KONG_VERSION && make install

# run Kong
CMD kong start

EXPOSE 8000 8001

