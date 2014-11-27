OPENRESTY_PREFIX=/usr/local/openresty

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install

DEV_DAEMON=off
PROD_DAEMON=on

DEV_LUA_CODE_CACHE=off
PROD_LUA_CODE_CACHE=on

PROD_LUA_PATH=/usr/local/lib/lua/?.lua;;

CURRENT_PATH ?= `pwd`/lib/?.lua;;

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

	sed -e "s/{DAEMON}/$(PROD_DAEMON)/g" -e "s/{LUA_CODE_CACHE}/$(PROD_LUA_CODE_CACHE)/g" -e "s@{LUA_PATH}@$(PROD_LUA_PATH)@g" nginx.conf > $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf

# - conf.yaml
	$(INSTALL) -d /etc/apenode
	$(INSTALL) conf.yaml /etc/apenode/

uninstall: all

	rm -rf $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode
	rm -rf /etc/apenode/
	mv $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf.old $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf

run-dev: all
	rm -rf nginx_tmp
	mkdir -p nginx_tmp/logs
	echo "" > nginx_tmp/logs/error.log
	echo "" > nginx_tmp/logs/access.log

	sed -e "s/{DAEMON}/$(DEV_DAEMON)/g" -e "s/{LUA_CODE_CACHE}/$(DEV_LUA_CODE_CACHE)/g" -e "s@{LUA_PATH}@$(CURRENT_PATH)@g" nginx.conf > nginx_tmp/nginx_dev.conf

	nginx -p ./nginx_tmp -c nginx_dev.conf

test: all
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t
