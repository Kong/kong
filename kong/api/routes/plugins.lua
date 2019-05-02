local cjson = require "cjson"
local utils = require "kong.tools.utils"
local reports = require "kong.reports"
local endpoints = require "kong.api.endpoints"
local arguments = require "kong.api.arguments"
local singletons = require "kong.singletons"


local kong = kong
local type = type
local pairs = pairs
local setmetatable = setmetatable


local get_plugin = endpoints.get_entity_endpoint(kong.db.plugins.schema)
local put_plugin = endpoints.put_entity_endpoint(kong.db.plugins.schema)
local delete_plugin = endpoints.delete_entity_endpoint(kong.db.plugins.schema)


local function before_plugin_for_entity(entity_name, plugin_field)
  return function(self, db, helpers)
    local entity, _, err_t = endpoints.select_entity(self, db, kong.db[entity_name].schema)
    if err_t then
      return endpoints.handle_error(err_t)
    end

    if not entity then
      return kong.response.exit(404, { message = "Not found" })
    end

    local plugin, _, err_t = endpoints.select_entity(self, db, db.plugins.schema)
    if err_t then
      return endpoints.handle_error(err_t)
    end

    if not plugin
       or type(plugin[plugin_field]) ~= "table"
       or plugin[plugin_field].id ~= entity.id then
      return kong.response.exit(404, { message = "Not found" })
    end

    self.plugin = plugin
  end
end


local function fill_plugin_data(args, plugin)
  local post = args.post

  post.name = post.name or plugin.name

  -- Only now we can decode the 'config' table for form-encoded values
  post = arguments.decode(post, kong.db.plugins.schema)

  -- While we're at it, get values for composite uniqueness check
  post.route = post.route or plugin.route
  post.service = post.service or plugin.service
  post.consumer = post.consumer or plugin.consumer

  args.post = post
end


local patch_plugin
do
  local patch_plugin_endpoint = endpoints.patch_entity_endpoint(kong.db.plugins.schema)

  patch_plugin = function(self, db, helpers)
    local plugin = self.plugin
    fill_plugin_data(self.args, plugin)
    return patch_plugin_endpoint(self, db, helpers)
  end
end


-- Remove functions from a schema definition so that
-- cjson can encode the schema.
local schema_to_jsonable
do
  local insert = table.insert
  local ipairs = ipairs
  local next = next

  local fdata_to_jsonable


  local function fields_to_jsonable(fields)
    local out = {}
    for _, field in ipairs(fields) do
      local fname = next(field)
      local fdata = field[fname]
      insert(out, { [fname] = fdata_to_jsonable(fdata, "no") })
    end
    setmetatable(out, cjson.array_mt)
    return out
  end


  -- Convert field data from schemas into something that can be
  -- passed to a JSON encoder.
  -- @tparam table fdata A Lua table with field data
  -- @tparam string is_array A three-state enum: "yes", "no" or "maybe"
  -- @treturn table A JSON-convertible Lua table
  fdata_to_jsonable = function(fdata, is_array)
    local out = {}
    local iter = is_array == "yes" and ipairs or pairs

    for k, v in iter(fdata) do
      if is_array == "maybe" and type(k) ~= "number" then
        is_array = "no"
      end

      if k == "schema" then
        out[k] = schema_to_jsonable(v)

      elseif type(v) == "table" then
        if k == "fields" and fdata.type == "record" then
          out[k] = fields_to_jsonable(v)

        elseif k == "default" and fdata.type == "array" then
          out[k] = fdata_to_jsonable(v, "yes")

        else
          out[k] = fdata_to_jsonable(v, "maybe")
        end

      elseif type(v) == "number" then
        if v ~= v then
          out[k] = "nan"
        elseif v == math.huge then
          out[k] = "inf"
        elseif v == -math.huge then
          out[k] = "-inf"
        else
          out[k] = v
        end

      elseif type(v) ~= "function" then
        out[k] = v
      end
    end
    if is_array == "yes" or is_array == "maybe" then
      setmetatable(out, cjson.array_mt)
    end
    return out
  end


  schema_to_jsonable = function(schema)
    local fields = fields_to_jsonable(schema.fields)
    return { fields = fields }
  end
end


local function post_process(data)
  local r_data = utils.deep_copy(data)

  r_data.config = nil
  r_data.route = nil
  r_data.service = nil
  r_data.consumer = nil
  r_data.enabled = nil

  if type(data.service) == "table" and data.service.id then
    r_data.e = "s"

  elseif type(data.route) == "table" and data.route.id then
    r_data.e = "r"

  elseif type(data.consumer) == "table" and data.consumer.id then
    r_data.e = "c"
  end

  reports.send("api", r_data)

  return data
end


return {
  ["/plugins"] = {
    POST = function(_, _, _, parent)
      return parent(post_process)
    end,
  },

  ["/plugins/:plugins"] = {
    PATCH = function(self, db, helpers, parent)
      local post = self.args and self.args.post

      -- Read-before-write only if necessary
      if post and (post.name     == nil or
                   post.route    == nil or
                   post.service  == nil or
                   post.consumer == nil) then

        -- We need the name, otherwise we don't know what type of
        -- plugin this is and we can't perform *any* validations.
        local plugin, _, err_t = endpoints.select_entity(self, db, db.plugins.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if not plugin then
          return kong.response.exit(404, { message = "Not found" })
        end

        fill_plugin_data(self.args, plugin)
      end
      return parent()
    end,
  },

  ["/plugins/schema/:name"] = {
    GET = function(self, db, helpers)
      local subschema = db.plugins.schema.subschemas[self.params.name]
      if not subschema then
        return kong.response.exit(404, { message = "No plugin named '" .. self.params.name .. "'" })
      end

      local copy = schema_to_jsonable(subschema.fields.config)
      return kong.response.exit(200, copy)
    end
  },

  ["/plugins/enabled"] = {
    GET = function(_, _, helpers)
      local enabled_plugins = setmetatable({}, cjson.array_mt)
      for k in pairs(singletons.configuration.loaded_plugins) do
        enabled_plugins[#enabled_plugins+1] = k
      end
      return kong.response.exit(200, {
        enabled_plugins = enabled_plugins
      })
    end
  },

  -- Available for backward compatibility
  ["/consumers/:consumers/plugins/:plugins"] = {
    before = before_plugin_for_entity("consumers", "consumer"),
    PATCH = patch_plugin,
    GET = get_plugin,
    PUT = put_plugin,
    DELETE = delete_plugin,
  },

  -- Available for backward compatibility
  ["/routes/:routes/plugins/:plugins"] = {
    before = before_plugin_for_entity("routes", "route"),
    PATCH = patch_plugin,
    GET = get_plugin,
    PUT = put_plugin,
    DELETE = delete_plugin,
  },

  -- Available for backward compatibility
  ["/services/:services/plugins/:plugins"] = {
    before = before_plugin_for_entity("services", "service"),
    PATCH = patch_plugin,
    GET = get_plugin,
    PUT = put_plugin,
    DELETE = delete_plugin,
  },
}
