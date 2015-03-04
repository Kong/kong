KONG_HOME = `pwd`

export CONF ?= kong.yml
export SILENT_FLAG ?=
export COVERAGE_FLAG ?=

# Tests variables
TESTS_CONF ?= kong_TEST.yml
DEVELOPMENT_CONF ?= kong_DEVELOPMENT.yml

.PHONY: install dev clean migrate reset seed drop test coverage run-integration-tests test-web test-proxy test-all

install:
	@if [ `uname` == "Darwin" ]; then \
		luarocks make kong-*.rockspec; \
	else \
		luarocks make kong-*.rockspec \
		PCRE_LIBDIR=`find / -type f -name "libpcre.so*" -print -quit | xargs dirname` \
		OPENSSL_LIBDIR=`find / -type f -name "libssl.so*" -print -quit | xargs dirname`; \
	fi

dev:
	@scripts/dev_rocks.sh
	@scripts/config.lua -k $(KONG_HOME) -e TEST create
	@scripts/config.lua -k $(KONG_HOME) -e DEVELOPMENT create
	@scripts/db.lua migrate $(DEVELOPMENT_CONF)

migrate:
	@scripts/db.lua $(SILENT_FLAG) migrate $(CONF)

reset:
	@scripts/db.lua $(SILENT_FLAG) reset $(CONF)

seed:
	@scripts/db.lua $(SILENT_FLAG) seed $(CONF)

drop:
	@scripts/db.lua $(SILENT_FLAG) drop $(CONF)

test:
	@busted $(COVERAGE_FLAG) spec/unit

coverage:
	@rm -f luacov.*
	@$(MAKE) test COVERAGE_FLAG=--coverage

clean:
	@rm -f luacov.*

lint:
	@luacheck kong*.rockspec

run-integration-tests:
	@$(MAKE) migrate CONF=$(TESTS_CONF)
	@bin/kong -c $(TESTS_CONF) start
	@while ! [ `ps aux | grep nginx | grep -c -v grep` -gt 0 ]; do sleep 1; done # Wait until nginx starts
	@$(MAKE) seed CONF=$(TESTS_CONF)
	@busted $(COVERAGE_FLAG) $(FOLDER) || (bin/kong stop; make drop CONF=$(TESTS_CONF) SILENT_FLAG=$(SILENT_FLAG); exit 1)
	@bin/kong stop
	@$(MAKE) reset CONF=$(TESTS_CONF)

test-web:
	@$(MAKE) run-integration-tests FOLDER=spec/web SILENT_FLAG=-s

test-proxy:
	@$(MAKE) run-integration-tests FOLDER=spec/proxy SILENT_FLAG=-s

test-all:
	@$(MAKE) run-integration-tests FOLDER=spec SILENT_FLAG=-s
