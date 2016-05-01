local BasePlugin = require "kong.plugins.base_plugin"

local https = require 'ssl.https'
local ltn12 = require 'ltn12'
local prepare_request = require "kong.plugins.aws-lambda.aws.v4".prepare_request

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
	local method = 'POST'

	local opts = {
	    Region = conf.aws_region;
	    Service = "lambda";
	    method = method;
	    headers = {
		["X-Amz-Target"] = "invoke";
		["Content-Type"] = "application/x-amz-json-1.1";
		["Content-Length"] = tostring(string.len(content))
	    };
	    body = content;
	    path = '/2015-03-31/functions/'..conf.function_name..'/invocations';
	    AccessKey = conf.aws_access_key;
	    SecretKey = conf.aws_secret_key;
	};

	local request, extra = prepare_request(opts)
	local response = {}
	local one, code, headers, status = https.request{
		url = request.url,
		method = method,
		headers = request.headers,
		source = ltn12.source.string(request.body),
		sink = ltn12.sink.table(response),
		protocol = 'tlsv1'
	}
	--print(r, c, prtable(h), s, prtable(resp))

	ngx.say(response)
	return ngx.exit(ngx.HTTP_OK)
end


return AwsLambdaHandler
