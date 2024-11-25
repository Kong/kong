-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local meta = require("kong.meta")
local re_find = ngx.re.find
local unescape_uri = ngx.unescape_uri
local split = require("kong.tools.string").split
local strip = require("kong.tools.string").strip
local sub = string.sub
local kong = kong
local type = type
local regex_flags = "joi"

local plugin = {
  PRIORITY = 1007,
  VERSION = meta.core_version,
}


local INJECTIONS = {
  { name = "sql", regex = "[\\s]*((delete)|(exec)|(drop\\s*table)|(insert)|(shutdown)|(update)|(\\bor\\b))" },
  { name = "js", regex = "<\\s*script\\b[^>]*>[^<]+<\\s*\\/\\s*script\\s*>" },
  { name = "ssi", regex = "<!--#(include|exec|echo|config|printenv)\\s+.*" },
  { name = "xpath_abbreviated", regex = "\\/(@?[\\w_?\\w:\\*]+(\\[[^]]+\\])*?)+" },
  { name = "xpath_extended", regex = "/?(ancestor(-or-self)?|descendant(-or-self)?|following(-sibling))" },
  { name = "java_exception", regex = ".*?Exception in thread.*" },
}

local SEARCH_LOCATIONS = {
  "path_and_query",
  "headers",
  "body",
}


local function log_injection(name, location, details, action)

  local log_payload = {
    name = name,
    location = location,
    details = details,
    action = action,
  }

  kong.log.set_serialize_value("threats.injection", log_payload)
  kong.log.warn("threat detected: '", name, "', action taken: ", action, ", found in ", location, ", ", details)
  

end


local function check_headers(regex)

  local headers = kong.request.get_headers()

  for header_name, header_value in pairs(headers) do
    -- Check header name
    if re_find(header_name, regex, regex_flags) then
      return true, nil, "Header name: " .. header_name
    end

    -- Check header value(s)
    if type(header_value) == "table" then
      for _, value in ipairs(header_value) do
        if re_find(value, regex, regex_flags) then
          return true, nil, "Header value: " .. header_name .. ": " .. value
        end
      end
    else
      if re_find(header_value, regex, regex_flags) then
        return true, nil, "Header value: " .. header_name .. ": " .. header_value
      end
    end
  end

  return false
end


local function check_path_and_query(regex)

  -- split the path into segments,
  -- unescape and check each segment

  for segment in split(kong.request.get_path(), "/"):iter() do
    if strip(segment) ~= "" then
      if re_find(unescape_uri(segment), regex, regex_flags) then
        return true, nil, "Path segment: " .. segment
      end
    end
  end

  local query_params = kong.request.get_query()

  for param_name, param_value in pairs(query_params) do
    -- Check param name
    if re_find(param_name, regex, regex_flags) then
      return true, nil, "query param name: " .. param_name
    end

    -- Check param value(s)
    if type(param_value) == "table" then
      for _, value in ipairs(param_value) do
        if re_find(value, regex, regex_flags) then
          return true, nil, "query param value: " .. param_name .. ": " .. value
        end
      end
    else
      if re_find(param_value, regex, regex_flags) then
        return true, nil, "query param value: " .. param_name .. ": " .. param_value
      end
    end
  end

  return false

end

local function check_body(regex)

  local body, err = kong.request.get_raw_body()

  if not body then
    kong.log.err(err)
    return kong.response.error(500) -- TODO: test for body larger than client_body_buffer_size
  end

  local from, to, err = re_find(body, regex, regex_flags)
  if from then
    return true, nil, "Body: " .. sub(sub(body, from, to), 1, 100)
  end
  return false, err
end

-- TODO: Move to configure()
local function load_injections(conf)

  -- combine custom regexes with predefined ones

  local injections = {}

  if conf.custom_injections then 
    for _, custom_injection in ipairs(conf.custom_injections) do
      table.insert(injections, {
        name = custom_injection.name,
        regex = custom_injection.regex,
      })
    end
  end

  for _, injection in ipairs(INJECTIONS) do
    local name = injection.name
    if conf.injection_types[name] then 
      table.insert(injections, {
        name = name,
        regex = injection.regex,
      })
    end
  end

  return injections

end

local function check_injections(conf, injections) 

  for _, location in ipairs(SEARCH_LOCATIONS) do

    if conf.locations[location] then

      for _, injection in ipairs(injections) do
        local found, err, details
        if location == "headers" then
          found, err, details = check_headers(injection.regex)
        elseif location == "path_and_query" then
          found, err, details = check_path_and_query(injection.regex)
        elseif location == "body" then
          found, err, details = check_body(injection.regex)
        end

        if err then
          kong.log.err("bad regex pattern '", injection.regex ,"', failed to execute: ", err)
          return kong.response.error(500) -- regex failed, this should be impossible
        end
        if found then
          return false, "injection found", injection.name, location, details
        end
      end
    end
  end

  return true, nil

end


function plugin:access(conf)
  local injections = load_injections(conf)
  local ok, _, name, location, details = check_injections(conf, injections) -- TODO: don't return error if it isn't used

  if not ok then
      -- Always log injection
      log_injection(name, location, details, conf.enforcement_mode)
      if conf.enforcement_mode == "block" then
        return kong.response.error(conf.error_status_code, conf.error_message)
      end
  end

  return

end


return plugin