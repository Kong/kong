-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe").new()

local json_decode = cjson.decode
local gsub = string.gsub
local match = string.match
local lower = string.lower
local pairs = pairs

cjson.decode_array_with_array_mt(true)

local EMPTY_T = {}

local _M = {}


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

function _M.retrieve_operation(spec, path, method)
  for _, spec_path in pairs(spec.sorted_paths or EMPTY_T) do
    local formatted_path = gsub(spec_path, "[-.]", "%%%1")
    formatted_path = "^" .. gsub(formatted_path, "{(.-)}", "[^/]+") .. "$"
    if match(path, formatted_path) then
      return spec.paths[spec_path], spec_path, spec.paths[spec_path][lower(method)]
    end
  end
end

return _M
