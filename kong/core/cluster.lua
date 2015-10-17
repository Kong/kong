local cluster_utils = require "kong.tools.cluster"

local resty_lock
local status, res = pcall(require, "resty.lock")
if status then
  resty_lock = res
end

local INTERVAL = 30

local function create_timer(at, cb)
  local ok, err = ngx.timer.at(at, cb)
  if not ok then
    ngx.log(ngx.ERR, "[cluster] failed to create timer: ", err)
  end
end

local function send_keepalive(premature)
  if premature then return end

  local lock = resty_lock:new("cluster_locks", {
    exptime = INTERVAL - 0.001
  })
  local elapsed = lock:lock("keepalive")
  if elapsed and elapsed == 0 then
    -- Send keepalive
    local node_name = cluster_utils.get_node_name(configuration)
    local nodes, err = dao.nodes:find_by_keys({name = node_name})
    if err then
      ngx.log(ngx.ERR, tostring(err))
    elseif #nodes == 1 then
      local node = table.remove(nodes, 1)
      local _, err = dao.nodes:update(node)
      if err then
        ngx.log(ngx.ERR, tostring(err))
      end
    end
  end

  create_timer(INTERVAL, send_keepalive)
end

return {
  init_worker = function()
    create_timer(INTERVAL, send_keepalive)
  end
}
