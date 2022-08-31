local pb = require "pb"
local grpc = require "kong.tools.grpc"

local grpc_new = grpc.new
local pb_encode = pb.encode
local setmetatable = setmetatable
local string_format = string.format

local _M = {}
local _MT = { __index = _M, }

local wrpc_proto_name = "wrpc.wrpc"

local function parse_annotation(annotation)
  local parsed = {}
  for kv_pair in annotation:gmatch("[^;]+=[^;]+") do
    local key, value = kv_pair:match("^%s*(%S-)%s*=%s*(%S+)%s*$")
    if key and value then
      parsed[key] = value
    end
  end

  return parsed
end

---@TODO: better way to do this
-- Parse annotations in proto files with format:
-- +wrpc: key1=val1; key2=val2; ...
-- Use key service-id and rpc-id to get IDs for service and RPC.
local function parse_annotations(proto_obj, proto_file)
  local svc_ids = proto_obj.svc_ids
  local rpc_ids = proto_obj.rpc_ids
  local annotations = proto_obj.annotations

  local service = ""
  for line in proto_file:lines() do
    local annotation = line:match("//%s*%+wrpc:%s*(.-)%s*$")
    if not annotation then
      goto continue
    end

    local nextline = proto_file:read("*l")
    local keyword, identifier = nextline:match("^%s*(%a+)%s+(%w+)")
    if not keyword or not identifier then
      goto continue
    end

    local name, id_tag_name, ids
    if keyword == "service" then
      name = identifier
      id_tag_name = "service-id"
      service = identifier
      ids = svc_ids

    elseif keyword == "rpc" then
      id_tag_name = "rpc-id"
      name = service .. '.' .. identifier
      ids = rpc_ids

    else
      error("unknown type of protobuf identity")
    end

    annotations[name] = parse_annotation(annotation)
    local id = assert(annotations[name][id_tag_name],
      keyword .. " with no id assigned")
    ids[name] = assert(tonumber(id), keyword .. "'s id should be a number")

    ::continue::
  end
end

function _M.new()
  local proto_instance = setmetatable({
    grpc_instance = grpc_new(),
    svc_ids = {},
    rpc_ids = {},
    annotations = {},
    name_to_mthd = {},
  }, _MT)

  proto_instance:import(wrpc_proto_name)
  return proto_instance
end

-- Add searching path for proto files.
---@param proto_path (string or table) path to search proto files in
function _M:addpath(proto_path)
  self.grpc_instance:addpath(proto_path)
end

-- Import wrpc proto.
-- Search from default and user specified paths(addpath)
--
-- Throw when error occurs.
-- pcall if you do not want it throw.
---@param name(string) name for prototype. a.b will be found at a/b.proto
function _M:import(name)
  local fname = name:gsub('%.', '/') .. '.proto'

  local fh = assert(self.grpc_instance:get_proto_file(fname),
    "module " .. name .. " cannot be found or cannot be opened")
  parse_annotations(self, fh)
  fh:close()

  local svc_ids = self.svc_ids
  local rpc_ids = self.rpc_ids
  -- may throw from this call
  self.grpc_instance:each_method(fname,
    function(_, srvc, mthd)
      local svc_id = svc_ids[srvc.name]
      local rpc_id = rpc_ids[srvc.name .. '.' .. mthd.name]

      if not svc_id then
        error("service " .. srvc.name .. " has no id assigned")
      end
      if not rpc_id then
        error("rpc " .. mthd.name .. " has no id assigned")
      end

      mthd.svc_id = svc_id
      mthd.rpc_id = rpc_id

      self.name_to_mthd[srvc.name .. "." .. mthd.name] = mthd
      self.name_to_mthd[svc_id .. "." .. rpc_id] = mthd
    end
  )
end

-- Get rpc object.
-- Both service_name.rpc_name and 1.2(service_id.rpc_id) supported.
function _M:get_rpc(rpc_name)
  return self.name_to_mthd[rpc_name]
end

-- Sets a service handler for the given rpc method.
--- @param rpc_name string Full name of the rpc method
--- @param handler function Function called to handle the rpc method.
--- @param response_handler function|nil Fallback function for responses.
function _M:set_handler(rpc_name, handler, response_handler)
  local rpc = self:get_rpc(rpc_name)
  if not rpc then
    return nil, string_format("unknown method %q", rpc_name)
  end

  rpc.handler = handler
  rpc.response_handler = response_handler

  return rpc
end

-- Part of wrpc_peer:call()
-- If calling the same method with the same args several times,
-- (to the same or different peers), this method returns the
-- invariant part, so it can be cached to reduce encoding overhead
function _M:encode_args(name, arg)
  local rpc = self:get_rpc(name)
  if not rpc then
    return nil, string_format("unknown method %q", name)
  end

  return rpc, assert(pb_encode(rpc.input_type, arg))
end

-- this is just for unit tests
_M.__parse_annotations = parse_annotations

return _M
