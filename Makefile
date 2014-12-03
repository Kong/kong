PWD = `pwd`
# Dev environment variables
DEV_DAEMON ?= off
DEV_LUA_LIB ?= lua_package_path \"$(PWD)/src/?.lua\;\;\"\;
DEV_LUA_CODE_CACHE ?= off
DEV_APENODE_CONF ?= $(PWD)/tmp/apenode.dev.yaml
DEV_APENODE_PORT ?= 8000
DEV_APENODE_WEB_PORT ?= 8001

.PHONY: test local global

test:
	@echo "Tests with busted"

local:
	@luarocks make apenode-0.0-1.rockspec --local

global:
	@sudo luarocks make apenode-0.0-1.rockspec

run:
	@mkdir -p tmp/nginx/logs
	@cp templates/apenode.yaml $(DEV_APENODE_CONF)
	@echo "" > tmp/nginx/logs/error.log
	@echo "" > tmp/nginx/logs/access.log
	@sed \
		-e "s/{{DAEMON}}/$(DEV_DAEMON)/g" \
		-e "s@{{LUA_LIB_PATH}}@$(DEV_LUA_LIB)@g" \
		-e "s/{{LUA_CODE_CACHE}}/$(DEV_LUA_CODE_CACHE)/g" \
		-e "s/{{PORT}}/$(DEV_APENODE_PORT)/g" \
		-e "s/{{WEB_PORT}}/$(DEV_APENODE_WEB_PORT)/g" \
		-e "s@{{APENODE_CONF}}@$(DEV_APENODE_CONF)@g" \
		templates/nginx.conf > tmp/nginx/nginx.conf;

	@nginx -p ./tmp/nginx -c nginx.conf
