local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"
local conf_loader = require "kong.conf_loader"
local cjson = require "cjson"
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


local shms = {}

for shm_name, shm in pairs(ngx.shared) do
  table.insert(shms, {
    zone = shm,
    name = shm_name,
    capacity = shm:capacity(),
  })
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
          scale = query.scale
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
        memory = {
          workers_lua_vms = kong.table.new(ngx.worker.count(), 0),
          lua_shared_dicts = kong.table.new(0, #shms),
        }
      }

      -- TODO: no way to bypass connection pool
      local ok, err = kong.db:connect()
      if not ok then
        ngx.log(ngx.ERR, "failed to connect to ", kong.db.infos.strategy,
                         " during /status endpoint check: ", err)
        status_response.database.reachable = false
      end

      kong.db:close() -- ignore errors

      -- memory stats
      -- get workers Lua VM allocated memory

      local keys, err = ngx.shared.kong:get_keys()
      if not keys then
        ngx.log(ngx.ERR, "could not get kong shm keys: ", err)
        goto lua_shared_dicts
      end

      for i = 1, #keys do
        local pid = string.match(keys[i], "kong:mem:(%d+)")
        if not pid then
          goto continue
        end

        local count, err = ngx.shared.kong:get("kong:mem:" .. pid)
        if err then
          ngx.log(ngx.ERR, "could not get Lua VM allocated memory (pid: ",
                           pid, "): ", err)
        end

        if count then
          table.insert(status_response.memory.workers_lua_vms, {
            pid = pid,
            allocated_gc = utils.bytes_to_str(count, unit, scale)
          })
        end

        ::continue::
      end

      table.sort(status_response.memory.workers_lua_vms, function(a, b)
        return a.pid > b.pid
      end)

      -- get lua_shared_dicts allocated slabs

      ::lua_shared_dicts::

      for _, shm in ipairs(shms) do
        local allocated = shm.capacity - shm.zone:free_space()

        status_response.memory.lua_shared_dicts[shm.name] = {
          capacity = utils.bytes_to_str(shm.capacity, unit, scale),
          allocated_slabs = utils.bytes_to_str(allocated, unit, scale),
        }
      end

      return kong.response.exit(200, status_response)
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
}
