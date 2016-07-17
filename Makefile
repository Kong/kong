DEV_ROCKS = busted luacheck

.PHONY: install dev doc lint test test-integration test-plugins test-all

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

doc:
	@ldoc -c config.ld kong

lint:
	@luacheck -q . \
						--exclude-files 'kong/vendor/**/*.lua' \
						--exclude-files 'spec/fixtures/invalid-module.lua' \
						--std 'ngx_lua+busted' \
						--globals '_KONG' \
						--globals 'ngx' \
						--globals 'assert' \
						--no-redefined \
						--no-unused-args

test:
	@bin/busted -v spec/01-unit

test-integration:
	@bin/busted -v spec/02-integration

test-plugins:
	@bin/busted -v spec/03-plugins

test-all:
	@bin/busted -v spec/
