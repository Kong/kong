-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


local http_subschema = {
  name = "http",

  fields = {
    { sources = typedefs.no_sources { err = "cannot set 'sources' when 'protocols' is 'http' or 'https'" } },
    { destinations = typedefs.no_destinations { err = "cannot set 'destinations' when 'protocols' is 'http' or 'https'" } },
  },
  entity_checks = {
    { conditional_at_least_one_of = { if_field = "protocols",
                                      if_match = { contains = "https" },
                                      then_at_least_one_of = { "methods", "hosts", "headers", "paths", "snis" },
                                      then_err = "must set one of %s when 'protocols' is 'https'",
                                      else_match = { contains = "http" },
                                      else_then_at_least_one_of = { "methods", "hosts", "headers", "paths" },
                                      else_then_err = "must set one of %s when 'protocols' is 'http'",
                                    }},
  },
}

local stream_subschema = {
  name = "tcp",

  fields = {
    { methods = typedefs.no_methods { err = "cannot set 'methods' when 'protocols' is 'tcp', 'tls', 'tls_passthrough' or 'udp'" } },
    { hosts = typedefs.no_hosts { err = "cannot set 'hosts' when 'protocols' is 'tcp', 'tls', 'tls_passthrough' or 'udp'" } },
    { paths = typedefs.no_paths { err = "cannot set 'paths' when 'protocols' is 'tcp', 'tls', 'tls_passthrough' or 'udp'" } },
    { headers = typedefs.no_headers { err = "cannot set 'headers' when 'protocols' is 'tcp', 'tls', 'tls_passthrough' or 'udp'" } },
  },
  entity_checks = {
    { conditional_at_least_one_of = { if_field = "protocols",
                                      if_match = { elements = { type = "string", one_of = { "tcp", "tls", "udp", } } },
                                      then_at_least_one_of = { "sources", "destinations", "snis" },
                                      then_err = "must set one of %s when 'protocols' is 'tcp', 'tls' or 'udp'",
                                    }},
    {conditional_at_least_one_of = { if_field = "protocols",
                                      if_match = { elements = { type = "string", one_of = { "tls_passthrough" } } },
                                      then_at_least_one_of = { "snis" },
                                      then_err = "must set snis when 'protocols' is 'tls_passthrough'",
                                    }},
  },
}

local grpc_subschema = {
  name = "grpc",

  fields = {
    { strip_path = { description = "When matching a Route via one of the paths, strip the matching prefix from the upstream request URL.", type = "boolean", required = true, default = false, ne = true, err = "cannot set 'strip_path' when 'protocols' is 'grpc' or 'grpcs'" }, },
    { methods = typedefs.no_methods { err = "cannot set 'methods' when 'protocols' is 'grpc' or 'grpcs'" } },
    { sources = typedefs.no_sources { err = "cannot set 'sources' when 'protocols' is 'grpc' or 'grpcs'" } },
    { destinations = typedefs.no_sources { err = "cannot set 'destinations' when 'protocols' is 'grpc' or 'grpcs'" } },
  },

  entity_checks = {
    { conditional_at_least_one_of = { if_field = "protocols",
                                      if_match = { contains = "grpcs" },
                                      then_at_least_one_of = { "hosts", "headers", "paths", "snis" },
                                      then_err = "must set one of %s when 'protocols' is 'grpcs'",
                                      else_match = { contains = "grpc" },
                                      else_then_at_least_one_of = { "hosts", "headers", "paths" },
                                      else_then_err = "must set one of %s when 'protocols' is 'grpc'",
                                    }},
  },
}

local websocket_subschema = {
  name = "ws",

  fields = {
    { sources = typedefs.no_sources { err = "cannot set 'sources' when 'protocols' is 'ws' or 'wss'" } },
    { destinations = typedefs.no_destinations { err = "cannot set 'destinations' when 'protocols' is 'ws' or 'wss'" } },
    { methods = typedefs.no_methods { err = "cannot set 'methods' when 'protocols' is 'ws' or 'wss'" } },
  },
  entity_checks = {
    { conditional_at_least_one_of = { if_field = "protocols",
                                      if_match = { contains = "wss" },
                                      then_at_least_one_of = { "hosts", "headers", "paths", "snis" },
                                      then_err = "must set one of %s when 'protocols' is 'wss'",
                                      else_match = { contains = "ws" },
                                      else_then_at_least_one_of = { "hosts", "headers", "paths" },
                                      else_then_err = "must set one of %s when 'protocols' is 'ws'",
                                    }},
  },
}



-- NOTICE: make sure we have correct schema constraion for flavor 'expressions'
if kong and kong.configuration and  kong.configuration.router_flavor == "expressions" then

  -- now http route in flavor 'expressions' accepts `sources` and `destinations`

  assert(http_subschema.fields[1].sources)
  http_subschema.fields[1] = nil  -- sources

  assert(http_subschema.fields[2].destinations)
  http_subschema.fields[2] = nil  -- destinations

  -- the route should have the field 'expression' if no others

  table.insert(http_subschema.entity_checks[1].conditional_at_least_one_of.then_at_least_one_of, "expression")
  table.insert(http_subschema.entity_checks[1].conditional_at_least_one_of.else_then_at_least_one_of, "expression")

  -- now grpc route in flavor 'expressions' accepts `sources` and `destinations`

  assert(grpc_subschema.fields[3].sources)
  grpc_subschema.fields[3] = nil  -- sources

  assert(grpc_subschema.fields[4].destinations)
  grpc_subschema.fields[4] = nil  -- destinations

  -- the route should have the field 'expression' if no others

  table.insert(grpc_subschema.entity_checks[1].conditional_at_least_one_of.then_at_least_one_of, "expression")
  table.insert(grpc_subschema.entity_checks[1].conditional_at_least_one_of.else_then_at_least_one_of, "expression")

  table.insert(stream_subschema.entity_checks[1].conditional_at_least_one_of.then_at_least_one_of, "expression")
  table.insert(stream_subschema.entity_checks[2].conditional_at_least_one_of.then_at_least_one_of, "expression")

  -- EE websockets [[
  -- now ws/wss route in flavor 'expressions' accepts `sources` and `destinations`

  assert(websocket_subschema.fields[1].sources)
  websocket_subschema.fields[1] = nil  -- sources

  assert(websocket_subschema.fields[2].destinations)
  websocket_subschema.fields[2] = nil  -- destinations

  table.insert(websocket_subschema.entity_checks[1].conditional_at_least_one_of.then_at_least_one_of, "expression")
  table.insert(websocket_subschema.entity_checks[1].conditional_at_least_one_of.else_then_at_least_one_of, "expression")
  -- EE websockets ]]
end

return {
  http = http_subschema,  -- protocols is the subschema key, and the first
  https = http_subschema, -- matching protocol name is selected as subschema name
  tcp = stream_subschema,
  tls = stream_subschema,
  udp = stream_subschema,
  tls_passthrough = stream_subschema,
  grpc = grpc_subschema,
  grpcs = grpc_subschema,

  -- EE websockets [[
  ws = websocket_subschema,
  wss = websocket_subschema,
  -- EE websockets ]]
}
