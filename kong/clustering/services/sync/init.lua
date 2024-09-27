local _M = {}
local _MT = { __index = _M, }


local events = require("kong.clustering.events")
local hooks = require("kong.clustering.services.sync.hooks")
local strategy = require("kong.clustering.services.sync.strategies.postgres")
local rpc = require("kong.clustering.services.sync.rpc")


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
  if self.is_cp then
    -- enable clustering broadcasts in CP
    events.init()

    self.strategy:init_worker()
    return
  end

  -- is dp, sync in worker 0
  if ngx.worker.id() == 0 then
    assert(self.rpc:sync_once(0.5))
    assert(ngx.timer.every(30, function(premature)
      if premature then
        return
      end

      assert(self.rpc:sync_once(0))
    end))
  end
end


return _M
