FROM kong/kong:3.0.0-ubuntu

USER root

RUN apt-get update

RUN apt-get install -y \
        build-essential \
        unzip \
        git \
        m4 \
        libyaml-dev
RUN addgroup -S kong && adduser -S kong -G kong
RUN chown -R kong:kong /home/kong/
USER kong
