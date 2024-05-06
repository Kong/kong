-- Copyright (c) Kong Inc. 2020

local cjson = require "cjson.safe".new()
local buffer = require "string.buffer"
local pb = require "pb"
local grpc_tools = require "kong.tools.grpc"
local grpc_frame = grpc_tools.frame
local grpc_unframe = grpc_tools.unframe

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

local valid_method = {
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

local function parse_options_path(path)
  local match_groups = {}
  local match_group_idx = 1
  local path_regex, _, err = re_gsub("^" .. path .. "$", options_path_regex, function(m)
    local var = m[1]
    local paths = m[2]
    -- store lookup table to matched groups to variable name
    match_groups[match_group_idx] = var
    match_group_idx = match_group_idx + 1
    if not paths or paths == "*" then
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

  return path_regex, match_groups
end


-- parse, compile and load .proto file
-- returns a table mapping valid request URLs to input/output types
local _proto_info = {}
local function get_proto_info(fname)
  local info = _proto_info[fname]
  if info then
    return info
  end

  info = {}

  local grpc_tools_instance = grpc_tools.new()
  grpc_tools_instance:each_method(fname, function(parsed, srvc, mthd)
    local options_bindings =  {
      safe_access(mthd, "options", "google.api.http"),
      safe_access(mthd, "options", "google.api.http", "additional_bindings")
    }
    for _, options in ipairs(options_bindings) do
      for http_method, http_path in pairs(options) do
        http_method = http_method:lower()
        if valid_method[http_method] then
          local preg, grp, err = parse_options_path(http_path)
          if err then
            ngx.log(ngx.ERR, "error ", err, "parsing options path ", http_path)
          else
            if not info[http_method] then
              info[http_method] = {}
            end
            table.insert(info[http_method], {
              regex = preg,
              varnames = grp,
              rewrite_path = ("/%s.%s/%s"):format(parsed.package, srvc.name, mthd.name),
              input_type = mthd.input_type,
              output_type = mthd.output_type,
              body_variable = options.body,
            })
          end
        end
      end
    end
  end, true)

  _proto_info[fname] = info
  return info
end

-- return input and output names of the method specified by the url path
-- TODO: memoize
local function rpc_transcode(method, path, protofile)
  if not protofile then
    return nil
  end

  local info = get_proto_info(protofile)
  info = info[method]
  if not info then
    return nil, ("Unknown method %q"):format(method)
  end
  for _, endpoint in ipairs(info) do
    local m, err = re_match(path, endpoint.regex, "jo")
    if err then
      return nil, ("Cannot match path %q"):format(err)
    end
    if m then
      local vars = {}
      for i, name in ipairs(endpoint.varnames) do
        vars[name] = m[i]
      end
      return endpoint, vars
    end
  end
  return nil, ("Unknown path %q"):format(path)
end


function deco.new(method, path, protofile)
  if not protofile then
    return nil, "transcoding requests require a .proto file defining the service"
  end

  local endpoint, vars = rpc_transcode(method, path, protofile)

  if not endpoint then
    return nil, "failed to transcode .proto file " .. vars
  end

  return setmetatable({
    template_payload = vars,
    endpoint = endpoint,
    rewrite_path = endpoint.rewrite_path,
  }, deco)
end

local function get_field_type(typ, field)
  local _, _, field_typ = pb.field(typ, field)
  return field_typ
end

local function encode_fix(v, typ)
  if typ == "bool" then
    -- special case for URI parameters
    return v and v ~= "0" and v ~= "false"
  end

  return v
end

--[[
  // Set value `v` at `path` in table `t`
  // Path contains value address in dot-syntax. For example:
  // `path="a.b.c"` would lead to `t[a][b][c] = v`.
]]
local function add_to_table( t, path, v, typ )
  local tab = t -- set up pointer to table root
  local msg_typ = typ;
  for m in re_gmatch( path , "([^.]+)(\\.)?", "jo" ) do
    local key, dot = m[1], m[2]
    msg_typ = get_field_type(msg_typ, key)

    -- not argument that we concern with
    if not msg_typ then
      return
    end

    if dot then
      tab[key] = tab[key] or {} -- create empty nested table if key does not exist
      tab = tab[key]
    else
      tab[key] = encode_fix(v, msg_typ)
    end
  end

  return t
end

function deco:upstream(body)
  --[[
    // Note that when using `*` in the body mapping, it is not possible to
    // have HTTP parameters, as all fields not bound by the path end in
    // the body. This makes this option more rarely used in practice when
    // defining REST APIs. The common usage of `*` is in custom methods
    // which don't use the URL at all for transferring data.
  ]]
  -- TODO: do we allow http parameter when body is not *?
  local payload = self.template_payload
  local body_variable = self.endpoint.body_variable
  if body_variable then
    if body and #body > 0 then
      local body_decoded, err = decode_json(body)
      if err then
        return nil, "decode json err: " .. err
      end
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
    if not err then
      for k, v in pairs(args) do
        --[[
          // According to [spec](https://github.com/googleapis/googleapis/blob/master/google/api/http.proto#L113)
          // non-repeated message fields are supported.
          //
          // For example: `GET /v1/messages/123456?revision=2&sub.subfield=foo`
          // translates into `payload = { sub = { subfield = "foo" }}`
        ]]--
        add_to_table( payload, k, v, self.endpoint.input_type)
      end
    end
  end

  local pok, msg = pcall(pb.encode, self.endpoint.input_type, payload)
  if not pok or not msg then
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
    msg = encode_json(pb.decode(self.endpoint.output_type, msg))

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
