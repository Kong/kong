local utils = require "kong.tools.utils"

local SCHEMA = {
  primary_key = {"id"},
  table = "hmacauth_credentials",
  cache_key = { "username" },
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = { type = "id", required = true,
                   -- foreign = "consumers:id" -- manually tested in self-check
                  },
    username = {type = "string", required = true, unique = true},
    secret = {type = "string", default = utils.random_string}
  },
  self_check = function(schema, plugin_t, dao, is_update)
    local consumer_id = plugin_t.consumer_id
    if consumer_id ~= nil then
      local ok, err = dao.db.new_db.consumers:check_foreign_key({ id = consumer_id },
                                                                "Consumer")
      if not ok then
        return false, err
      end
    end

    return true
  end,
}

return {hmacauth_credentials = SCHEMA}
