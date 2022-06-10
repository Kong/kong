local cjson = require "cjson"
local api_helpers = require "kong.api.api_helpers"
local Schema = require "kong.db.schema"
local Errors = require "kong.db.errors"
local process = require "ngx.process"

local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()
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

      return kong.response.exit(200, {
        tagline = tagline,
        version = version,
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
        configuration = kong.configuration.remove_sensitive(),
        pids = pids,
      })
    end
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
  ["/timers"] = {
    GET = function (self, db, helpers)
      return kong.response.exit(200, _G.timerng_stats())
    end
  }
}
