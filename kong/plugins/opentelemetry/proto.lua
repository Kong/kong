local grpc = require("kong.tools.grpc").new()

local proto_fpath = "opentelemetry/proto/collector/trace/v1/trace_service.proto"

local function load_proto()
  local protoc = grpc.protoc

  protoc:loadfile(proto_fpath)
end

load_proto()
