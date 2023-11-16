---
-- Module containing some general utility functions used in many places in Kong.
--
-- NOTE: Before implementing a function here, consider if it will be used in many places
-- across Kong. If not, a local function in the appropriate module is preferred.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.utils

local pairs    = pairs
local ipairs   = ipairs
local require  = require
local fmt      = string.format
local re_match = ngx.re.match


local _M = {}


local validate_labels
do
  local nkeys = require "table.nkeys"

  local MAX_KEY_SIZE   = 63
  local MAX_VALUE_SIZE = 63
  local MAX_KEYS_COUNT = 10

  -- validation rules based on Kong Labels AIP
  -- https://kong-aip.netlify.app/aip/129/
  local BASE_PTRN = "[a-z0-9]([\\w\\.:-]*[a-z0-9]|)$"
  local KEY_PTRN  = "(?!kong)(?!konnect)(?!insomnia)(?!mesh)(?!kic)" .. BASE_PTRN
  local VAL_PTRN  = BASE_PTRN

  local function validate_entry(str, max_size, pattern)
    if str == "" or #str > max_size then
      return nil, fmt(
        "%s must have between 1 and %d characters", str, max_size)
    end
    if not re_match(str, pattern, "ajoi") then
      return nil, fmt("%s is invalid. Must match pattern: %s", str, pattern)
    end
    return true
  end

  -- Validates a label array.
  -- Validates labels based on the kong Labels AIP
  function validate_labels(raw_labels)
    if nkeys(raw_labels) > MAX_KEYS_COUNT then
      return nil, fmt(
        "labels validation failed: count exceeded %d max elements",
        MAX_KEYS_COUNT
      )
    end

    for _, kv in ipairs(raw_labels) do
      local del = kv:find(":", 1, true)
      local k = del and kv:sub(1, del - 1) or ""
      local v = del and kv:sub(del + 1) or ""

      local ok, err = validate_entry(k, MAX_KEY_SIZE, KEY_PTRN)
      if not ok then
        return nil, "label key validation failed: " .. err
      end
      ok, err = validate_entry(v, MAX_VALUE_SIZE, VAL_PTRN)
      if not ok then
        return nil, "label value validation failed: " .. err
      end
    end

    return true
  end
end
_M.validate_labels = validate_labels


do
  local modules = {
    "kong.tools.table",
    "kong.tools.sha256",
    "kong.tools.yield",
    "kong.tools.string",
    "kong.tools.uuid",
    "kong.tools.rand",
    "kong.tools.system",
    "kong.tools.time",
    "kong.tools.module",
    "kong.tools.ip",
    "kong.tools.http",
  }

  for _, str in ipairs(modules) do
    local mod = require(str)
    for name, func in pairs(mod) do
      _M[name] = func
    end
  end
end


return _M
