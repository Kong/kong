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

ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
KONG_GMP_VERSION ?= `grep KONG_GMP_VERSION $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
RESTY_VERSION ?= `grep RESTY_VERSION $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
RESTY_LUAROCKS_VERSION ?= `grep RESTY_LUAROCKS_VERSION $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
RESTY_OPENSSL_VERSION ?= `grep RESTY_OPENSSL_VERSION $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
RESTY_PCRE_VERSION ?= `grep RESTY_PCRE_VERSION $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
KONG_BUILD_TOOLS ?= `grep KONG_BUILD_TOOLS $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
KONG_NGINX_MODULE_BRANCH ?= `grep KONG_NGINX_MODULE_BRANCH $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
OPENRESTY_PATCHES_BRANCH ?= `grep KONG_NGINX_MODULE_BRANCH $(ROOT_DIR)/.requirements | awk -F"=" '{print $$2}'`
KONG_VERSION ?= `cat kong-*.rockspec | grep tag | awk '{print $$3}' | sed 's/"//g'`
KONG_SOURCE_LOCATION ?= $(ROOT_DIR)

setup-ci:
	DOWNLOAD_ROOT=$(DOWNLOAD_ROOT) \
	OPENRESTY_BUILD_TOOLS_VERSION=$(OPENRESTY_BUILD_TOOLS_VERSION) \
	BUILD_TOOLS_DOWNLOAD=$(BUILD_TOOLS_DOWNLOAD) \
	INSTALL_CACHE=$(INSTALL_CACHE) \
	INSTALL_ROOT=$(INSTALL_ROOT) \
	RESTY_VERSION=$(RESTY_VERSION) \
	OPENRESTY_PATCHES_BRANCH=$(OPENRESTY_PATCHES_BRANCH) \
	KONG_NGINX_MODULE_BRANCH=$(KONG_NGINX_MODULE_BRANCH) \
	RESTY_LUAROCKS_VERSION=$(RESTY_LUAROCKS_VERSION) \
	RESTY_OPENSSL_VERSION=$(RESTY_OPENSSL_VERSION) \
	JOBS=$(JOBS) \
	.ci/setup_env.sh

setup-kong-build-tools:
	-rm -rf kong-build-tools
	git clone --single-branch --branch $(KONG_BUILD_TOOLS) https://github.com/Kong/kong-build-tools.git

functional-tests: setup-kong-build-tools
	cd kong-build-tools; \
	$(MAKE) setup-build && \
	$(MAKE) build-kong && \
	$(MAKE) test

nightly-release: setup-kong-build-tools
	sed -i -e '/return string\.format/,/\"\")/c\return "$(KONG_VERSION)\"' kong/meta.lua && \
	cd kong-build-tools; \
	$(MAKE) setup-build && \
	$(MAKE) build-kong && \
	$(MAKE) release-kong

release: setup-kong-build-tools
	cd kong-build-tools; \
	$(MAKE) setup-build && \
	$(MAKE) build-kong && \
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
