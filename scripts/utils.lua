local ltn12 = require "ltn12"
local http = require "socket.http"
local url = require "socket.url"

local _M = {}

--
-- Disk I/O utils
--
function _M.read_file(path)
  local contents = nil
  local file = io.open(path, "rb")
  if file then
    contents = file:read("*all")
    file:close()
  end
  return contents
end

function _M.write_to_file(path, value)
  local file = io.open(path, "w")
  file:write(value)
  file:close()
end

--
-- Lua script utils
--

-- getopt, POSIX style command line argument parser
-- param arg contains the command line arguments in a standard table.
-- param options is a string with the letters that expect string values.
-- returns a table where associated keys are true, nil, or a string value.
-- The following example styles are supported
--   -a one  ==> opts["a"]=="one"
--   -bone   ==> opts["b"]=="one"
--   -c      ==> opts["c"]==true
--   --c=one ==> opts["c"]=="one"
--   -cdaone ==> opts["c"]==true opts["d"]==true opts["a"]=="one"
-- note POSIX demands the parser ends at the first non option
--      this behavior isn't implemented.
function _M.getopt( arg, options )
  local tab = {}
  for k, v in ipairs(arg) do
    if string.sub( v, 1, 2) == "--" then
      local x = string.find( v, "=", 1, true )
      if x then tab[ string.sub( v, 3, x-1 ) ] = string.sub( v, x+1 )
      else tab[ string.sub( v, 3 ) ] = true end
    elseif string.sub( v, 1, 1 ) == "-" then
      local y = 2
      local l = string.len(v)
      local jopt
      while ( y <= l ) do
        jopt = string.sub( v, y, y )
        if string.find( options, jopt, 1, true ) then
          if y < l then
            tab[ jopt ] = string.sub( v, y+1 )
            y = l
          else
            tab[ jopt ] = arg[ k + 1 ]
          end
        else
          tab[ jopt ] = true
        end
        y = y + 1
      end
    end
  end
  return tab
end

--
-- HTTP calls utils
--

-- Builds a querystring from a table, separated by `&`
-- @param tab The key/value parameters
-- @param key The parent key if the value is multi-dimensional (optional)
-- @return a string representing the built querystring
local function build_query(tab, key)
  if ngx then
    return ngx.encode_args(tab)
  else
    local query = {}
    local keys = {}

    for k in pairs(tab) do
      keys[#keys+1] = k
    end

    table.sort(keys)

    for _,name in ipairs(keys) do
      local value = tab[name]
      if key then
        name = string.format("%s[%s]", tostring(key), tostring(name))
      end
      if type(value) == "table" then
        query[#query+1] = build_query(value, name)
      else
        local value = tostring(value)
        if value ~= "" then
          query[#query+1] = string.format("%s=%s", name, value)
        else
          query[#query+1] = name
        end
      end
    end

    return table.concat(query, "&")
  end
end

local function http_call(options)
  -- Set Host header accordingly
  if not options.headers["host"] then
    local parsed_url = url.parse(options.url)
    local port_segment = ""
    if parsed_url.port then
      port_segment = ":" .. parsed_url.port
    end
    options.headers["host"] = parsed_url.host .. port_segment
  end

  -- Returns: response, code, headers
  local resp = {}
  options.sink = ltn12.sink.table(resp)

  local r, code, headers = http.request(options)
  return resp[1], code, headers
end

function _M.get(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  return http_call {
    method = "GET",
    url = url,
    headers = headers
  }
end

function _M.delete(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  return http_call {
    method = "DELETE",
    url = url,
    headers = headers
  }
end

function _M.post(url, form, headers)
  if not headers then headers = {} end
  if not form then form = {} end

  local body = build_query(form)
  headers["content-length"] = string.len(body)
  headers["content-type"] = "application/x-www-form-urlencoded"

  return http_call {
    method = "POST",
    url = url,
    headers = headers,
    source = ltn12.source.string(body)
  }
end

return _M
