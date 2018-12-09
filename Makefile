OS := $(shell uname)

DEV_ROCKS = "busted 2.0.rc12" "luacheck 0.20.0" "lua-llthreads2 0.1.4"
BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)

ifeq ($(OS), Darwin)
OPENSSL_DIR ?= /usr/local/opt/openssl
else
OPENSSL_DIR ?= /usr
endif

.PHONY: install dev lint test test-integration test-plugins test-all

install:
	@luarocks make OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR)

dev:
	-@luarocks remove kong
	@luarocks make OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR)
	@for rock in $(DEV_ROCKS) ; do \
	  if luarocks list --porcelain $$rock | grep -q "installed" ; then \
	    echo $$rock already installed, skipping ; \
	  else \
	    echo $$rock not found, installing via luarocks... ; \
	    luarocks install $$rock ; \
	  fi \
	done;
	luarocks install luacheck 0.20.0

lint:
	@luacheck -q .

test:
	@$(TEST_CMD) spec/01-unit

test-ee:
	@$(TEST_CMD) spec-ee/01-unit

test-integration:
	@$(TEST_CMD) spec/02-integration

test-integration-ee:
	@$(TEST_CMD) spec-ee/02-integration

test-plugins:
	@$(TEST_CMD) spec/03-plugins

test-plugins-ee:
	@$(TEST_CMD) spec-ee/03-plugins

test-all:
	@$(TEST_CMD) spec/

test-all-ee:
	@$(TEST_CMD) spec-ee/

old-test:
	@$(TEST_CMD) spec-old-api/01-unit

old-test-integration:
	@$(TEST_CMD) spec-old-api/02-integration

old-test-plugins:
	@$(TEST_CMD) spec-old-api/03-plugins

old-test-all:
	@$(TEST_CMD) spec-old-api/
