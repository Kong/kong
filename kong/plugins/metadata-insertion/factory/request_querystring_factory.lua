local req_get_uri_args = ngx.req.get_uri_args
local req_set_uri_args = ngx.req.set_uri_args

local RequestQuerystringFactory = {}
local args = {}

function RequestQuerystringFactory:new()
  return RequestQuerystringFactory
end

function RequestQuerystringFactory:getArgs()
  return args
end

function RequestQuerystringFactory:mergeArgsWithRequestArgs()
  local requestArgs = req_get_uri_args()
  for k, v in pairs(requestArgs) do
    args[k] = v
  end
end

function RequestQuerystringFactory:persist()
  req_set_uri_args(args)
end

function RequestQuerystringFactory:removeArgByKey(key)
  if args[key] then
    args[key] = nil
  end
end

function RequestQuerystringFactory:replaceArgByKey(key, value)
  if args[key] then
    args[key] = value
  end
end

function RequestQuerystringFactory:add(key, value)
  args[key] = value
end

return RequestQuerystringFactory