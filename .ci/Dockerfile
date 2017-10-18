FROM kong:latest

COPY kong.tar.gz kong.tar.gz

RUN tar -xzf kong.tar.gz -C /tmp \
  rm -f kong.tar.gz \
  cp -R /tmp/usr / \