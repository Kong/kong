-- Stub _G.ngx for unit testing.
-- Creates a stub for `ngx` for use by Kong's modules such as the DAO. It allows to use them
-- outside of the nginx context such as when using the CLI, or unit testing.
--
-- Monkeypatches the global `ngx` table.

local reg = require "rex_pcre"
local utils = require "kong.tools.utils"

-- DICT Proxy
-- https://github.com/bsm/fakengx/blob/master/fakengx.lua

local SharedDict = {}

local function set(data, key, value)
  data[key] = {
    value = value,
    info = {expired = false}
  }
end

function SharedDict:new()
  return setmetatable({data = {}}, {__index = self})
end

function SharedDict:get(key)
  return self.data[key] and self.data[key].value, nil
end

function SharedDict:set(key, value)
  set(self.data, key, value)
  return true, nil, false
end

SharedDict.safe_set = SharedDict.set

function SharedDict:add(key, value)
  if self.data[key] ~= nil then
    return false, "exists", false
  end

  set(self.data, key, value)
  return true, nil, false
end

function SharedDict:replace(key, value)
  if self.data[key] == nil then
    return false, "not found", false
  end

  set(self.data, key, value)
  return true, nil, false
end

function SharedDict:delete(key)
  self.data[key] = nil
end

function SharedDict:incr(key, value)
  if not self.data[key] then
    return nil, "not found"
  elseif type(self.data[key].value) ~= "number" then
    return nil, "not a number"
  end

  self.data[key].value = self.data[key].value + value
  return self.data[key].value, nil
end

function SharedDict:flush_all()
  for _, item in pairs(self.data) do
    item.info.expired = true
  end
end

function SharedDict:flush_expired(n)
  local data = self.data
  local flushed = 0

  for key, item in pairs(self.data) do
    if item.info.expired then
      data[key] = nil
      flushed = flushed + 1
      if n and flushed == n then
        break
      end
    end
  end

  self.data = data

  return flushed
end

local shared = {}
local shared_mt = {
  __index = function(self, key)
    if shared[key] == nil then
      shared[key] = SharedDict:new()
    end
    return shared[key]
  end
}

_G.ngx = {
  stub = true,
  req = {
    get_headers = function()
      return {}
    end,
    set_header = function()
      return {}
    end
  },
  ctx = {},
  header = {},
  get_phase = function() return "init" end,
  socket = {},
  exit = function() end,
  say = function() end,
  log = function() end,
  --socket = { tcp = {} },
  now = function() return os.time() end,
  time = function() return os.time() end,
  timer = {
    at = function() end
  },
  shared = setmetatable({}, shared_mt),
  re = {
    match = reg.match,
    gsub = function(str, pattern, sub)
      local res_str, _, sub_made = reg.gsub(str, pattern, sub)
      return res_str, sub_made
    end
  },
  encode_base64 = function(str)
    return string.format("base64_%s", str)
  end,
  encode_args = utils.encode_args
}
