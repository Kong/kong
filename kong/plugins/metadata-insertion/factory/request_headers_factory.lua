local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local HOST = "host"
local RequestHeadersFactory = {}
local args = {}

function RequestHeadersFactory:new()
  return RequestHeadersFactory
end

function RequestHeadersFactory:getArgs()
  return args
end

function RequestHeadersFactory:mergeArgsWithRequestArgs()
  local requestArgs = req_get_headers()
  for k, v in pairs(requestArgs) do
    args[k] = v
  end
end

function RequestHeadersFactory:persist()
  for key, value in pairs(args) do
    if key:lower() ~= HOST then
      if value == "metadata_asked_for_removal" then
        req_set_header(key, nil)
      else
        req_set_header(key, value)
      end
    end
  end
end

function RequestHeadersFactory:removeArgByKey(key)
  if args[key] then
    args[key] = "metadata_asked_for_removal"
  end
end

function RequestHeadersFactory:replaceArgByKey(key, value)
  if args[key] then
    args[key] = value
  end
end

function RequestHeadersFactory:add(key, value)
  args[key] = value
end

return RequestHeadersFactory