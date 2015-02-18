KONG_HOME = `pwd`

# Dev environment variables
export DEV_DIR ?= $(KONG_HOME)/dev
export TEST_DIR ?= $(KONG_HOME)/test
export KONG_CONF ?= $(DEV_DIR)/kong-dev.yaml
export DEV_LUA_LIB ?= lua_package_path \"$(KONG_HOME)/src/?.lua\;\;\"\;

.PHONY: install dev clean reset seed drop test test-integration test-web test-proxy test-all

install:
	@luarocks make kong-*.rockspec

dev:
	@mkdir -p $(DEV_DIR)
	@sed -e "s@lua_package_path.*;@$(DEV_LUA_LIB)@g" $(KONG_HOME)/conf/nginx.conf > $(DEV_DIR)/nginx-dev.conf
	@cp $(KONG_HOME)/conf/kong.yaml $(DEV_DIR)/kong-dev.yaml

clean:
	@rm -rf $(DEV_DIR)

reset:
	@scripts/migrate reset --conf=$(KONG_CONF)

seed:
	@scripts/seed seed --conf=$(KONG_CONF)

drop:
	@scripts/seed drop --conf=$(KONG_CONF)

test:
	@busted spec/unit

test-integration:
	@$(MAKE) dev DEV_DIR=$(TEST_DIR)
	@bin/kong -c $(TEST_DIR)/kong-dev.yaml -n $(TEST_DIR)/nginx-dev.conf start > /dev/null
	@bin/kong migrate > /dev/null
	@$(MAKE) seed > /dev/null
	@busted $(FOLDER) || (bin/kong stop > /dev/null;make drop > /dev/null; exit 1)
	@bin/kong stop > /dev/null
	@$(MAKE) drop > /dev/null
	@$(MAKE) clean DEV_DIR=$(TEST_DIR)

test-web:
	@$(MAKE) test-integration FOLDER=spec/web

test-proxy:
	@$(MAKE) test-integration FOLDER=spec/proxy

test-all:
	@$(MAKE) test-integration FOLDER=spec/
