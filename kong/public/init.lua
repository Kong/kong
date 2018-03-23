local require      = require
local meta         = require "kong.meta"


local setmetatable = setmetatable
local getmetatable = getmetatable
local tonumber     = tonumber
local tostring     = tostring
local ipairs       = ipairs
local pcall        = pcall
local match        = string.match
local find         = string.find
local type         = type
local fmt          = string.format
local sub          = string.sub


local NAME = meta._NAME .. " public api"

local VERSIONS = {
  "1.0.0",
  "1.0.1",
}

local APIS = {
  "cache",
  "configuration",
  "ctx",
  "dao",
  "db",
  "dns",
  "http",
  "ipc",
  "log",
  "request",
  "response",
  "shm",
  "timers",
  "utils",
  "upstream",
  "upstream.response",
}

local COMPATIBLE_VERSIONS = {}

local LATEST_VERSION

local KONG_VERSION = meta._VERSION
local KONG_VERSION_NUM = tonumber(fmt("%02u%02u%02u", meta._VERSION_TABLE.major,
                                                      meta._VERSION_TABLE.minor,
                                                      meta._VERSION_TABLE.patch))


local function parse_version(version)
  local major, minor, patch

  local s1 = find(version, ".", 1, true)

  if not s1 then
    if not match(version, "^%d+$") then
      return
    end

    return tonumber(version), nil, nil
  end

  major = sub(version, 1, s1 - 1)
  if not match(major, "^%d+$") then
    return
  end

  major = tonumber(major)

  local s2 = find(version, ".", s1 + 1, true)
  if not s2 then
    minor = sub(version, s1 + 1)
    if not match(minor, "^%d+$") then
      return
    end

    return major, tonumber(minor), nil
  end

  minor = sub(version, s1 + 1, s2 - 1)
  if not match(minor, "^%d+$") then
    return
  end

  minor = tonumber(minor)

  patch = sub(version, s2 + 1)
  if not match(patch, "^%d+$") then
    return
  end

  patch = tonumber(patch)

  return major, minor, patch
end


local function load_api(major, minor, patch)
  local version

  if major and minor and patch then
    version = fmt("%u.%u.%u", major, minor, patch)

  elseif major and minor then
    version = fmt("%u.%u", major, minor)

  elseif major then
    version = major

  else
    return LATEST_VERSION
  end

  local api = COMPATIBLE_VERSIONS[version]
  if not api then
    return nil, 'invalid ' .. NAME .. ' version "' .. tostring(version) .. '"'
  end

  return api
end


local function set_api_meta(major, minor, patch, name, found, api)
  if not found then
    return
  end

  local mt_index
  local mt_call

  if type(api) == "table" then
    mt_index = api
    local api_mt = getmetatable(api)
    if api_mt and api_mt.__call then
      mt_call = function(_, ...)
        return api(...)
      end
    end

  elseif type(api) == "function" then
    mt_call = function(_, ...)
      return api(...)
    end
  end

  local version     = fmt("%u.%u.%u", major, minor, patch)
  local version_num = tonumber(fmt("%02u%02u%02u", major, minor, patch))

  return setmetatable({
    _NAME        = name,
    _VERSION     = version,
    _VERSION_NUM = version_num,
    v            = function(major, minor, patch)
      local apis, err = load_api(major, minor, patch)
      if not apis then
        return nil, err
      end

      if not apis[name] then
        return nil, NAME .. ' "' .. name .. '" (' .. version .. ") was not found"
      end

      return apis[name]
    end
  }, {
    __index = mt_index,
    __call  = mt_call,
  })
end


local function require_api(major, minor, patch, compatible, name)
  local module = fmt("kong.public.%02u.%02u.%02u.%s", major, minor, patch, name)
  local api = set_api_meta(major, minor, patch, name, pcall(require, module))
  if api then
    return api
  end

  if compatible[name] then
    return compatible[name]
  end

  module = fmt("kong.public.%02u.%02u.%s", major, minor, name)
  api = set_api_meta(major, minor, 0, name, pcall(require, module))
  if api then
    return api
  end

  module = fmt("kong.public.%02u.%s", major, name)
  api = set_api_meta(major, 0, 0, name, pcall(require, module))
  if api then
    return api
  end
end


local function require_apis(major, minor, patch, compatible)
  local apis = {
    _NAME            = NAME,
    _VERSION         = KONG_VERSION,
    _VERSION_NUM     = KONG_VERSION_NUM,
    _API_VERSION     = fmt("%u.%u.%u", major, minor, patch),
    _API_VERSION_NUM = tonumber(fmt("%02u%02u%02u", major, minor, patch)),
    v                = load_api,
  }
  for _, name in ipairs(APIS) do
    apis[name] = require_api(major, minor, patch, compatible, name)
  end
  return apis
end


for _, version in ipairs(VERSIONS) do
  local major, minor, patch = parse_version(version)

  major = major or 0
  minor = minor or 0
  patch = patch or 0

  local apis = require_apis(major, minor, patch, COMPATIBLE_VERSIONS[major] or {})

  COMPATIBLE_VERSIONS[apis._API_VERSION]       = apis
  COMPATIBLE_VERSIONS[apis._API_VERSION_NUM]   = apis
  COMPATIBLE_VERSIONS[major]                   = apis
  COMPATIBLE_VERSIONS[tostring(major)]         = apis
  COMPATIBLE_VERSIONS[major .. "." .. minor]   = apis

  LATEST_VERSION = apis
end


return LATEST_VERSION
