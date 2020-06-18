local log           = require "kong.plugins.openid-connect.log"
local json          = require "cjson.safe"


local type          = type
local ipairs        = ipairs
local tostring      = tostring


local null          = ngx.null
local header        = ngx.header
local set_header    = ngx.req.set_header
local encode_base64 = ngx.encode_base64


local function append_header(name, value)
  if type(value) == "table" then
    for _, val in ipairs(value) do
      append_header(name, val)
    end

  else
    local header_value = header[name]

    if header_value ~= nil then
      if type(header_value) == "table" then
        header_value[#header_value+1] = value

      else

        header_value = { header_value, value }
      end

    else
      header_value = value
    end

    header[name] = header_value
  end
end


local function set_upstream_header(header_key, header_value)
  if not header_key or not header_value or header_value == null then
    return
  end

  if header_key == "authorization:bearer" then
    set_header("Authorization", "Bearer " .. header_value)

  elseif header_key == "authorization:basic" then
    set_header("Authorization", "Basic " .. header_value)

  else
    set_header(header_key, header_value)
  end
end


local function set_downstream_header(header_key, header_value)
  if not header_key or not header_value or header_value == null then
    return
  end

  if header_key == "authorization:bearer" then
    append_header("Authorization", "Bearer " .. header_value)

  elseif header_key == "authorization:basic" then
    append_header("Authorization", "Basic " .. header_value)

  else
    append_header(header_key, header_value)
  end
end


local function get_header_value(header_value)
  if not header_value or header_value == null then
    return
  end

  local val_type = type(header_value)
  if val_type == "table" then
    header_value = json.encode(header_value)
    if header_value then
      header_value = encode_base64(header_value)
    end

  elseif val_type ~= "string" then
    return tostring(header_value)
  end

  return header_value
end


local function set_headers(args, header_key, header_value)
  if not header_key or not header_value or header_value == null then
    return
  end

  local us = "upstream_"   .. header_key
  local ds = "downstream_" .. header_key

  do
    local value

    local usm = args.get_conf_arg(us .. "_header")
    if usm then
      if type(header_value) == "function" then
        value = header_value()

      else
        value = header_value
      end

      if value and value ~= null then
        set_upstream_header(usm, get_header_value(value))
      end
    end

    local dsm = args.get_conf_arg(ds .. "_header")
    if dsm then
      if not usm then
        if type(header_value) == "function" then
          value = header_value()

        else
          value = header_value
        end
      end

      if value and value ~= null then
        set_downstream_header(dsm, get_header_value(value))
      end
    end
  end
end


local function replay_downstream_headers(args, headers, auth_method)
  if headers and auth_method then
    local replay_for = args.get_conf_arg("token_headers_grants")
    if not replay_for then
      return
    end
    log("replaying token endpoint request headers")
    local replay_prefix = args.get_conf_arg("token_headers_prefix")
    for _, v in ipairs(replay_for) do
      if v == auth_method then
        local replay_headers = args.get_conf_arg("token_headers_replay")
        if replay_headers then
          for _, replay_header in ipairs(replay_headers) do
            local extra_header = headers[replay_header]
            if extra_header then
              if replay_prefix then
                append_header(replay_prefix .. replay_header, extra_header)

              else
                append_header(replay_header, extra_header)
              end
            end
          end
        end
        return
      end
    end
  end
end


local function no_cache_headers()
  header["Cache-Control"] = "no-cache, no-store"
  header["Pragma"]        = "no-cache"
end


return {
  set               = set_headers,
  get               = get_header_value,
  replay_downstream = replay_downstream_headers,
  set_upstream      = set_upstream_header,
  set_downstream    = set_downstream_header,
  no_cache          = no_cache_headers,
}
