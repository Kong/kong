# Use the specified Kong development image
FROM kong/kong-gateway-dev:f73e9f191ce645bb2f55ea4b3c83e6602abf4948-ubuntu

# Copy the specified files from the build host to the container
COPY ../vector-poc/kong/fastrace.lua /usr/local/share/lua/5.1/kong/fastrace.lua
COPY kong/runloop/handler.lua /usr/local/share/lua/5.1/kong/runloop/handler.lua
COPY kong/tracing/instrumentation.lua /usr/local/share/lua/5.1/kong/tracing/instrumentation.lua

# Copy the .so file to the specified directory in the container
COPY ../vector-poc/build/libfastrace.so /usr/local/lib/libfastrace.so
