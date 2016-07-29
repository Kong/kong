DEV_ROCKS = busted luacheck lua-llthreads2
BUSTED_ARGS ?= -v
TEST_CMD = bin/busted $(BUSTED_ARGS)

.PHONY: install dev lint test test-integration test-plugins test-all

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
	@$(TEST_CMD) spec/01-unit

test-integration:
	@$(TEST_CMD) spec/02-integration

test-plugins:
	@$(TEST_CMD) spec/03-plugins

test-all:
	@$(TEST_CMD) spec/
