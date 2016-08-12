local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"

local default_slots = 100
local slots_min, slots_max = 10, 2^16
local slots_msg = "number of slots must be between "..slots_min.." and "..slots_max

return {
  table = "upstreams",
  primary_key = {"id", "name"},
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
      -- name is a hostname like name that can be referenced in an `upstream_url` field, 
      -- may include a port, if omitted defaults to 'default_port'
      type = "string", 
      unique = true, 
      required = true,
    },
    slots = {
      -- the number of slots in the loadbalancer algorithm
      type = "number",
      default = default_slots,
    },
    orderlist = {
      -- a list of sequential, but randomly ordered, integer numbers. In the datastore
      -- because all Kong nodes need the exact-same 'randomness'. If changed, consistency is lost.
      -- must have exactly `slots` number of entries, so regenerated whenever `slots` is changed.
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
    if config.slots < slots_min or config.slots > slots_max then
      return false, Errors.schema(slots_msg)
    end
    
    -- check the order array
    local order = config.orderlist
    if #order == config.slots then
      -- array size unchanged, check consistency
      local t = {}
      for i = 1, config.slots do
        local v = order[i]
        if type(v) ~= "number" or v ~= math.floor(v) then
          return false, Errors.schema("non-integer value found in order array")
        end
        if v < 1 or v > config.slots then
          return false, Errors.schema("order value out of bounds")
        end
        if t[v] then 
          return false, Errors.schema("duplicate value in order array")
        end
        t[v] = true
      end
    else
      -- size mismatch, regenerate order array
--TODO: check if it is safe to update data here!
      local t = {}
      for i = 1, config.slots do
        t[i] = {
          id = i, 
          order = math.random(1, config.slots),
        }
      end
      table.sort(t, function(a,b) return a.order < b.order end)
      for i, v in ipairs(t) do
        t[i] = v.id
      end
      
      config.orderlist = t
    end
    return true
  end,
  marshall_event = function(self, t)
    return { id = t.id }
  end
}
