OPENRESTY_PREFIX=/usr/local/openresty

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install
CURRENT_FOLDER ?= `pwd`

DEV_DAEMON=off
PROD_DAEMON=on

DEV_LUA_CODE_CACHE=off
PROD_LUA_CODE_CACHE=on

PROD_LUA_PATH=/usr/local/lib/lua/?.lua;;
DEV_LUA_PATH ?= $(CURRENT_FOLDER)/lib/?.lua;;

DEV_CONF_PATH ?= $(CURRENT_FOLDER)/etc/conf.yaml

PROD_CONF_DIR ?= /etc/apenode
PROD_CONF_PATH ?= $(PROD_CONF_DIR)/conf.yaml

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

	sed -e "s/{DAEMON}/$(PROD_DAEMON)/g" -e "s/{LUA_CODE_CACHE}/$(PROD_LUA_CODE_CACHE)/g" -e "s@{LUA_PATH}@$(PROD_LUA_PATH)@g" -e "s@{CONF_PATH}@$(PROD_CONF_PATH)@g" nginx.conf > $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf

# - conf.yaml
	$(INSTALL) -d $(PROD_CONF_DIR)
	$(INSTALL) etc/conf.yaml $(PROD_CONF_DIR)

uninstall: all

	rm -rf $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode
	rm -rf $(PROD_CONF_DIR)
	mv $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf.old $(OPENRESTY_PREFIX)/nginx/conf/nginx.conf

run-dev: all
	rm -rf nginx_tmp
	mkdir -p nginx_tmp/logs
	echo "" > nginx_tmp/logs/error.log
	echo "" > nginx_tmp/logs/access.log

	sed -e "s/{DAEMON}/$(DEV_DAEMON)/g" -e "s/{LUA_CODE_CACHE}/$(DEV_LUA_CODE_CACHE)/g" -e "s@{LUA_PATH}@$(DEV_LUA_PATH)@g" -e "s@{CONF_PATH}@$(DEV_CONF_PATH)@g" nginx.conf > nginx_tmp/nginx_dev.conf

	nginx -p ./nginx_tmp -c nginx_dev.conf

test: all
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t
