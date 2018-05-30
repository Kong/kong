local ngx = ngx
local sub = string.sub
local fmt = string.format
local gsub = string.gsub
local type = type
local error = error
local lower = string.lower
local tonumber = tonumber
local getmetatable = getmetatable


local function headers(response_headers)
  local mt = getmetatable(response_headers)
  local index = mt.__index
  mt.__index = function(_, name)
    if type(name) == "string" then
      local var = fmt("upstream_http_%s", gsub(lower(name), "-", "_"))
      if not ngx.var[var] then
        return nil
      end
    end

    return index(response_headers, name)
  end

  return response_headers
end


local function new(sdk, major_version)
  local response = {}


  local MIN_HEADERS            = 1
  local MAX_HEADERS_DEFAULT    = 100
  local MAX_HEADERS            = 1000


  function response.get_status()
     return tonumber(sub(ngx.var.upstream_status or "", -3))
  end


  function response.get_headers(max_headers)
    if max_headers == nil then
      return headers(ngx.resp.get_headers(MAX_HEADERS_DEFAULT))
    end

    if type(max_headers) ~= "number" then
      error("max_headers must be a number", 2)

    elseif max_headers < MIN_HEADERS then
      error("max_headers must be >= " .. MIN_HEADERS, 2)

    elseif max_headers > MAX_HEADERS then
      error("max_headers must be <= " .. MAX_HEADERS, 2)
    end

    return headers(ngx.resp.get_headers(max_headers))
  end


  function response.get_header(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local header_value = response.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function response.get_raw_body()
    -- TODO: implement
  end


  function response.get_body()
    -- TODO: implement
  end


  return response
end


return {
  new = new,
}
