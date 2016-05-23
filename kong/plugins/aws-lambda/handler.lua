local cjson = require 'cjson'
local https = require 'ssl.https'
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
	end

	--conf.qualifier ???
	--conf.client_context ???
	--conf.invocation_type ???
	--conf.log_type ???

        local body = cjson.decode(conf.body)
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
	    AccessKey = conf.aws_access_key,
	    SecretKey = conf.aws_secret_key
	})

	local response = {}
        -- one, code, headers, status = https.request
	local _, _, headers, _ = https.request{
		url = request.url,
		method = 'POST',
		headers = request.headers,
		source = ltn12.source.string(request.body),
		sink = ltn12.sink.table(response),
		protocol = 'tlsv1'
	}

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
