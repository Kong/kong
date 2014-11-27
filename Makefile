OPENRESTY_PREFIX=/usr/local/openresty

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install

.PHONY: all test install

all: ;

install: all

################################
# Install the base structure   #
################################

	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode
	cp -R lib/resty/apenode/ $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/

################################
# Install the configuration    #
################################

# - nginx.conf
	cp $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf.old
	$(INSTALL) nginx.conf $(OPENRESTY_PREFIX)/nginx/conf/

# - conf.yaml
	$(INSTALL) -d /etc/apenode
	$(INSTALL) conf.yaml /etc/apenode/

uninstall: all

	rm -rf $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode
	rm -rf /etc/apenode/
	mv $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf.old $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf


test: all
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t
