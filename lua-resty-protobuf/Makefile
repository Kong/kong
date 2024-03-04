CXXFLAGS = -O2 \
		   -g3 \
		   -Werror \
		   -Iinclude/ \
		   -Isrc/

LDFLAGS = -Wl,--copy-dt-needed-entries -shared -fPIC -lprotobuf

SRCS = ngx_lua_resty_protobuf.cpp

PROTO_SRCS = include/opentelemetry/proto/collector/trace/v1/trace_service.proto \
			 include/opentelemetry/proto/common/v1/common.proto \
			 include/opentelemetry/proto/resource/v1/resource.proto \
			 include/opentelemetry/proto/trace/v1/trace.proto

SRCS_GENERATED = include/opentelemetry/proto/collector/trace/v1/trace_service.pb.h \
				 include/opentelemetry/proto/common/v1/common.pb.h \
				 include/opentelemetry/proto/resource/v1/resource.pb.h \
				 include/opentelemetry/proto/trace/v1/trace.pb.h \
				 include/opentelemetry/proto/collector/trace/v1/trace_service.pb.cc \
				 include/opentelemetry/proto/common/v1/common.pb.cc \
				 include/opentelemetry/proto/resource/v1/resource.pb.cc \
				 include/opentelemetry/proto/trace/v1/trace.pb.cc

PROTOC ?= protoc

LIB_NAME         = libresty_protobuf
OPENRESTY_PREFIX?= /usr/local/openresty
LUA_LIB_DIR     ?= $(OPENRESTY_PREFIX)/lualib

ifeq ($(shell uname), Darwin)
	SUFFIX = dylib
else
	SUFFIX = so
endif

clean:
	@rm -rf *.o *.so *.dylib $(LIB_NAME).$(SUFFIX) $(SRCS_GENERATED)

proto: $(PROTO_SRCS) 
	@for proto in $(PROTO_SRCS); do \
		$(PROTOC) --cpp_out=include --proto_path=include $$proto; \
	done

lib: clean proto $(SRCS)
	@$(CXX) $(CXXFLAGS) $(SRCS_GENERATED) $(SRCS) $(LDFLAGS) -o $(LIB_NAME).$(SUFFIX)

# install: lib lualib/resty/kong/kproto/init.lua
# 	@rm -rf $(OPENRESTY_PREFIX)/lualib/resty/kong/kproto $(LUA_LIB_DIR)/$(LIB_NAME).$(SUFFIX)
# 	@mkdir -p $(OPENRESTY_PREFIX)/lualib/resty/kong/kproto
# 	@cp -r lualib/resty/kong/kproto $(OPENRESTY_PREFIX)/lualib/resty/kong/
# 	@cp $(LIB_NAME).$(SUFFIX) $(LUA_LIB_DIR)/