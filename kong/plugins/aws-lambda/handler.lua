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

	--conf.qualifier ???
	--conf.client_context ???
	--conf.invocation_type ???
	--conf.log_type ???

	local content = conf.body

	local request, _ = prepare_request({
	    Region = conf.aws_region,
	    Service = "lambda",
	    method = 'POST',
	    headers = {
		["X-Amz-Target"] = "invoke";
		["Content-Type"] = "application/x-amz-json-1.1";
		["Content-Length"] = tostring(string.len(content))
	    },
	    body = content,
	    path = '/2015-03-31/functions/'..conf.function_name..'/invocations',
	    AccessKey = conf.aws_access_key,
	    SecretKey = conf.aws_secret_key
	})

	local response = {}
	local _, _, _, _ = https.request{
		url = request.url,
		method = 'POST',
		headers = request.headers,
		source = ltn12.source.string(request.body),
		sink = ltn12.sink.table(response),
		protocol = 'tlsv1'
	}

	ngx.say(response)
	return ngx.exit(ngx.HTTP_OK)
end

return AwsLambdaHandler
