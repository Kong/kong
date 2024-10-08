local _M = {}
local _MT = { __index = _M, }


local events = require("kong.clustering.events")
local strategy = require("kong.clustering.services.sync.strategies.postgres")
local rpc = require("kong.clustering.services.sync.rpc")


-- TODO: what is the proper value?
local FIRST_SYNC_DELAY = 0.5  -- seconds
local EACH_SYNC_DELAY  = 30   -- seconds


function _M.new(db, is_cp)
  local strategy = strategy.new(db)

  local self = {
    db = db,
    strategy = strategy,
    rpc = rpc.new(strategy),
    is_cp = is_cp,
  }

  -- only cp needs hooks
  if is_cp then
    self.hooks = require("kong.clustering.services.sync.hooks").new(strategy)
  end

  return setmetatable(self, _MT)
end


function _M:init(manager)
  if self.hooks then
    self.hooks:register_dao_hooks()
  end
  self.rpc:init(manager, self.is_cp)
end


function _M:init_worker()
  -- is CP, enable clustering broadcasts
  if self.is_cp then
    events.init()

    self.strategy:init_worker()
    return
  end

  -- is DP, sync only in worker 0
  if ngx.worker.id() ~= 0 then
    return
  end

  -- sync to CP ASAP
  assert(self.rpc:sync_once(FIRST_SYNC_DELAY))

  assert(self.rpc:sync_every(EACH_SYNC_DELAY))
end


return _M
