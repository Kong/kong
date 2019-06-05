local cjson         = require "cjson.safe"
local upload        = require "resty.upload"


local setmetatable  = setmetatable
local getmetatable  = getmetatable
local tonumber      = tonumber
local rawget        = rawget
local concat        = table.concat
local insert        = table.insert
local ipairs        = ipairs
local pairs         = pairs
local lower         = string.lower
local find          = string.find
local sub           = string.sub
local next          = next
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
  decode        = true,
  multipart     = true,
  timeout       = 1000,
  chunk_size    = 4096,
  max_uri_args  = 100,
  max_post_args = 100,
  max_line_size = nil,
  max_part_size = nil,
}


defaults.__index = defaults


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


local function find_content_type_boundary(content_type)
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

    if (sub(boundary, 1, 1) == '"' and sub(boundary, -1)  == '"') or
       (sub(boundary, 1, 1) == "'" and sub(boundary, -1)  == "'") then
      boundary = sub(boundary, 2, -2)
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


local infer


local function infer_value(value, field)
  if not value or type(field) ~= "table" then
    return value
  end

  if value == "" then
    return ngx.null
  end

  if field.type == "number" or field.type == "integer" then
    return tonumber(value) or value

  elseif field.type == "boolean" then
    if value == "true" then
      return true

    elseif value == "false" then
      return false
    end

  elseif field.type == "array" or field.type == "set" then
    if type(value) ~= "table" then
      value = { value }
    end

    for i, item in ipairs(value) do
      value[i] = infer_value(item, field.elements)
    end

  elseif field.type == "foreign" then
    if type(value) == "table" then
      return infer(value, field.schema)
    end

  elseif field.type == "map" then
    if type(value) == "table" then
      for k, v in pairs(value) do
        value[k] = infer_value(v, field.values)
      end
    end

  elseif field.type == "record" and not field.abstract then
    if type(value) == "table" then
      for k, v in pairs(value) do
        for i in ipairs(field.fields) do
          local item = field.fields[i]
          if item then
            local key = next(item)
            local fld = item[key]
            if k == key then
              value[k] = infer_value(v, fld)
            end
          end
        end
      end
    end
  end

  return value
end


infer = function(args, schema)
  if not args then
    return
  end

  if not schema then
    return args
  end

  for field_name, field in schema:each_field(args) do
    local value = args[field_name]
    if value then
      args[field_name] = infer_value(value, field)
    end
  end

  if schema.ttl == true and args.ttl then
    args.ttl = tonumber(args.ttl) or args.ttl
  end

  return args
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


local function decode(args, schema)
  local i = 0
  local r = {}

  if type(args) ~= "table" then
    return r
  end

  for name, value in pairs(args) do
    i = i + 1
    r[i] = decode_arg(name, value)
  end

  return infer(combine(r), schema)
end


local function parse_multipart_header(header, results)
  local name
  local value

  local boundary = find(header, "=", 1, true)
  if boundary then
    name  = sub(header, 2, boundary - 1)
    value = sub(header, boundary + 2, -2)

    if (sub(value, 1, 1) == '"' and sub(value, -1)  == '"') or
       (sub(value, 1, 1) == "'" and sub(value, -1)  == "'") then
      value = sub(value, 2, -2)
    end

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


local function parse_multipart_stream(options, boundary)
  local part_args = {}

  local max_part_size = options.max_part_size
  local max_post_args = options.max_post_args
  local chunk_size    = options.chunk_size

  local multipart, err = upload:new(chunk_size, options.max_line_size)
  if not multipart then
    return nil, err
  end

  multipart:set_timeout(options.timeout)

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

  multipart:read()

  return part_args
end


local function parse_multipart(options, content_type)
  local boundary

  if content_type then
    boundary = find_content_type_boundary(content_type)
  end

  return parse_multipart_stream(options, boundary)
end


local function load(opts)
  local options = setmetatable(opts or {}, defaults)

  local args  = setmetatable({
    uri  = {},
    post = {},
  }, arguments_mt)

  local uargs = get_uri_args(options.max_uri_args)

  if options.decode then
    args.uri = decode(uargs, options.schema)

  else
    args.uri = uargs
  end

  local content_type = ngx.var.content_type
  if not content_type then
    return args
  end

  local content_type_lower = lower(content_type)

  if find(content_type_lower, "application/x-www-form-urlencoded", 1, true) == 1 then
    req_read_body()
    local pargs, err = get_post_args(options.max_post_args)
    if pargs then
      if options.decode then
        args.post = decode(pargs, options.schema)

      else
        args.post = pargs
      end

    elseif err then
      log(NOTICE, err)
    end

  elseif find(content_type_lower, "application/json", 1, true) == 1 then
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

  elseif options.multipart and find(content_type_lower, "multipart/form-data", 1, true) == 1 then
    if options.request and options.request.params_post then
      local pargs = {}
      for k, v in pairs(options.request.params_post) do
        if type(v) == "table" and v.name and v.content then
          pargs[k] = v.content
        else
          pargs[k] = v
        end
      end

      args.post = decode(pargs, options.schema)

    else
      local pargs, err = parse_multipart(options, content_type)
      if pargs then
        if options.decode then
          args.post = decode(pargs, options.schema)

        else
          args.post = pargs
        end

      elseif err then
        log(NOTICE, err)
      end
    end

  else
    req_read_body()

    -- we don't support file i/o in case the body is
    -- buffered to a file, and that is how we want it.
    local body_data = get_body_data()

    if body_data then
      args.body = body_data
    end
  end

  return args
end


return {
  load         = load,
  decode       = decode,
  decode_arg   = decode_arg,
  infer        = infer,
  infer_value  = infer_value,
  combine      = combine,
  multipart_mt = multipart_mt,
}
