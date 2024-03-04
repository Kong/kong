OPENRESTY_PREFIX?= /usr/local/openresty
LUA_LIB_DIR     ?= $(OPENRESTY_PREFIX)/lualib

LIB_NAME = libprost_test

ifeq ($(shell uname), Darwin)
	SUFFIX = dylib
else
	SUFFIX = so
endif

install-lualib:
	$(INSTALL) -d $(DESTDIR)$(LUA_LIB_DIR)/resty/kong/kproto/
	$(INSTALL) -m 664 lualib/resty/kong/kproto/*.lua $(DESTDIR)$(LUA_LIB_DIR)/resty/kong/kproto/