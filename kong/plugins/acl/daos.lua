local singletons = require "kong.singletons"

local function check_unique(group, acl)
  -- If dao required to make this work in integration tests when adding fixtures
  if singletons.dao and acl.consumer_id and group then
    local res, err = singletons.dao.acls:find_all {consumer_id = acl.consumer_id, group = group}
    if not err and #res > 0 then
      return false, "ACL group already exist for this consumer"
    elseif not err then
      return true
    end
  end
end

local SCHEMA = {
  primary_key = {"id"},
  table = "acls",
  cache_key = { "consumer_id" },
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true,
                    -- foreign = "consumers:id" -- manually tested in self-check
                  },
    group = { type = "string", required = true, func = check_unique }
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

return {acls = SCHEMA}
