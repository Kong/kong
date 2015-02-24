KONG_HOME = `pwd`

# Environment variables (default)
export DIR ?= $(KONG_HOME)/config.dev
export KONG_CONF ?= $(DIR)/kong.yml
export NGINX_CONF ?= $(DIR)/nginx.conf
export DEV_LUA_LIB ?= lua_package_path \"$(KONG_HOME)/src/?.lua\;\;\"\;
export SILENT_FLAG ?=
# Tests variables
TESTS_DIR ?= $(KONG_HOME)/config.tests
TESTS_KONG_CONF ?= $(TESTS_DIR)/kong.yml
TESTS_NGINX_CONF ?= $(TESTS_DIR)/nginx.conf

.PHONY: install dev clean migrate reset seed drop test test-integration test-web test-proxy test-all

install:
	@if [[ $EUID -ne 0 ]]; then echo "Please try running this command again as root/Administrator."; exit 1; fi
	@echo "Please wait, this process could take some time.."
	@if [ `uname` == "Darwin" ]; then \
		luarocks make kong-*.rockspec; \
	else \
		luarocks make kong-*.rockspec \
		PCRE_LIBDIR=`find / -type f -name "libpcre.so*" -print -quit | xargs dirname` \
		OPENSSL_LIBDIR=`find / -type f -name "libssl.so*" -print -quit | xargs dirname`; \
	fi

dev:
	@mkdir -p $(DIR)
	@sed -e "s@lua_package_path.*;@$(DEV_LUA_LIB)@g" $(KONG_HOME)/config.default/nginx.conf > $(NGINX_CONF)
	@cp $(KONG_HOME)/config.default/kong.yml $(KONG_CONF)
	@mkdir -p $(TESTS_DIR)
	@sed -e "s@lua_package_path.*;@$(DEV_LUA_LIB)@g" $(KONG_HOME)/config.default/nginx.conf > $(TESTS_NGINX_CONF)
	@cp $(KONG_HOME)/config.default/kong.yml $(TESTS_KONG_CONF)

clean:
	@rm -rf $(DIR)
	@rm -rf $(TESTS_DIR)

migrate:
	@scripts/db.lua $(SILENT_FLAG) migrate $(KONG_CONF)

reset:
	@scripts/db.lua $(SILENT_FLAG) reset $(KONG_CONF)

seed:
	@scripts/db.lua $(SILENT_FLAG) seed $(KONG_CONF)

drop:
	@scripts/db.lua $(SILENT_FLAG) drop $(KONG_CONF)

test:
	@busted spec/unit

run-integration-tests:
	@$(MAKE) migrate KONG_CONF=$(TESTS_KONG_CONF) SILENT_FLAG=-s
	@bin/kong -c $(TESTS_KONG_CONF) -n $(TESTS_NGINX_CONF) start
	@while ! [ `ps aux | grep nginx | grep -c -v grep` -gt 0 ]; do sleep 1; done # Wait until nginx starts
	@$(MAKE) seed KONG_CONF=$(TESTS_KONG_CONF) SILENT_FLAG=-s
	@busted $(FOLDER) || (bin/kong stop; make drop KONG_CONF=$(TESTS_KONG_CONF) SILENT_FLAG=-s; exit 1)
	@bin/kong stop
	@$(MAKE) reset KONG_CONF=$(TESTS_KONG_CONF) SILENT_FLAG=-s

test-web:
	@$(MAKE) run-integration-tests FOLDER=spec/web

test-proxy:
	@$(MAKE) run-integration-tests FOLDER=spec/proxy

test-all:
	@$(MAKE) run-integration-tests FOLDER=spec
