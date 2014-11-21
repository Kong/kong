-- Copyright (C) Mashape, Inc.


local cjson = require "cjson"
local inspect = require "inspect"
local utils = require "resty.apenode.utils"
local dao = require "resty.apenode.base.dao.mock"


local _M = { _VERSION = '0.1' }


function _M.execute()
	ngx.log(ngx.DEBUG, "Access")

	-- Setting the version header
	ngx.header["X-Apenode-Version"] = _M._VERSION

	-- Retrieving the API from the Host that has been requested
	local api = dao.get_api(ngx.var.http_host)
	if not api then
		utils.show_error(404, "API not found")
	end

	-- Setting the backend URL for the proxy_pass directive
	local querystring = ngx.encode_args(ngx.req.get_uri_args());
	ngx.var.backend_url = api.backend_url .. ngx.var.uri .. "?" .. querystring

	-- There are some requests whose authentication needs to be skipped
	if _M.skip_authentication(ngx.req.get_headers()) then
		return -- Returning and keeping the Lua code running to the next handler
	end

	-- Retrieving the application from the key being passed along with the request
	local application_key = _M.get_application_key(ngx.req, api)
	local application = dao.get_application(application_key)
	if not dao.is_application_valid(application, api) then
		utils.show_error(403, "Your authentication credentials are invalid")
	end

	-- Saving these properties for the other handlers, especially the log handler
	ngx.ctx.application = application
	ngx.ctx.api = api
end


function _M.skip_authentication(headers)
	-- Skip upload request that expect a 100 Continue response
	return headers["expect"] and _M.starts_with(headers["expect"], "100")
end


function _M.get_application_key(request, api)
	local application_key = nil

	-- Let's check if the credential is in a request parameter
	if api.authentication_key_name then
		-- Try to get it from the querystring
		application_key = request.get_uri_args()[api.authentication_key_name]
		local content_type = ngx.req.get_headers()["content-type"]
		if not application_key and content_type then -- If missing from querystring, get it from the body
			content_type = string.lower(content_type) -- Lower it for easier comparison
			if content_type == "application/x-www-form-urlencoded" or _M.starts_with(content_type, "multipart/form-data") then
				local post_args = request.get_post_args()
				if post_args then
					application_key = post_args[api.authentication_key_name]
				end
			elseif content_type == "application/json" then
				-- Call ngx.req.read_body to read the request body first or turn on the lua_need_request_body directive to avoid errors.
				request.read_body()
				local body_data = request.get_body_data()
				if body_data and string.len(body_data) > 0 then
					local json = cjson.decode(body_data)
					application_key = json[api.authentication_key_name]
				end
			end
		end
	end

	-- The credentials might also be in the header
	if not application_key and api.authentication_header_name then
		application_key = request.get_headers()[api.authentication_header_name]
	end

	return dao.get_application(application_key)
end


function _M.starts_with(str, piece)
  return string.sub(str, 1, string.len(piece)) == piece
end


return _M
