KONG_HOME = `pwd`

# Environment variables (default)
export DIR ?= $(KONG_HOME)/config.dev
export KONG_CONF ?= $(DIR)/kong.yaml
export NGINX_CONF ?= $(DIR)/nginx.conf
export DEV_LUA_LIB ?= lua_package_path \"$(KONG_HOME)/src/?.lua\;\;\"\;
# Tests variables
TESTS_DIR ?= $(KONG_HOME)/config.tests
TESTS_KONG_CONF ?= $(TESTS_DIR)/kong.yaml
TESTS_NGINX_CONF ?= $(TESTS_DIR)/nginx.conf

.PHONY: install dev clean reset seed drop test test-integration test-web test-proxy test-all

install:
	@if [[ $EUID -ne 0 ]]; then echo "Please try running this command again as root/Administrator."; exit 1; fi
	@echo "Please wait, this process could take some time.."
	@luarocks make kong-*.rockspec PCRE_LIBDIR=`find / -type f -name "libpcre.so*" -print -quit | xargs dirname` OPENSSL_LIBDIR=`find / -type f -name "libssl.so*" -print -quit | xargs dirname`

dev:
	@mkdir -p $(DIR)
	@sed -e "s@lua_package_path.*;@$(DEV_LUA_LIB)@g" $(KONG_HOME)/config.default/nginx.conf > $(NGINX_CONF)
	@cp $(KONG_HOME)/config.default/kong.yaml $(KONG_CONF)
	@mkdir -p $(TESTS_DIR)
	@sed -e "s@lua_package_path.*;@$(DEV_LUA_LIB)@g" $(KONG_HOME)/config.default/nginx.conf > $(TESTS_NGINX_CONF)
	@cp $(KONG_HOME)/config.default/kong.yaml $(TESTS_KONG_CONF)

clean:
	@rm -rf $(DIR)
	@rm -rf $(TESTS_DIR)

reset:
	@scripts/migrate reset --conf=$(KONG_CONF)

seed:
	@scripts/seed seed --conf=$(KONG_CONF)

drop:
	@scripts/seed drop --conf=$(KONG_CONF)

test:
	@busted spec/unit

run-integration-tests:
	@bin/kong -c $(TESTS_KONG_CONF) migrate
	@bin/kong -c $(TESTS_KONG_CONF) -n $(TESTS_NGINX_CONF) start
	@$(MAKE) seed KONG_CONF=$(TESTS_KONG_CONF)
	@busted $(FOLDER) || (bin/kong stop; make drop KONG_CONF=$(TESTS_KONG_CONF); exit 1)
	@bin/kong stop
	@$(MAKE) reset KONG_CONF=$(TESTS_KONG_CONF)

test-web:
	@$(MAKE) run-integration-tests FOLDER=spec/web

test-proxy:
	@$(MAKE) run-integration-tests FOLDER=spec/proxy

test-all:
	@$(MAKE) run-integration-tests FOLDER=spec
