local type   = type
local error  = error
local sub    = string.sub

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


return {
  sanitize_uri_postfix = sanitize_uri_postfix,
  check_select_params = check_select_params,
  debug_http_headers = debug_http_headers,
}
