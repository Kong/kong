Working:
- Specify aws credentials (IAM access_key and secret_key) in config
- Return appropriate error response on request if api.upstream_url is *not* aws-lambda://
- Allow merging of query parameters from api to lambda payload
- Allow merging of body from api to lambda
- Error handling
- Specify IAM credentials in Authentication header of api to lambda
- IAM Instance Role authentication
- Specify region, function name, and qualifier declaratively in aws-lambda schemed upstream_url of parent api

ToDo:
- Add support for logging
- Allow sepecifying invocation type, and log type declaratively in aws-lambda schemed upstream_url of parent api
- Restrict Basic Authentication to HTTPS-only
- Add support for client context?
- Rewrite as "pure" nginx request to aws-lambda (i.e. without capturing and/or making origin request via resty) -- is this possible?

request_url:
	aws-lambda://<aws_region>/<function_name>?qualifier=qualifier&invocation_type=invocation_type&log_type=log_type&client_context=client_context
	# http://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html

Plugin:
- Should fail on add api with aws-lambda scheme upstream_url if aws-lambda plugin not present and enabled
- Should force/default strip_request_path=true
- Should force/default preserve_host=false
