OPENRESTY_PREFIX=/usr/local/openresty

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install

.PHONY: all test install

all: ;

install: all
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode
	$(INSTALL) lib/resty/apenode/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/

	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/base
	$(INSTALL) lib/resty/apenode/base/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/base/

	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/transformations
	$(INSTALL) lib/resty/apenode/transformations/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/transformations/

	$(INSTALL) nginx.conf $(OPENRESTY_PREFIX)/nginx/conf/

test: all
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t
