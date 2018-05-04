local ngx = ngx
local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local insert = table.insert


local function new(sdk, major_version)
  local _RESPONSE = {}


  local MIN_HEADERS            = 1
  local MAX_HEADERS_DEFAULT    = 100
  local MAX_HEADERS            = 1000


  function _RESPONSE.get_status()
    return ngx.status
  end


  function _RESPONSE.set_status(code)
    if type(code) ~= "number" then
      error("code must be a number", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    ngx.status = code
  end


  function _RESPONSE.get_headers(max_headers)
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


  function _RESPONSE.get_header(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local header_value = _RESPONSE.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function _RESPONSE.set_header(name, value)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    ngx.header[name] = value
  end


  function _RESPONSE.add_header(name, value)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    local header = _RESPONSE.get_headers()[name]
    if type(header) ~= "table" then
      header = { header }
    end

    insert(header, value ~= "" and value or " ")

    ngx.header[name] = header
  end


  function _RESPONSE.clear_header(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    ngx.header[name] = nil
  end


  function _RESPONSE.set_headers(headers)
    if type(headers) ~= "table" then
      error("headers must be a table", 2)
    end

    -- Check for type errors first
    for name, value in pairs(headers) do
      local name_t = type(name)
      if name_t ~= "string" then
        error(("invalid name %q: got %s, expected string"):format(name, name_t), 2)
      end

      local value_t = type(value)
      if value_t == "table" then
        for _, array_value in ipairs(value) do
          local array_value_t = type(array_value)
          if array_value_t ~= "string" then
            error(("invalid value in array %q: got %s, expected string"):format(name, array_value_t), 2)
          end
        end

      elseif value_t ~= "string" then
        error(("invalid value in %q: got %s, expected string"):format(name, value_t), 2)
      end
    end

    for name, value in pairs(headers) do
      ngx.header[name] = value ~= "" and value or " "
    end
  end


  function _RESPONSE.get_raw_body()
    -- TODO: implement
  end


  function _RESPONSE.get_parsed_body()
    -- TODO: implement
  end


  function _RESPONSE.set_raw_body()
    -- TODO: implement
  end


  function _RESPONSE.set_parsed_body()
    -- TODO: implement
  end


  return _RESPONSE
end


return {
  new = new,
}
