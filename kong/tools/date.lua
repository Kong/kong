-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local luatz = require("luatz")

-- The date format follows RFC3339
-- YYYY-MM-DDTHH:MI:SSZ
-- 1985-04-12T23:20:50Z
-- as defined in Kong AIP: https://kong-aip.netlify.app/aip/142/
-- (except for fractions of a second to avoid precision errors)
local function aip_date_to_timestamp(date)
  local year, month, day, hour, min, sec = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
  if not year then
		return nil, "date param: '" .. date .. "' does not match expected format: YYYY-MM-DDTHH:MI:SSZ"
	end

  -- We need to use luatz.timetable.timestamp instead of os.time to correctly build
  -- timestamp based on datetime. The reason why os.time is not suitable is that
  -- it uses system timezone so it'll interpret passed hour within it's timezone
  -- to shift to timestamp (which is in utc by definition).
  local timetable = luatz.timetable.new(year, month, day, hour, min, sec)
  return timetable:timestamp()
end

return {
  aip_date_to_timestamp = aip_date_to_timestamp
}
