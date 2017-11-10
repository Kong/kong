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
    hash_on = {
      -- primary hash-key
      type = "string",
      default = "none",
      enum = {
        "none",
        "consumer",
        "ip",
        "header",
      },
    },
    hash_fallback = {
      -- secondary key, if primary fails
      type = "string",
      default = "none",
      enum = {
        "none",
        "consumer",
        "ip",
        "header",
      },
    },
    hash_on_header = {
      -- header name, if `hash_on == "header"`
      type = "string",
    },
    hash_fallback_header = {
      -- header name, if `hash_fallback == "header"`
      type = "string",
    },
    slots = {
      -- the number of slots in the loadbalancer algorithm
      type = "number",
      default = DEFAULT_SLOTS,
    },
  },
  self_check = function(schema, config, dao, is_updating)

    -- check the name
    if config.name then
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
    end

    if config.hash_on_header then
      local ok, err = utils.validate_header_name(config.hash_on_header)
      if not ok then
        return false, Errors.schema("Header: " .. err)
      end
    end

    if config.hash_fallback_header then
      local ok, err = utils.validate_header_name(config.hash_fallback_header)
      if not ok then
        return false, Errors.schema("Header: " .. err)
      end
    end

    if (config.hash_on == "header"
        and not config.hash_on_header) or
       (config.hash_fallback == "header"
        and not config.hash_fallback_header) then
      return false, Errors.schema("Hashing on 'header', " ..
                                  "but no header name provided")
    end

    if config.hash_on and config.hash_fallback then
      if config.hash_on == "none" then
        if config.hash_fallback ~= "none" then
          return false, Errors.schema("Cannot set fallback if primary " ..
                                      "'hash_on' is not set")
        end

      else
        if config.hash_on == config.hash_fallback then
          if config.hash_on ~= "header" then
            return false, Errors.schema("Cannot set fallback and primary " ..
                                        "hashes to the same value")

          else
            local upper_hash_on = config.hash_on_header:upper()
            local upper_hash_fallback = config.hash_fallback_header:upper()
            if upper_hash_on == upper_hash_fallback then
              return false, Errors.schema("Cannot set fallback and primary "..
                                          "hashes to the same value")
            end
          end
        end
      end
    end

    if config.slots then
      -- check the slots number
      if config.slots < SLOTS_MIN or config.slots > SLOTS_MAX then
        return false, Errors.schema(SLOTS_MSG)
      end
    end

    return true
  end,
}
