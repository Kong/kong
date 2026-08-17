local encode = require "cjson".encode


local function get(conf, resource, version)
  return encode({
    prefix = conf.prefix,
    suffix = conf.suffix,
    resource = resource,
    version = version,
  })
end


return {
  VERSION = "1.0.0",
  get = get,
}
