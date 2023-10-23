-- Copyright (c) Kong Inc. 2020

local cjson = require "cjson"
local buffer = require "string.buffer"
local grpc_tools = require "kong.tools.grpc"
local grpc_frame = grpc_tools.frame
local grpc_unframe = grpc_tools.unframe

local protojson = require "kong.tools.protojson"

local pcall = pcall
local setmetatable = setmetatable

local ngx = ngx
local re_gsub = ngx.re.gsub
local re_match = ngx.re.match
local re_gmatch = ngx.re.gmatch

local encode_json = cjson.encode
local decode_json = cjson.decode
local pcall = pcall

local deco = {}
deco.__index = deco

local get_call_info_cache = {}

--- Sort endpoints by specificity (longer regex tend to be more specific).
-- Endpoints are sorted on per-method basis
-- The similar rule applies for [Kong ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/#multiple-matches).
-- @param endpoints Endpoints to sort
local function sort_endpoints(endpoints)
  for _, method_endpoints in pairs(endpoints) do
    table.sort(method_endpoints, function (a, b)
      return #(a.regex) > #(b.regex)
    end)
  end
end

local function safe_access(t, ...)
  for _, k in ipairs({...}) do
    if t[k] then
      t = t[k]
    else
      return
    end
  end
  return t
end

local is_valid_method = {
  get = true,
  post = true,
  put = true,
  patch = true,
  delete = true,
}

--[[
  // ### Path template syntax
  //
  //     Template = "/" Segments [ Verb ] ;
  //     Segments = Segment { "/" Segment } ;
  //     Segment  = "*" | "**" | LITERAL | Variable ;
  //     Variable = "{" FieldPath [ "=" Segments ] "}" ;
  //     FieldPath = IDENT { "." IDENT } ;
  //     Verb     = ":" LITERAL ;
]]
-- assume LITERAL = [-_.~0-9a-zA-Z], needs more
local options_path_regex = [=[{([-_.~0-9a-zA-Z]+)=?((?:(?:\*|\*\*|[-_.~0-9a-zA-Z])/?)+)?}]=]

--- Parse path in http.options
-- @param request path
-- @return Regular expression to extract variables from request path
-- @return Variables found in request path
-- @return Error string
local function parse_options_path(path)
  local path_vars = {}
  local path_vars_idx = 1

  local path_regex, _, err = re_gsub("^" .. path .. "$", options_path_regex, function(m)
    local var = m[1]
    local paths = m[2]
    -- store lookup table to matched groups to variable name
    path_vars[path_vars_idx] = var
    path_vars_idx = path_vars_idx + 1

    if (not paths) or (paths == "*") then
      return "([^/]+)"
    else
      return ("(%s)"):format(
        paths:gsub("%*%*", ".+"):gsub("%*", "[^/]+")
      )
    end
  end, "jo")

  if err then
    return nil, nil, err
  end

  return path_regex, path_vars
end

--- Get information about call
-- @param cfg Call configuration
-- @return information about call
local function get_call_info(cfg)
  local filename = cfg.proto

  if get_call_info_cache[filename] then
    return get_call_info_cache[filename]
  end

  local info = {
    endpoints = {},
    json_names = {}
  }

  local load_bindings_info = function(file, service, method)
    local bindings =  {
      safe_access(method, "options", "google.api.http"),
      safe_access(method, "options", "google.api.http", "additional_bindings")
    }

    for _, binding in ipairs(bindings) do
      for http_method, http_path in pairs(binding) do

        http_method = http_method:lower()

        if is_valid_method[http_method] then
          local regex, varnames, err = parse_options_path(http_path)

          if err then
            ngx.log(ngx.ERR, "error: ", err, " parsing options path: ", http_path)
          else
            if not info.endpoints[http_method] then
              info.endpoints[http_method] = {}
            end

            table.insert(info.endpoints[http_method], {
              regex = regex,
              varnames = varnames,
              rewrite_path = ("/%s.%s/%s"):format(file.package, service.name, method.name),
              input_type = method.input_type,
              output_type = method.output_type,
              body_variable = binding.body,
            })
          end
        end
      end
    end
  end

  local load_json_names_info = function(_, msg, field)
    if (field.json_name ~= nil) then
      local full_name = msg.full_name .. "." .. field.name

      info.json_names[full_name] = field.json_name
    end
  end

  local grpc = grpc_tools.new()

  grpc:traverse_proto_file(filename, load_bindings_info, load_json_names_info)

  if (cfg.additional_protos ~= nil) then
    for _, fn in ipairs(cfg.additional_protos) do
      -- We are only interested in types here (necessary for handling `google.protobuf.Any` type)
      grpc:traverse_proto_file(fn, nil, load_json_names_info)
    end
  end

  --[[
    Sort by regex length to avoid situations where shorter regex matches also longer string
    e.g. ^/v1/kong/([^/]+)$ matches both "/v1/kong/{uuid}" and "/v1/kong/{uuid}:customMethod" 
    The former would have uuid = "f05c29ef-b6f7-4b3d-85a0-b84b85794fb1:customMethod"
  ]]
  sort_endpoints(info.endpoints)

  get_call_info_cache[filename] = info

  return info
end

--- Return input and output names of the method specified by the url path
-- @param method
-- @param path
-- @param cfg
-- @return
-- TODO: memoize - still valid?
local function rpc_transcode(method, path, cfg)
  local info = get_call_info(cfg)

  local endpoints = info.endpoints[method] or nil

  if not endpoints then
    return nil, ("unknown method %q"):format(method)
  end

  for _, endpoint in ipairs(endpoints) do
    local m, err = re_match(path, endpoint.regex, "jo")

    if err then
      return nil, ("cannot match path %q"):format(err)
    end

    if m then
      local vars = {}
      for i, name in ipairs(endpoint.varnames) do
        -- check handling of dotted variables (e.g. entity.uuid)
        vars[name] = m[i]
      end
      return endpoint, vars
    end
  end

  return nil, ("unknown path %q"):format(path)
end

--- Constructor
-- @param method
-- @param path
-- @param cfg
function deco.new(method, path, cfg)
  if not cfg.proto then
    return nil, "transcoding requests require a .proto file defining the service"
  end

  local endpoint, vars = rpc_transcode(method, path, cfg)

  if not endpoint then
    return nil, "failed to transcode .proto file " .. vars
  end

  local info = get_call_info(cfg)

  protojson:configure({
    use_proto_names = cfg.use_proto_names,
    enum_as_name = cfg.enum_as_name,
    emit_defaults = cfg.emit_defaults,
    json_names = info.json_names,
  })

  return setmetatable({
    template_payload = vars,
    endpoint = endpoint,
    rewrite_path = endpoint.rewrite_path,
  }, deco)
end

local upstream_payload_metatable = {
  --[[
    // Set value at dot-separated path. For example: `GET /v1/messages/123456?revision=2&sub.subfield=foo`
    // translates into `payload = { sub = { subfield = "foo" }}`
    //
    // This is to comply with [spec](https://github.com/googleapis/googleapis/blob/master/google/api/http.proto#L113),
    // where also fields of messages can be passed in query string.
    //
  ]]--
 __newindex = function (t, k, v)
    for m in re_gmatch(k, "([^.]+)(\\.)?") do
      local key, dot = m[1], m[2]

      if dot then
        rawset(t, key, t[key] or {}) -- create empty nested table if key does not exist
        t = t[key]
      else
        rawset(t, key, v)
      end
    end

    return t
  end
}

function deco:upstream(body)
  --[[
    // Note that when using `*` in the body mapping, it is not possible to
    // have HTTP parameters, as all fields not bound by the path end in
    // the body. This makes this option more rarely used in practice when
    // defining REST APIs. The common usage of `*` is in custom methods
    // which don't use the URL at all for transferring data.
  ]]
  -- TODO: do we allow http parameter when body is not *?
  --local payload = self.template_payload
  local payload = setmetatable(self.template_payload, upstream_payload_metatable)

  local body_variable = self.endpoint.body_variable
  if body_variable then
    if body and #body > 0 then
      local body_decoded = decode_json(body)
      if body_variable ~= "*" then
        --[[
          // For HTTP methods that allow a request body, the `body` field
          // specifies the mapping. Consider a REST update method on the
          // message resource collection:
        ]]
        payload[body_variable] = body_decoded
      elseif type(body_decoded) == "table" then
        --[[
          // The special name `*` can be used in the body mapping to define that
          // every field not bound by the path template should be mapped to the
          // request body.  This enables the following alternative definition of
          // the update method:
        ]]
        for k, v in pairs(body_decoded) do
          payload[k] = v
        end
      else
        return nil, "body must be a table"
      end
    end
  else
    --[[
      // Any fields in the request message which are not bound by the path template
      // automatically become HTTP query parameters if there is no HTTP request body.
    ]]--
    -- TODO primitive type checking
    local args, err = ngx.req.get_uri_args()

    if err then
      return nil, "invalid URI arguments"
    end

    for k, v in pairs(args) do
      payload[k] = v
    end
  end

  local status, msg = pcall(protojson.encode_from_json, protojson, self.endpoint.input_type, payload)
  if not status or not msg then
    if msg then
      ngx.log(ngx.ERR, msg)
    end
    -- should return error msg to client?
    return nil, "failed to encode payload"
  end

  body = grpc_frame(0x0, msg)
  return body
end


function deco:downstream(chunk)
  local body = (self.downstream_body or "") .. chunk

  local out = buffer.new()
  local msg, body = grpc_unframe(body)

  while msg do
    msg = encode_json(protojson:decode_to_json(self.endpoint.output_type, msg))

    out:put(msg)
    msg, body = grpc_unframe(body)
  end

  self.downstream_body = body
  chunk = out:get()

  return chunk
end

function deco:get_raw_downstream_body()
  return self.downstream_body
end


return deco
