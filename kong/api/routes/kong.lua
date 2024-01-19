-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"
local ee_api = require "kong.enterprise_edition.api_helpers"
local admins = require "kong.enterprise_edition.admins_helpers"
local auth_plugin_helpers = require "kong.enterprise_edition.auth_plugin_helpers"
local auth_helpers = require "kong.enterprise_edition.auth_helpers"
local cjson = require "cjson"
local rbac = require "kong.rbac"
local api_helpers = require "kong.api.api_helpers"
local Schema = require "kong.db.schema"
local Errors = require "kong.db.errors"
local process = require "ngx.process"
local wasm = require "kong.runloop.wasm"
local null = ngx.null
-- Add JWT decoder to decode id_token
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

local endpoints  = require "kong.api.endpoints"
local hooks = require "kong.hooks"

local kong = kong
local meta = require "kong.meta"
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()
local log = ngx.log
local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local errors = Errors.new()
local get_sys_filter_level = require "ngx.errlog".get_sys_filter_level
local LOG_LEVELS = require "kong.constants".LOG_LEVELS


local tagline = "Welcome to " .. _KONG._NAME
local version = meta.version
local lua_version = jit and jit.version or _VERSION


local strip_foreign_schemas = function(fields)
  for _, field in ipairs(fields) do
    local fname = next(field)
    local fdata = field[fname]
    if fdata["type"] == "foreign" then
      fdata.schema = nil
    end
  end
end

local function ws_and_rbac_helper(self)
  local admin_auth = kong.configuration.admin_gui_auth

  if not admin_auth and not ngx.ctx.rbac then
    return kong.response.exit(404, { message = "Not found" })
  end

  -- For when only RBAC token comes in
  if not self.admin then
    local admins, err = kong.db.admins:page_for_rbac_user({
      id = ngx.ctx.rbac.user.id
    })

    if err then
      return kong.response.exit(500, err)
    end

    if not admins[1] then
      -- no admin associated with this rbac_user
      return kong.response.exit(404, { message = "Not found" })
    end

    ee_api.attach_consumer_and_workspaces(self, admins[1].consumer.id)
    self.admin = admins[1]
  end

  -- now to get the right permission set
  self.permissions = {
    endpoints = {
      ["*"] = {
        ["*"] = {
          actions = { "delete", "create", "update", "read", },
          negative = false,
        }
      }
    },
    entities = {
      ["*"] = {
        actions = { "delete", "create", "update", "read", },
        negative = false,
      }
    },
  }

  --invalidate rbac_user_groups cache
  local cache_key = kong.db.rbac_user_groups:cache_key(ngx.ctx.rbac.user.id)
  kong.cache:invalidate(cache_key)

  -- get roles across all workspaces
  local roles, err = rbac.get_user_roles(kong.db, ngx.ctx.rbac.user, null)
  local group_roles = rbac.get_groups_roles(kong.db, ngx.ctx.rbac.user, null)
  roles = rbac.merge_roles(roles, group_roles)
  ee_api.attach_workspaces_roles(self, roles)

  if err then
    log(ERR, "[userinfo] ", err)
    return kong.response.exit(500, err)
  end

  local rbac_enabled = kong.configuration.rbac
  if rbac_enabled == "on" or rbac_enabled == "both" then
    self.permissions.endpoints = rbac.readable_endpoints_permissions(roles)
  end

  if rbac_enabled == "entity" or rbac_enabled == "both" then
    self.permissions.entities = rbac.readable_entities_permissions(roles)
  end
end


local function validate_schema(db_entity_name, params)
  local entity = kong.db[db_entity_name]
  local schema = entity and entity.schema or nil
  if not schema then
    return kong.response.exit(404, { message = "No entity named '"
                              .. db_entity_name .. "'" })
  end
  local schema = assert(Schema.new(schema))
  local _, err_t = schema:validate(schema:process_auto_fields(params, "insert"))
  if err_t then
    return kong.response.exit(400, errors:schema_violation(err_t))
  end
  return kong.response.exit(200, { message = "schema validation successful" })
end

local default_filter_config_schema
do
  local default

  function default_filter_config_schema(db)
    if default then
      return default
    end

    local dao = db.filter_chains or kong.db.filter_chains
    for key, field in dao.schema:each_field() do
      if key == "filters" then
        for _, ffield in ipairs(field.elements.fields) do
          if ffield.config and ffield.config.json_schema then
            default = ffield.config.json_schema.default
            return default
          end
        end
      end
    end
  end
end


return {
  ["/"] = {
    GET = function(self, dao, helpers)
      local distinct_plugins = setmetatable({}, cjson.array_mt)
      local pids = {
        master = process.get_master_pid()
      }

      do
        local set = {}
        for row, err in kong.db.plugins:each() do
          if err then
            kong.log.err(err)
            return kong.response.exit(500, { message = "An unexpected error happened" })
          end

          if not set[row.name] then
            distinct_plugins[#distinct_plugins+1] = row.name
            set[row.name] = true
          end
        end

        kong.internal_proxies:add_internal_plugins(distinct_plugins, set)
      end

      do
        local kong_shm = ngx.shared.kong
        local worker_count = ngx.worker.count() - 1
        for i = 0, worker_count do
          local worker_pid, err = kong_shm:get("pids:" .. i)
          if not worker_pid then
            err = err or "not found"
            ngx.log(ngx.ERR, "could not get worker process id for worker #", i , ": ", err)

          else
            if not pids.workers then
              pids.workers = {}
            end

            pids.workers[i + 1] = worker_pid
          end
        end
      end

      local node_id, err = knode.get_id()
      if node_id == nil then
        ngx.log(ngx.ERR, "could not get node id: ", err)
      end

      local available_plugins = {}
      for name in pairs(kong.configuration.loaded_plugins) do
        available_plugins[name] = {
          version = kong.db.plugins.handlers[name].VERSION,
          priority = kong.db.plugins.handlers[name].PRIORITY,
        }
      end

      local configuration = kong.configuration.remove_sensitive()
      configuration.log_level = LOG_LEVELS[get_sys_filter_level()]

      -- [[ XXX EE
      -- decorate kong info with EE data
      return kong.response.exit(200, assert(hooks.run_hook("api:kong:info", {
        -- XXX EE ]]
        tagline = tagline,
        version = version,
        edition = meta._VERSION:match("enterprise") and "enterprise" or "community",
        hostname = knode.get_hostname(),
        node_id = node_id,
        timers = {
          running = ngx.timer.running_count(),
          pending = ngx.timer.pending_count(),
        },
        plugins = {
          available_on_server = available_plugins,
          enabled_in_cluster = distinct_plugins,
        },
        lua_version = lua_version,
        configuration = configuration,
        pids = pids,
      })))
    end
  },
  --- Retrieves current user info, either an admin or an rbac user
  -- This route is whitelisted from RBAC validation. It requires that an admin
  -- is set on the headers, but should only work for a consumer that is set when
  -- an authentication plugin has set the admin_gui_auth_header.
  -- See for reference: kong.rbac.authorize_request_endpoint()
  ["/userinfo"] = {
    GET = function(self, dao, helpers)
      ws_and_rbac_helper(self)

      local user_session = kong.ctx.shared.authenticated_session
      if not user_session then
        return endpoints.handle_error('could not find session')
      end

      local idling_timeout = user_session.idling_timeout
      local rolling_timeout = user_session.rolling_timeout
      local absolute_timeout = user_session.absolute_timeout
      local stale_ttl = user_session.stale_ttl
      local expires_in = user_session:get_property("timeout")
      local expires = ngx.time() + expires_in

      local renew = 0
      if absolute_timeout > 0 then
        renew = math.min(600, absolute_timeout)
      end

      if rolling_timeout > 0 then
        renew = math.min(renew > 0 and renew or 600, rolling_timeout)
      end

      if idling_timeout > 0 then
        renew = math.min(renew > 0 and renew or 600, idling_timeout)
      end

      return kong.response.exit(200, {
        admin = admins.transmogrify(self.admin),
        groups = self.groups,
        permissions = self.permissions,
        workspaces = self.workspaces,
        session = {
          idling_timeout = idling_timeout,
          rolling_timeout = rolling_timeout,
          absolute_timeout = absolute_timeout,
          stale_ttl = stale_ttl,
          expires_in = expires_in,
          expires = expires, -- unix timestamp seconds
          -- TODO: below should be removed, kept for backward compatibility:
          cookie = {
            discard = stale_ttl,
            renew = renew,
            -- see: https://github.com/bungle/lua-resty-session/blob/v4.0.0/lib/resty/session.lua#L1999
            idletime = idling_timeout,
            lifetime = rolling_timeout,
          },
        }
      })
    end,
  },
  ["/endpoints"] = {
    GET = function(self, dao, helpers)
      local endpoints = setmetatable({}, cjson.array_mt)
      local application = require("kong.api")
      local each_route = require("lapis.application.route_group").each_route
      local filled_endpoints = {}
      each_route(application, true, function(path)
        if type(path) == "table" then
          path = next(path)
        end
        if not filled_endpoints[path] then
          filled_endpoints[path] = true
          endpoints[#endpoints + 1] = path:gsub(":([^/:]+)", function(m)
            return "{" .. m .. "}"
          end)
        end
      end)
      table.sort(endpoints, function(a, b)
        -- when sorting use lower-ascii char for "/" to enable segment based
        -- sorting, so not this:
        --   /a
        --   /ab
        --   /ab/a
        --   /a/z
        -- But this:
        --   /a
        --   /a/z
        --   /ab
        --   /ab/a
        return a:gsub("/", "\x00") < b:gsub("/", "\x00")
      end)

      return kong.response.exit(200, { data = endpoints })
    end
  },
  ["/schemas/:name"] = {
    GET = function(self, db, helpers)
      local entity = kong.db[self.params.name]
      local schema = entity and entity.schema or nil
      if not schema then
        return kong.response.exit(404, { message = "No entity named '"
                                      .. self.params.name .. "'" })
      end
      local copy = api_helpers.schema_to_jsonable(schema)
      strip_foreign_schemas(copy.fields)
      return kong.response.exit(200, copy)
    end
  },
  ["/schemas/plugins/validate"] = {
    POST = function(self, db, helpers)
      return validate_schema("plugins", self.params)
    end
  },
  ["/schemas/:db_entity_name/validate"] = {
    POST = function(self, db, helpers)
      local db_entity_name = self.params.db_entity_name
      -- What happens when db_entity_name is a field name in the schema?
      self.params.db_entity_name = nil
      return validate_schema(db_entity_name, self.params)
    end
  },

  ["/schemas/vaults/:name"] = {
    GET = function(self, db, helpers)
      local subschema = kong.db.vaults.schema.subschemas[self.params.name]
      if not subschema then
        return kong.response.exit(404, { message = "No vault named '"
                                  .. self.params.name .. "'" })
      end
      local copy = api_helpers.schema_to_jsonable(subschema)
      strip_foreign_schemas(copy.fields)
      return kong.response.exit(200, copy)
    end
  },
  ["/schemas/plugins/:name"] = {
    GET = function(self, db, helpers)
      local subschema = kong.db.plugins.schema.subschemas[self.params.name]
      if not subschema then
        return kong.response.exit(404, { message = "No plugin named '"
                                  .. self.params.name .. "'" })
      end

      local copy = api_helpers.schema_to_jsonable(subschema)
      strip_foreign_schemas(copy.fields)
      return kong.response.exit(200, copy)
    end
  },
  ["/schemas/filters/:name"] = {
    GET = function(self, db)
      local name = self.params.name

      if not wasm.filters_by_name[name] then
        local msg = "Filter '" .. name .. "' not found"
        return kong.response.exit(404, { message = msg })
      end

      local schema = wasm.filter_meta[name]
                 and wasm.filter_meta[name].config_schema
                  or default_filter_config_schema(db)

      return kong.response.exit(200, schema)
    end
  },
  ["/auth"] = {
    before = function(self, dao_factory, helpers)
      local gui_auth = kong.configuration.admin_gui_auth
      local gui_auth_conf = kong.configuration.admin_gui_auth_conf
      local invoke_plugin = kong.invoke_plugin

      local _log_prefix = "kong[auth]"

      if not gui_auth and not ngx.ctx.rbac then
        return kong.response.exit(404, { message = "Not found" })
      end

      if gui_auth == "openid-connect" then
        gui_auth_conf = utils.shallow_copy(kong.configuration.admin_gui_auth_conf)
        gui_auth_conf.admin_claim = nil
        gui_auth_conf.admin_by = nil
        gui_auth_conf.admin_auto_create_rbac_token_disabled = nil
        gui_auth_conf.admin_auto_create = nil
      end

      local admin
      local by_username_ignore_case =
              gui_auth_conf and gui_auth_conf.by_username_ignore_case

      -- Defer admin valdition and ctx attachement after Auth Plugin execution,
      -- when using OIDC AUTH
      if gui_auth ~= "openid-connect" then
        local user_header = kong.configuration.admin_gui_auth_header
        local args = ngx.req.get_uri_args()

        local user_name = args[user_header] or ngx.req.get_headers()[user_header]

        -- for ldap auth, validates admin by the username from the authorization header
        if (gui_auth == "ldap-auth-advanced") then
          local header_type = kong.configuration.admin_gui_auth_conf and
                              kong.configuration.admin_gui_auth_conf.header_type or
                              "Basic"

          local auth_header_value = ngx.req.get_headers()['authorization']

          if not auth_header_value then
            return kong.response.exit(401,
            { message = "Authorization header is required" })
          end

          user_name = auth_plugin_helpers.retrieve_credentials(auth_header_value, header_type)
        end

        admin = auth_plugin_helpers.validate_admin_and_attach_ctx(
                  self,
                  by_username_ignore_case,
                  user_name
                )
      end

      local session_conf = kong.configuration.admin_gui_session_conf

      -- run the session plugin access to see if we have a current session
      -- with a valid authenticated consumer.
      local ok, err = invoke_plugin({
        name = "session",
        config = session_conf,
        phases = { "access" },
        api_type = ee_api.apis.ADMIN,
        db = kong.db,
      })

      if err or not ok then
        log(ERR, _log_prefix, err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      -- logging out
      if kong.request.get_method() == 'DELETE' then
        return
      end

      -- apply auth plugin
      local plugin_auth_response
      local id_token_claim_name = "id_token"
      local access_token_claim_name = "access_token"
      local userinfo_claim_name = "user_info"

      if not ngx.ctx.authenticated_consumer then
        -- Before Auth Plugin execution.
        if gui_auth == "openid-connect" then
          gui_auth_conf.consumer_optional = true
          -- by default id_token contains data the auth flow required
          gui_auth_conf.upstream_id_token_header = id_token_claim_name
          gui_auth_conf.upstream_access_token_header = access_token_claim_name
          -- fallback to fetch admin_claim from 'user_info'
          if gui_auth_conf.search_user_info then
            gui_auth_conf.upstream_user_info_header = userinfo_claim_name
          end
        end

        if gui_auth == "ldap-auth-advanced" then
          -- since the OIDC create if admin not exists improvement,
          -- the admin.username no longer as same as consumer.username
          gui_auth_conf.consumer_optional = true
        end

        plugin_auth_response, err = invoke_plugin({
          name = gui_auth,
          config = gui_auth_conf,
          phases = { "access" },
          api_type = ee_api.apis.ADMIN,
          db = kong.db,
          exit_handler = function (res) return res end,
        })

        if err or not plugin_auth_response then
          log(ERR, _log_prefix, err)
          return kong.response.exit(500, err)
        end

        -- After Auth Plugin execution.
        if gui_auth == "openid-connect" then
          local id_token_claims = function ()
            local id_token_header = ngx.req.get_headers()[id_token_claim_name]
            if not id_token_header then
              log(DEBUG, _log_prefix, "failed to get id_token from upstream header")
              return nil
            end
            -- decode id_token
            local jwt, err = jwt_decoder:new(id_token_header)
            if err then
              log(ERR, _log_prefix, "failed to decode id token.", err)
              return nil
            end

            return jwt.claims
          end

          local access_token_claims = function()
            local access_token_header = ngx.req.get_headers()[access_token_claim_name]
            if not access_token_header then
              log(DEBUG, _log_prefix, "failed to get access_token from upstream header")
              return nil
            end
            -- decode id_token
            local jwt, err = jwt_decoder:new(access_token_header)
            if err then
              log(ERR, _log_prefix, "failed to decode access token.", err)
              return nil
            end

            return jwt.claims
          end

          local user_info_claims = function ()
            local userinfo_header = ngx.req.get_headers()[userinfo_claim_name]
            if not userinfo_header then
              log(DEBUG, _log_prefix, "failed to get user_info from upstream header")
              return nil
            end
            local userinfo_json, base64_err = ngx.decode_base64(userinfo_header)
            local userinfo, json_err = cjson.decode(userinfo_json)
            if base64_err or json_err then
              log(ERR, _log_prefix, "failed to decode userinfo.", base64_err or json_err)
              return nil
            end

            return userinfo
          end

          local default_admin_by = "username"
          local gui_auth_conf_origin = kong.configuration.admin_gui_auth_conf
          local admin_claim = gui_auth_conf_origin
                              and gui_auth_conf_origin.admin_claim

          local admin_by = gui_auth_conf_origin and gui_auth_conf_origin.admin_by
                           or default_admin_by
          local search_user_info = gui_auth_conf_origin and gui_auth_conf_origin.search_user_info
          -- use admin_auto_create to control admin auto creation, it is true if it is not set
          local admin_auto_create = gui_auth_conf_origin and gui_auth_conf_origin.admin_auto_create
                            or gui_auth_conf_origin.admin_auto_create == nil

          -- use claims to map kong admin
          local claims = id_token_claims()

          if not (claims and claims[admin_claim]) then
            claims = access_token_claims()
          end

          if search_user_info and not (claims and claims[admin_claim]) then
            claims = user_info_claims()
          end

          local admin_claim_value = claims and claims[admin_claim]
          if not admin_claim_value then
            log(ERR, _log_prefix, "the 'admin_claim' not found from the claims.", gui_auth)
            return kong.response.exit(401, { message = "Unauthorized" })
          end

          admin = auth_plugin_helpers.validate_admin_and_attach_ctx(
            self,
            by_username_ignore_case,
            admin_claim_value,
            admin_by == "custom_id" and admin_claim_value or nil,
            admin_auto_create,
            true,
            not (gui_auth_conf_origin and gui_auth_conf_origin.admin_auto_create_rbac_token_disabled)
          )

          -- role mapping or group mapping
          local role_claim = gui_auth_conf and
                             gui_auth_conf.authenticated_groups_claim and
                             gui_auth_conf.authenticated_groups_claim[1]
          -- use claims in id_token or acces_token or userinfo to map groups here
          local role_claim_values = claims and claims[role_claim] or ngx.ctx.authenticated_groups

          if role_claim_values then
            auth_plugin_helpers.map_admin_groups_by_idp_claim(admin, role_claim_values)
            auth_plugin_helpers.map_admin_roles_by_idp_claim(admin, role_claim_values)
          elseif role_claim then
            auth_plugin_helpers.delete_admin_groups_or_roles(admin)
            -- only logs an error if kong-ee can not find the claims
            ngx.log(ERR, role_claim .. " not found from the id_token or access_token or userinfo claims.", gui_auth)
          end

        end

        if gui_auth == "ldap-auth-advanced" then
          -- since the OIDC create if admin not exists improvement,
          -- plugin not longer handle conusmer mapping.
          auth_plugin_helpers.map_admin_groups_by_idp_claim(admin, ngx.ctx.authenticated_groups)
          auth_plugin_helpers.set_admin_consumer_to_ctx(admin)
        end

      end

      -- Plugin ran but consumer was not created on context
      if not ngx.ctx.authenticated_consumer and not plugin_auth_response then
        log(DEBUG, _log_prefix, "no consumer mapped from plugin ", gui_auth)

        return kong.response.exit(401, { message = "Unauthorized" })
      end

      local max_attempts = kong.configuration.admin_gui_auth_login_attempts
      auth_helpers.plugin_res_handler(plugin_auth_response, admin, max_attempts)

      if self.consumer
         and ngx.ctx.authenticated_consumer.id ~= self.consumer.id
      then
        log(DEBUG, _log_prefix, "authenticated consumer is not an admin")
        return kong.response.exit(401, { message = "Unauthorized" })
      end

      local ok, err = invoke_plugin({
        name = "session",
        config = session_conf,
        phases = { "header_filter" },
        api_type = ee_api.apis.ADMIN,
        db = kong.db,
      })

      if err or not ok then
        log(ERR, _log_prefix, err)
        return kong.response.exit(500, err)
      end
    end,

    GET = function(self, dao_factory, helpers)
      return kong.response.exit(200)
    end,

    POST = function(self, dao_factory, helpers)
      return kong.response.exit(200)
    end,

    DELETE = function(self, dao_factory, helpers)
      -- stub for logging out
      return kong.response.exit(200)
    end,
  },
  ["/timers"] = {
    GET = function (self, db, helpers)
      local body = {
        worker = {
          id = ngx.worker.id(),
          count = ngx.worker.count(),
        },
        stats = kong.timer:stats({
          verbose = true,
          flamegraph = true,
        })
      }
      return kong.response.exit(200, body)
    end
  }
}
