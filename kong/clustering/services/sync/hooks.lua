local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.hooks")


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _MT)
end


function _M:register_dao_hooks()
  hooks.register_hook("dao:insert:post", function(row, name, options, ws_id)
    local deltas = {
      {
        ["type"] = name,
        id = row.id,
        ws_id = ws_id,
        row = row, },
    }

    local res, err = self.strategy:insert_delta(deltas)
    if not res then
      return nil, err
    end

    return row, name, options, ws_id
  end)

  hooks.register_hook("dao:delete:post", function(row, name, options, ws_id, cascade_entries)
    local deltas = {
      {
        ["type"] = name,
        id = row.id,
        ws_id = ws_id,
        row = ngx.null, },
    }

    local res, err = self.strategy:insert_delta(deltas)
    if not res then
      return nil, err
    end

    return row, name, options, ws_id, cascade_entries
  end)
end


return _M
