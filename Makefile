OPENRESTY_PREFIX=/usr/local/openresty

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
APENODE_PLUGINS_DIR ?=	$(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/plugins
INSTALL ?= install

.PHONY: all test install

all: ;

install: all

################################
# Install the base structure   #
################################

# - Base files
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode
	$(INSTALL) lib/resty/apenode/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/

# - DAO
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/dao/mock
	$(INSTALL) lib/resty/apenode/dao/mock/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/dao/mock

# - Web
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/web
	$(INSTALL) lib/resty/apenode/web/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/resty/apenode/web/

# - Static
	$(INSTALL) -d $(OPENRESTY_PREFIX)/nginx/static
	$(INSTALL) static/*.* $(OPENRESTY_PREFIX)/nginx/static/

################################
# Install the configuration    #
################################

# - nginx.conf
	$(INSTALL) nginx.conf $(OPENRESTY_PREFIX)/nginx/conf/

# - conf.yaml
	$(INSTALL) -d /etc/apenode
	$(INSTALL) conf.yaml /etc/apenode/

################################
# Install the plugins          #
################################

# - Base
	$(INSTALL) -d $(APENODE_PLUGINS_DIR)/base
	$(INSTALL) lib/resty/apenode/plugins/base/*.lua $(APENODE_PLUGINS_DIR)/base/

# - Transformations
	$(INSTALL) -d $(APENODE_PLUGINS_DIR)/transformations
	$(INSTALL) lib/resty/apenode/plugins/transformations/*.lua $(APENODE_PLUGINS_DIR)/transformations/

test: all
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -I../test-nginx/lib -r t
