-- ©2016 API Fortress Inc.
local stringy = require "stringy"

local _M = {}

-- pre-indexing global functions
local str_startswith = stringy.startswith
local str_endswith = stringy.endswith
local str_sub = string.sub
local str_len = string.len
local table_insert = table.insert
local encode_base64 = ngx.encode_base64

function _M.serialize(ngx)

  -- pre-indexing to reduce the number of lookups later on
  local ngx_req = ngx.req
  local ngx_resp = ngx.resp
  local ngx_var = ngx.var
  local ngx_ctx = ngx.ctx

  local contentType =  nil
  local request_headers = {}

  local status = ngx.status
  local method = ngx_req.get_method()
  local reqContentType = nil

  local reqBody = ngx_req.get_body_data()
  local requestUri = ngx_var.request_uri
  local uri = ngx_ctx.api.upstream_url

  -- Adjusting the URI ending character to be chained with requestUri
  if str_endswith(uri,"/") and str_startswith(requestUri, "/") then
    uri = str_sub(uri,0,str_len(uri)-1)
  end

  -- This should represent the whole URL
  uri = uri .. requestUri

  local postBody = nil
  local putBody = nil

  if method=="POST" then
    postBody = reqBody
  end

  -- PUT and PATCH share the same body. Subject to change later on
  if method=="PUT" or method=="PATCH" then
    putBody = reqBody
  end

  for k, v in pairs(ngx_req.get_headers()) do
    local val = v
    if type(val)=="table" then val = val[0] end
    local item = {name=k,value=v}
    if k=="content-type" then
      reqContentType = v
    end
    request_headers[#request_headers+1] = item
  end
  local response_headers = {}
  local propCompressed = false
  for k,v in pairs(ngx_resp.get_headers()) do
    if type(val)=="table" then val = val[0] end
    local item = {name=k,value=v}
    if k=="content-type" then
      contentType = v
    end
    if k=='content-encoding' and v=='gzip' then
      propCompressed = true
    end
    response_headers[#response_headers+1] = item
  end
  local dummy_cookies = {}
  table_insert(dummy_cookies,{name="apif",value="1"})
  local failed = false
  if status>340 or status<200 then
    failed = true
  end



  local metrics = {times={overall=ngx_var.request_time * 1000}}

  return {
    request = {
      url = uri,
      querystring = ngx_req.get_uri_args(), -- parameters, as a table
      method = method, -- http method
      headers = request_headers,
      cookies = dummy_cookies,
      size = ngx_var.request_length,
      putBody = putBody,
      postBody = postBody,
      contentType = reqContentType
    },
    response = {
      statusCode = tostring(status),
      headers = response_headers,
      contentType = contentType,
      cookies = dummy_cookies,
      failed = failed,
      data = encode_base64(ngx_ctx.captured_body),
      metrics = metrics
    },
    props = {
      compressed = propCompressed
    },
    started_at = ngx_req.start_time() * 1000
  }
end

return _M
