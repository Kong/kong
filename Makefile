ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
KONG_SOURCE_LOCATION?=$(ROOT_DIR)/kong-source
KONG?=master

setup-kong:
	-rm -rf $(KONG_SOURCE_LOCATION); \
	git clone --branch $(KONG) https://github.com/Kong/kong.git $(KONG_SOURCE_LOCATION)

setup-ci: setup-kong
	cd $(KONG_SOURCE_LOCATION); \
	$(MAKE) setup-ci
