$(info starting make in kong-ee)

OS := $(shell uname | awk '{print tolower($$0)}')
MACHINE := $(shell uname -m)

DEV_ROCKS = "busted 2.1.1" "busted-hjtest 0.0.4" "luacheck 1.1.0" "lua-llthreads2 0.1.6" "http 0.4" "ldoc 1.4.6"
WIN_SCRIPTS = "bin/busted" "bin/kong" "bin/kong-health"
BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)

ifeq ($(OS), darwin)
HOMEBREW_DIR ?= /opt/homebrew
OPENSSL_DIR ?= $(shell brew --prefix)/opt/openssl
EXPAT_DIR ?= $(HOMEBREW_DIR)/opt/expat
LIBXML2_DIR ?= $(HOMEBREW_DIR)/opt/libxml2
GRPCURL_OS ?= osx
YAML_DIR ?= $(shell brew --prefix)/opt/libyaml
else
LIBRARY_PREFIX ?= /usr
OPENSSL_DIR ?= $(LIBRARY_PREFIX)
EXPAT_DIR ?= $(LIBRARY_PREFIX)
LIBXML2_DIR ?= $(LIBRARY_PREFIX)
GRPCURL_OS ?= $(OS)
YAML_DIR ?= /usr
endif

ifeq ($(MACHINE), aarch64)
GRPCURL_MACHINE ?= arm64
else
GRPCURL_MACHINE ?= $(MACHINE)
endif

.PHONY: install dependencies dev remove grpcurl \
	setup-ci setup-kong-build-tools \
	sca test test-integration test-plugins test-all \
	pdk-phase-check functional-tests \
	fix-windows release

ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
KONG_SOURCE_LOCATION ?= $(ROOT_DIR)
KONG_BUILD_TOOLS_LOCATION ?= $(KONG_SOURCE_LOCATION)/../kong-build-tools
KONG_GMP_VERSION ?= `grep KONG_GMP_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_VERSION ?= `grep RESTY_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_LUAROCKS_VERSION ?= `grep RESTY_LUAROCKS_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_OPENSSL_VERSION ?= `grep RESTY_OPENSSL_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
RESTY_PCRE_VERSION ?= `grep RESTY_PCRE_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
KONG_BUILD_TOOLS ?= `grep KONG_BUILD_TOOLS_VERSION $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`
GRPCURL_VERSION ?= 1.8.5
OPENRESTY_PATCHES_BRANCH ?= master
KONG_NGINX_MODULE_BRANCH ?= master

PACKAGE_TYPE ?= deb

GITHUB_TOKEN ?=

# whether to enable bytecompilation of kong lua files or not
ENABLE_LJBC ?= `grep ENABLE_LJBC $(KONG_SOURCE_LOCATION)/.requirements | awk -F"=" '{print $$2}'`

TAG := $(shell git describe --exact-match --tags HEAD 2>/dev/null || true)

ifneq ($(TAG),)
	# if we're building a tag the tag name is the KONG_VERSION (allows for environment var to override)
	ISTAG = true
	KONG_TAG = $(TAG)

	POSSIBLE_PRERELEASE_NAME = $(shell git describe --tags --abbrev=0 | awk -F"-" '{print $$2}')
	ifneq ($(POSSIBLE_PRERELEASE_NAME),)
		# it's a pre-release if the tag has a - in which case it's an internal release only
		OFFICIAL_RELEASE = false
	else
		# it's not a pre-release so do the release officially
		OFFICIAL_RELEASE = true
	endif
else
	# we're not building a tag so this is a nightly build
	RELEASE_DOCKER_ONLY = true
	OFFICIAL_RELEASE = false
	ISTAG = false
endif

release-docker-images:
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	$(MAKE) \
	KONG_SOURCE_LOCATION=${KONG_SOURCE_LOCATION} \
	package-kong && \
	$(MAKE) \
	KONG_SOURCE_LOCATION=${KONG_SOURCE_LOCATION} \
	release-kong-docker-images

release:
ifeq ($(ISTAG),false)
	sed -i -e '/return string\.format/,/\"\")/c\return "$(KONG_VERSION)\"' kong/meta.lua
endif
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	$(MAKE) \
	KONG_SOURCE_LOCATION=${KONG_SOURCE_LOCATION} \
	KONG_TAG=${KONG_TAG} \
	package-kong && \
	$(MAKE) \
	KONG_SOURCE_LOCATION=${KONG_SOURCE_LOCATION} \
	KONG_TAG=${KONG_TAG} \
	RELEASE_DOCKER_ONLY=${RELEASE_DOCKER_ONLY} \
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
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) package-kong && \
	cp $(KONG_BUILD_TOOLS_LOCATION)/output/*.deb .

package/apk: setup-kong-build-tools
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) package-kong && \
	cp $(KONG_BUILD_TOOLS_LOCATION)/output/*.apk.* .

package/rpm: setup-kong-build-tools
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) package-kong && \
	cp $(KONG_BUILD_TOOLS_LOCATION)/output/*.rpm .

package/test/deb: package/deb
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) test

package/test/apk: package/apk
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) test

package/test/rpm: package/rpm
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) test

package/docker/deb: package/deb
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) build-test-container

package/docker/apk: package/apk
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) build-test-container

package/docker/rpm: package/rpm
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) build-test-container

release/docker/deb: package/docker/deb
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=deb RESTY_IMAGE_BASE=ubuntu RESTY_IMAGE_TAG=22.04 $(MAKE) release-kong-docker-images

release/docker/apk: package/docker/apk
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=apk RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 $(MAKE) release-kong-docker-images

release/docker/rpm: package/docker/rpm
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	KONG_SOURCE_LOCATION=$(PWD) PACKAGE_TYPE=rpm RESTY_IMAGE_BASE=rhel RESTY_IMAGE_TAG=8.6 $(MAKE) release-kong-docker-images

setup-kong-build-tools:
	-git submodule update --init --recursive
	-git submodule status
	-rm -rf $(KONG_BUILD_TOOLS_LOCATION)
	-git clone https://github.com/Kong/kong-build-tools.git --recursive $(KONG_BUILD_TOOLS_LOCATION)
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	git reset --hard && git checkout $(KONG_BUILD_TOOLS); \

functional-tests: setup-kong-build-tools
	cd $(KONG_BUILD_TOOLS_LOCATION); \
	$(MAKE) setup-build && \
	$(MAKE) build-kong && \
	$(MAKE) test

install-kong:
	@luarocks make OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR) EXPAT_DIR=$(EXPAT_DIR) LIBXML2_DIR=$(LIBXML2_DIR) YAML_DIR=$(YAML_DIR)

install: install-kong
	cd ./plugins-ee/application-registration; \
	luarocks make

remove:
	-@luarocks remove kong

remove-plugins-ee:
	scripts/enterprise_plugin.sh remove-all

dependencies: bin/grpcurl
	@for rock in $(DEV_ROCKS) ; do \
	  if luarocks list --porcelain $$rock | grep -q "installed" ; then \
	    echo $$rock already installed, skipping ; \
	  else \
	    echo $$rock not found, installing via luarocks... ; \
	    luarocks install $$rock OPENSSL_DIR=$(OPENSSL_DIR) CRYPTO_DIR=$(OPENSSL_DIR) EXPAT_DIR=$(EXPAT_DIR) LIBXML2_DIR=$(LIBXML2_DIR) || exit 1; \
	  fi \
	done;

bin/grpcurl:
	@curl -s -S -L \
		https://github.com/fullstorydev/grpcurl/releases/download/v$(GRPCURL_VERSION)/grpcurl_$(GRPCURL_VERSION)_$(GRPCURL_OS)_$(GRPCURL_MACHINE).tar.gz | tar xz -C bin;
	@rm bin/LICENSE

dev: remove install dependencies

sca:
	$(info Beginning static code analysis)
	@luacheck --exclude-files ./distribution/ -q .
	@!(grep -R -E -I -n -w '#only|#o' spec && echo "#only or #o tag detected") >&2
	@!(grep -R -E -I -n -w '#only|#o' spec-ee && echo "#only or #o tag detected") >&2
	@!(grep -R -E -I -n -- '---\s+ONLY' t && echo "--- ONLY block detected") >&2
	@$(KONG_SOURCE_LOCATION)/scripts/copyright-header-checker

install-plugins-ee:
	scripts/enterprise_plugin.sh install-all

try-install-plugins-ee:
	scripts/enterprise_plugin.sh install-all --ignore-errors

test:
	@$(TEST_CMD) spec/01-unit

trigger-api-tests:
	-docker manifest inspect kong/kong-gateway-internal:${DOCKER_IMAGE_TAG} 2>&1 >/dev/null && \
		curl \
			-X POST \
			-H "Accept: application/vnd.github+json" \
			-H "Authorization: Bearer ${GITHUB_TOKEN}" \
			https://api.github.com/repos/kong/kong-api-tests/dispatches \
			-d '{"event_type":"per-commit-test","client_payload":{"docker_image":"kong/kong-gateway-internal:${DOCKER_IMAGE_TAG}"}' \

test-ee:
	@$(TEST_CMD) spec-ee/01-unit

test-integration:
	@$(TEST_CMD) spec/02-integration

test-integration-ee:
	@$(TEST_CMD) spec-ee/02-integration

test-plugins-spec:
	@$(TEST_CMD) spec/03-plugins

test-plugins-spec-ee:
	@$(TEST_CMD) spec-ee/03-plugins

test-all:
	@$(TEST_CMD) spec/

test-all-ee:
	@$(TEST_CMD) spec-ee/

test-build-package:
	$(KONG_SOURCE_LOCATION)/dist/dist.sh build alpine

test-build-image: test-build-package
	$(KONG_SOURCE_LOCATION)/dist/dist.sh build-image alpine

test-build-pongo-deps:
	scripts/enterprise_plugin.sh build-deps

test-forward-proxy:
	scripts/enterprise_plugin.sh test forward-proxy

test-canary:
	scripts/enterprise_plugin.sh test canary

test-application-registration:
	scripts/enterprise_plugin.sh test application-registration

test-degraphql:
	scripts/enterprise_plugin.sh test degraphql

test-exit-transformer:
	scripts/enterprise_plugin.sh test exit-transformer

test-graphql-proxy-cache-advanced:
	scripts/enterprise_plugin.sh test graphql-proxy-cache-advanced

test-graphql-rate-limiting-advanced:
	scripts/enterprise_plugin.sh test graphql-rate-limiting-advanced

test-jq:
	scripts/enterprise_plugin.sh test jq

test-jwt-signer:
	scripts/enterprise_plugin.sh test jwt-signer

test-kafka-log:
	scripts/enterprise_plugin.sh test kafka-log

test-kafka-upstream:
	scripts/enterprise_plugin.sh test kafka-upstream

test-key-auth-enc:
	scripts/enterprise_plugin.sh test key-auth-enc

test-ldap-auth-advanced:
	scripts/enterprise_plugin.sh test ldap-auth-advanced

test-mocking:
	scripts/enterprise_plugin.sh test mocking

test-mtls-auth:
	scripts/enterprise_plugin.sh test mtls-auth

test-oauth2-introspection:
	scripts/enterprise_plugin.sh test oauth2-introspection

test-opa:
	scripts/enterprise_plugin.sh test opa

test-openid-connect:
	scripts/enterprise_plugin.sh test openid-connect

test-proxy-cache-advanced:
	scripts/enterprise_plugin.sh test proxy-cache-advanced

test-request-transformer-advanced:
	scripts/enterprise_plugin.sh test request-transformer-advanced

test-request-validator:
	scripts/enterprise_plugin.sh test request-validator

test-response-transformer-advanced:
	scripts/enterprise_plugin.sh test response-transformer-advanced

test-route-by-header:
	scripts/enterprise_plugin.sh test route-by-header

test-route-transformer-advanced:
	scripts/enterprise_plugin.sh test route-transformer-advanced

test-statsd-advanced:
	scripts/enterprise_plugin.sh test statsd-advanced

test-upstream-timeout:
	scripts/enterprise_plugin.sh test upstream-timeout

test-vault-auth:
	scripts/enterprise_plugin.sh test vault-auth

test-rate-limiting-advanced:
	scripts/enterprise_plugin.sh test rate-limiting-advanced

test-tls-handshake-modifier:
	scripts/enterprise_plugin.sh test tls-handshake-modifier

test-tls-metadata-headers:
	scripts/enterprise_plugin.sh test tls-metadata-headers

test-oas-validation:
	scripts/enterprise_plugin.sh test oas-validation

test-websocket-size-limit:
	scripts/enterprise_plugin.sh test websocket-size-limit

test-websocket-validator:
	scripts/enterprise_plugin.sh test websocket-validator

test-konnect-application-auth:
	scripts/enterprise_plugin.sh test konnect-application-auth

test-app-dynamics:
	scripts/enterprise_plugin.sh test app-dynamics

test-xml-threat:
	scripts/enterprise_plugin.sh test xml-threat

test-saml:
	scripts/enterprise_plugin.sh test saml

test-jwe-decrypt:
	scripts/enterprise_plugin.sh test jwe-decrypt

test-datadog-tracing:
	scripts/enterprise_plugin.sh test datadog-tracing

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
