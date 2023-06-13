-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson                 = require("cjson.safe").new()
local pl_stringx            = require "pl.stringx"

local re_match              = ngx.re.match
local json_decode           = cjson.decode
local gsub                  = string.gsub


cjson.decode_array_with_array_mt(true)


local _M = {}


function _M.extract_media_type(content_type)
  if not content_type then
    return nil
  end

  local capture, err = re_match(content_type, "([^;]+)")
  if err then
    return nil
  end

  return pl_stringx.strip(capture[0])
end


function _M.get_req_body_json()
  ngx.req.read_body()

  local body_data = ngx.req.get_body_data()

  if not body_data then
    --no raw body, check temp body
    local body_file = ngx.req.get_body_file()
    if body_file then
      local file, err = io.open(body_file, "r")
      if err then
        return nil, err
      end

      body_data = file:read("*all")
      file:close()
    end
  end

  if not body_data or #body_data == 0 then
    return nil
  end

  -- try to decode body data as json
  local body, err = json_decode(body_data)
  if err then
    return nil, "request body is not valid JSON"
  end

  return body
end


function _M.exists(tab, val)
  for _, value in pairs(tab) do
      if value:lower() == val:lower() then
          return true
      end
  end
  return false
end


function _M.to_wildcard_subtype(content_type)
  -- remove parameter in content type
  return gsub(content_type, "([^/]+)/([^/]+)", "%1") .. "/*"
end


return _M
