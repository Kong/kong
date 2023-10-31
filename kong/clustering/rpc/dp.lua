--local cjson = require("cjson.safe")
local constants = require("kong.clustering.rpc.constants")
local callbacks = require("kong.clustering.rpc.callbacks")
local connector = require("kong.clustering.rpc.connector")
local handler = require("kong.clustering.rpc.handler")
local threads = require("kong.clustering.rpc.threads")
local peer = require("kong.clustering.rpc.peer")


local timer_at = ngx.timer.at


local META_HELLO_METHOD = constants.META_HELLO_METHOD


local _M = {}
local _MT = { __index = _M, }


local function random_delay()
  -- gen a random number [2.0, 10.0]
  --return math.random(200, 1000) / 100
  return math.random(5, 10)
end


local function meta_capabilities(pr, capabilities)
  -- kong.meta.v1.hello
  assert(timer_at(0, function(premature)
    pr:call(META_HELLO_METHOD, capabilities)
    --local res, err = pr:call(constants.META_HELLO_METHOD, self.capabilities)
    --ngx.log(ngx.ERR, "meta res = ", cjson.encode(res))
  end))
end


function _M.new(conf, capabilities)
  local self = {
    connector = connector.new(conf),
    conf = conf,

    -- kong.meta.v1.hello
    capabilities = capabilities or {},
  }

  return setmetatable(self, _MT)
end


function _M:connect()
  return self.connector:init()
end


function _M:register(method, func)
  callbacks.register(method, func)
end


function _M:unregister(method)
  callbacks.unregister(method)
end


-- opts.node_id
function _M:notify(method, params, opts)
  if not self.peer then
    return nil, "peer is not available"
  end

  return self.peer:notify(method, params, opts)
end


-- opts.node_id
function _M:call(method, params, opts)
  if not self.peer then
    return nil,{ code = constants.INTERNAL_ERROR,
                 message = "peer is not available", }
  end

  return self.peer:call(method, params, opts)
end


function _M:init_worker()
  self:reconnect()
end


function _M:reconnect(delay)
  --if self.reconnecting then
  --  return
  --end
  --self.reconnecting = true

  -- already has running threads
  if self.threads then
    self.threads:abort()
    self.threads = nil
  end

  -- clear rpc peer
  self.peer = nil

  assert(timer_at(delay or 0, function(premature)
    self:communicate(premature)
  end))
end


function _M:communicate(premature)
  if premature then
    return
  end

  local wb, err = self:connect()
  if not wb then
    ngx.log(ngx.ERR, "[dp] wb:connect err: ", err)

    --self.reconnecting = false

    -- retry to connect
    self:reconnect(random_delay())

    return
  end

  ngx.log(ngx.ERR, "[dp] wb:connect ok")

  -- set rpc peer
  local hdl = handler.new()
  local pr = peer.new(hdl)
  local thds = threads.new(wb, hdl)

  -- kong.meta.v1.hello
  meta_capabilities(pr, self.capabilities)

  self.peer = pr
  self.threads = thds

  --self.reconnecting = false

  -- cp/dp has almost the same workflow
  thds:run()

  wb:close()

  if thds:aborting() then
    return
  end

  ngx.log(ngx.ERR, "try re-connect wb")

  -- reconnect automaticly if not manual abort
  self:reconnect(random_delay())
end


return _M
