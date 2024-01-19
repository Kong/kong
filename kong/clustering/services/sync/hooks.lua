local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.hooks")


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _MT)
end


function _M:register_dao_hooks(is_cp)
  if is_cp then
    local update = function(row, name, options, ws_id)
      row = assert(kong.db[name]:select({ id = row.id }))
      ngx.log(ngx.ERR, " %%%%% update hook ", name, " ", require("inspect")(row))
      local deltas = {
        {
          ["type"] = name,
          id = row.id,
          ws_id = ws_id or require("kong.workspaces").get_workspace_id(),
          row = row, },
      }

      local res, err = self.strategy:insert_delta(deltas)
      if not res then
        return nil, err
      end

      local latest_version = self.strategy:get_latest_version()

      for node, cap in pairs(kong.rpc:get_peers()) do
        if cap["kong.sync.v2"] then
          ngx.log(ngx.ERR, "notified ", node, " ", latest_version)
          assert(kong.rpc:call(node, "kong.sync.v2.notify_new_version", latest_version))
        end
      end

      return row, name, options, ws_id
    end

    hooks.register_hook("dao:insert:post", update)
    hooks.register_hook("dao:upsert:post", update)
    hooks.register_hook("dao:update:post", update)

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

      local latest_version = self.strategy:get_latest_version()

      for node, cap in pairs(kong.rpc:get_peers()) do
        if cap["kong.sync.v2"] then
          assert(kong.rpc:call(node, "kong.sync.v2.notify_new_version", latest_version))
        end
      end

      return row, name, options, ws_id, cascade_entries
    end)
  end
end


return _M
