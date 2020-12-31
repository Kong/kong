-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"
local conf_loader = require "kong.conf_loader"
local ee_api = require "kong.enterprise_edition.api_helpers"
local admins = require "kong.enterprise_edition.admins_helpers"
local auth_helpers = require "kong.enterprise_edition.auth_helpers"
local cjson = require "cjson"
local rbac = require "kong.rbac"
local api_helpers = require "kong.api.api_helpers"
local Schema = require "kong.db.schema"
local Errors = require "kong.db.errors"
local endpoints  = require "kong.api.endpoints"

local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()
local log = ngx.log
local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local errors = Errors.new()


local tagline = "Welcome to " .. _KONG._NAME
local version = _KONG._VERSION
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
  local admin_auth = singletons.configuration.admin_gui_auth

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

  -- get roles across all workspaces
  local roles, err = rbac.get_user_roles(kong.db, ngx.ctx.rbac.user, ngx.null)
  local group_roles = rbac.get_groups_roles(kong.db, ngx.ctx.authenticated_groups)
  roles = rbac.merge_roles(roles, group_roles)
  ee_api.attach_workspaces_roles(self, roles)

  if err then
    log(ERR, "[userinfo] ", err)
    return kong.response.exit(500, err)
  end

  local rbac_enabled = singletons.configuration.rbac
  if rbac_enabled == "on" or rbac_enabled == "both" then
    self.permissions.endpoints = rbac.readable_endpoints_permissions(roles)
  end

  if rbac_enabled == "entity" or rbac_enabled == "both" then
    self.permissions.entities = rbac.readable_entities_permissions(roles)
  end
end


return {
  ["/"] = {
    GET = function(self, dao, helpers)
      local distinct_plugins = setmetatable({}, cjson.array_mt)
      local prng_seeds = {}

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

        local master_pid, err = kong_shm:get("pids:master")
        if not master_pid then
          err = err or "not found"
          ngx.log(ngx.ERR, "could not get master process id: ", err)

        else
          local master_seed, err = kong_shm:get("seeds:" .. master_pid)
          if not master_seed then
            err = err or "not found"
            ngx.log(ngx.ERR, "could not get process id for master process: ", err)

          else
            prng_seeds["pid: " .. master_pid] = master_seed
          end
        end

        local worker_count = ngx.worker.count() - 1
        for i = 0, worker_count do
          local worker_pid, err = kong_shm:get("pids:" .. i)
          if not worker_pid then
            err = err or "not found"
            ngx.log(ngx.ERR, "could not get worker process id for worker #", i , ": ", err)

          else
            local worker_seed, err = kong_shm:get("seeds:" .. worker_pid)
            if not worker_seed then
              err = err or "not found"
              ngx.log(ngx.ERR, "could not get PRNG seed for worker #", i, ":", err)

            else
              prng_seeds["pid: " .. worker_pid] = worker_seed
            end
          end
        end
      end

      local license
      if kong.license then
        license = utils.deep_copy(kong.license).license.payload
        license.license_key = nil
      end

      local node_id, err = knode.get_id()
      if node_id == nil then
        ngx.log(ngx.ERR, "could not get node id: ", err)
      end

      return kong.response.exit(200, {
        tagline = tagline,
        version = version,
        hostname = knode.get_hostname(),
        node_id = node_id,
        timers = {
          running = ngx.timer.running_count(),
          pending = ngx.timer.pending_count()
        },
        plugins = {
          available_on_server = singletons.configuration.loaded_plugins,
          enabled_in_cluster = distinct_plugins
        },
        lua_version = lua_version,
        configuration = conf_loader.remove_sensitive(singletons.configuration),
        prng_seeds = prng_seeds,
        license = license,
      })
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
      local cookie = user_session and user_session.cookie

      if not user_session or (user_session and not user_session.expires) then
        return endpoints.handle_error('could not find session')
      end

      if cookie then
        if not cookie.renew or not cookie.lifetime then
          return endpoints.handle_error('could not find session cookie data')
        end
      end

      return kong.response.exit(200, {
        admin = admins.transmogrify(self.admin),
        groups = self.groups,
        permissions = self.permissions,
        workspaces = self.workspaces,
        session = {
          expires = user_session.expires, -- unix timestamp seconds
          cookie = {
            discard = user_session.cookie.discard,
            renew = user_session.cookie.renew,
            idletime = user_session.cookie.idletime,
            lifetime = user_session.cookie.lifetime,
          },
        }
      })
    end,
  },
  ["/endpoints"] = {
    GET = function(self, dao, helpers)
      local endpoints = setmetatable({}, cjson.array_mt)
      local lapis_endpoints = require("kong.api").ordered_routes

      for k, v in pairs(lapis_endpoints) do
        if type(k) == "string" then -- skip numeric indices
          endpoints[#endpoints + 1] = k:gsub(":([^/:]+)", function(m)
              return "{" .. m .. "}"
            end)
        end
      end
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
  ["/schemas/:db_entity_name/validate"] = {
    POST = function(self, db, helpers)
      local db_entity_name = self.params.db_entity_name
      -- What happens when db_entity_name is a field name in the schema?
      self.params.db_entity_name = nil
      local entity = kong.db[db_entity_name]
      local schema = entity and entity.schema or nil
      if not schema then
        return kong.response.exit(404, { message = "No entity named '"
                                  .. db_entity_name .. "'" })
      end
      local schema = assert(Schema.new(schema))
      local _, err_t = schema:validate(schema:process_auto_fields(
                                        self.params, "insert"))
      if err_t then
        return kong.response.exit(400, errors:schema_violation(err_t))
      end
      return kong.response.exit(200, { message = "schema validation successful" })
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
  ["/auth"] = {
    before = function(self, dao_factory, helpers)
      local gui_auth = singletons.configuration.admin_gui_auth
      local gui_auth_conf = singletons.configuration.admin_gui_auth_conf
      local invoke_plugin = singletons.invoke_plugin

      local _log_prefix = "kong[auth]"

      if not gui_auth and not ngx.ctx.rbac then
        return kong.response.exit(404, { message = "Not found" })
      end

      local admin, err = ee_api.validate_admin()
      if not admin then
        log(DEBUG, _log_prefix, "Admin not found")
        return kong.response.exit(401, { message = "Unauthorized" })
      end

      if err then
        log(ERR, _log_prefix, err)
        return kong.response.exit(500, err)
      end

      -- Check if an admin exists before going through auth plugin flow
      if self.params.validate_user then
        return admin and true
      end

      local consumer_id = admin.consumer.id

      ee_api.attach_consumer_and_workspaces(self, consumer_id)

      local session_conf = singletons.configuration.admin_gui_session_conf

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
      if not ngx.ctx.authenticated_consumer then
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
      end

      -- Plugin ran but consumer was not created on context
      if not ngx.ctx.authenticated_consumer and not plugin_auth_response then
        log(DEBUG, _log_prefix, "no consumer mapped from plugin ", gui_auth)

        return kong.response.exit(401, { message = "Unauthorized" })
      end

      local max_attempts = singletons.configuration.admin_gui_auth_login_attempts
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

    DELETE = function(self, dao_factory, helpers)
      -- stub for logging out
      return kong.response.exit(200)
    end,
  },
}
