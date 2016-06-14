local cjson = require 'cjson'
local http_client = require 'kong.tools.http_client'

local prepare_request = require "kong.plugins.aws-lambda.aws.v4".prepare_request

local BasePlugin = require "kong.plugins.base_plugin"

local AwsLambdaHandler = BasePlugin:extend()

function AwsLambdaHandler:new()
	AwsLambdaHandler.super.new(self, "aws-lambda")
end

local function getCreds(conf, reqHeaders)
	local creds = {}

	local auth = reqHeaders["Authorization"]
	if string.len(auth or "") > 0 then
		local parts = {} local partsLen = 0
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
	if string.len(creds.access_key or "") > 0 or string.len(creds.secret_key or "") > 0 then return creds end

	creds.access_key = conf.aws_access_key
	creds.secret_key = conf.aws_secret_key
	if string.len(creds.access_key or "") > 0 or string.len(creds.secret_key or "") > 0 then return creds end

	local security_credentials_url = 'http://169.254.169.254/latest/meta-data/iam/security-credentials/'
	local response, code, _ = http_client.get(security_credentials_url, nil, {})
	if code == 404 then return creds end

	local role_name = response
	response, code, _ = http_client.get(security_credentials_url..role_name, nil, {})
	if code == 404 then return creds end

	local security_credentials_json = response
	local security_credentials = cjson.decode(security_credentials_json)
	creds.access_key = security_credentials.AccessKeyId
	creds.secret_key = security_credentials.SecretAccessKey
	creds.security_token = security_credentials.Token
	return creds
end

local function getBodyJson(conf, reqHeaders)
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
        return cjson.encode(body)
end

local function getTarget(conf)
	local target = {
		region = nil,
		function_name = nil,
		qualifier = nil,
		is_valid = true,
		error_message = nil
	}

	local upstream_url = ngx.ctx.api.upstream_url

	if upstream_url:find("^aws%-lambda://[^/]+/[^/]+") == nil then
		target.is_valid = false
		target.error_message = "Invalid upstream_url - must be 'aws-lambda://<aws_region>/<function_name>'."
		return target
	end

	local url = require("socket.url").parse(upstream_url)
	target.region = url.host
	target.function_name = url.path:sub(2)
	local query = url.query
	if string.len(query or "") > 0 then
		local segments = query:gfind("([^&]+)")
		for segment in segments do
			local parts = segment:gfind("([^=]+)")
			local arr = {}
			for part in parts do
				table.insert(arr, part)
			end
			if arr[1] == 'qualifier' and #arr > 1 then
				target.qualifier = arr[2]
			end
		end
	end
	return target
end

function AwsLambdaHandler:access(conf)
	AwsLambdaHandler.super.access(self)

	local target = getTarget(conf)
	if not target.is_valid then
		ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
		ngx.print(target.error_message)
		return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
	end

	local reqHeaders = ngx.req.get_headers()

	local creds = getCreds(conf, reqHeaders)
	local bodyJson = getBodyJson(conf, reqHeaders)

	--conf.log_type ???
	--conf.client_context ???
	--conf.invocation_type ???

	local opts = {
	    Region = target.region,
	    Service = "lambda",
	    method = 'POST',
	    headers = {
		["X-Amz-Target"] = "invoke";
		["Content-Type"] = "application/x-amz-json-1.1";
		["Content-Length"] = tostring(string.len(bodyJson))
	    },
	    body = bodyJson,
	    path = '/2015-03-31/functions/'..target.function_name..'/invocations',
	    AccessKey = creds.access_key,
	    SecretKey = creds.secret_key
	}
	if string.len(target.qualifier or "") > 0 then
		opts.query = "Qualifier="..target.qualifier
	end
	if string.len(creds.security_token or "") > 0 then
		opts.headers["X-Amz-Security-Token"] = creds.security_token
	end
	local request, _ = prepare_request(opts)

        -- response, code, headers = http_client.get
	local response, _, headers = http_client.post(
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
