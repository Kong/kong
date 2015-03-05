KONG_HOME = `pwd`
DEVELOPMENT_CONF ?= kong_DEVELOPMENT.yml

.PHONY: install dev seed drop test coverage test-api test-proxy test-server test-all

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
	@scripts/db.lua -c $(DEVELOPMENT_CONF) migrate

run:
	@bin/kong -c $(DEVELOPMENT_CONF) start

seed:
	@scripts/db.lua -c $(DEVELOPMENT_CONF) seed

drop:
	@scripts/db.lua -c $(DEVELOPMENT_CONF) drop

lint:
	@luacheck kong*.rockspec

test:
	@busted spec/unit

coverage:
	@rm -f luacov.*
	@busted --coverage spec/unit
	@luacov -c spec/.luacov

test-api:
	@busted spec/api

test-proxy:
	@busted spec/proxy

test-server:
	@busted spec/server

test-all:
	@busted spec/
