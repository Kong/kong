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

include .requirements
.PHONY: install dev lint test test-integration test-plugins test-all fix-windows

KONG_GMP_VERSION ?= `grep KONG_GMP_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_VERSION ?= `grep RESTY_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_LUAROCKS_VERSION ?= `grep RESTY_LUAROCKS_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_OPENSSL_VERSION ?= `grep RESTY_OPENSSL_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_PCRE_VERSION ?= `grep RESTY_PCRE_VERSION .requirements | awk -F"=" '{print $$2}'`
KONG_BUILD_TOOLS ?= `grep KONG_BUILD_TOOLS .requirements | awk -F"=" '{print $$2}'`
KONG_VERSION ?= `cat kong-*.rockspec | grep tag | awk '{print $$3}' | sed 's/"//g'`

setup-release:
	if cd kong-build-tools; \
	then git pull; \
	else git clone https://github.com/Kong/kong-build-tools.git; fi
	cd kong-build-tools; \
	git fetch; \
	git reset --hard origin/$(KONG_BUILD_TOOLS); \
	make setup_tests

functional_tests: setup-release
	cd kong-build-tools; \
	export KONG_SOURCE_LOCATION=`pwd`/../ && \
	make package-kong && \
	make test

nightly-release: setup-release
	sed -i -e '/return string\.format/,/\"\")/c\return "$(KONG_VERSION)\"' kong/meta.lua && \
	cd kong-build-tools; \
	export KONG_SOURCE_LOCATION=`pwd`/../ && \
	make package-kong && \
	make release-kong

release: setup-release
	cd kong-build-tools; \
	export KONG_SOURCE_LOCATION=`pwd`/../ && \
	make package-kong && \
	make release-kong

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
