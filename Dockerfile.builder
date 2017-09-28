FROM mashape/alpine-bash:latest

COPY .docker/ /tmp/

RUN /tmp/base-build.sh
RUN /tmp/build-kong.sh