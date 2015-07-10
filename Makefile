TESTING_CONF = kong_TEST.yml
DEVELOPMENT_CONF = kong_DEVELOPMENT.yml
DEV_ROCKS="busted 2.0.rc9-0" "luacov" "luacov-coveralls" "luacheck"

.PHONY: install dev clean start seed drop lint test coverage test-all

install:
	@if [ `uname` = "Darwin" ]; then \
		luarocks make kong-*.rockspec; \
	else \
		luarocks make kong-*.rockspec \
		PCRE_LIBDIR=`find / -type f -name "libpcre.so*" -print -quit | xargs dirname` \
		OPENSSL_LIBDIR=`find / -type f -name "libssl.so*" -print -quit | xargs dirname`; \
	fi

dev: install
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
	@bin/kong migrations -c $(DEVELOPMENT_CONF) reset
	rm -f $(DEVELOPMENT_CONF) $(TESTING_CONF)
	rm -f luacov.*
	rm -rf nginx_tmp

start:
	@bin/kong start -c $(DEVELOPMENT_CONF)

stop:
	@bin/kong stop -c $(DEVELOPMENT_CONF)

seed:
	@bin/kong db -c $(DEVELOPMENT_CONF) seed

drop:
	@bin/kong db -c $(DEVELOPMENT_CONF) drop

lint:
	@find kong spec -name '*.lua' ! -name 'invalid-module.lua' | xargs luacheck -q

test:
	@busted spec/unit

coverage:
	@rm -f luacov.*
	@busted --coverage spec/unit
	@luacov -c spec/.luacov
	@tail -n 1 luacov.report.out | awk '{ print $$3 }'

test-all:
	@busted spec/
