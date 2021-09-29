# Table of Contents

- [0.1.3](#013---20210603)
- [0.1.2](#012---20201105)
- [0.1.1](#011---20200526)
- [0.1.0](#010---20200521)

##  [0.2.0] - 2021-09-28

- Transcode `.google.protobuf.Timestamp` fields to and from datetime strings (#7538)
- Support structured URL arguments (#7564)

##  [0.1.3] - 2021/06/03

- Fix typo from gatewat to gateway (#16)
- Correctly clear URI args in rewrite (#23)
- Map grpc-status to HTTP status code (#25)

##  [0.1.2] - 2020/11/05

- Allows `include` directives in protoc files by adding the
main protoc file's directory as base for non-absolute paths
- Clear up output buffer when getting partial response (#12)

##  [0.1.1] - 2020/05/26

- Set priority to 998 to avoid clash with other plugins.
- Pin lua-protobuf to 0.3

##  [0.1.0] - 2020/05/21

- Initial release of gRPC gateway plugin for Kong.

[0.1.3]: https://github.com/Kong/kong-plugin-grpc-gateway/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/Kong/kong-plugin-grpc-gateway/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/Kong/kong-plugin-grpc-gateway/compare/0.1.0...0.1.1
[0.1.0]
