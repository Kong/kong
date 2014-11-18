-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"
local inspect = require "inspect"

local _M = { _VERSION = '0.1' }


function _M.execute()
    ngx.log(ngx.INFO, "Access")

    ngx.header["X-Apenode-Version"] = _M._VERSION

    local api = _M.get_api(ngx.var.http_host)
    if not api then
    	_M.show_error(404, "API not found")
    end

    -- Set the backend URL
    local querystring = ngx.encode_args(ngx.req.get_uri_args());
    ngx.var.backend_url = api.backend_url .. ngx.var.uri .. "?" .. querystring

    if _M.skip_authentication(ngx.req.get_headers()) then
    	return
    end

    local account = _M.get_account(ngx.req, api)
    if not account or not _M.is_account_valid(account, api) then
		_M.show_error(403, "Your authentication credentials are invalid")
    end

end


function _M.skip_authentication(headers)
	-- Skip upload request that expect a 100 Continue response
	if headers["expect"] and _M.starts_with(headers["expect"], "100") then
		return true
	end
	return false
end


function _M.get_api(host)
	local api = {
		id = "123",
		backend_url = "https://httpbin.org",
		authentication_key_name = "apikey",
		authentication_header_name = nil
	}
	return api
end


function _M.get_account(request, api)
	local account_key = nil

	-- Let's check if the credential is in a request parameter
	if api.authentication_key_name then
		account_key = request.get_uri_args()[api.authentication_key_name]
		if not account_key and request.get_headers()["content-type"] then
			local content_type = string.lower(ngx.req.get_headers()["content-type"])
			if content_type == "application/x-www-form-urlencoded" or _M.starts_with(content_type, "multipart/form-data") then
				local post_args = request.get_post_args()
				if post_args then
					account_key = post_args[api.authentication_key_name]
				end
			elseif content_type == "application/json" then
				-- Call ngx.req.read_body to read the request body first or turn on the lua_need_request_body directive to avoid errors.
    			request.read_body()
    			local body_data = request.get_body_data()
				if body_data and string.len(body_data) > 0 then
					local json = cjson.decode(body_data)
					account_key = json[api.authentication_key_name]
				end
			end
		end
	end

	-- The credentials might also be in the header
	if not account_key and api.authentication_header_name then
		account_key = request.get_headers()[api.authentication_header_name]
	end

	return account_key
end


function _M.is_account_valid(account, api)
	return true
end


function _M.show_error(status, message)
	ngx.status = status
	ngx.print(cjson.encode({status = status, message = message}))
	ngx.exit(status)
end


function _M.starts_with(str, piece)
  return string.sub(str, 1, string.len(piece)) == piece
end


return _M
