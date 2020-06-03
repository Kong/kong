# Kong gRPC-Web plugin

A [Kong] plugin to allow access to a gRPC service via the [gRPC-Web](https://github.com/grpc/grpc-web) protocol.  Primarily, this means JS browser apps using the [gRPC-Web library](https://github.com/grpc/grpc-web).

## Description

A service that presents a gRPC API can be used by clients written in many languages, but the network specifications are oriented primarily to connections within a datacenter.  In order to expose the API to the Internet, and to be called from brower-based JS apps, [gRPC-Web] was developed.

This plugin translates requests and responses between gRPC-Web and "real" gRPC.  Supports both HTTP/1.1 and HTTP/2, over plaintext (HTTP) and TLS (HTTPS) connections.

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
    - name: grpc-web
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
  --data paths=/

$ # add the plugin to the route
$ curl -XPOST localhost:8001/routes/web-service/plugins \
  --data name=grpc-web
```

In these examples we don't set any configuration for the plugin.  This minimal setup works for the default varieties of the [gRPC-Web protocol], which use ProtocolBuffer messages either directly in binary or with base64 encoding.  The related `Content-Type` headers are `application/grpc-web` or `application/grpc-web+proto` for binary and `application/grpc-web-text` or `application/grpc-web-text+proto`.

If we wish to use JSON encoding, we have to provide the gRPC specification in a .proto file.  For example:

```protobuf
syntax = "proto2";

package hello;

service HelloService {
  rpc SayHello(HelloRequest) returns (HelloResponse);
  rpc LotsOfReplies(HelloRequest) returns (stream HelloResponse);
  rpc LotsOfGreetings(stream HelloRequest) returns (HelloResponse);
  rpc BidiHello(stream HelloRequest) returns (stream HelloResponse);
}

message HelloRequest {
  optional string greeting = 1;
}

message HelloResponse {
  required string reply = 1;
}
```

The declarative configuration becomes:

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
    - name: grpc-web
      proto: path/to/hello.proto
```

or via the administration API:

```bash
$ # add the plugin to the route
$ curl -XPOST localhost:8001/routes/web-service/plugins \
  --data name=grpc-web \
  --data config.proto=path/to/hello.proto
```

With this setup, we can support gRPC-Web/JSON clients using `Content-Type` headers like `application/grpc-web+json` or `application/grpc-web-text+json`.

Additionaly, non-gRPC-Web clients can do simple POST requests with `Content-Type: application/json`.  In this case, the data payloads are simple JSON objects, without gPRC frames.  This allows clients to perform calls without using the gRPC-Web library, but streaming responses are delivered as a continous stream of JSON objects.  It's up to the client to split into separate objects if it has to support multiple response messages.

## Dependencies

The gRPC-Web plugin depends on [lua-protobuf], [lua-cjson] and [lua-pack]

[Kong]: https://konghq.com
[gRPC-Web]: https://github.com/grpc/grpc-web
[gRPC-Web protocol]: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md#protocol-differences-vs-grpc-over-http2
[lua-protobuf]: https://github.com/starwing/lua-protobuf
[lua-cjson]: https://github.com/openresty/lua-cjson
[lua-pack]: https://github.com/Kong/lua-pack
