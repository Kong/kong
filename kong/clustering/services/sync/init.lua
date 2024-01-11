local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.clustering.services.sync.hooks")
local strategy = require("kong.clustering.services.sync.strategies.postgres")


function _M.new(db)
  local strategy = strategy.new(db)

  local self = {
    db = db,
    strategy = strategy,
    hooks = hooks.new(strategy),
  }

  return setmetatable(self, _MT)
end


function _M:init()
  self.hooks:register_dao_hooks()
end


return _M
