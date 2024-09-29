local _M = {}
local _MT = { __index = _M, }


local events = require("kong.clustering.events")
local hooks = require("kong.clustering.services.sync.hooks")
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
    hooks = hooks.new(strategy),
    rpc = rpc.new(strategy),
    is_cp = is_cp,
  }

  return setmetatable(self, _MT)
end


function _M:init(manager)
  self.hooks:register_dao_hooks(self.is_cp)
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

  assert(ngx.timer.every(EACH_SYNC_DELAY, function(premature)
    if premature then
      return
    end

    assert(self.rpc:sync_once(0))
  end))
end


return _M
