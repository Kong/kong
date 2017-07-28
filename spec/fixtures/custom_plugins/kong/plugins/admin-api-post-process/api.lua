local crud = require "kong.api.crud_helpers"


local function uppercase_table_values(tbl)
  local result = {}

  for k, v in pairs(tbl) do
    if type(v) == "string" then
      result[k] = string.upper(v)

    elseif type(v) == "table" then
      result[k] = uppercase_table_values(tbl)

    else
      result[k] = v
    end
  end

  return result
end


return {
  ["/consumers/post_processed"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.consumers, uppercase_table_values)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.consumers, nil,
                uppercase_table_values)
    end,
  },

  ["/consumers/:username_or_id/post_processed"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.consumer, dao_factory.consumers, uppercase_table_values)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.consumers, self.consumer,
                 uppercase_table_values)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.consumers, uppercase_table_values)
    end,
  },
}
