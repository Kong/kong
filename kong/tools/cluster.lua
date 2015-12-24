local utils = require "kong.tools.utils"

local _M = {}

function _M.get_node_name(conf)
  return utils.get_hostname().."_"..conf.cluster_listen
end

return _M