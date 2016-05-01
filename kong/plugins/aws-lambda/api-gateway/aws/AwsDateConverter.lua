--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]

--
-- User: ddascal
-- Date: 19/03/16
-- Time: 21:40
-- To change this template use File | Settings | File Templates.
--


local _M = {}

--- Converts an AWS Date String into a timestamp number
-- @param dateString  AWS Date String (i.e. 2016-03-19T06:44:17Z)
-- @param convertToUTC (default false). Boolean value to get the date in UTC or not
--
local function _convertDateStringToTimestamp(dateString, convertToUTC)
    local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z"
    local xyear, xmonth, xday, xhour, xminute,
    xseconds, xoffset, xoffsethour, xoffsetmin = dateString:match(pattern)

    -- the converted timestamp is in the local timezone
    local convertedTimestamp = os.time({
        year = xyear,
        month = xmonth,
        day = xday,
        hour = xhour,
        min = xminute,
        sec = xseconds
    })
    if (convertToUTC == true) then
        local offset = os.time() - os.time(os.date("!*t"))
        convertedTimestamp = convertedTimestamp + offset
    end
    return tonumber(convertedTimestamp)
end

_M.convertDateStringToTimestamp = _convertDateStringToTimestamp

return _M
