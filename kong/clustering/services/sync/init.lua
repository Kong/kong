local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.clustering.services.sync.hooks")
local strategy = require("kong.clustering.services.sync.strategies.postgres")
local rpc = require("kong.clustering.services.sync.rpc")


function _M.new(db)
  local strategy = strategy.new(db)

  local self = {
    db = db,
    strategy = strategy,
    hooks = hooks.new(strategy),
    rpc = rpc.new(strategy),
  }

  return setmetatable(self, _MT)
end


function _M:init(manager, is_cp)
  self.hooks:register_dao_hooks(is_cp)
  self.rpc:init(manager, is_cp)
end


function _M:init_worker_dp()
  if ngx.worker.id() == 0 then
    assert(self.rpc:sync_once(5))
  end
end


return _M
