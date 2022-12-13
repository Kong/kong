local grpc = require "kong.tools.grpc"

local proto_fpath = "opentelemetry/proto/collector/trace/v1/trace_service.proto"

local function load_proto()
  local grpc_util = grpc.new()
  local protoc_instance = grpc_util.protoc_instance

  protoc_instance:loadfile(proto_fpath)
end

load_proto()
