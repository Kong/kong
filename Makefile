OS := $(shell uname | awk '{print tolower($$0)}')
MACHINE := $(shell uname -m)

DEV_ROCKS = "busted 2.0.rc13" "luacheck 0.20.0" "lua-llthreads2 0.1.5"
WIN_SCRIPTS = "bin/busted" "bin/kong"
BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)

ifeq ($(OS), darwin)
OPENSSL_DIR ?= /usr/local/opt/openssl
GRPCURL_OS ?= osx
else
OPENSSL_DIR ?= /usr
GRPCURL_OS ?= $(OS)
endif

.PHONY: install remove dependencies grpcurl dev \
	lint test test-integration test-plugins test-all fix-windows

KONG_GMP_VERSION ?= `grep KONG_GMP_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_VERSION ?= `grep RESTY_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_LUAROCKS_VERSION ?= `grep RESTY_LUAROCKS_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_OPENSSL_VERSION ?= `grep RESTY_OPENSSL_VERSION .requirements | awk -F"=" '{print $$2}'`
RESTY_PCRE_VERSION ?= `grep RESTY_PCRE_VERSION .requirements | awk -F"=" '{print $$2}'`
KONG_BUILD_TOOLS ?= 'origin/feat/arm32'
KONG_VERSION ?= `cat kong-*.rockspec | grep tag | awk '{print $$3}' | sed 's/"//g'`

setup-kong-build-tools:
	-rm -rf kong-build-tools; \
	git clone https://github.com/Kong/kong-build-tools.git; fi
	cd kong-build-tools; \
	git reset --hard $(KONG_BUILD_TOOLS); \

functional-tests: setup-kong-build-tools
	cd kong-build-tools; \
	export KONG_SOURCE_LOCATION=`pwd`/../ && \
	$(MAKE) setup-build && \
	$(MAKE) build-kong && \
	$(MAKE) test

nightly-release: setup-kong-build-tools
	sed -i -e '/return string\.format/,/\"\")/c\return "$(KONG_VERSION)\"' kong/meta.lua && \
	cd kong-build-tools; \
	export KONG_SOURCE_LOCATION=`pwd`/../ && \
	$(MAKE) setup-build && \
	$(MAKE) build-kong && \
	$(MAKE) release-kong

release: setup-release
	cd kong-build-tools; \
	export KONG_SOURCE_LOCATION=`pwd`/../ && \
	$(MAKE) package-kong && \
	$(MAKE) release-kong

install:
	@luarocks make OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR)

remove:
	-@luarocks remove kong

dependencies:
	@for rock in $(DEV_ROCKS) ; do \
	  if luarocks list --porcelain $$rock | grep -q "installed" ; then \
	    echo $$rock already installed, skipping ; \
	  else \
	    echo $$rock not found, installing via luarocks... ; \
	    luarocks install $$rock OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR); \
	  fi \
	done;

grpcurl:
	@curl -s -S -L \
		https://github.com/fullstorydev/grpcurl/releases/download/v1.3.0/grpcurl_1.3.0_$(GRPCURL_OS)_$(MACHINE).tar.gz | tar xz -C bin;
	@rm bin/LICENSE

dev: remove install dependencies grpcurl

lint:
	@luacheck -q .
	@!(grep -R -E -n -w '#only|#o' spec && echo "#only or #o tag detected") >&2
	@!(grep -R -E -n -- '---\s+ONLY' t && echo "--- ONLY block detected") >&2

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
