local type = type


local CacheHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}


function CacheHandler:access(conf)
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

  local value, err = kong.cache:get(cache_key, nil, cb)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  return kong.response.exit(200, type(value) == "table" and value or { message = value })
end


return CacheHandler
