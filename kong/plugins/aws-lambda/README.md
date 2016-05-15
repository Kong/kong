Working:
- Add plugin to api
- Specify aws credentials (IAM access_key and secret_key) in config
- Specify region, function name, body in config
- Return response value

ToDo:
- Error handling
- Allow sepecifying region, function name, qualifier, invocation type, log type and client context declartively in aws-lambda schemed upstream_url of parent api
- Allow passing body from client through to lambda (without specifying in config)
- Allow merging of body/query parameters from api to lambda
- Allow merging of parameters from api and plugin config to lambda
- Allow specifying IAM (and role?) credentials in Authentication header of api to lambda
- Allow overriding config credentials via Authentication header of api
- Add spport for IAM Instance Role authentication
- Add support for other invocation types?
- Add support for logging?
- Add support for client context?
- Add support for qualifier (requires updating api-gateway-aws lib)
- Rewrite as "pure" nginx request to aws-lambda (i.e. without capturing and/or making origin request via resty) -- is this possible?
- Rewrite without api-gateway dependencies (worthwhile?)

Client Request:
- Should be able to include Authentication: Basic base64(aws_access_key:aws_secret_key) [HTTPS-only]
- Could add auth plugin to translate other Auth header to valid aws auth credential/info
- Should be GET unless there is a payload, which should be POST
- What to do about verbs in general?

request_url:
	aws-lambda://<aws_region>/<function_name>?qualifier=qualifier&invocation_type=invocation_type&log_type=log_type&client_context=client_context
	# http://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html

Plugin:
- Should fail on add api with aws-lambda scheme upstream_url if aws-lambda plugin not present and enabled
- Should force/default strip_request_path=true
- Should force/default preserve_host=false

Notes:
- The aws-lambda schemed upstream_url is not at all a necessity, but makes sense and is a really nice to have. It could even be replaced by the https://lambda.us-west-2.amazonaws.com/2015-03-31/functions/FunctionName/invocations?Qualifier=Qualifier invocation URL, but that seems too tightly bound to implementation details. Also, having a different scheme nicely reflects the, at least for now, shunting of the origin request off to resty rather than nginx's normal origin flow. I'm anxious for feedback on this one.
- The api-gateway (adobe-apiplatform) dependencies are not available via luarocks or I would have added them via the rockspec rather than include them here. It feels a bit odd to have this project depend on that one, so I'm open to suggestions here. At least the licenses are compatible and included here.
- It would be nice to be able to have the plugin pick up the parameters that are required for the config from the aws-lambda upstream_url, but I haven't been able to figure out how to do access this upstream_url let alone the api itself from the plugin as yet. Though this totally seems like something one should be able to do somehow - I'm probably just missing something.
- Please be kind - this is my first lua work. (I am <3'ing it, tho).
