local ngx = ngx
local type = type
local error = error


local function new(sdk, major_version)
  local _UPSTREAM_RESPONSE = {}


  local MIN_HEADERS            = 1
  local MAX_HEADERS_DEFAULT    = 100
  local MAX_HEADERS            = 1000


  function _UPSTREAM_RESPONSE.get_status()
    return ngx.status
  end


  function _UPSTREAM_RESPONSE.get_headers(max_headers)
    if max_headers == nil then
      return ngx.resp.get_headers(MAX_HEADERS_DEFAULT)
    end

    if type(max_headers) ~= "number" then
      error("max_headers must be a number", 2)

    elseif max_headers < MIN_HEADERS then
      error("max_headers must be >= " .. MIN_HEADERS, 2)

    elseif max_headers > MAX_HEADERS then
      error("max_headers must be <= " .. MAX_HEADERS, 2)
    end

    return ngx.resp.get_headers(max_headers)
  end


  function _UPSTREAM_RESPONSE.get_header(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local header_value = _UPSTREAM_RESPONSE.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function _UPSTREAM_RESPONSE.get_raw_body()
    -- TODO: implement
  end


  function _UPSTREAM_RESPONSE.get_parsed_body()
    -- TODO: implement
  end


  return _UPSTREAM_RESPONSE
end


return {
  new = new,
}
