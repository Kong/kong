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
    consumer_id = { type = "id", required = true, foreign = "consumers:id" },
    group = { type = "string", required = true, func = check_unique }
  },
}

return {acls = SCHEMA}
