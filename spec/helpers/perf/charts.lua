-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local math = require "math"
local max, min = math.max, math.min
local utils = require("spec.helpers.perf.utils")
local logger = require("spec.helpers.perf.logger")
local cjson = require("cjson")

local my_logger = logger.new_logger("[charts]")

-- to increase the yrange by a factor so we leave some space
-- for the legends
local yr_factor = 1.1
local y2r_factor = 1.3
local color_palettes = {
  "7,5,15", -- traditional pm3d (black-blue-red-yellow)
  "3,11,6", -- green-red-violate
  "23,28,3", -- ocean (green-blue-white)
  "21,22,23", -- hot (black-red-yellow-white)
  "34,35,36", -- FM hot (black-red-yellow-white)
}
math.randomseed(ngx.now())

local current_test_element
local enabled = true
local unsaved_result = {}
local versions_key = {}

local function on_test_start(element, parent, status, debug)
  if not enabled then
    return true
  end

  current_test_element = element
end

local function on_test_end(element, parent, status, debug)
  if not enabled then
    return true
  end

end

local function gnuplot_sanitize(s)
  return s:gsub("_", [[\\_]]):gsub("\n", "\\n")
end

local function on_file_end(file)
  if not enabled then
    return true
  end

  local result = unsaved_result
  unsaved_result = {}

  os.execute("mkdir -p output")
  local outf_prefix = file.name:gsub("[:/]", "#"):gsub("[ ,]", "_"):gsub("__", "_")

  local f = io.open(string.format("output/%s.json", outf_prefix), "w")
  local rr = {}
  for k, v in pairs(result) do -- strip the "versions_key"
    if type(k) ~= "table" then
      rr[k] = v
    end
  end
  f:write(cjson.encode(rr))
  f:close()
  my_logger.info(string.format("parsed result for %s saved to output/%s.json", file.name, outf_prefix))

  local perf = require("spec.helpers.perf")

  if not result[versions_key] or not next(result[versions_key]) then
    my_logger.debug("no versions found in result, skipping")
    return
  end

  local versions = {}
  for k, _ in pairs(result[versions_key]) do
    table.insert(versions, k)
  end

  table.sort(versions, function(a, b) return a > b end) -- reverse order
  local version_count = #versions

  local f = assert(io.open("output/" .. outf_prefix .. ".plot", "w"))
  f:write("$Data <<EOD\nH")
  for _, v in ipairs(versions) do
    f:write(string.format('\t%s\trps_err\t"%s avg"\t"%s p90"\t"%s p99"', v, v, v, v))
  end
  f:write("\n")

  local suites = {}
  local y1max, y2max = 0, 0
  for suite, data in pairs(result) do
    if suite ~= versions_key then
      table.insert(suites, string.format("Suite #%d: %s", #suites+1, suite))
      f:write(string.format([["Suite #%d"]], #suites))
      --f:write(string.format([["%s"]], gnuplot_sanitize(suite)))
      for _, v in ipairs(versions) do
        local p = data[v] and data[v].parsed
        if p then
          f:write(string.format("\t%s\t%s\t%s\t%s\t%s", p.rps or 0, max(unpack(p.rpss)) - min(unpack(p.rpss)),
                                p.latency_avg or 0, p.latency_p90 or 0, p.latency_p99 or 0))
          y1max = max(y1max, p.rps)
          y2max = max(y2max, p.latency_p99)
        else
          f:write("\t0\t0\t0")
        end
      end
      f:write("\n")
    end
  end
  f:write("EOD\n")

  f:write(string.format([[
set title "%s"

set key autotitle columnheader
# set xtics nomirror rotate by 315
set yr [0:%f] # y-axis always start from 0
set y2r [0:%f] # y2-axis always start from 0
set ylabel 'RPS'
set y2tics autofreq textcolor lt 2
set y2label 'Latency/ms' textcolor lt 2

set term svg enhanced font "Droid Sans"
set output "output/%s.svg"

set style fill solid
set palette rgb %s
unset colorbox # no color<->value box on the right
set style histogram errorbars lw 2
set style line 1 lc rgb '#0060ad' lt 1 lw 2 pt 7 pi -1 ps 0.5
set pointintervalbox 1 # make some nice outlining for the point

]], gnuplot_sanitize(file.name .. "\n" .. table.concat(suites, "\n")),
    y1max * yr_factor, y2max * y2r_factor,
    outf_prefix, color_palettes[1+math.floor(#color_palettes * math.random())]))

    -- each column set +2 rps, +3 rps_err, +4 lat_avg, +5 lat_p90, +6 lat_p99
    f:write("plot $Data using 2:3:xtic(1) title columnheader(2) w histograms palette frac 0, \\\n")
    if version_count > 1 then
      f:write(string.format(
"for [i=1:%d] '' using (column(5*i+2)):(column(5*i+3)) title columnheader(5*i+2) w histograms palette frac i/%d., \\\n", version_count-1, version_count))
    end

    local lines = {}
    for col=4,6 do
      table.insert(lines, string.format(
  "'' using %d:xtic(1) t columnheader(%d) axes x1y2 w linespoints ls 1 palette frac (1/%d.)*(%d/4.)", col, col, version_count, col-3))
      if version_count > 1 then
        table.insert(lines, string.format(
  "for [i=1:%d] '' using 5*i+%d title columnheader(5*i+%d) axes x1y2 w linespoints ls 1 palette frac i/%d.+(1/%d.)*(%d/4.)",
  version_count-1, col, col, version_count, version_count, col-3))
      end
    end

    f:write(table.concat(lines, ", \\\n"))
--[[
# set term pngcairo enhanced font "Droid Sans,9"
# set output "output/%s.png"
# replot
]]

  f:close()

  local _, err = perf.execute(string.format("gnuplot \"output/%s.plot\"", outf_prefix),
                            { logger = my_logger.log_exec })
  if err then
    my_logger.info(string.format("error generating graph for %s: %s", file.name, err))
    return false
  end

  my_logger.info(string.format("graph for %s saved to output/%s.svg", file.name, outf_prefix))
  return true
end

local function ingest_combined_results(results)
  if not enabled then
    return true
  end

  local desc = utils.get_test_descriptor(false, current_test_element)
  local ver = results.version
  if not ver then
    error("no version in combined results, can't save")
  end

  -- escape lua patterns
  local pattern = ver:gsub([=[[%[%(%)%.%%%+%-%*%?%[%^%$%]]]=], "%%%1")
  -- remove version and surround string from title
  desc = desc:gsub("%s?"..pattern, ""):gsub(pattern.."%s?", "")

  if not unsaved_result[versions_key] then
    unsaved_result[versions_key] = { [ver] = true }
  else
    unsaved_result[versions_key][ver] = true
  end

  if not unsaved_result[desc] then
    unsaved_result[desc] = {}
  elseif unsaved_result[desc][ver] then
    my_logger.warn(string.format("version %s for \"%s\" already has results, current result will be discarded",
                    ver, desc))
    return false
  end

  unsaved_result[desc][ver] = results
end

local function register_busted_hook(opts)
  local busted = require("busted")

  busted.subscribe({'file', 'end' }, on_file_end)
  busted.subscribe({'test', 'start'}, on_test_start)
  busted.subscribe({'test', 'end'}, on_test_end)
end

return {
  register_busted_hook = register_busted_hook,
  ingest_combined_results = ingest_combined_results,
  on = function() enabled = true end,
  off = function() enabled = false end,
}
