local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"

local DEFAULT_SLOTS = 100
local SLOTS_MIN, SLOTS_MAX = 10, 2^16
local SLOTS_MSG = "number of slots must be between " .. SLOTS_MIN .. " and " .. SLOTS_MAX

return {
  table = "upstreams",
  primary_key = {"id"},
  fields = {
    id = {
      type = "id", 
      dao_insert_value = true, 
      required = true,
    },
    created_at = {
      type = "timestamp", 
      immutable = true, 
      dao_insert_value = true, 
      required = true,
    },
    name = {
      -- name is a hostname like name that can be referenced in an `upstream_url` field
      type = "string", 
      unique = true, 
      required = true,
    },
    slots = {
      -- the number of slots in the loadbalancer algorithm
      type = "number",
      default = DEFAULT_SLOTS,
    },
  },
  self_check = function(schema, config, dao, is_updating)
    
    -- check the name
    local p = utils.normalize_ip(config.name)
    if not p then
      return false, Errors.schema("Invalid name; must be a valid hostname")
    end
    if p.type ~= "name" then
      return false, Errors.schema("Invalid name; no ip addresses allowed")
    end
    if p.port then
      return false, Errors.schema("Invalid name; no port allowed")
    end
    
    -- check the slots number
    if config.slots < SLOTS_MIN or config.slots > SLOTS_MAX then
      return false, Errors.schema(SLOTS_MSG)
    end
    
    return true
  end,
}
