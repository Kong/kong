KONG_HOME = `pwd`

# Environment variables (default)
export DIR ?= $(KONG_HOME)/config.dev
export KONG_CONF ?= $(DIR)/kong.yml
export NGINX_CONF ?= $(DIR)/nginx.conf
export DEV_LUA_LIB ?= lua_package_path \"$(KONG_HOME)/src/?.lua\;\;\"\;
export SILENT_FLAG ?=
export COVERAGE_FLAG ?=
# Tests variables
TESTS_DIR ?= $(KONG_HOME)/config.tests
TESTS_KONG_CONF ?= $(TESTS_DIR)/kong.yml
TESTS_NGINX_CONF ?= $(TESTS_DIR)/nginx.conf

.PHONY: install dev clean migrate reset seed drop test coverage run-integration-tests test-web test-proxy test-all

install:
	@echo "Please wait, this process could take some time.."
	@if [ `uname` == "Darwin" ]; then \
		luarocks make kong-*.rockspec; \
	else \
		luarocks make kong-*.rockspec \
		PCRE_LIBDIR=`find / -type f -name "libpcre.so*" -print -quit | xargs dirname` \
		OPENSSL_LIBDIR=`find / -type f -name "libssl.so*" -print -quit | xargs dirname`; \
	fi

dev:
	@scripts/dev_rocks.sh
	@mkdir -p $(DIR)
	@sed -e "s@lua_package_path.*;@$(DEV_LUA_LIB)@g" $(KONG_HOME)/config.default/nginx.conf > $(NGINX_CONF)
	@cp $(KONG_HOME)/config.default/kong.yml $(KONG_CONF)
	@mkdir -p $(TESTS_DIR)
	@sed -e "s@lua_package_path.*;@$(DEV_LUA_LIB)@g" $(KONG_HOME)/config.default/nginx.conf > $(TESTS_NGINX_CONF)
	@cp $(KONG_HOME)/config.default/kong.yml $(TESTS_KONG_CONF)

clean:
	@rm -rf $(DIR)
	@rm -rf $(TESTS_DIR)
	@rm -f luacov.*

migrate:
	@scripts/db.lua $(SILENT_FLAG) migrate $(KONG_CONF)

reset:
	@scripts/db.lua $(SILENT_FLAG) reset $(KONG_CONF)

seed:
	@scripts/db.lua $(SILENT_FLAG) seed $(KONG_CONF)

drop:
	@scripts/db.lua $(SILENT_FLAG) drop $(KONG_CONF)

test:
	@busted $(COVERAGE_FLAG) spec/unit

coverage:
	@rm -f luacov.*
	@$(MAKE) test COVERAGE_FLAG=--coverage
	@luacov kong

lint:
	@luacheck kong*.rockspec

run-integration-tests:
	@$(MAKE) migrate KONG_CONF=$(TESTS_KONG_CONF)
	@bin/kong -c $(TESTS_KONG_CONF) -n $(TESTS_NGINX_CONF) start
	@while ! [ `ps aux | grep nginx | grep -c -v grep` -gt 0 ]; do sleep 1; done # Wait until nginx starts
	@$(MAKE) seed KONG_CONF=$(TESTS_KONG_CONF)
	@busted $(COVERAGE_FLAG) $(FOLDER) || (bin/kong stop; make drop KONG_CONF=$(TESTS_KONG_CONF) SILENT_FLAG=$(SILENT_FLAG); exit 1)
	@bin/kong stop
	@$(MAKE) reset KONG_CONF=$(TESTS_KONG_CONF)

test-web:
	@$(MAKE) run-integration-tests FOLDER=spec/web SILENT_FLAG=-s

test-proxy:
	@$(MAKE) run-integration-tests FOLDER=spec/proxy SILENT_FLAG=-s

test-all:
	@$(MAKE) run-integration-tests FOLDER=spec SILENT_FLAG=-s
