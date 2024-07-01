FROM kong:3.7.1

USER root

RUN luarocks install lua-resty-gcp
COPY kong/plugins/ai-proxy/ /usr/local/share/lua/5.1/kong/plugins/ai-proxy/
COPY kong/llm/ /usr/local/share/lua/5.1/kong/llm/
COPY kong/tools/aws_stream.lua /usr/local/share/lua/5.1/kong/tools/aws_stream.lua

USER kong
