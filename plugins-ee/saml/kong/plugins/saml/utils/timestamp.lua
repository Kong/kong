-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local luatz     = require "luatz"


local function format(timetable)
  return timetable:normalize():rfc_3339() .. "Z"
end


local function parse(string)
  return luatz.parse.rfc_3339(string)
end


local function now()
  return luatz.timetable.new_from_timestamp(ngx.time())
end

return {
  format = format,
  parse = parse,
  now = now,
}
