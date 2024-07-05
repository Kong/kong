-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local _M = {}

function _M.set_tried_target(id)
  kong.ctx.plugin.tried_targets = kong.ctx.plugin.tried_targets or {}
  kong.ctx.plugin.tried_targets[id] = true
  return true
end

function _M.get_tried_targets()
  return kong.ctx.plugin.tried_targets or {}
end

return _M