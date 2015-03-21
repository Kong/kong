TESTING_CONF = kong_TEST.yml
DEVELOPMENT_CONF = kong_DEVELOPMENT.yml

.PHONY: install dev clean seed drop test coverage test-api test-proxy test-server test-all

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
	@bin/kong config -e TEST
	@bin/kong config -e DEVELOPMENT
	@scripts/db.lua -c $(DEVELOPMENT_CONF) migrate

clean:
	@rm -f luacov.*
	@rm -f $(DEVELOPMENT_CONF) $(TESTING_CONF)
	@rm -rf nginx_tmp
	@scripts/db.lua -c $(DEVELOPMENT_CONF) reset

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
	@busted spec/integration/api

test-proxy:
	@busted spec/integration/proxy

test-server:
	@busted spec/integration/server

test-all:
	@busted spec/
