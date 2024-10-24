-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local grpc = require "kong.tools.grpc"

local proto_fpath = "opentelemetry/proto/collector/trace/v1/trace_service.proto"
local proto_logs_fpath = "opentelemetry/proto/collector/logs/v1/logs_service.proto"

local function load_proto()
  local grpc_util = grpc.new()
  local protoc_instance = grpc_util.protoc_instance

  protoc_instance:loadfile(proto_fpath)
  protoc_instance:loadfile(proto_logs_fpath)
end

load_proto()
