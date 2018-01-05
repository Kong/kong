local cjson         = require "cjson.safe"
local upload        = require "resty.upload"
local utils         = require "kong.tools.utils"


local setmetatable  = setmetatable
local getmetatable  = getmetatable
local tonumber      = tonumber
local tostring      = tostring
local rawget        = rawget
local concat        = table.concat
local insert        = table.insert
local ipairs        = ipairs
local pairs         = pairs
local lower         = string.lower
local find          = string.find
local fmt           = string.format
local sub           = string.sub
local type          = type
local ngx           = ngx
local req           = ngx.req
local log           = ngx.log
local re_match      = ngx.re.match
local re_gmatch     = ngx.re.gmatch
local req_read_body = req.read_body
local get_uri_args  = req.get_uri_args
local get_body_data = req.get_body_data
local get_post_args = req.get_post_args
local json_decode   = cjson.decode
local json_encode   = cjson.encode


local NOTICE        = ngx.NOTICE


local multipart_mt = {}
local arguments_mt = {}


function multipart_mt:__tostring()
  return self.data
end


function multipart_mt:__index(name)
  local json = rawget(self, "json")
  if json then
    return json[name]
  end

  return nil
end


function arguments_mt:__index(name)
  return rawget(self, "post")[name] or
         rawget(self,  "uri")[name]
end


local defaults = {
  timeout       = 1000,
  chunk_size    = 4096,
  max_uri_args  = 100,
  max_post_args = 100,
  max_line_size = nil,
  max_part_size = nil,
}


local function escape_unescaped_double_quotes(value)
  if type(value) ~= "string" then
    return nil
  end

  local s = find(value, '"', 1, true)

  if not s then
    return value
  end

  local r = {}
  local i = 0
  local p = 1

  while s do
    local escape = false
    if s == 1 then
      escape = true

    else
      local backslashes = 0

      for n = s - 1, p, -1 do
        if sub(value, n, n) ~= [[\]] then
          break
        end

        backslashes = backslashes + 1
      end

      if backslashes % 2 == 0 then
        escape = true
      end
    end

    if escape then
      r[i + 1] = sub(value, p, s - 1)
      r[i + 2] = [[\"]]
      i = i + 2
      p = s + 1
    end

    s = find(value, '"', s + 1, true)
  end

  r[i + 1] = sub(value, p)

  return concat(r)
end


local function basename(path, separator)
  if not path then
    return nil
  end

  local sep = separator or "/"

  local location = 1

  local boundary = find(path, sep, 1, true)
  while boundary do
    location = boundary + 1
    boundary = find(path, sep, location, true)
  end

  if location > 1 then
    path = sub(path, location)
  end

  if not separator then
    return basename(path, "\\")
  end

  return path
end


local function content_type_boundary(content_type)
  if not content_type then
    return nil
  end

  local boundary, e = find(content_type, "boundary=", 21, true)
  if boundary then
    local s = find(content_type, ";", e + 1, true)

    if s then
      boundary = sub(content_type, e + 1, s - 1)

    else
      boundary = sub(content_type, e + 1)
    end
  end

  if boundary ~= "" then
    return boundary
  end

  return nil
end


local function combine_arg(to, arg)
  if type(arg) ~= "table" or getmetatable(arg) == multipart_mt then
    insert(to, #to + 1, arg)

  else
    for k, v in pairs(arg) do
      local t = to[k]

      if not t then
        to[k] = v

      else
        if type(t) == "table" and getmetatable(t) ~= multipart_mt then
          combine_arg(t, v)

        else
          to[k] = { t }
          combine_arg(to[k], v)
        end
      end
    end
  end
end


local function combine(args)
  local to = {}

  if type(args) ~= "table" then
    return to
  end

  for _, arg in ipairs(args) do
    combine_arg(to, arg)
  end

  return to
end


local function decode_value(value)
  if type(value) == "string" then
    if value == "" then
      return ngx.null
    end

    if value == "true" then
      return true
    end

    if value == "false" then
      return false
    end

    local n = tonumber(value)
    if n then
      return n
    end

  elseif type(value) == "table" then
    for i, v in ipairs(value) do
      value[i] = decode_value(v)
    end
  end

  return value
end


local function decode_array_arg(name, value, container)
  container = container or {}

  if type(name) ~= "string" then
    container[name] = value
    return container[name]
  end

  local indexes = {}
  local count   = 0
  local search  = name

  while true do
    local captures, err = re_match(search, [[(.+)\[(\d*)\]$]], "ajos")
    if captures then
      search = captures[1]
      count = count + 1
      indexes[count] = tonumber(captures[2])

    elseif err then
      log(NOTICE, err)
      break

    else
      break
    end
  end

  if count == 0 then
    container[name] = value
    return container[name]
  end

  container[search] = {}
  container = container[search]

  for i = count, 1, -1 do
    local index = indexes[i]

    if i == 1 then
      if index then
        insert(container, index, value)
        return container[index]
      end

      if type(value) == "table" and getmetatable(value) ~= multipart_mt then
        for j, v in ipairs(value) do
          insert(container, j, v)
        end

      else
        container[#container + 1] = value
      end

      return container

    else
      if not container[index or 1] then
        container[index or 1] = {}
        container = container[index or 1]
      end
    end
  end
end


local function decode_arg(name, value)
  if type(name) ~= "string" or re_match(name, [[^\.+|\.$]], "jos") then
    return { name = value }
  end

  local iterator, err = re_gmatch(name, [[[^.]+]], "jos")
  if not iterator then
    if err then
      log(NOTICE, err)
    end

    return decode_array_arg(name, value)
  end

  local names = {}
  local count = 0

  while true do
    local captures, err = iterator()
    if captures then
      count = count + 1
      names[count] = captures[0]

    elseif err then
      log(NOTICE, err)
      break

    else
      break
    end
  end

  if count == 0 then
    return decode_array_arg(name, value)
  end

  local container = {}
  local bucket = container

  for i = 1, count do
    if i == count then
      decode_array_arg(names[i], value, bucket)
      return container

    else
      bucket = decode_array_arg(names[i], {}, bucket)
    end
  end
end


local function decode(args)
  local i = 0
  local r = {}

  if type(args) ~= "table" then
    return r
  end

  for name, value in pairs(args) do
    i = i + 1
    r[i] = decode_arg(name, decode_value(value))
  end

  return combine(r)
end


local function encode_value(value)
  if value == ngx.null then
    return ""
  end

  if getmetatable(value) == multipart_mt then
    return value
  end

  return tostring(value)
end


local function encode_args(args, results, prefix)
  if type(args) ~= "table" then
    return results
  end

  for k, v in pairs(args) do
    local name

    if prefix then
      if type(k) == "number" then
        name = fmt("%s[%d]", prefix, k)

      else
        if sub(prefix, -1) == "." then
          name = prefix .. k

        else
          name = fmt("%s.%s", prefix, k)
        end
      end

    else
      if type(k) == "number" then
        name = fmt("[%d]", prefix, k)

      else
        name = k
      end
    end

    if type(v) == "table" and getmetatable(v) ~= multipart_mt then
      encode_args(v, results, name)

    else
      results[name] = encode_value(v)
    end
  end

  return results
end


local function encode(args, content_type)
  if not content_type then
    content_type = ngx.var.content_type

    if not content_type then
      return nil, "missing encoding content type"
    end

    if type(content_type) == "table" then
      content_type = content_type[1]
    end
  end

  if sub(content_type, 1, 33) == "application/x-www-form-urlencoded" then
    return ngx.encode_args(encode_args(args, {}))

  elseif sub(content_type, 1, 19) == "multipart/form-data" then
    local boundary = content_type_boundary(content_type) or utils.random_string()

    local encoded_args = encode_args(args, {})
    local i = 0
    local r = {}

    for k, v in pairs(encoded_args) do
      r[i + 1] = "\r\n--"
      r[i + 2] = boundary
      r[i + 3] = "\r\n"
      r[i + 4] = 'Content-Disposition: form-data; name="'
      r[i + 5] = escape_unescaped_double_quotes(k)
      r[i + 6] = '"'

      i = i + 6

      if getmetatable(v) == multipart_mt then

        if v.filename then
          r[i + 1] = '" filename="'
          r[i + 2] = escape_unescaped_double_quotes(v.filename)
          r[i + 3] = '"\r\n'

          i = i + 3
        end

        if v.type then
          r[i + 1] = "Content-Type: "
          r[i + 2] = v.type

          i = i + 2
        end

        r[i + 1] = "\r\n\r\n"
        r[i + 2] = v.data

        i = i + 2

      else
        r[i + 1] = "\r\n\r\n"
        r[i + 2] = v

        i = i + 2
      end
    end

    if i > 0 then
      r[i + 1] = "\r\n--"
      r[i + 2] = boundary
      r[i + 3] = "--"

      i = i + 3

      return concat(r, nil, 1, i)
    end

    return ""

  elseif sub(content_type, 1, 16) == "application/json" then
    return json_encode(args)
  end

  return nil, "unsupported encoding content type '" .. content_type .. "'"
end


local function parse_multipart_header(header, results)
  local name, value

  local boundary = find(header, "=", 1, true)
  if boundary then
    name = sub(header, 2, boundary - 1)
    value = sub(header, boundary + 2, -2)

    if sub(name, -1) == "*" and lower(sub(value, 1, 7)) == "utf-8''" then
      name = sub(name, 1, -2)
      value = sub(value, 8)

      results[name] = value

    else
      if not results[name] then
        results[name] = value
      end
    end

  else
    results[#results + 1] = header
  end
end


local function parse_multipart_headers(headers)
  if not headers then
    return nil
  end

  local results  = {}
  local location = 1

  local boundary = find(headers, ";", 1, true)
  while boundary do
    local header = sub(headers, location, boundary - 1)
    parse_multipart_header(header, results)
    location = boundary + 1
    boundary = find(headers, ";", location, true)
  end

  local header = sub(headers, location)
  if header ~= "" then
    parse_multipart_header(header, results)
  end

  return results
end


local function parse_multipart(options, content_type)
  local boundary

  if content_type then
    boundary = content_type_boundary(content_type)
  end

  local part_args = {}

  local max_part_size = options.max_part_size or defaults.max_part_size
  local max_post_args = options.max_post_args or defaults.max_post_args
  local chunk_size    = options.chunk_size    or defaults.chunk_size

  local multipart, err = upload:new(chunk_size, options.max_line_size or defaults.max_line_size)
  if not multipart then
    return nil, err
  end

  multipart:set_timeout(options.timeout or defaults.timeout)

  local parts_count = 0

  local headers, headers_count, part

  while true do
    local chunk_type, chunk

    chunk_type, chunk, err = multipart:read()
    if not chunk_type then
      return nil, err
    end

    if chunk_type == "header" then
      if not headers then
        headers = {}
        headers_count = 0
      end

      if type(chunk) == "table" then
        headers_count = headers_count + 1
        headers[headers_count] = chunk[3]

        local key, value = chunk[1], parse_multipart_headers(chunk[2])
        if value then
          headers[key] = value
        end
      end

    elseif chunk_type == "body" then
      if headers then
        local content_disposition = headers["Content-Disposition"] or {}
        local content_type        = headers["Content-Type"]

        if type(content_type) == "table" then
          content_type = content_type[1]
        end

        part = setmetatable({
          boundary = boundary,
          headers  = headers,
          name     = content_disposition.name,
          type     = content_type,
          file     = basename(content_disposition.filename),
          size     = 0,
          data     = {
            n      = 0,
          }
        }, multipart_mt)

        headers = nil
      end

      if part then
        part.size = #chunk + part.size

        if max_part_size then
          if max_part_size < part.size then
            return nil, "maximum size of multipart parameter exceeded"
          end
        end

        if max_post_args and max_post_args < parts_count + 1 then
          return nil, "maximum number of multipart parameters exceeded"
        end

        local n      = part.data.n + 1
        part.data[n] = chunk
        part.data.n  = n
      end

    elseif chunk_type == "part_end" then
      if part then
        if max_post_args then
          parts_count = parts_count + 1
        end

        if part.data.n > 0 then
          part.data = concat(part.data, nil, 1, part.data.n)

        else
          part.data = nil
        end

        if part.type and sub(part.type, 1, 16) == "application/json" then
          local json
          json, err = json_decode(part.data)
          if json then
            part.json = json

          else
            log(NOTICE, err)
          end
        end

        local part_name = part.name
        if part_name then
          local enclosure = part_args[part_name]
          if enclosure then
            if type(enclosure) == "table" and getmetatable(enclosure) ~= multipart_mt then
              enclosure[#enclosure + 1] = part

            else
              enclosure = { enclosure, part }
            end

            part_args[part_name] = enclosure

          else
            part_args[part_name] = part
          end

        else
          part_args[#part_args + 1] = part
        end

        part = nil
      end

    elseif chunk_type == "eof" then
      break
    end
  end

  return part_args
end


local function load(options)
  options = options or defaults

  local args  = setmetatable({
    uri  = {},
    post = {},
  }, arguments_mt)

  args.uri = decode(get_uri_args(options.max_uri_args or defaults.max_uri_args))

  local content_length = ngx.var.content_length
  if content_length then
    if type(content_length) == "table" then
      content_length = content_length[1]
    end

    if content_length == "0" then
      return args
    end

    content_length = tonumber(content_length)

    if content_length and content_length < 1 then
      return args
    end
  end

  local content_type = ngx.var.content_type
  if not content_type then
    return args
  end

  if type(content_type) == "table" then
    content_type = content_type[1]
  end

  if sub(content_type, 1, 33) == "application/x-www-form-urlencoded" then
    req_read_body()
    local pargs, err = get_post_args(options.max_post_args or defaults.max_post_args)
    if pargs then
      args.post = decode(pargs)

    elseif err then
      log(NOTICE, err)
    end

  elseif sub(content_type, 1, 19) == "multipart/form-data" then
    local pargs, err = parse_multipart(options, content_type)
    if pargs then
      args.post = decode(pargs)

    elseif err then
      log(NOTICE, err)
    end

  elseif sub(content_type, 1, 16) == "application/json" then
    req_read_body()

    -- we don't support file i/o in case the body is
    -- buffered to a file, and that is how we want it.
    local body_data = get_body_data()

    if body_data then
      local pargs, err = json_decode(body_data)
      if pargs then
        args.post = pargs

      elseif err then
        log(NOTICE, err)
      end
    end
  end

  return args
end


return {
  load         = load,
  decode       = decode,
  decode_arg   = decode_arg,
  decode_value = decode_value,
  encode       = encode,
  encode_args  = encode,
  encode_value = encode_value,
  combine      = combine,
  multipart_mt = multipart_mt,
}
