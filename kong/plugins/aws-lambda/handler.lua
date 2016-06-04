local cjson = require 'cjson'
local http_client = require 'kong.tools.http_client'
local ltn12 = require 'ltn12'

local prepare_request = require "kong.plugins.aws-lambda.aws.v4".prepare_request

local BasePlugin = require "kong.plugins.base_plugin"

local AwsLambdaHandler = BasePlugin:extend()

function AwsLambdaHandler:new()
	AwsLambdaHandler.super.new(self, "aws-lambda")
end

function AwsLambdaHandler:access(conf)
	AwsLambdaHandler.super.access(self)

	if ngx.ctx.api.upstream_url:find("^aws%-lambda") == nil then
		ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
		ngx.print("Invalid upstream_url - must be 'aws-lambda'.")
		return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
	end

	local creds = {
		access_key = conf.aws_access_key,
		secret_key = conf.aws_secret_key
	}
	local reqHeaders = ngx.req.get_headers()
	local auth = reqHeaders["Authorization"]
	if auth ~= nil and auth ~= "" then
		local parts = {} partsLen = 0
		for p in string.gmatch(auth, "%S+") do
			table.insert(parts, p)
			partsLen = partsLen + 1
		end
		if partsLen > 1 then
			local base64 = parts[2]
			local plain = ngx.decode_base64(base64)
			parts = {} partsLen = 0
			for p in string.gmatch(plain, "[^:]+") do
				table.insert(parts, p)
				partsLen = partsLen + 1
			end
			if partsLen > 1 then
				creds.access_key = parts[1]
				creds.secret_key = parts[2]
			end
		end
	end

	--conf.qualifier ???
	--conf.client_context ???
	--conf.invocation_type ???
	--conf.log_type ???

        local body = cjson.decode(conf.body)
	ngx.req.read_body()
	local post
	local contentType = reqHeaders["content-type"]
	if contentType ~= nil and contentType:find("application/json") ~= nil then
		post = cjson.decode(ngx.req.get_body_data())
	else
		post = ngx.req.get_post_args()
	end
	for k, v in pairs(post) do
		body[k] = v
	end
        local args = ngx.req.get_uri_args()
        for k, v in pairs(args) do
          body[k] = v
        end
        local bodyJson = cjson.encode(body)

	local request, _ = prepare_request({
	    Region = conf.aws_region,
	    Service = "lambda",
	    method = 'POST',
	    headers = {
		["X-Amz-Target"] = "invoke";
		["Content-Type"] = "application/x-amz-json-1.1";
		["Content-Length"] = tostring(string.len(bodyJson))
	    },
	    body = bodyJson,
	    path = '/2015-03-31/functions/'..conf.function_name..'/invocations',
	    AccessKey = creds.access_key,
	    SecretKey = creds.secret_key
	})

	local response = {}
        -- one, code, headers, status = https.request
	local response, status, headers, _ = http_client.post(
		request.url,
		request.body,
		request.headers
	)

        local errorType = headers["x-amz-function-error"]
        if errorType ~= nil and errorType ~= "" then
		ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
		ngx.print(response)
		return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
	end

	ngx.print(response)
	return ngx.exit(ngx.HTTP_OK)
end

return AwsLambdaHandler
