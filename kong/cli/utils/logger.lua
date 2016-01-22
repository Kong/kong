--[[
Kong CLI logging
--]]

local ansicolors = require "ansicolors"
local Object = require "classic"
local stringy = require "stringy"

--
-- Colors
--
local colors = {}
for _, v in ipairs({"red", "green", "yellow", "blue"}) do
  colors[v] = function(str) return ansicolors("%{"..v.."}"..str.."%{reset}") end
end

--
-- Logging
--
local Logger = Object:extend()

Logger.colors = colors

function Logger:set_silent(silent)
  self._silent = silent
end

function Logger:print(str)
  if not self._silent then
    print(stringy.strip(str))
  end
end

function Logger:info(str)
  self:print(colors.blue("[INFO] ")..str)
end

function Logger:success(str)
  self:print(colors.green("[OK] ")..str)
end

function Logger:warn(str)
  self:print(colors.yellow("[WARN] ")..str)
end

function Logger:error(str)
  self:print(colors.red("[ERR] ")..str)
end

return Logger()
