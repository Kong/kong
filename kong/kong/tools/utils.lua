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


local _M = {}


do
  local modules = {
    -- [[ keep it here for compatibility
    "kong.tools.table",
    "kong.tools.uuid",
    "kong.tools.rand",
    "kong.tools.time",
    "kong.tools.string",
    "kong.tools.ip",
    "kong.tools.http",
    -- ]] keep it here for compatibility
  }

  for _, str in ipairs(modules) do
    local mod = require(str)
    for name, func in pairs(mod) do
      _M[name] = func
    end
  end
end


return _M
