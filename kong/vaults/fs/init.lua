local kong_meta = require "kong.meta"


local normpath = require("pl.path").normpath
local type = type
local open = io.open


local function file_read(file_path)
  local file, err = open(file_path, "rb")
  if not file then
    return nil, err
  end

  local content, err = file:read("*a")

  file:close()

  if not content then
    return nil, err
  end

  return content
end


local function get(conf, resource, _)
  local prefix = conf.prefix
  if type(prefix) ~= "string" then
    return nil, "fs vault prefix is mandatory, please configure it"
  end

  local file_path = normpath(prefix) .. "/" .. normpath(resource)
  local value, err = file_read(file_path)
  return value, err
end


return {
  VERSION = kong_meta.version,
  get = get,
}
