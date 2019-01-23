OS := $(shell uname)

DEV_ROCKS = "busted 2.0.rc13" "luacheck 0.20.0" "lua-llthreads2 0.1.5"
WIN_SCRIPTS = "bin/busted" "bin/kong"
BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)

ifeq ($(OS), Darwin)
OPENSSL_DIR ?= /usr/local/opt/openssl
else
OPENSSL_DIR ?= /usr
endif

.PHONY: install dev lint test test-integration test-plugins test-all fix-windows

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
	    luarocks install $$rock OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR); \
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

pdk-phase-checks:
	rm -f t/phase_checks.stats
	rm -f t/phase_checks.report
	PDK_PHASE_CHECKS_LUACOV=1 prove -I. t/01*/*/00-phase*.t
	luacov -c t/phase_checks.luacov
	grep "ngx\\." t/phase_checks.report
	grep "check_" t/phase_checks.report

fix-windows:
	@for script in $(WIN_SCRIPTS) ; do \
	  echo Converting Windows file $$script ; \
	  mv $$script $$script.win ; \
	  tr -d '\015' <$$script.win >$$script ; \
	  rm $$script.win ; \
	  chmod 0755 $$script ; \
	done;

