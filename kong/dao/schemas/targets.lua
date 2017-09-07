-- This schema defines a sequential list of updates to the upstream/loadbalancer algorithm
-- hence entries cannot be deleted or modified. Only new ones appended that will overrule
-- previous entries.

local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"

local DEFAULT_PORT = 8000
local DEFAULT_WEIGHT = 100
local WEIGHT_MIN, WEIGHT_MAX = 0, 1000
local WEIGHT_MSG = "weight must be from " .. WEIGHT_MIN .. " to " .. WEIGHT_MAX

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
      required = true,
    },
    weight = {
      -- weight in the loadbalancer algorithm.
      -- to disable an entry, set the weight to 0
      type = "number",
      default = DEFAULT_WEIGHT,
    },
  },
  self_check = function(schema, config, dao, is_updating)
    
    -- check weight
    if config.weight < WEIGHT_MIN or config.weight > WEIGHT_MAX then
      return false, Errors.schema(WEIGHT_MSG)
    end

    -- check the target
    local p = utils.normalize_ip(config.target)
    if not p then
      return false, Errors.schema("Invalid target; not a valid hostname or ip address")
    end
    config.target = utils.format_host(p, DEFAULT_PORT)

    return true
  end,
}
