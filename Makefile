OS := $(shell uname | awk '{print tolower($$0)}')
MACHINE := $(shell uname -m)

DEV_ROCKS = "busted 2.0.0" "busted-htest 1.0.0" "luacheck 0.25.0" "lua-llthreads2 0.1.6" "http 0.4" "ldoc 1.4.6"
WIN_SCRIPTS = "bin/busted" "bin/kong"
BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)

BUILD_NAME ?= kong-dev
BAZEL_ARGS ?= --verbose_failures --action_env=BUILD_NAME=$(BUILD_NAME) --//:skip_webui=true

ifeq ($(OS), darwin)
OPENSSL_DIR ?= /usr/local/opt/openssl
GRPCURL_OS ?= osx
else
OPENSSL_DIR ?= /usr
GRPCURL_OS ?= $(OS)
endif

ifeq ($(MACHINE), aarch64)
GRPCURL_MACHINE ?= arm64
H2CLIENT_MACHINE ?= arm64
else
GRPCURL_MACHINE ?= $(MACHINE)
H2CLIENT_MACHINE ?= $(MACHINE)
endif

ifeq ($(MACHINE), aarch64)
BAZELISK_MACHINE ?= arm64
else ifeq ($(MACHINE), x86_64)
BAZELISK_MACHINE ?= amd64
else
BAZELISK_MACHINE ?= $(MACHINE)
endif

.PHONY: install dependencies dev remove grpcurl \
	setup-ci setup-kong-build-tools \
	lint test test-integration test-plugins test-all \
	pdk-phase-check functional-tests \
	fix-windows release \
	nightly-release release

ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
KONG_SOURCE_LOCATION ?= $(ROOT_DIR)
KONG_BUILD_TOOLS_LOCATION ?= $(KONG_SOURCE_LOCATION)/../kong-build-tools
RESTY_VERSION ?= `grep RESTY_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_LUAROCKS_VERSION ?= `grep RESTY_LUAROCKS_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_OPENSSL_VERSION ?= `grep RESTY_OPENSSL_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_PCRE_VERSION ?= `grep RESTY_PCRE_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
KONG_BUILD_TOOLS ?= `grep KONG_BUILD_TOOLS_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
GRPCURL_VERSION ?= 1.8.5
BAZLISK_VERSION ?= 1.18.0
OPENRESTY_PATCHES_BRANCH ?= master
KONG_NGINX_MODULE_BRANCH ?= master
BAZEL := $(shell command -v bazel 2> /dev/null)
VENV = /dev/null # backward compatibility when no venv is built

# Use x86_64 grpcurl v1.8.5 for Apple silicon chips
ifeq ($(GRPCURL_OS)_$(MACHINE)_$(GRPCURL_VERSION), osx_arm64_1.8.5)
GRPCURL_MACHINE = x86_64
endif

H2CLIENT_VERSION ?= 0.4.0

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

release-docker-images:
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	$(MAKE) \
	KONG_SOURCE_LOCATION=${KONG_SOURCE_LOCATION} \
	package-kong && \
	$(MAKE) \
	KONG_SOURCE_LOCATION=${KONG_SOURCE_LOCATION} \
	release-kong-docker-images

bin/bazel:
	@curl -s -S -L \
		https://github.com/bazelbuild/bazelisk/releases/download/v$(BAZLISK_VERSION)/bazelisk-$(OS)-$(BAZELISK_MACHINE) -o bin/bazel
	@chmod +x bin/bazel

bin/grpcurl:
	@curl -s -S -L \
		https://github.com/fullstorydev/grpcurl/releases/download/v$(GRPCURL_VERSION)/grpcurl_$(GRPCURL_VERSION)_$(GRPCURL_OS)_$(GRPCURL_MACHINE).tar.gz | tar xz -C bin;
	@$(RM) bin/LICENSE

bin/h2client:
	@curl -s -S -L \
		https://github.com/Kong/h2client/releases/download/v$(H2CLIENT_VERSION)/h2client_$(H2CLIENT_VERSION)_$(OS)_$(H2CLIENT_MACHINE).tar.gz | tar xz -C bin;
	@$(RM) bin/README.md

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

package/deb: setup-kong-build-tools
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) package-kong && \
	cp $(KONG_BUILD_TOOLS_LOCATION)/output/*.deb .

package/apk: setup-kong-build-tools
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) package-kong && \
	cp $(KONG_BUILD_TOOLS_LOCATION)/output/*.apk.* .

package/rpm: setup-kong-build-tools
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) package-kong && \
	cp $(KONG_BUILD_TOOLS_LOCATION)/output/*.rpm .

package/test/deb: package/deb
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) test

package/test/apk: package/apk
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) test

package/test/rpm: package/rpm
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) test

package/docker/deb: package/deb
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) build-test-container

package/docker/apk: package/apk
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) build-test-container

package/docker/rpm: package/rpm
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) build-test-container

release/docker/deb: package/docker/deb
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) release-kong-docker-images

release/docker/apk: package/docker/apk
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) release-kong-docker-images

release/docker/rpm: package/docker/rpm
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) release-kong-docker-images

setup-kong-build-tools:
	-rm -rf $(KONG_BUILD_TOOLS_LOCATION)
	-git clone https://github.com/Kong/kong-build-tools.git --recursive $(KONG_BUILD_TOOLS_LOCATION)
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	git reset --hard && git checkout $(KONG_BUILD_TOOLS); \

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
	    luarocks install $$rock OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR) || exit 1; \
	  fi \
	done;

build-kong: check-bazel
	$(BAZEL) build //build:kong --verbose_failures --action_env=BUILD_NAME=$(BUILD_NAME)

build-venv: check-bazel
	$(eval VENV := bazel-bin/build/$(BUILD_NAME)-venv.sh)

	@if [ ! -e bazel-bin/build/$(BUILD_NAME)-venv.sh ]; then \
		$(BAZEL) build //build:venv $(BAZEL_ARGS); \
	fi

install-dev-rocks: build-venv
	@. $(VENV) ;\
	for rock in $(DEV_ROCKS) ; do \
	  if luarocks list --porcelain $$rock | grep -q "installed" ; then \
		echo $$rock already installed, skipping ; \
	  else \
		echo $$rock not found, installing via luarocks... ; \
		LIBRARY_PREFIX=$$(pwd)/bazel-bin/build/$(BUILD_NAME)/kong ; \
		luarocks install $$rock OPENSSL_DIR=$$LIBRARY_PREFIX CRYPTO_DIR=$$LIBRARY_PREFIX YAML_DIR=$(YAML_DIR) || exit 1; \
	  fi \
	done;

dev: remove install dependencies

venv-dev: build-venv install-dev-rocks bin/grpcurl bin/h2client

check-bazel: bin/bazel
ifndef BAZEL
	$(eval BAZEL := bin/bazel)
endif

clean:  check-bazel
	$(BAZEL) clean
	$(RM) bin/bazel bin/grpcurl bin/h2client


lint:
	@luacheck -q . --exclude-files=bazel-*
	@!(grep -R -E -I -n -w '#only|#o' spec && echo "#only or #o tag detected") >&2
	@!(grep -R -E -I -n -- '---\s+ONLY' t && echo "--- ONLY block detected") >&2

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
