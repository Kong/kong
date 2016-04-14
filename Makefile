TESTING_CONF = kong_TEST.yml
DEVELOPMENT_CONF = kong_DEVELOPMENT.yml
DEV_ROCKS = busted luacov luacov-coveralls luacheck

.PHONY: install dev clean doc lint test test-integration test-plugins test-all coverage

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
		if ! command -v $$rock > /dev/null ; then \
      echo $$rock not found, installing via luarocks... ; \
      luarocks install $$rock ; \
    else \
      echo $$rock already installed, skipping ; \
    fi \
	done;
	bin/kong config -c kong.yml -e TEST -s TEST
	bin/kong config -c kong.yml -e DEVELOPMENT -s DEVELOPMENT
	bin/kong migrations -c $(DEVELOPMENT_CONF) up

clean:
	@bin/kong migrations -c $(DEVELOPMENT_CONF) reset
	rm -f $(DEVELOPMENT_CONF) $(TESTING_CONF)
	rm -f luacov.*
	rm -rf nginx_tmp

doc:
	@ldoc -c config.ld kong

lint:
	@luacheck -q . \
						--exclude-files 'kong/vendor/**/*.lua' \
						--exclude-files 'spec/unit/fixtures/invalid-module.lua' \
						--std 'ngx_lua+busted' \
						--globals '_KONG' \
						--globals 'ngx' \
						--no-redefined \
						--no-unused-args

test:
	@busted -v spec/unit

test-integration:
	@busted -v spec/integration

test-plugins:
	@busted -v spec/plugins

test-all:
	@busted -v spec/

coverage:
	@rm -f luacov.*
	@busted --coverage spec/
	@luacov -c spec/.luacov
	@tail -n 1 luacov.report.out | awk '{ print $$3 }'
