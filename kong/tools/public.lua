local pcall = pcall
local ngx_log = ngx.log
local ERR = ngx.ERR


local _M = {}


do
  local multipart = require "multipart"
  local cjson     = require "cjson.safe"


  local str_find              = string.find
  local ngx_req_get_post_args = ngx.req.get_post_args
  local ngx_req_get_body_data = ngx.req.get_body_data


  local content_type_map = {
    [1] = function(content_type) -- multipart
      return multipart(ngx_req_get_body_data(), content_type):get_all()
    end,

    [2] = function() -- json
      local body, err = cjson.decode(ngx_req_get_body_data())
      if err then
        ngx_log(ERR, "could not decode JSON body args: ", err)
        return {}
      end

      return body
    end,

    [3] = function() -- encoded form
      local ok, res, err = pcall(ngx_req_get_post_args)
      if not ok or err then
        local msg = res and res or err
        ngx_log(ERR, "could not get body args: ", msg)
        return {}
      end

      return res
    end,
  }

  function _M.get_body_args()
    local content_type = ngx.var.http_content_type

    if not content_type or content_type == "" then
      return {}
    end

    local map_type

    if str_find(content_type, "multipart/form-data", nil, true) then
      map_type = 1

    elseif str_find(content_type, "application/json", nil, true) then
      map_type = 2

    elseif str_find(content_type, "application/www-form-urlencoded", nil, true) or
      str_find(content_type, "application/x-www-form-urlencoded", nil, true) then
      map_type = 3

    else
      ngx_log(ERR, "don't know how to parse request body of Content-Type: '", content_type, "'")
      return {}
    end

    return content_type_map[map_type](content_type)
  end
end


return _M
