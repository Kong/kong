-- This schema defines a sequential list of updates to the upstream/loadbalancer algorithm
-- hence entries cannot be deleted or modified. Only new ones appended that will overrule
-- previous entries.

local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"

local default_port = 8000
local default_weight = 100
local weight_min, weight_max = 0, 1000
local weight_msg = "weight must be from "..weight_min.." to "..weight_max

return {
  table = "targets",
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
    upstream_id = {
      type = "id",
      foreign = "upstreams:id"
    },
    target = {
      -- in 'hostname:port' format, if omitted default port will be inserted
      type = "string",
      unique = true, 
      required = true,
    },
    weight = {
      -- weight in the laodbalancer algorithm.
      -- to disable an entry, set the weight to 0
      type = "number",
      default = default_weight,
    },
  },
  self_check = function(schema, config, dao, is_updating)
    
    -- check weight
    if config.weight < weight_min or config.weight > weight_max then
      return false, Errors.schema(weight_msg)
    end

    -- check the target
    local p, err = utils.normalize_ip(config.target)
    if not p then
      return false, Errors.schema("Invalid target; not a valid hostname or ip address")
    end
    config.target = utils.format_host(p, default_port)

    return true
  end,
  marshall_event = function(self, t)
    return { id = t.id }
  end
}
