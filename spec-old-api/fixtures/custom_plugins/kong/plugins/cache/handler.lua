local BasePlugin = require "kong.plugins.base_plugin"
local singletons = require "kong.singletons"
local responses  = require "kong.tools.responses"


local CacheHandler = BasePlugin:extend()


CacheHandler.PRIORITY = 1000


function CacheHandler:new()
  CacheHandler.super.new(self, "cache")
end


function CacheHandler:access(conf)
  CacheHandler.super.access(self)

  ngx.req.read_body()

  local args, err = ngx.req.get_post_args()
  if not args then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local cache_key = args.cache_key
  if not cache_key then
    return responses.send_HTTP_BAD_REQUEST("missing cache_key")
  end

  local cache_value = args.cache_value
  if not cache_value then
    return responses.send_HTTP_BAD_REQUEST("missing cache_value")
  end

  local function cb()
    return cache_value
  end

  local value, err = singletons.cache:get(cache_key, nil, cb)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return responses.send_HTTP_OK(value)
end


return CacheHandler
