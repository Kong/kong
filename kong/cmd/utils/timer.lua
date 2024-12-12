-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

function _M.shutdown()
  if _G.timerng then
    pcall(_G.timerng.destroy, _G.timerng)
  end

  -- kong.init_worker() stashes the timerng instance within the kong global and
  -- removes the _G.timerng reference, so check there too
  if _G.kong and _G.kong.timer and _G.kong.timer ~= _G.timerng then
    pcall(_G.kong.timer.destroy, _G.kong.timer)
    _G.kong.timer = nil
  end

  _G.timerng = nil
end

return _M
