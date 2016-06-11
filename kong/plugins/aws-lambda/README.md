Working:
- Add plugin to api
- Specify aws credentials (IAM access_key and secret_key) in config
- Specify region, function name, body in config
- Return response value
- Return appropriate error response on request if api.upstream_url is *not* aws-lambda://
- Allow merging of query parameters from api to lambda payload
- Allow merging of body from api to lambda
- Error handling
- Allow specifying IAM credentials in Authentication header of api to lambda
- Allow sepecifying region and function name declaratively in aws-lambda schemed upstream_url of parent api
- Add support for IAM Instance Role authentication

ToDo:
- Add support for client context?
- Add support for logging?
- Add support for qualifier
- Add support for other invocation types?
- Restrict Basic Authentication to HTTPS-only
- Allow sepecifying qualifier, invocation type, log type and client context declaratively in aws-lambda schemed upstream_url of parent api
- Rewrite as "pure" nginx request to aws-lambda (i.e. without capturing and/or making origin request via resty) -- is this possible?

request_url:
	aws-lambda://<aws_region>/<function_name>?qualifier=qualifier&invocation_type=invocation_type&log_type=log_type&client_context=client_context
	# http://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html

Plugin:
- Should fail on add api with aws-lambda scheme upstream_url if aws-lambda plugin not present and enabled
- Should force/default strip_request_path=true
- Should force/default preserve_host=false
