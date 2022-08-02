local type   = type
local error  = error
local sub    = string.sub
local byte   = string.byte


local SLASH  = byte("/")


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 5 MiBs

LRU size must be: (5 * 2^20) / 1024 = 5120
Floored: 5000 items should be a good default
--]]
local MATCH_LRUCACHE_SIZE = 5e3


local function sanitize_uri_postfix(uri_postfix)
  if not uri_postfix or uri_postfix == "" then
    return uri_postfix
  end

  if uri_postfix == "." or uri_postfix == ".." then
    return ""
  end

  if sub(uri_postfix, 1, 2) == "./" then
    return sub(uri_postfix, 3)
  end

  if sub(uri_postfix, 1, 3) == "../" then
    return sub(uri_postfix, 4)
  end

  return uri_postfix
end


local function check_select_params(req_method, req_uri, req_host, req_scheme,
                                   src_ip, src_port,
                                   dst_ip, dst_port,
                                   sni, req_headers)
  if req_method and type(req_method) ~= "string" then
    error("method must be a string", 2)
  end
  if req_uri and type(req_uri) ~= "string" then
    error("uri must be a string", 2)
  end
  if req_host and type(req_host) ~= "string" then
    error("host must be a string", 2)
  end
  if req_scheme and type(req_scheme) ~= "string" then
    error("scheme must be a string", 2)
  end
  if src_ip and type(src_ip) ~= "string" then
    error("src_ip must be a string", 2)
  end
  if src_port and type(src_port) ~= "number" then
    error("src_port must be a number", 2)
  end
  if dst_ip and type(dst_ip) ~= "string" then
    error("dst_ip must be a string", 2)
  end
  if dst_port and type(dst_port) ~= "number" then
    error("dst_port must be a number", 2)
  end
  if sni and type(sni) ~= "string" then
    error("sni must be a string", 2)
  end
  if req_headers and type(req_headers) ~= "table" then
    error("headers must be a table", 2)
  end
end


local function debug_http_headers(var, header, match_t)
  if not var.http_kong_debug then
    return
  end

  local route = match_t.route
  if route then
    if route.id then
      header["Kong-Route-Id"] = route.id
    end

    if route.name then
      header["Kong-Route-Name"] = route.name
    end
  end

  local service = match_t.service
  if service then
    if service.id then
      header["Kong-Service-Id"] = service.id
    end

    if service.name then
      header["Kong-Service-Name"] = service.name
    end
  end
end


local function get_upstream_uri(matched_route, request_postfix, req_uri,
                                upstream_base)
  local upstream_uri

  local strip_path = matched_route.strip_path or matched_route.strip_uri

  if byte(upstream_base, -1) == SLASH then
    -- ends with / and strip_path = true
    if strip_path then
      if request_postfix == "" then
        if upstream_base == "/" then
          upstream_uri = "/"

        elseif byte(req_uri, -1) == SLASH then
          upstream_uri = upstream_base

        else
          upstream_uri = sub(upstream_base, 1, -2)
        end

      elseif byte(request_postfix, 1, 1) == SLASH then
        -- double "/", so drop the first
        upstream_uri = sub(upstream_base, 1, -2) .. request_postfix

      else -- ends with / and strip_path = true, no double slash
        upstream_uri = upstream_base .. request_postfix
      end

    else -- ends with / and strip_path = false
      -- we retain the incoming path, just prefix it with the upstream
      -- path, but skip the initial slash
      upstream_uri = upstream_base .. sub(req_uri, 2)
    end

  else -- does not end with /
    -- does not end with / and strip_path = true
    if strip_path then
      if request_postfix == "" then
        if #req_uri > 1 and byte(req_uri, -1) == SLASH then
          upstream_uri = upstream_base .. "/"

        else
          upstream_uri = upstream_base
        end

      elseif byte(request_postfix, 1, 1) == SLASH then
        upstream_uri = upstream_base .. request_postfix

      else
        upstream_uri = upstream_base .. "/" .. request_postfix
      end

    else -- does not end with / and strip_path = false
      if req_uri == "/" then
        upstream_uri = upstream_base

      else
        upstream_uri = upstream_base .. req_uri
      end
    end
  end

  return upstream_uri
end


return {
  MATCH_LRUCACHE_SIZE  = MATCH_LRUCACHE_SIZE,

  sanitize_uri_postfix = sanitize_uri_postfix,
  check_select_params  = check_select_params,
  debug_http_headers   = debug_http_headers,
  get_upstream_uri     = get_upstream_uri,
}
