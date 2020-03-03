```yaml
_format_version: "1.1"
services:
- protocol: grpc
  host: localhost
  port: 50051
  routes:
  - protocols:
    - http
    paths:
    - /
    strip_path: true
    plugins:
    - name: grpc-gateway
      config:
        proto: /kong/helloworld.proto
```

(see helloworld.proto)


```shell
grpc-go/examples/features/reflection/server $ go run main.go &

curl localhost:8000/v1/messages/Kong2.0
{"message":"Hello Kong2.0"}

curl localhost:8000/v1/messages/legacy/Kong2.0
{"message":"Hello Kong2.0"}

curl localhost:8000/v1/messages/legacy/Kong2.0/more/paths
{"message":"Hello Kong2.0\/more\/paths"}

curl localhost:8000/v1/messages/Kong2.0 -d '{"name":"kong2.0"}'
{"message":"Hello kong2.0"}
```

