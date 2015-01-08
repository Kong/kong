PWD = `pwd`

# Dev environment variables
ENV_DAEMON ?= off
ENV_LUA_LIB ?= lua_package_path \"$(PWD)/src/?.lua\;\;\"\;
ENV_LUA_CODE_CACHE ?= off
ENV_APENODE_PORT ?= 8000
ENV_APENODE_WEB_PORT ?= 8001
ENV_DIR ?= $(PWD)/tmp
ENV_APENODE_CONF ?= $(ENV_DIR)/apenode.dev.yaml

.PHONY: test local global run populate drop test-web test-all

local:
	@luarocks make apenode-*.rockspec --local

global:
	@luarocks make apenode-*.rockspec

test:
	@busted spec/unit

test-web:
	@$(MAKE) build ENV_DAEMON=on
	@scripts/populate --conf=$(ENV_APENODE_CONF)
	@nginx -p ./tmp/nginx -c nginx.conf
	- @busted spec/web/
	@nginx -p ./tmp/nginx -c nginx.conf -s stop
	@scripts/populate --conf=$(ENV_APENODE_CONF) --drop

test-proxy:
	@$(MAKE) build ENV_DAEMON=on
	@scripts/populate --conf=$(ENV_APENODE_CONF)
	@nginx -p ./tmp/nginx -c nginx.conf
	- @busted spec/proxy/
	@nginx -p ./tmp/nginx -c nginx.conf -s stop
	@scripts/populate --conf=$(ENV_APENODE_CONF) --drop

test-all:
	@echo "Unit tests:"
	@$(MAKE) test
	@echo "\nAPI tests:"
	@$(MAKE) test-web
	@echo "\nProxy tests:"
	@$(MAKE) test-proxy

populate:
	@scripts/populate --conf=$(ENV_APENODE_CONF)

drop:
	@scripts/populate --conf=$(ENV_APENODE_CONF) --drop

run:
	@$(MAKE) build
	@nginx -p ./tmp/nginx -c nginx.conf

build:
	@mkdir -p $(ENV_DIR)/nginx/logs
	@cp templates/apenode.yaml $(ENV_APENODE_CONF)
	@echo "" > tmp/nginx/logs/error.log
	@echo "" > tmp/nginx/logs/access.log
	@sed \
		-e "s/{{DAEMON}}/$(ENV_DAEMON)/g" \
		-e "s@{{LUA_LIB_PATH}}@$(ENV_LUA_LIB)@g" \
		-e "s/{{LUA_CODE_CACHE}}/$(ENV_LUA_CODE_CACHE)/g" \
		-e "s/{{PORT}}/$(ENV_APENODE_PORT)/g" \
		-e "s/{{WEB_PORT}}/$(ENV_APENODE_WEB_PORT)/g" \
		-e "s@{{APENODE_CONF}}@$(ENV_APENODE_CONF)@g" \
		templates/nginx.conf > $(ENV_DIR)/nginx/nginx.conf;

	@cp -R src/apenode/web/static $(ENV_DIR)/nginx
	@cp -R src/apenode/web/admin $(ENV_DIR)/nginx
