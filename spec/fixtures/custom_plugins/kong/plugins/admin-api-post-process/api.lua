local crud = require "kong.api.crud_helpers"


local function uppercase_table_values(tbl, depth)
  depth = depth or 0
  local result = {}

  if depth > 4 then
    return "{...}"
  end

  for k, v in pairs(tbl) do
    if type(v) == "string" then
      result[k] = string.upper(v)

    elseif type(v) == "table" then
      result[k] = uppercase_table_values(v, depth + 1)

    else
      result[k] = v
    end
  end

  return result
end


return {
  ["/plugins/post_processed"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins, uppercase_table_values)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.plugins, uppercase_table_values)
    end,
  },

  ["/plugins/:id/post_processed"] = {
    before = function(self, dao_factory, helpers)
      crud.find_plugin_by_filter(self, dao_factory, {
        id = self.params.id
      }, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.plugin, dao_factory.plugins, uppercase_table_values)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.plugins, self.plugin,
                 uppercase_table_values)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.plugins, uppercase_table_values)
    end,
  },
}
