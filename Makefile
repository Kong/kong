PWD = `pwd`

# Dev environment variables
export ENV_DAEMON ?= off
export ENV_LUA_LIB ?= lua_package_path \"$(PWD)/src/?.lua\;\;\"\;
export ENV_LUA_CODE_CACHE ?= off
export ENV_APENODE_PORT ?= 8000
export ENV_APENODE_WEB_PORT ?= 8001
export ENV_DIR ?= $(PWD)/tmp
export ENV_APENODE_CONF ?= $(ENV_DIR)/apenode.dev.yaml
export ENV_SILENT ?=

.PHONY: build local global test test-web test-all run migrate populate drop

local:
	@luarocks make apenode-*.rockspec --local

global:
	@luarocks make apenode-*.rockspec

test:
	@busted spec/unit

test-web:
	@$(MAKE) build ENV_DAEMON=on
	@$(MAKE) migrate ENV_SILENT=-s
	@$(MAKE) run
	@$(MAKE) seed ENV_SILENT=-s
	@busted spec/web/ || (make stop;make drop; exit 1)
	@$(MAKE) stop
	@$(MAKE) drop ENV_SILENT=-s

test-proxy:
	@$(MAKE) build ENV_DAEMON=on
	@$(MAKE) migrate ENV_SILENT=-s
	@$(MAKE) run
	@$(MAKE) seed ENV_SILENT=-s
	@busted spec/proxy/ || (make stop;make drop; exit 1)
	@$(MAKE) stop
	@$(MAKE) drop ENV_SILENT=-s

test-all:
	@$(MAKE) build ENV_DAEMON=on
	@$(MAKE) migrate ENV_SILENT=-s
	@$(MAKE) run
	@$(MAKE) seed ENV_SILENT=-s
	@busted spec/ || (make stop;make drop; exit 1)
	@$(MAKE) stop
	@$(MAKE) drop ENV_SILENT=-s

migrate:
	@scripts/migrate migrate $(ENV_SILENT) --conf=$(ENV_APENODE_CONF)

seed:
	@scripts/seed seed $(ENV_SILENT) --conf=$(ENV_APENODE_CONF)

drop:
	@scripts/seed drop $(ENV_SILENT) --conf=$(ENV_APENODE_CONF)

run:
	@nginx -p $(ENV_DIR)/nginx -c nginx.conf

stop:
	@nginx -p $(ENV_DIR)/nginx -c nginx.conf -s stop

build:
	@mkdir -p $(ENV_DIR)/nginx/logs
	@cp templates/apenode.yaml $(ENV_APENODE_CONF)
	@echo "" > $(ENV_DIR)/nginx/logs/error.log
	@echo "" > $(ENV_DIR)/nginx/logs/access.log
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
