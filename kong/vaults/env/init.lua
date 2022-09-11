local kong_meta = require "kong.meta"
local ffi = require "ffi"


local type = type
local gsub = string.gsub
local upper = string.upper
local find = string.find
local sub = string.sub
local str = ffi.string
local kong = kong


local ENV = {}

ffi.cdef [[
  extern char **environ;
]]


local function init()
  local e = ffi.C.environ
  if not e then
    kong.log.warn("could not access environment variables")
    return
  end

  local i = 0
  while e[i] ~= nil do
    local var = str(e[i])
    local p = find(var, "=", nil, true)
    if p then
      ENV[sub(var, 1, p - 1)] = sub(var, p + 1)
    end

    i = i + 1
  end
end


local function get(conf, resource, version)
  local prefix = conf.prefix
  if type(prefix) == "string" then
    resource = prefix .. resource
  end

  resource = upper(gsub(resource, "-", "_"))

  if version == 2 then
    resource = resource .. "_PREVIOUS"
  end

  return ENV[resource]
end


return {
  VERSION = kong_meta.version,
  init = init,
  get = get,
}
