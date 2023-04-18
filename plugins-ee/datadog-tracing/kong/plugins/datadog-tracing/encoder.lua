-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--[[
  The internal data structure is used by Datadog's v0.4 trace api endpoint.
  It is encoded in msgpack using the customized encoder.
]]

local msgpack = require "MessagePack"
local new_tab = require "table.new"
local nkeys = require "table.nkeys"
local ffi = require "ffi"
local rand_bytes = require "kong.tools.utils".get_rand_bytes
local char = require "string".char

local bit = bit
local band = bit.band
local rshift = bit.rshift
local tonumber = tonumber
local sub = string.sub

ffi.cdef [[
typedef struct {
    char data[8];
} uint64_be_bytes;
]]

local uint64_be_bytes_t = ffi.typeof("uint64_be_bytes")

local int64_t = ffi.typeof("int64_t")

local function truncate_to_uint64_be_bytes(x)
  if #x > 8 then
    x = sub(x, -8)
  elseif #x < 8 then
    x = ("\0"):rep(8 - #x) .. x
  end

  return uint64_be_bytes_t(x)
end

local function generate_span_id()
  return uint64_be_bytes_t(rand_bytes(8))
end

-- from https://github.com/DataDog/kong-plugin-ddtrace
msgpack.packers["cdata"] = function(buffer, cdata)
  if ffi.istype(uint64_be_bytes_t, cdata) then
    buffer[#buffer+1] = char(0xCF)           -- uint64
                        .. ffi.string(cdata, 8)

  elseif ffi.istype(int64_t, cdata) then
    buffer[#buffer+1] = char(0xd3,             -- int64
    tonumber(band(rshift(cdata, 56), 0xFFULL)),
    tonumber(band(rshift(cdata, 48), 0xFFULL)),
    tonumber(band(rshift(cdata, 40), 0xFFULL)),
    tonumber(band(rshift(cdata, 32), 0xFFULL)),
    tonumber(band(rshift(cdata, 24), 0xFFULL)),
    tonumber(band(rshift(cdata, 16), 0xFFULL)),
    tonumber(band(rshift(cdata, 8), 0xFFULL)),
    tonumber(band(rshift(cdata, 0), 0xFFULL)))

  else
     error "can only encode cdata with type uint64_t or int64_t"
  end
end


local function transform_attributes(attr)
  if type(attr) ~= "table" then
    error("invalid attributes", 2)
  end

  local dd_meta = new_tab(nkeys(attr), 0)
  for k, v in pairs(attr) do
    dd_meta[k] = tostring(v)
  end

  return dd_meta
end


local default_metrics = {
  [0] = {["_sampling_priority_v1"] = 0 },
  [1] = {["_sampling_priority_v1"] = 1 },
}

local uint64_be_bytes_zero = uint64_be_bytes_t("")

local function get_resource_name(span)
  local attributes = span.attributes
  if span.name == "kong.database.query" then
    return attributes["db.statement"]
  elseif span.name == "kong.balancer" then
    return "balancer try #" .. attributes["try_count"]
  elseif span.name == "kong.internal.request" or span.name == "kong" then
    return attributes["http.method"] .. " " .. attributes["http.url"]
  elseif span.name == "kong.dns" then
    return "dns " .. attributes["dns.record.domain"]
  else
    return span.name
  end
end

local function transform_span(span, service_name, origin)
  assert(type(span) == "table")

  local sampling_priority = span.should_sample and 1 or 0

  -- TODO: cache table
  local dd_span = {
    type = "web",
    service = service_name or "kong",
    name = span.name,
    resource = get_resource_name(span),
    trace_id = truncate_to_uint64_be_bytes(span.trace_id),
    span_id = truncate_to_uint64_be_bytes(span.span_id),
    parent_id = span.parent_id and truncate_to_uint64_be_bytes(span.parent_id) or uint64_be_bytes_zero,
    -- span.start_time_ns and span.end_time_ns are stored as lua number (from kong/tools/utils)
    -- if there's loss of precision, it's already there; not trying to solve it from here and keep as is
    start = int64_t(span.start_time_ns),
    duration = int64_t(span.end_time_ns - span.start_time_ns),
    sampling_priority = sampling_priority,
    origin = origin,
    meta = span.attributes and transform_attributes(span.attributes),
    metrics = default_metrics[sampling_priority],
  }

  return dd_span
end

return {
  generate_span_id = generate_span_id,
  transform_span = transform_span,
  encode_spans = msgpack.pack,
  -- test only
  _truncate_to_uint64_be_bytes = truncate_to_uint64_be_bytes,
}
