local luatz = require "luatz"

local _M = {}

function _M.get_utc()
  return math.floor(luatz.time()) * 1000
end

function _M.get_timestamps(now)
  local timestamp = now and now or _M.get_utc()
  if string.len(tostring(timestamp)) == 13 then
    timestamp = timestamp / 1000
  end

  local timetable = luatz.timetable.new_from_timestamp(timestamp)

  local second = luatz.timetable.new(timetable.year, timetable.month,
                                     timetable.day, timetable.hour,
                                     timetable.min, timetable.sec)

  local minute = luatz.timetable.new(timetable.year, timetable.month,
                                     timetable.day, timetable.hour,
                                     timetable.min, 0)

  local hour = luatz.timetable.new(timetable.year, timetable.month,
                                   timetable.day, timetable.hour,
                                   0, 0)

  local day = luatz.timetable.new(timetable.year, timetable.month,
                                  timetable.day, 0, 0, 0)

  local month = luatz.timetable.new(timetable.year, timetable.month,
                                    1, 0, 0, 0)

  local year = luatz.timetable.new(timetable.year, 1, 1, 0, 0, 0)

  return {
    second = math.floor(second:timestamp() * 1000),
    minute = minute:timestamp() * 1000,
    hour = hour:timestamp() * 1000,
    day = day:timestamp() * 1000,
    month = month:timestamp() * 1000,
    year = year:timestamp() * 1000
  }
end

return _M
