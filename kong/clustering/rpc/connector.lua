local ws_client = require("resty.websocket.client")
local ws_server = require("resty.websocket.server")


local constants = require("constants")


local _M = {}
local _MT = { __index = _M, }


local WS_OPTS = {
  timeout         = constants.TIMEOUT,
  max_payload_len = constants.MAX_PAYLOAD,
}


local function connect(conf)
  local wb, _ = ws_client:new(WS_OPTS)

  local ok, err = wb:connect(conf.uri, conf.opts)
  if not ok then
    return nil, err
  end

  return wb
end


local function accept(conf)
  local wb, err = ws_server:new(WS_OPTS)
  if not wb then
    return nil, err
  end

  return wb
end


function _M.new(conf)
  local self = {
    conf = conf,
  }
  return setmetatable(self, _MT)
end


function _M:init()
  local conf = self.conf

  if conf and conf.uri then
    return connect(conf)
  end

  return accept(conf)
end


return _M
