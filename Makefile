OS := $(shell uname | awk '{print tolower($$0)}')
MACHINE := $(shell uname -m)

DEV_ROCKS = "busted 2.0.0" "busted-htest 1.0.0" "luacheck 0.24.0" "lua-llthreads2 0.1.5" "http 0.3" "ldoc 1.4.6"
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

.PHONY: install dependencies dev remove grpcurl \
	setup-ci setup-kong-build-tools \
	lint test test-integration test-plugins test-all \
	pdk-phase-check functional-tests \
	fix-windows \
	nightly-release release

ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
KONG_SOURCE_LOCATION ?= $(ROOT_DIR)
KONG_BUILD_TOOLS_LOCATION ?= $(KONG_SOURCE_LOCATION)/../kong-build-tools
RESTY_VERSION ?= `grep RESTY_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_LUAROCKS_VERSION ?= `grep RESTY_LUAROCKS_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_OPENSSL_VERSION ?= `grep RESTY_OPENSSL_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_PCRE_VERSION ?= `grep RESTY_PCRE_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
KONG_BUILD_TOOLS ?= '4.12.1'
GRPCURL_VERSION ?= '9846afccbc2f34255dfb459dc6f0196a2b6dbe05'
OPENRESTY_PATCHES_BRANCH ?= master
KONG_NGINX_MODULE_BRANCH ?= master

PACKAGE_TYPE ?= deb
REPOSITORY_NAME ?= kong-${PACKAGE_TYPE}
REPOSITORY_OS_NAME ?= ${RESTY_IMAGE_BASE}
KONG_PACKAGE_NAME ?= kong
# This logic should mirror the kong-build-tools equivalent
KONG_VERSION ?= `echo $(KONG_SOURCE_LOCATION)/kong-*.rockspec | sed 's,.*/,,' | cut -d- -f2`

TAG := $(shell git describe --exact-match HEAD || true)

ifneq ($(TAG),)
	# We're building a tag
	ISTAG = true
	POSSIBLE_PRERELEASE_NAME = $(shell git describe --tags --abbrev=0 | awk -F"-" '{print $$2}')
	ifneq ($(POSSIBLE_PRERELEASE_NAME),)
		# We're building a pre-release tag
		OFFICIAL_RELEASE = false
		REPOSITORY_NAME = kong-prerelease
	else
		# We're building a semver release tag
		OFFICIAL_RELEASE = true
		KONG_VERSION ?= `cat $(KONG_SOURCE_LOCATION)/kong-*.rockspec | grep -m1 tag | awk '{print $$3}' | sed 's/"//g'`
		ifeq ($(PACKAGE_TYPE),apk)
		    REPOSITORY_NAME = kong-alpine-tar
		endif
	endif
else
	OFFICIAL_RELEASE = false
	ISTAG = false
	BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
	REPOSITORY_NAME = kong-${BRANCH}
	REPOSITORY_OS_NAME = ${BRANCH}
	KONG_PACKAGE_NAME ?= kong-${BRANCH}
	KONG_VERSION ?= `date +%Y-%m-%d`
endif

release:
ifeq ($(ISTAG),false)
	sed -i -e '/return string\.format/,/\"\")/c\return "$(KONG_VERSION)\"' kong/meta.lua
endif
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	$(MAKE) \
	KONG_VERSION=${KONG_VERSION} \
	KONG_PACKAGE_NAME=${KONG_PACKAGE_NAME} \
	package-kong && \
	$(MAKE) \
	KONG_VERSION=${KONG_VERSION} \
	KONG_PACKAGE_NAME=${KONG_PACKAGE_NAME} \
	REPOSITORY_NAME=${REPOSITORY_NAME} \
	REPOSITORY_OS_NAME=${REPOSITORY_OS_NAME} \
	KONG_PACKAGE_NAME=${KONG_PACKAGE_NAME} \
	KONG_VERSION=${KONG_VERSION} \
	OFFICIAL_RELEASE=$(OFFICIAL_RELEASE) \
	release-kong

setup-ci:
	OPENRESTY=$(RESTY_VERSION) \
	LUAROCKS=$(RESTY_LUAROCKS_VERSION) \
	OPENSSL=$(RESTY_OPENSSL_VERSION) \
	OPENRESTY_PATCHES_BRANCH=$(OPENRESTY_PATCHES_BRANCH) \
	KONG_NGINX_MODULE_BRANCH=$(KONG_NGINX_MODULE_BRANCH) \
	.ci/setup_env.sh

setup-kong-build-tools:
	-rm -rf $(KONG_BUILD_TOOLS_LOCATION)
	-git clone https://github.com/Kong/kong-build-tools.git $(KONG_BUILD_TOOLS_LOCATION)
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	git reset --hard $(KONG_BUILD_TOOLS); \

functional-tests: setup-kong-build-tools
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	$(MAKE) setup-build && \
	$(MAKE) build-kong && \
	$(MAKE) test

install:
	@luarocks make OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR)

remove:
	-@luarocks remove kong

dependencies: bin/grpcurl
	@for rock in $(DEV_ROCKS) ; do \
	  if luarocks list --porcelain $$rock | grep -q "installed" ; then \
	    echo $$rock already installed, skipping ; \
	  else \
	    echo $$rock not found, installing via luarocks... ; \
	    luarocks install $$rock OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR); \
	  fi \
	done;

bin/grpcurl:
ifeq (, $(shell which go))
	$(error "error building grpcurl: no go compiler found in PATH")
endif
	@cd bin && \
	go mod init grpcurl && \
	go get -v -d github.com/fullstorydev/grpcurl@$(GRPCURL_VERSION) && \
	go build -ldflags '-X "main.version=kong dev build $(GRPCURL_VERSION)"' github.com/fullstorydev/grpcurl/cmd/grpcurl && \
	rm -f go.mod go.sum

dev: remove install dependencies

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
