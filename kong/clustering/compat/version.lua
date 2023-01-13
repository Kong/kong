-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local utils = require("kong.tools.utils")

local type = type
local tonumber = tonumber
local split = utils.split

local MAJOR_MINOR_PATTERN = "^(%d+)%.(%d+)%.%d+"

local _M = {}


---@param  version     string
---@return integer|nil major
---@return integer|nil minor
function _M.extract_major_minor(version)
  if type(version) ~= "string" then
    return nil, nil
  end

  local major, minor = version:match(MAJOR_MINOR_PATTERN)
  if not major then
    return nil, nil
  end

  major = tonumber(major, 10)
  minor = tonumber(minor, 10)

  return major, minor
end


---@param s string
---@return integer
function _M.string_to_number(s)
  local base = 1000000000
  local num = 0
  for _, v in ipairs(split(s, ".", 4)) do
    v = v:match("^(%d+)")
    num = num + base * (tonumber(v, 10) or 0)
    base = base / 1000
  end

  return num
end

return _M
