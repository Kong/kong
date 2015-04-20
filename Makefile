TESTING_CONF = kong_TEST.yml
DEVELOPMENT_CONF = kong_DEVELOPMENT.yml
DEV_ROCKS=busted luacov luacov-coveralls luacheck

.PHONY: install dev clean run seed drop lint test coverage test-api test-proxy test-server test-all

install:
	@if [ `uname` == "Darwin" ]; then \
		luarocks make kong-*.rockspec; \
	else \
		luarocks make kong-*.rockspec \
		PCRE_LIBDIR=`find / -type f -name "libpcre.so*" -print -quit | xargs dirname` \
		OPENSSL_LIBDIR=`find / -type f -name "libssl.so*" -print -quit | xargs dirname`; \
	fi

dev:
	@for rock in $(DEV_ROCKS) ; do \
		if ! command -v $$rock &> /dev/null ; then \
      echo $$rock not found, installing via luarocks... ; \
      luarocks install $$rock ; \
    else \
      echo $$rock already installed, skipping ; \
    fi \
	done;
	bin/kong config -c kong.yml -e TEST
	bin/kong config -c kong.yml -e DEVELOPMENT
	bin/kong migrations -c $(DEVELOPMENT_CONF) up

clean:
	@rm -f luacov.*
	@rm -rf nginx_tmp
	@bin/kong migrations -c $(DEVELOPMENT_CONF) reset
	@rm -f $(DEVELOPMENT_CONF) $(TESTING_CONF)

run:
	@bin/kong start -c $(DEVELOPMENT_CONF)

seed:
	@bin/kong db -c $(DEVELOPMENT_CONF) seed

drop:
	@bin/kong db -c $(DEVELOPMENT_CONF) drop

lint:
	@luacheck kong*.rockspec

test:
	@busted spec/unit

coverage:
	@rm -f luacov.*
	@busted --coverage spec/unit
	@luacov -c spec/.luacov
	@tail -n 1 luacov.report.out | awk '{ print $$3 }'

test-api:
	@busted spec/integration/api

test-proxy:
	@busted spec/integration/proxy

test-server:
	@busted spec/integration/server

test-all:
	@busted spec/
