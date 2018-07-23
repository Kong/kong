FROM openresty/openresty:1.13.6.2-xenial

ADD . /kong
ADD ./entrypoint.sh /

WORKDIR /kong

RUN apt-get update && apt-get install -y \
  libssl-dev \
  git \
  iputils-ping \
  vim \
  psmisc

RUN make dev

ENTRYPOINT ["/entrypoint.sh"]