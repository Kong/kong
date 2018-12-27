local kong = kong
local null = ngx.null
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local reports = require "kong.reports"
local endpoints = require "kong.api.endpoints"
local arguments = require "kong.api.arguments"
local singletons = require "kong.singletons"


local type = type
local pairs = pairs


local get_plugin = endpoints.get_entity_endpoint(kong.db.plugins.schema)
local put_plugin = endpoints.put_entity_endpoint(kong.db.plugins.schema)
local delete_plugin = endpoints.delete_entity_endpoint(kong.db.plugins.schema)


local function before_plugin_for_entity(entity_name, plugin_field)
  return function(self, db, helpers)
    local entity = endpoints.select_entity(self, db, kong.db[entity_name].schema)
    if not entity then
      return helpers.responses.send_HTTP_NOT_FOUND()
    end

    local plugin = db.plugins:select({ id = self.params.id })
    if not plugin
       or type(plugin[plugin_field]) ~= "table"
       or plugin[plugin_field].id ~= entity.id then
      return helpers.responses.send_HTTP_NOT_FOUND()
    end
    self.plugin = plugin

    self.params.plugins = self.params.id
  end
end


local function fill_plugin_data(args, plugin)
  local post = args.post

  post.name = post.name or plugin.name

  -- Only now we can decode the 'config' table for form-encoded values
  post = arguments.decode(post, kong.db.plugins.schema)

  -- While we're at it, get values for composite uniqueness check
  post.api = post.api or plugin.api
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
  local function fdata_to_jsonable(fdata)
    local out = {}
    for k, v in pairs(fdata) do
      if k == "schema" then
        out[k] = schema_to_jsonable(v)

      elseif type(v) == "table" then
        out[k] = fdata_to_jsonable(v)

      elseif type(v) ~= "function" then
        out[k] = v
      end
    end
    return out
  end

  local insert = table.insert
  local ipairs = ipairs
  local next = next

  schema_to_jsonable = function(schema)
    local fields = {}
    for _, field in ipairs(schema.fields) do
      local fname = next(field)
      local fdata = field[fname]
      insert(fields, { [fname] = fdata_to_jsonable(fdata) })
    end
    return { fields = fields }
  end
end


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  if data.service ~= null and data.service.id then
    r_data.e = "s"
  elseif data.route ~= null and data.route.id then
    r_data.e = "r"
  elseif data.consumer ~= null and data.consumer.id then
    r_data.e = "c"
  elseif data.api ~= null and data.api.id then
    r_data.e = "a"
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
                   post.consumer == nil or
                   post.api      == nil) then

        -- We need the name, otherwise we don't know what type of
        -- plugin this is and we can't perform *any* validations.
        local plugin = db.plugins:select({ id = self.params.plugins })
        if not plugin then
          return helpers.responses.send_HTTP_NOT_FOUND()
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
        return helpers.responses.send_HTTP_NOT_FOUND("No plugin named '" .. self.params.name .. "'")
      end

      local copy = schema_to_jsonable(subschema.fields.config)
      return helpers.responses.send_HTTP_OK(copy)
    end
  },

  ["/plugins/enabled"] = {
    GET = function(_, _, helpers)
      local enabled_plugins = setmetatable({}, cjson.empty_array_mt)
      for k in pairs(singletons.configuration.loaded_plugins) do
        enabled_plugins[#enabled_plugins+1] = k
      end
      return helpers.responses.send_HTTP_OK {
        enabled_plugins = enabled_plugins
      }
    end
  },

  -- Available for backward compatibility
  ["/consumers/:consumers/plugins/:id"] = {
    before = before_plugin_for_entity("consumers", "consumer"),
    PATCH = patch_plugin,
    GET = get_plugin,
    PUT = put_plugin,
    DELETE = delete_plugin,
  },

  -- Available for backward compatibility
  ["/routes/:routes/plugins/:id"] = {
    before = before_plugin_for_entity("routes", "route"),
    PATCH = patch_plugin,
    GET = get_plugin,
    PUT = put_plugin,
    DELETE = delete_plugin,
  },

  -- Available for backward compatibility
  ["/services/:services/plugins/:id"] = {
    before = before_plugin_for_entity("services", "service"),
    PATCH = patch_plugin,
    GET = get_plugin,
    PUT = put_plugin,
    DELETE = delete_plugin,
  },

  -- Available for backward compatibility
  ["/apis/:apis/plugins/:id"] = {
    before = before_plugin_for_entity("apis", "api"),
    PATCH = patch_plugin,
    GET = get_plugin,
    PUT = put_plugin,
    DELETE = delete_plugin,
  },

}
