local pcall = pcall
local ngx_log = ngx.log
local ERR = ngx.ERR


local _M = {}


do
  local multipart = require "multipart"
  local cjson     = (require "cjson.safe").new()
  cjson.decode_array_with_array_mt(true)

  local utils     = require "kong.tools.utils"


  local str_find              = string.find
  local str_format            = string.format
  local ngx_req_get_post_args = ngx.req.get_post_args
  local ngx_req_get_body_data = ngx.req.get_body_data


  local MIME_TYPES = {
    form_url_encoded = 1,
    json             = 2,
    xml              = 3,
    multipart        = 4,
    text             = 5,
    html             = 6,
  }


  local ERRORS     = {
    no_ct          = 1,
    [1]            = "don't know how to parse request body (no Content-Type)",
    unknown_ct     = 2,
    [2]            = "don't know how to parse request body (" ..
                     "unknown Content-Type '%s')",
    unsupported_ct = 3,
    [3]            = "don't know how to parse request body (" ..
                     "can't decode Content-Type '%s')",
  }


  _M.req_mime_types  = MIME_TYPES
  _M.req_body_errors = ERRORS


  local MIME_DECODERS = {
    [MIME_TYPES.multipart] = function(content_type)
      local raw_body = ngx_req_get_body_data()
      if not raw_body then
        ngx_log(ERR, "could not read request body (ngx.req.get_body_data() ",
                     "returned nil)")
        return {}, raw_body
      end

      local args = multipart(raw_body, content_type):get_all()

      return args, raw_body
    end,

    [MIME_TYPES.json] = function()
      local raw_body = ngx_req_get_body_data()
      if not raw_body then
        ngx_log(ERR, "could not read request body (ngx.req.get_body_data() ",
                     "returned nil)")
        return {}, raw_body
      end

      local args, err = cjson.decode(raw_body)
      if err then
        ngx_log(ERR, "could not decode JSON body args: ", err)
        return {}, raw_body
      end

      return args, raw_body
    end,

    [MIME_TYPES.form_url_encoded] = function()
      local ok, res, err = pcall(ngx_req_get_post_args)
      if not ok or err then
        local msg = res and res or err
        ngx_log(ERR, "could not get body args: ", msg)
        return {}
      end

      -- don't read raw_body if not necessary
      -- if we called get_body_args(), we only want the parsed body
      return res
    end,
  }


  local function get_body_info()
    local content_type = ngx.var.http_content_type

    if not content_type or content_type == "" then
      ngx_log(ERR, ERRORS[ERRORS.no_ct])

      return {}, ERRORS.no_ct
    end

    local req_mime

    if str_find(content_type, "multipart/form-data", nil, true) then
      req_mime = MIME_TYPES.multipart

    elseif str_find(content_type, "application/json", nil, true) then
      req_mime = MIME_TYPES.json

    elseif str_find(content_type, "application/www-form-urlencoded", nil, true) or
           str_find(content_type, "application/x-www-form-urlencoded", nil, true)
    then
      req_mime = MIME_TYPES.form_url_encoded

    elseif str_find(content_type, "text/plain", nil, true) then
      req_mime = MIME_TYPES.text

    elseif str_find(content_type, "text/html", nil, true) then
      req_mime = MIME_TYPES.html

    elseif str_find(content_type, "application/xml", nil, true) or
           str_find(content_type, "text/xml", nil, true)        or
           str_find(content_type, "application/soap+xml", nil, true)
    then
      -- considering SOAP 1.1 (text/xml) and SOAP 1.2 (application/soap+xml)
      -- as XML only for now.
      req_mime = MIME_TYPES.xml
    end

    if not req_mime then
      -- unknown Content-Type
      ngx_log(ERR, str_format(ERRORS[ERRORS.unsupported_ct], content_type))

      return {}, ERRORS.unknown_ct
    end

    if not MIME_DECODERS[req_mime] then
      -- known Content-Type, but cannot decode
      ngx_log(ERR, str_format(ERRORS[ERRORS.unsupported_ct], content_type))

      return {}, ERRORS.unsupported_ct, nil, req_mime
    end

    -- decoded Content-Type
    local args, raw_body = MIME_DECODERS[req_mime](content_type)

    return args, nil, raw_body, req_mime
  end


  function _M.get_body_args()
    -- only return args
    return (get_body_info())
  end


  function _M.get_body_info()
    local args, err_code, raw_body, req_mime = get_body_info()
    if not raw_body then
      -- if our body was form-urlencoded and read via ngx.req.get_post_args()
      -- we need to retrieve the raw body because it was not retrieved by the
      -- decoder
      raw_body = ngx_req_get_body_data()
    end

    return args, err_code, raw_body, req_mime
  end


  -- Obtain the unique node id for this node.
  do
    local node_id
    function _M.get_node_id()
      if node_id then
        return node_id
      end

      local shm = ngx.shared.kong
      local NODE_ID_KEY = "kong:node_id"

      local ok, err = shm:safe_add(NODE_ID_KEY, utils.uuid())
      if not ok and err ~= "exists" then
        return nil, "failed to set 'node_id' in shm: " .. err
      end

      node_id, err = shm:get(NODE_ID_KEY)
      if err then
        return nil, "failed to get 'node_id' in shm: " .. err
      end

      if not node_id then
        return nil, "no 'node_id' set in shm"
      end

      return node_id
    end
  end

end


return _M
