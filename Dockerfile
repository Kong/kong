FROM kong:3.6.1

USER root

COPY kong/plugins/ai-proxy/ /usr/local/share/lua/5.1/kong/plugins/ai-proxy/
COPY kong/llm/ /usr/local/share/lua/5.1/kong/llm/

USER kong
