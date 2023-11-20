-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
local match    = string.match


local _M = {}


--- Extract the parent domain of CN and CN itself from X509 certificate
-- @tparam resty.openssl.x509 x509 the x509 object to extract CN
-- @return cn (string) CN + parent (string) parent domain of CN, or nil+err if any
function _M.get_cn_parent_domain(x509)
  local name, err = x509:get_subject_name()
  if err then
    return nil, err
  end
  local cn, _, err = name:find("CN")
  if err then
    return nil, err
  end
  cn = cn.blob
  local parent = match(cn, "^[%a%d%*-]+%.(.+)$")
  return cn, parent
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
