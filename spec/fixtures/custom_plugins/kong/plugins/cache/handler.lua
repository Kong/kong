-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local BasePlugin = require "kong.plugins.base_plugin"
local singletons = require "kong.singletons"


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
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local cache_key = args.cache_key
  if not cache_key then
    return kong.response.exit(400, { message = "missing cache_key" })
  end

  local cache_value = args.cache_value
  if not cache_value then
    return kong.response.exit(400, { message = "missing cache_value" })
  end

  local function cb()
    return cache_value
  end

  local value, err = singletons.cache:get(cache_key, nil, cb)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  return kong.response.exit(200, type(value) == "table" and value or { message = value })
end


return CacheHandler
