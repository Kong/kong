local type = type
local gsub = string.gsub
local upper = string.upper
local kong = kong


local ENV = {}


local function init()
  local ffi = require "ffi"

  ffi.cdef("extern char **environ;")

  local e = ffi.C.environ
  if not e then
    kong.log.warn("could not access environment variables")
  end

  local find = string.find
  local sub = string.sub
  local str = ffi.string

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

  resource = gsub(resource, "-", "_")

  if type(prefix) == "string" then
    resource = prefix .. resource
  end

  resource = upper(resource)

  if version == 2 then
    resource = resource .. "_PREVIOUS"
  end

  return ENV[resource]
end


return {
  VERSION = "1.0.0",
  init = init,
  get = get,
}
