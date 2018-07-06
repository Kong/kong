OS := $(shell uname)

DEV_ROCKS = "busted 2.0.rc12" "luacheck 0.20.0" "lua-llthreads2 0.1.5"
WIN_SCRIPTS = "bin/busted" "bin/kong"
BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)

ifeq ($(OS), Darwin)
OPENSSL_DIR ?= /usr/local/opt/openssl
else
OPENSSL_DIR ?= /usr
endif

.PHONY: install dev lint test test-integration test-plugins test-all win_scripts

install: win_scripts
	@luarocks make OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR)

dev: win_scripts
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

lint:
	@luacheck -q .

test: win_scripts
	@$(TEST_CMD) spec/01-unit

test-integration: win_scripts
	@$(TEST_CMD) spec/02-integration

test-plugins: win_scripts
	@$(TEST_CMD) spec/03-plugins

test-all: win_scripts
	@$(TEST_CMD) spec/

old-test: win_scripts
	@$(TEST_CMD) spec-old-api/01-unit

old-test-integration: win_scripts
	@$(TEST_CMD) spec-old-api/02-integration

old-test-plugins: win_scripts
	@$(TEST_CMD) spec-old-api/03-plugins

old-test-all: win_scripts
	@$(TEST_CMD) spec-old-api/

pdk-phase-checks:
	rm -f t/phase_checks.stats
	rm -f t/phase_checks.report
	PDK_PHASE_CHECKS_LUACOV=1 prove -I. t/01*/*/00-phase*.t
	luacov -c t/phase_checks.luacov
	grep "ngx\\." t/phase_checks.report
	grep "check_" t/phase_checks.report

win_scripts:
	@for script in $(WIN_SCRIPTS) ; do \
	  if [ $$(grep -obUaPc '\015' $$script) -gt 0 ] ; then \
	    echo Converting Windows file $$script ; \
	    mv $$script $$script.win ; \
	    tr -d '\015' <$$script.win >$$script ; \
	    rm $$script.win ; \
	  fi \
	done;

