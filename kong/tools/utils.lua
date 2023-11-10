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


function _M.get_runtime_data_path(prefix)
  local prefix = pl_path.normpath(prefix)
  -- Path used for runtime data such as unix domain sockets
  local prefix_hash = string.sub(ngx.md5(prefix), 1, 7)
  return fmt("/var/run/kong/%s", prefix_hash)
end
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
