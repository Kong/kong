-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants      = require "kong.plugins.upstream-oauth.cache.constants"
local is_lapis_array = require "kong.tools.utils".is_lapis_array
local sha256_hex     = require "kong.tools.sha256".sha256_hex


local CACHE_PREFIX   = "upstream-oauth:"
local type = type
local table_sort = table.sort
local table_insert = table.insert
local tostring = tostring
local ipairs = ipairs


local _M             = { constants = constants }


local function serialize(data, cur_key)
  local result = ""
  if type(data) ~= "table" then
    result = "&" .. cur_key .. "=" .. tostring(data)
  else
    -- Array of keys in the order in which they should be seralized
    local data_keys = {}
    if is_lapis_array(data) then
      -- Arrays are sorted by their values
      table_sort(data)
      for k in pairs(data) do table_insert(data_keys, k) end
    else
      -- Hashes are sorted by their key names
      for k in pairs(data) do table_insert(data_keys, k) end
      table_sort(data_keys)
    end

    for _, key_name in ipairs(data_keys) do
      local nested_key = cur_key and cur_key .. "." .. key_name or key_name
      result = result .. serialize(data[key_name], nested_key)
    end
  end
  return result
end

--- Create a unique identifier which can be used to cache an OAuth 2.0 access token
--- The obj parameter can be any lua type.  Tables are tested for logical equivalence
--- Ordering of keys in a hash or values in an array will not effect the result.
-- @param obj (table) describing all parameters used to fetch the key from the IdP
-- @return (string) the key computed for the given params
function _M.key(obj)
  return CACHE_PREFIX .. sha256_hex(serialize(obj))
end

function _M.strategy(opts)
  local strategy = require("kong.plugins.upstream-oauth.cache.strategies." .. opts.strategy_name)
  return strategy.new(opts.strategy_opts)
end

return _M
