local ngx = ngx
local kong = kong


local EnableBuffering = {
  PRIORITY = math.huge
}


function EnableBuffering:access()
  kong.service.request.enable_buffering()
end


function EnableBuffering:header_filter(conf)
  if conf.mode == "modify-json" then
    local body = assert(kong.service.response.get_body())
    body.modified = true
    return kong.response.exit(kong.response.get_status(), body, {
      Modified = "yes",
    })
  end

  if conf.mode == "md5-header" then
    local body = kong.service.response.get_raw_body()
    kong.response.set_header("MD5", ngx.md5(body))
  end
end


return EnableBuffering
