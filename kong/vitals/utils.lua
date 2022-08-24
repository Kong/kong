-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local duration_to_interval = {
  [1] = "seconds",
  [60] = "minutes",
  [3600] = "hours",
  [86400] = "days",
  [604800] = "weeks",
}
_M.duration_to_interval = duration_to_interval

local interval_to_duration = {
  seconds = 1,
  minutes = 60,
  hours = 3600,
  days = 86400,
  weeks = 604800,
}
_M.interval_to_duration = interval_to_duration

return _M
