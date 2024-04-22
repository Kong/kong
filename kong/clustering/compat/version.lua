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
local floor = math.floor

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

---@param n integer
---@return string
function _M.number_to_string(n)
  -- This function takes a version number in the form of a single integer
  -- and converts it to a string in the format "major.minor.patch.build".

  -- The major version number is the quotient of n divided by 1 billion (1e9).
  -- We use the floor function to get the largest integer less than or equal to the quotient.
  local major = floor(n / 1e9)

  -- The minor version number is the remainder of n divided by 1 billion (1e9),
  -- divided by 1 million (1e6). We use the floor function to get the largest integer
  -- less than or equal to the quotient.
  local minor = floor((n % 1e9) / 1e6)

  -- The patch version number is the remainder of n divided by 1 million (1e6),
  -- divided by 1 thousand (1e3). We use the floor function to get the largest integer
  -- less than or equal to the quotient.
  local patch = floor((n % 1e6) / 1e3)

  -- The build number is the remainder of n divided by 1 thousand (1e3).
  local build = n % 1e3

  -- We concatenate the major, minor, patch, and build numbers with periods
  -- in between to get the string representation of the version number.
  return major .. "." .. minor .. "." .. patch .. "." .. build
end
return _M
