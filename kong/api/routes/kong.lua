local cjson = require "cjson"
local api_helpers = require "kong.api.api_helpers"
local Schema = require "kong.db.schema"
local Errors = require "kong.db.errors"
local process = require "ngx.process"
local wasm = require "kong.runloop.wasm"

local kong = kong
local meta = require "kong.meta"
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()
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

      return kong.response.exit(200, {
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
      })
    end
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
  ["/schemas/vaults/validate"] = {
    POST = function(self, db, helpers)
      return validate_schema("vaults", self.params)
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
  ["/timers"] = {
    GET = function (self, db, helpers)
      local body = {
        worker = {
          id = ngx.worker.id() or -1,
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
