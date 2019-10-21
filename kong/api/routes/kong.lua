local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"
local workspaces = require "kong.workspaces"
local conf_loader = require "kong.conf_loader"
local ee_api = require "kong.enterprise_edition.api_helpers"
local admins = require "kong.enterprise_edition.admins_helpers"
local auth_helpers = require "kong.enterprise_edition.auth_helpers"
local cjson = require "cjson"
local rbac = require "kong.rbac"
local api_helpers = require "kong.api.api_helpers"
local Schema = require "kong.db.schema"
local Errors = require "kong.db.errors"

local sub = string.sub
local find = string.find
local select = select
local tonumber = tonumber
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


return {
  ["/"] = {
    GET = function(self, dao, helpers)
      local distinct_plugins = setmetatable({}, cjson.array_mt)
      local prng_seeds = {}

      do
        local set = {}
        for row, err in kong.db.plugins:each(1000) do
          if err then
            kong.log.err(err)
            return kong.response.exit(500, { message = "An unexpected error happened" })
          end

          if not set[row.name] then
            distinct_plugins[#distinct_plugins+1] = row.name
            set[row.name] = true
          end
        end

        singletons.internal_proxies:add_internal_plugins(distinct_plugins, set)
      end

      do
        local kong_shm = ngx.shared.kong
        local shm_prefix = "pid: "
        local keys, err = kong_shm:get_keys()
        if not keys then
          ngx.log(ngx.ERR, "could not get kong shm keys: ", err)
        else
          for i = 1, #keys do
            if sub(keys[i], 1, #shm_prefix) == shm_prefix then
              prng_seeds[keys[i]], err = kong_shm:get(keys[i])
              if err then
                ngx.log(ngx.ERR, "could not get PRNG seed from kong shm")
              end
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
        hostname = utils.get_hostname(),
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
  ["/status"] = {
    GET = function(self, dao, helpers)
      local query = self.req.params_get
      local unit = "m"
      local scale

      if query then
        if query.unit then
          unit = query.unit
        end

        if query.scale then
          scale = tonumber(query.scale)
        end

        -- validate unit and scale arguments

        local pok, perr = pcall(utils.bytes_to_str, 0, unit, scale)
        if not pok then
          return kong.response.exit(400, { message = perr })
        end
      end

      -- nginx stats

      local r = ngx.location.capture "/nginx_status"
      if r.status ~= 200 then
        kong.log.err(r.body)
        return kong.response.exit(500, { message = "An unexpected error happened" })
      end

      local var = ngx.var
      local accepted, handled, total = select(3, find(r.body, "accepts handled requests\n (%d*) (%d*) (%d*)"))

      local status_response = {
        memory = knode.get_memory_stats(unit, scale),
        server = {
          connections_active = tonumber(var.connections_active),
          connections_reading = tonumber(var.connections_reading),
          connections_writing = tonumber(var.connections_writing),
          connections_waiting = tonumber(var.connections_waiting),
          connections_accepted = tonumber(accepted),
          connections_handled = tonumber(handled),
          total_requests = tonumber(total)
        },
        database = {
          reachable = true,
        },
      }

      -- TODO: no way to bypass connection pool
      local ok, err = kong.db:connect()
      if not ok then
        ngx.log(ngx.ERR, "failed to connect to ", kong.db.infos.strategy,
                         " during /status endpoint check: ", err)
        status_response.database.reachable = false
      end

      kong.db:close() -- ignore errors

      return kong.response.exit(200, status_response)
    end
  },

  --- Retrieves current user info, either an admin or an rbac user
  -- This route is whitelisted from RBAC validation. It requires that an admin
  -- is set on the headers, but should only work for a consumer that is set when
  -- an authentication plugin has set the admin_gui_auth_header.
  -- See for reference: kong.rbac.authorize_request_endpoint()
  ["/userinfo"] = {
    before = function(self, dao_factory, helpers)
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
      local roles, err = workspaces.run_with_ws_scope({}, rbac.get_user_roles,
                                                      kong.db,
                                                      ngx.ctx.rbac.user)
      local group_roles = rbac.get_groups_roles(kong.db, ngx.ctx.authenticated_groups)
      roles = rbac.merge_roles(roles, group_roles)

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

      -- fetch workspace resources from workspace entities
      self.workspaces = {}

      local ws_dict = {} -- dict to keep track of which workspaces we have added
      local ws, err
      for k, v in ipairs(self.workspace_entities) do
        if not ws_dict[v.workspace_id] then
          ws, err = kong.db.workspaces:select({id = v.workspace_id})
          if err then
            return helpers.yield_error(err)
          end
          ws_dict[v.workspace_id] = true
          self.workspaces[k] = ws
        end
      end
    end,

    GET = function(self, dao, helpers)
      return kong.response.exit(200, {
        admin = admins.transmogrify(self.admin),
        groups = self.groups,
        permissions = self.permissions,
        workspaces = self.workspaces,
      })
    end,
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
