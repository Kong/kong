local grpc = require "kong.tools.grpc"
local pl_path = require "pl.path"

local abspath = pl_path.abspath
local splitpath = pl_path.splitpath

local proto_fpath = "kong/include/opentelemetry/proto/collector/trace/v1/trace_service.proto"

local function load_proto()
  local grpc_util = grpc.new()
  local protoc_instance = grpc_util.protoc_instance

  local dir = splitpath(abspath(proto_fpath))
  protoc_instance:addpath(dir)
  protoc_instance:loadfile(proto_fpath)
end

load_proto()
