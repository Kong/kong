# Kong gRPC-gateway plugin

A [Kong] plugin to allow access to a gRPC service via HTTP REST requests and translate requests and
responses in a JSON format. Similar to
[gRPC-gateway](https://github.com/grpc-ecosystem/grpc-gateway).

## Description

This plugin translates requests and responses between gRPC and HTTP REST.

## Usage

This plugin is intended to be used in a Kong route between a gRPC service and an HTTP endpoint.

Sample configuration via declarative (YAML):

```yaml
_format_version: "1.1"
services:
- protocol: grpc
  host: localhost
  port: 9000
  routes:
  - protocols:
    - http
    paths:
    - /
    plugins:
    - name: grpc-gateway
      config:
        proto: path/to/hello.proto
```

Same thing via the administation API:

```bash
$ # add the gRPC service
$ curl -XPOST localhost:8001/services \
  --data name=grpc \
  --data protocol=grpc \
  --data host=localhost \
  --data port=9000

$ # add an http route
$ curl -XPOST localhost:8001/services/grpc/routes \
  --data protocols=http \
  --data name=web-service \
  --data paths[]=/

$ # add the plugin to the route
$ curl -XPOST localhost:8001/routes/web-service/plugins \
  --data name=grpc-gateway
```

The proto file must contain the
[HTTP REST to gRPC mapping rule](https://github.com/googleapis/googleapis/blob/fc37c47e70b83c1cc5cc1616c9a307c4303fe789/google/api/http.proto).

In the example we use the following mapping (note the `option (google.api.http) = {}` section):

```protobuf
syntax = "proto2";

package hello;

service HelloService {
  rpc SayHello(HelloRequest) returns (HelloResponse) {
    option (google.api.http) = {
      get: "/v1/messages/{greeting}"
      additional_bindings {
        get: "/v1/messages/legacy/{greeting=**}"
      }
      post: "/v1/messages/"
      body: "*"
    }
  }
}


// The request message containing the user's name.
message HelloRequest {
  string greeting = 1;
}

// The response message containing the greetings
message HelloReply {
  string message = 1;
}
```

In this example, we can send following requests to Kong that translates to corresponding gRPC requests:

```shell
# grpc-go/examples/features/reflection/server $ go run main.go &

curl -XGET localhost:8000/v1/messages/Kong2.0
{"message":"Hello Kong2.0"}

curl -XGET localhost:8000/v1/messages/legacy/Kong2.0
{"message":"Hello Kong2.0"}

curl -XGET localhost:8000/v1/messages/legacy/Kong2.0/more/paths
{"message":"Hello Kong2.0\/more\/paths"}

curl -XPOST localhost:8000/v1/messages/Kong2.0 -d '{"greeting":"kong2.0"}'
{"message":"Hello kong2.0"}
```

All syntax defined in [Path template syntax](https://github.com/googleapis/googleapis/blob/fc37c47e70b83c1cc5cc1616c9a307c4303fe789/google/api/http.proto#L225)
is supported.

Currently only unary requests are supported, streaming requests are not supported.

## Dependencies

The gRPC-gateway plugin depends on [lua-protobuf], [lua-cjson] and [lua-pack]

[Kong]: https://konghq.com
[lua-protobuf]: https://github.com/starwing/lua-protobuf
[lua-cjson]: https://github.com/openresty/lua-cjson
[lua-pack]: https://github.com/Kong/lua-pack

