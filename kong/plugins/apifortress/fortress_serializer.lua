-- ©2016 API Fortress Inc.
require("kong.plugins.apifortress.base64")

local _M = {}
function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

function string.ends(String,End)
   return End=='' or string.sub(String,-string.len(End))==End
end

function _M.serialize(ngx)
  local authenticated_entity
  if ngx.ctx.authenticated_credential ~= nil then
    authenticated_entity = {
      id = ngx.ctx.authenticated_credential.id,
      consumer_id = ngx.ctx.authenticated_credential.consumer_id
    }
  end

	local contentType =  nil
	local request_headers = {}
	local reqBody = ngx.req.get_body_data()

	local postBody = nil
	local putBody = nil
	local method = ngx.req.get_method()
	local reqContentType = nil
	if method=="POST" then
		postBody = reqBody
	end
	if method=="PUT" or method=="PATCH" then
		putBody = reqBody
	end
	for k, v in pairs(ngx.req.get_headers()) do
		local val = v
		if type(val)=="table" then val = val[0] end
		local item = {name=k,value=v}
		if k=="content-type" then
			reqContentType = v
		end
		table.insert(request_headers,item)
	end
	local response_headers = {}
	local propCompressed = false
	for k,v in pairs(ngx.resp.get_headers()) do
		if type(val)=="table" then val = val[0] end
		local item = {name=k,value=v}
		if k=="content-type" then
			contentType = v
		end
		if k=='content-encoding' and v=='gzip' then
			propCompressed = true
		end
		table.insert(response_headers,item)
	end
	local dummy_cookies = {}
	table.insert(dummy_cookies,{name="apif",value="1"})
	local failed = false
	if ngx.status>340 or ngx.status<200 then
		failed = true
	end
	local uri = ngx.ctx.api.upstream_url
	if string.ends(uri,"/") and string.starts(ngx.var.request_uri, "/") then
		uri = string.sub(uri,0,string.len(uri)-1)
	end
	uri = uri .. ngx.var.request_uri

	local metrics = {times={overall=ngx.var.request_time * 1000}}

  return {
    request = {
      url = uri,
      querystring = ngx.req.get_uri_args(), -- parameters, as a table
      method = ngx.req.get_method(), -- http method
    	headers = request_headers,
			cookies = dummy_cookies,
      size = ngx.var.request_length,
			putBody = putBody,
			postBody = postBody,
			contentType = reqContentType
    },
    response = {
      statusCode = tostring(ngx.status),
      headers = response_headers,
			contentType = contentType,
			cookies = dummy_cookies,
			failed = failed,
			data = to_base64(ngx.ctx.captured_body),
			metrics = metrics
    },
		props = {
			compressed = propCompressed
		},
    started_at = ngx.req.start_time() * 1000
  }
end

return _M
