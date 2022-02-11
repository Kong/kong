
local cjson = require "cjson.safe"
local pl_file = require "pl.file"

local _M = {}


local function get_body()
  ngx.req.read_body()
  local body = ngx.req.get_body_data()
  if body then
    return body
  end

  local fname = ngx.req.get_body_file()
  if fname then
    return pl_file.read(fname)
  end

  return ""
end

local function response(status, body)
  ngx.status = status

  if type(body) == "table" then
    ngx.header["Content-Type"] = "application/json"
    body = cjson.encode(body)
  end

  ngx.say(body)
  return ngx.exit(status)
end

local function verify_request(body)
  if type(body.node) ~= "table" then
    return false, "field \"node\" must be an object."
  end

  if type(body.node.id) ~= "string" then
    return false, "field \"node.id\" must be a string."
  end

  if type(body.node.type) ~= "string" then
    return false, "field \"node.type\" must be a string."
  end

  if type(body.node.version) ~= "string" then
    return false, "field \"node.version\" must be a string."
  end

  if type(body.services_requested) ~= "table" then
    return false, "field \"services_requested\" must be an array."
  end

  return true
end

function _M.serve_version_handshake()
  local body = cjson.decode(get_body())
  if not body then
    return response(400, { message = "Not valid JSON data" })
  end

  local ok, err = verify_request(body)
  if not ok then
    return response(400, { message = err })
  end

  return response(200, {
    node = { id = kong.node.get_id() },
    services_accepted = {},
    services_rejected = {},
  })
end

return _M
