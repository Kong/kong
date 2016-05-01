local BasePlugin = require "kong.plugins.base_plugin"

local AwsLambdaHandler = BasePlugin:extend()

function AwsLambdaHandler:new()
	AwsLambdaHandler.super.new(self, "aws-lambda")
end

function AwsLambdaHandler:access(conf)
	AwsLambdaHandler.super.access(self)

	local LambdaService = require "kong.plugins.aws-lambda.api-gateway.aws.lambda.LambdaService"

	local lambda = LambdaService:new({
		aws_access_key = conf.aws_access_key,
		aws_secret_key = conf.aws_secret_key,
		aws_region = conf.aws_region
	})

	local err, code, headers, status, body = lambda:invoke(
		conf.function_name,
		require('cjson').decode(conf.body),
		conf.client_context,
		conf.invocation_type,
		conf.log_type)

	ngx.say(body)
	return ngx.exit(ngx.HTTP_OK)
end


return AwsLambdaHandler
