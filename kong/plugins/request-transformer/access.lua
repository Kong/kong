local multipart = require "multipart"
local cjson = require "cjson.safe"


local ngx = ngx
local kong = kong
local next = next
local type = type
local find = string.find
local upper = string.upper
local lower = string.lower
local pairs = pairs
local insert = table.insert
local noop = function() end


local _M = {}


local CONTENT_TYPE = "Content-Type"
local JSON = "json"
local FORM = "form"
local MULTIPART = "multipart"


local function get_content_type(content_type)
  if content_type == nil then
    return
  end

  content_type = lower(content_type)

  if find(content_type, "application/json", nil, true) then
    return JSON
  end

  if find(content_type, "application/x-www-form-urlencoded", nil, true) then
    return FORM
  end

  if find(content_type, "multipart/form-data", nil, true) then
    return MULTIPART
  end
end


local function iter(config_array)
  if type(config_array) ~= "table" then
    return noop
  end

  return function(config_array, i)
    i = i + 1

    local current_pair = config_array[i]
    if current_pair == nil then -- n + 1
      return nil
    end

    local current_name, current_value = current_pair:match("^([^:]+):*(.-)$")
    if current_value == "" then
      current_value = nil
    end

    return i, current_name, current_value
  end, config_array, 0
end


local function append_value(current_value, value)
  local current_value_type = type(current_value)

  if current_value_type  == "table" then
    insert(current_value, value)
    return current_value
  end

  if current_value_type == "string"  or
     current_value_type == "boolean" or
     current_value_type == "number" then
    return { current_value, value }
  end

  return { value }
end


local function transform_headers(conf)
  local clear_header = kong.service.request.clear_header

  local remove  = 0 < #conf.remove.headers
  local rename  = 0 < #conf.rename.headers
  local replace = 0 < #conf.replace.headers
  local add     = 0 < #conf.add.headers
  local append  = 0 < #conf.append.headers

  if not remove  and
     not rename  and
     not replace and
     not add     and
     not append then
    return
  end

  local removed
  local renamed
  local replaced
  local added
  local appended

  local headers = kong.request.get_headers()
  headers.host = nil

  if remove then
    for _, name, _ in iter(conf.remove.headers) do
      name = lower(name)
      if headers[name] ~= nil then
        headers[name] = nil
        clear_header(name)

        if not removed then
          removed = true
        end
      end
    end
  end

  if rename then
    for _, old_name, new_name in iter(conf.rename.headers) do
      old_name = lower(old_name)
      local value = headers[old_name]
      if value ~= nil then
        headers[new_name] = value
        headers[old_name] = nil

        clear_header(old_name)

        if not renamed then
          renamed = true
        end
      end
    end
  end

  if replace then
    for _, name, value in iter(conf.replace.headers) do
      if headers[name] ~= nil or lower(name) == "host" then
        headers[name] = value

        if not replaced then
          replaced = true
        end
      end
    end
  end

  if add then
    for _, name, value in iter(conf.add.headers) do
      if headers[name] == nil and lower(name) ~= "host" then
        headers[name] = value

        if not added then
          added = true
        end
      end
    end
  end

  if append then
    for _, name, value in iter(conf.append.headers) do
      name = lower(name)
      if name ~= "host" then
        headers[name] = append_value(headers[name], value)

        if not appended then
          appended = true
        end
      end
    end
  end

  if removed or renamed or replaced or added or appended then
    kong.service.request.set_headers(headers)
  end
end


local function transform_query(conf, query)
  local remove  = 0 < #conf.remove.querystring
  local rename  = 0 < #conf.rename.querystring
  local replace = 0 < #conf.replace.querystring
  local add     = 0 < #conf.add.querystring
  local append  = 0 < #conf.append.querystring

  if not remove  and
     not rename  and
     not replace and
     not add     and
     not append then
    return
  end

  local removed
  local renamed
  local replaced
  local added
  local appended


  if not query then
    query = kong.request.get_query()
  end

  if remove then
    for _, name, value in iter(conf.remove.querystring) do
      if query[name] ~= nil then
        query[name] = nil

        if not removed then
          removed = true
        end
      end
    end
  end

  if rename then
    for _, old_name, new_name in iter(conf.rename.querystring) do
      local value = query[old_name]
      if value ~= nil then
        query[new_name] = value
        query[old_name] = nil

        if not renamed then
          renamed = true
        end
      end
    end
  end

  if replace then
    for _, name, value in iter(conf.replace.querystring) do
      if query[name] ~= nil then
        query[name] = value

        if not replaced then
          replaced = true
        end
      end
    end
  end

  if add then
    for _, name, value in iter(conf.add.querystring) do
      if query[name] == nil then
        query[name] = value

        if not added then
          added = true
        end
      end
    end
  end

  if append then
    for _, name, value in iter(conf.append.querystring) do
      query[name] = append_value(query[name], value)

      if not appended then
        appended = true
      end
    end
  end

  if removed or renamed or replaced or added or appended then
    kong.service.request.set_query(query)
  end
end


local function transform_json_body(conf, body_raw, actions)
  local removed
  local renamed
  local replaced
  local added
  local appended

  local json

  if actions.has_content then
    cjson.decode_array_with_array_mt(true)
    json = cjson.decode(body_raw)
    cjson.decode_array_with_array_mt(false)

    if type(json) ~= "table" then
      return
    end

    if actions.remove then
      for _, name in iter(conf.remove.body) do
        if json[name] ~= nil then
          json[name] = nil

          if not removed then
            removed = true
          end
        end
      end
    end

    if actions.rename then
      for _, old_name, new_name in iter(conf.rename.body) do
        local value = json[old_name]
        if value ~= nil then
          json[new_name] = value
          json[old_name] = nil

          if not renamed then
            renamed = true
          end
        end
      end
    end

    if actions.replace then
      for _, name, value in iter(conf.replace.body) do
        if json[name] ~= nil then
          json[name] = value

          if not replaced then
            replaced = true
          end
        end
      end
    end
  end

  if actions.add then
    if json == nil then
      json = {}
    end

    for _, name, value in iter(conf.add.body) do
      if json[name] == nil then
        json[name] = value

        if not added then
          added = true
        end
      end
    end
  end

  if actions.append then
    if json == nil then
      json = {}
    end

    for _, name, value in iter(conf.append.body) do
      json[name] = append_value(json[name], value)

      if not appended then
        appended = true
      end
    end
  end

  if removed or renamed or replaced or added or appended then
    return true, cjson.encode(json)
  end
end


local function transform_form_body(conf, body_raw, actions)
  local removed
  local renamed
  local replaced
  local added
  local appended

  local form

  if actions.has_content then
    form = ngx.decode_args(body_raw)

    if type(form) ~= "table" then
      return
    end

    if actions.remove then
      for _, name in iter(conf.remove.body) do
        if form[name] ~= nil then
          form[name] = nil

          if not removed then
            removed = true
          end
        end
      end
    end

    if actions.rename then
      for _, old_name, new_name in iter(conf.rename.body) do
        local value = form[old_name]
        if value ~= nil then
          form[new_name] = value
          form[old_name] = nil

          if not renamed then
            renamed = true
          end
        end
      end
    end

    if actions.replace then
      for _, name, value in iter(conf.replace.body) do
        if form[name] ~= nil then
          form[name] = value

          if not replaced then
            replaced = true
          end
        end
      end
    end
  end

  if actions.add then
    if form == nil then
      form = {}
    end

    for _, name, value in iter(conf.add.body) do
      if form[name] == nil then
        form[name] = value

        if not added then
          added = true
        end
      end
    end
  end

  if actions.append then
    if form == nil then
      form = {}
    end

    for _, name, value in iter(conf.append.body) do
      form[name] = append_value(form[name], value)

      if not appended then
        appended = true
      end
    end
  end

  if removed or renamed or replaced or added or appended then
    return true, ngx.encode_args(form)
  end
end


local function transform_multipart_body(conf, body_raw, actions, content_type_value)
  if not content_type_value then
    return
  end

  local removed
  local renamed
  local replaced
  local added

  local parts

  if actions.has_content then
    parts =  multipart(body_raw, content_type_value)

    if type(parts) ~= "table" then
      return
    end

    if actions.remove then
      for _, name in iter(conf.remove.body) do
        if parts:get(name) then
          parts:delete(name)

          if not removed then
            removed = true
          end
        end
      end
    end

    if actions.rename then
      for _, old_name, new_name in iter(conf.rename.body) do
        if parts:get(old_name) then
          local value = parts:get(old_name).value

          parts:set_simple(new_name, value)
          parts:delete(old_name)

          if not renamed then
            renamed = true
          end
        end
      end
    end

    if actions.replace then
      for _, name, value in iter(conf.replace.body) do
        if parts:get(name) then
          parts:delete(name)
          parts:set_simple(name, value)

          if not replaced then
            replaced = true
          end
        end
      end
    end
  end

  if actions.add then
    if parts == nil then
      parts = multipart("", content_type_value)
    end

    for _, name, value in iter(conf.add.body) do
      if not parts:get(name) then
        parts:set_simple(name, value)

        if not added then
          added = true
        end
      end
    end
  end

  if removed or renamed or replaced or added then
    return true, parts:tostring()
  end
end


local function transform_body(conf, body_raw)
  local content_type_value = kong.request.get_header(CONTENT_TYPE)
  local content_type = get_content_type(content_type_value)
  if content_type == nil then
    return
  end

  local actions = {
    remove  = 0 < #conf.remove.body,
    rename  = 0 < #conf.rename.body,
    replace = 0 < #conf.replace.body,
    add     = 0 < #conf.add.body,
    append  = 0 < #conf.append.body,
  }

  if not actions.rename  and
     not actions.remove  and
     not actions.replace and
     not actions.add     and
     not actions.append then
    return
  end

  if not body_raw then
    body_raw = kong.request.get_raw_body()
  end

  if body_raw then
    actions.has_content = #body_raw ~= 0
  end

  local transformed
  if content_type == JSON then
    transformed, body_raw = transform_json_body(conf, body_raw, actions)
  elseif content_type == FORM then
    transformed, body_raw = transform_form_body(conf, body_raw, actions)
  elseif content_type == MULTIPART then
    transformed, body_raw = transform_multipart_body(conf, body_raw, actions,
                                                     content_type_value)
  end

  if transformed then
    kong.service.request.set_raw_body(body_raw)
  end
end


local function transform_method(conf)
  if not conf.http_method then
    return
  end

  local method = upper(conf.http_method)
  if method ~= kong.request.get_method() then
    kong.service.request.set_method(method)
  end

  if method ~= "GET" and method ~= "HEAD" and method ~= "TRACE" then
    return
  end

  local query
  local body_raw

  local content_type_value = kong.request.get_header(CONTENT_TYPE)
  local content_type = get_content_type(content_type_value)
  if content_type == FORM then
    -- Also put the body args into query args
    body_raw = kong.request.get_raw_body()
    if body_raw then
      local form = ngx.decode_args(body_raw)
      if type(form) == "table" and next(form) then
        query = kong.request.get_query()
        for name, value in pairs(form) do
          if query[name] then
            if type(query[name]) == "table" then
              insert(query[name], value)
            else
              query[name] = { query[name], value }
            end

          else
            query[name] = value
          end
        end

        kong.service.request.set_query(query)
      end
    end
  end

  return query, body_raw
end


function _M.execute(conf)
  transform_headers(conf)

  local query, body_raw = transform_method(conf)

  transform_query(conf, query)
  transform_body(conf, body_raw)
end


return _M
