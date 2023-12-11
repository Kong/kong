-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lrucache = require "resty.lrucache"
local threat_parser = require "lxp.threat"
local ngx_re_match = ngx.re.match
local kong_yield = require("kong.tools.yield").yield

local kb = 1024
local mb = kb * kb

local xml_threat = {
  PRIORITY = 999,
  VERSION = require("kong.meta").core_version,
}



local content_type_allowed do

  local media_type_pattern = [[(.+)\/([^ ;]+)]]

  local lru_cache_cache = setmetatable({}, {
    __mode = "k",
    __index = function(self, plugin_config)
      -- create if not found
      local lru = assert(lrucache.new(500))
      self[plugin_config] = lru
      return lru
    end
  })

  -- checks a received content-type against a list of masks "*/*" format.
  -- @param content_type the value received to check
  -- @param list an array of masks to validate against
  -- returns boolean
  local function match_type(content_type, mask_list)
    local matches = ngx_re_match(content_type:lower(), media_type_pattern, "ajo")
    if not matches then -- parse failed
      return false
    end
    local mtype = matches[1]
    local msubtype = matches[2]

    for i, mask in ipairs(mask_list) do
      matches = ngx_re_match(mask:lower(), media_type_pattern, "ajo")
      if matches and
        (matches[1] == "*" or matches[1] == mtype) and
        (matches[2] == "*" or matches[2] == msubtype) then
          return true
      end
    end
    return false
  end

  -- returns what to do with a request content-type.
  -- @param plugin_config the plugin config table
  -- @param content_type the content_type
  -- @returns "check", "allow", or false
  function content_type_allowed(plugin_config, content_type)
    if not content_type then
      return false
    end

    local lru = lru_cache_cache[plugin_config]

    -- test our cache
    local result = lru:get(content_type)
    if result ~= nil then
      return result
    end

    result = match_type(content_type, plugin_config.checked_content_types) and "check" or
             match_type(content_type, plugin_config.allowed_content_types) and "allow" or
             false

    -- store in cache
    lru:set(content_type, result)
    return result
  end
end


-- converts both hard+soft errors into soft errors
local function protect(f, ...)
  local ok, err, err2 = pcall(f, ...)
  if ok and not err then -- soft error
    return err, err2
  end
  return ok, err
end


local function validate_xml(conf)

  local body_size = tonumber(kong.request.get_header("content-length")) or 0
  if body_size > conf.document then
    kong.log.debug("validation failed: content-length too big")
    return false
  end

  local callbacks = { threat = {
    depth = conf.max_depth,
    maxChildren = conf.max_children,
    maxAttributes = conf.max_attributes,
    maxNamespaces = conf.max_namespaces,
    document = conf.document,
    buffer = conf.buffer,
    comment = conf.comment,
    localName = conf.localname,
    prefix = conf.prefix,
    namespaceUri = conf.namespaceuri,
    attribute = conf.attribute,
    text = conf.text,
    PITarget = conf.pitarget,
    PIData = conf.pidata,
    entityName = conf.entityname,
    entity = conf.entity,
    entityProperty = conf.entityproperty,
    allowDTD = conf.allow_dtd,
  }}
  local parser = assert(threat_parser.new(callbacks, "\1"):
                        setblamaxamplification(conf.bla_max_amplification):
                        setblathreshold(conf.bla_threshold))

  local body = kong.request.get_raw_body()
  if body then
    -- body read in memory
    if #body > conf.document then
      kong.log.debug("validation failed: request-body too big")
      return false
    end

    local ok, err = protect(parser.parse, parser, body)
    if ok then
      ok, err = protect(parser.parse, parser)
      if ok then
        protect(parser.close, parser)
        return true  -- success!
      end
    end

    kong.log.debug("validation failed: ", err)
    protect(parser.close, parser)
    return false
  end

  -- body cached to disk...
  kong.log.debug("body was cached to disk, reading it back in 1mb chunks")
  -- not calling 'ngx.req.read_body', since get_raw_body() already did that
  local filename = ngx.req.get_body_file()
  local file, err = io.open(filename, "r")
  if not file then
    kong.log.err("failed to open cached request body '",filename,"': ", err)
    return false
  end

  if (file:seek("end") or 0) > conf.document then
    kong.log.debug("validation failed: request-body-file too big")
    file:close()
    return false
  else
    -- the if-clause moved the file cursor to the end, reset it to the start
    file:seek("set")
  end

  while true do
    local data, err = file:read(mb) -- read in chunks of 1mb
    if not data then
      if err then
        -- error reading file contents
        kong.log.err("failed to read cached request body '",filename,"': ", err)
        file:close()
        protect(parser.close, parser)
        return false
      end
      -- reached end of file
      local ok, err = protect(parser.parse, parser)
      if not ok then
        kong.log.debug("validation failed: ", err)
        file:close()
        protect(parser.close, parser)
        return false
      end
      file:close()
      protect(parser.close, parser)
      return true  -- success!
    end

    -- chunk of data read, parse it
    local ok, err = protect(parser.parse, parser, data)
    if not ok then
      kong.log.debug("validation failed: ", err)
      file:close()
      protect(parser.close, parser)
      return false
    end

    kong_yield() -- yield to prevent starvation while doing blocking IO-reads
  end

  -- unreachable
end



function xml_threat:access(conf)

  local result = content_type_allowed(conf, kong.request.get_header("content-type"))
  if result == "check" then
    result = validate_xml(conf)
  end

  if not result then
    kong.response.exit(400)
  end
end


return xml_threat
