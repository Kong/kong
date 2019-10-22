[![Build Status][badge-travis-image]][badge-travis-url]

# kong-plugin-aws-lambda

Invoke an [AWS Lambda](https://aws.amazon.com/lambda/) function from Kong. It can be used in combination with other request plugins to secure, manage or extend the function.

## Configuration

### Enabling the plugin on a Service

#### With a database

Configure this plugin on a [Service](https://docs.konghq.com/latest/admin-api/#service-object) by making the following request:

```
$ curl -X POST http://kong:8001/services/{service}/plugins \
  --data name=aws-lambda \
  --data "config.aws_region=AWS_REGION" \
  --data "config.function_name=LAMBDA_FUNCTION_NAME"
```

#### Without a database

Configure this plugin on a [Service](https://docs.konghq.com/latest/admin-api/#service-object) by adding this section do your declarative configuration file:

```
plugins:
- name: aws-lambda
  service: {service}
  config:
    aws_region: AWS_REGION
    function_name: LAMBDA_FUNCTION_NAME
```

In both cases, `{service}` is the `id` or `name` of the Service that this plugin configuration will target.


### Enabling the plugin on a Route

#### With a database

Configure this plugin on a [Route](https://docs.konghq.com/latest/admin-api/#Route-object) with:

```
$ curl -X POST http://kong:8001/routes/{route}/plugins \
  --data name=aws-lambda \
  --data "config.aws_region=AWS_REGION" \
  --data "config.function_name=LAMBDA_FUNCTION_NAME"
```

#### Without a database

Configure this plugin on a [Route](https://docs.konghq.com/latest/admin-api/#route-object) by adding this section do your declarative configuration file:

```
plugins:
- name: aws-lambda
  route: {route}
  config:
    aws_region: AWS_REGION
    function_name: LAMBDA_FUNCTION_NAME
```

In both cases, `{route}` is the `id` or `name` of the Route that this plugin configuration will target.

### Enabling the plugin on a Consumer

#### With a database

You can use the `http://localhost:8001/plugins` endpoint to enable this plugin on specific [Consumers](https://docs.konghq.com/latest/admin-api/#Consumer-object):

```
$ curl -X POST http://kong:8001/consumers/{consumer}/plugins \
  --data name=aws-lambda \
  --data "config.aws_region=AWS_REGION" \
  --data "config.function_name=LAMBDA_FUNCTION_NAME"
```

#### Without a database

Configure this plugin on a [Consumer](https://docs.konghq.com/latest/admin-api/#Consumer-object) by adding this section do your declarative configuration file:

```
plugins:
- name: aws-lambda
  route: {route}
  config:
    aws_region: AWS_REGION
    function_name: LAMBDA_FUNCTION_NAME
```

In both cases, `{consumer}` is the `id` or `username` of the Consumer that this plugin configuration will target.

You can combine `consumer_id` and `service_id`

In the same request, to furthermore narrow the scope of the plugin.

### Global plugins

- **Using a database**, all plugins can be configured using the `http://kong:8001/plugins/` endpoint.
- **Without a database**, all plugins can be configured via the `plugins:` entry on the declarative configuration file.

A plugin which is not associated to any Service, Route or Consumer (or API, if you are using an older version of Kong) is considered "global", and will be run on every request. Read the [Plugin Reference](https://docs.konghq.com/latest/admin-api/#add-plugin) and the [Plugin Precedence](https://docs.konghq.com/latest/admin-api/#precedence)sections for more information.

## Parameters

Here's a list of all the parameters which can be used in this plugin's configuration:

| Form Parameter | default | description
|----------------|---------|-------------
| `name`|| The name of the plugin to use, in this case: `aws-lambda`.
| `service_id`|| The id of the Service which this plugin will target.
| `route_id` || The id of the Route which this plugin will target.
| `enabled` | `true` | Whether this plugin will be applied.
| `consumer_id` || The id of the Consumer which this plugin will target.
|`config.aws_key` <br>*semi-optional* || The AWS key credential to be used when invoking the function. This value is required if `aws_secret` is defined.
|`config.aws_secret` <br>*semi-optional* ||The AWS secret credential to be used when invoking the function. This value is required if `aws_key` is defined.
|`config.aws_region` || The AWS region where the Lambda function is located. Regions supported are: `ap-northeast-1`, `ap-northeast-2`, `ap-south-1`, `ap-southeast-1`, `ap-southeast-2`, `ca-central-1`, `cn-north-1`, `cn-northwest-1`, `eu-central-1`, `eu-west-1`, `eu-west-2`, `sa-east-1`, `us-east-1`, `us-east-2`, `us-gov-west-1`, `us-west-1`, `us-west-2`.
|`config.function_name` || The AWS Lambda function name to invoke.
|`config.timeout`| `60000` | Timeout protection in milliseconds when invoking the function.
|`config.keepalive`| `60000` | Max idle timeout in milliseconds when invoking the function.
|`config.qualifier` <br>*optional* || The [`Qualifier`](http://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html#API_Invoke_RequestSyntax) to use when invoking the function.
|`config.invocation_type` <br>*optional*| `RequestResponse` | The [`InvocationType`](http://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html#API_Invoke_RequestSyntax) to use when invoking the function. Available types are `RequestResponse`, `Event`, `DryRun`.
|`config.log_type` <br>*optional* | `Tail`| The [`LogType`](http://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html#API_Invoke_RequestSyntax) to use when invoking the function. By default `None` and `Tail` are supported.
|`config.port` <br>*optional* | `443` | The TCP port that this plugin will use to connect to the server.
|`config.unhandled_status` <br>*optional* | `200`, `202` or `204` | The response status code to use (instead of the default `200`, `202`, or `204`) in the case of an [`Unhandled` Function Error](https://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html#API_Invoke_ResponseSyntax)
|`config.forward_request_body` <br>*optional* | `false` | An optional value that defines whether the request body is to be sent in the `request_body` field of the JSON-encoded request. If the body arguments can be parsed, they will be sent in the separate `request_body_args` field of the request. The body arguments can be parsed for `application/json`, `application/x-www-form-urlencoded`, and `multipart/form-data` content types.
|`config.forward_request_headers` <br>*optional* | `false` | An optional value that defines whether the original HTTP request headers are to be sent as a map in the `request_headers` field of the JSON-encoded request.
|`config.forward_request_method` <br>*optional* | `false` | An optional value that defines whether the original HTTP request method verb is to be sent in the `request_method` field of the JSON-encoded request.
|`config.forward_request_uri` <br>*optional* |`false`|An optional value that defines whether the original HTTP request URI is to be sent in the `request_uri` field of the JSON-encoded request. Request URI arguments (if any) will be sent in the separate `request_uri_args` field of the JSON body.
|`config.is_proxy_integration` <br>*optional* | `false` | An optional value that defines whether the response format to receive from the Lambda to [this format](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-output-format). Note that the parameter `isBase64Encoded` is not implemented.
|`config.awsgateway_compatible` <br>*optional* | `false` | An optional value that defines whether the plugin should wrap requests into the Amazon API gateway.
|`config.proxy_url` <br>*semi-optional* || An optional value that defines whether the plugin should connect through the given proxy server URL. This value is required if `proxy_scheme` is defined.
|`config.proxy_scheme` <br>*semi-optional* || An optional value that defines which HTTP protocol scheme to use in order to connect through the proxy server. The schemes supported are: `http` and `https`. This value is required if `proxy_url` is defined.
|`config.skip_large_bodies` <br>*optional* | `true` | An optional value that defines whether very large bodies (that are buffered to disk) should be sent by Kong. Note that sending very large bodies will have an impact on the system memory.

## Notes

If you do not provide `aws.key` or `aws.secret`, the plugin uses an IAM role inherited from the instance running Kong. 

First, the plugin will try ECS metadata to get the role. If no ECS metadata is available, the plugin will fall back on EC2 metadata.

[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-aws-lambda.svg?branch=master
[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-aws-lambda
