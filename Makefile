DEV_ROCKS = busted luacheck lua-llthreads2
BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)
OPENSSL_DIR ?= /usr/local/opt/openssl

.PHONY: install dev lint test test-integration test-plugins test-all

install:
	@luarocks make OPENSSL_DIR=$(OPENSSL_DIR)

dev: install
	@for rock in $(DEV_ROCKS) ; do \
		if ! luarocks list | grep $$rock > /dev/null ; then \
      echo $$rock not found, installing via luarocks... ; \
      luarocks install $$rock ; \
    else \
      echo $$rock already installed, skipping ; \
    fi \
	done;

lint:
	@luacheck -q .

test:
	@$(TEST_CMD) spec/01-unit

test-integration:
	@$(TEST_CMD) spec/02-integration

test-plugins:
	@$(TEST_CMD) spec/03-plugins

test-all:
	@$(TEST_CMD) spec/
