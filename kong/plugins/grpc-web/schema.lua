local typedefs = require "kong.db.schema.typedefs"

return {
  name = "grpc-web",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
      type = "record",
      fields = {
        {
          proto = { description = "If present, describes the gRPC types and methods.\nRequired to support payload transcoding. When absent, the\nweb client must use application/grpw-web+proto content.", type = "string",
            required = false,
            default = nil,
          },
        },
        {
          pass_stripped_path = { description = "If set to `true` causes the plugin to pass the stripped request path to the upstream gRPC service (see the `strip_path` Route attribute).", type = "boolean",
            required = false,
          },
        },
        {
          allow_origin_header = { description = "The value of the `Access-Control-Allow-Origin` header in the response to\nthe gRPC-Web client.  The default of `*` is appropriate for requests without\ncredentials.  In other cases, specify the allowed origins of the client code.\nFor more information, see [MDN Web Docs - Access-Control-Allow-Origin](https://developer.mozilla.org/docs/Web/HTTP/Headers/Access-Control-Allow-Origin).", type = "string",
            required = false,
            default = "*",
          },
        },
      },
    }, },
  },
}
