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
    orderlist = {
      -- a list of sequential, but randomly ordered, integer numbers. In the datastore
      -- because all Kong nodes need the exact-same 'randomness'. If changed, consistency is lost.
      -- must have exactly `slots` number of entries.
      type = "array",
      default = {},
    }
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
    
    -- check the order array
    local order = config.orderlist
    if #order == config.slots then
      -- array size unchanged, check consistency

      local t = utils.shallow_copy(order)
      table.sort(t)
      local count, max = 0, 0
      for i, v in pairs(t) do
        if i ~= v then
          return false, Errors.schema("invalid orderlist")
        end

        count = count + 1
        if i > max then
          max = i
        end
      end

      if count ~= config.slots or max ~= config.slots then
        return false, Errors.schema("invalid orderlist")
      end

    else
      -- size mismatch
      if #order > 0 then
        -- size given, but doesn't match the size of the also given orderlist
        return false, Errors.schema("size mismatch between 'slots' and 'orderlist'")
      end

      -- No list given, generate order array
      local t = {}
      for i = 1, config.slots do
        t[i] = {
          id = i, 
          order = math.random(1, config.slots),
        }
      end

      -- sort the array (we don't check for -accidental- duplicates as the 
      -- id field is used for the order and that one is always unique)
      table.sort(t, function(a,b) 
        return a.order < b.order
      end)

      -- replace the created 'record' with only the id
      for i, v in ipairs(t) do
        t[i] = v.id
      end
      
      config.orderlist = t
    end

    return true
  end,
}
