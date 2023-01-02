local grpc_tools = require "kong.tools.grpc"

local proto_fpath = "opentelemetry/proto/collector/trace/v1/trace_service.proto"

local function load_proto()
  local grpc = grpc_tools.new()
  local protoc = grpc.protoc

  protoc:loadfile(proto_fpath)
end

load_proto()
