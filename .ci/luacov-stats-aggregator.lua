-- Aggregates stats from multiple luacov stat files.
-- If different stats files contain coverage information of common
-- source files, it assumes the provided stats refer to the same
-- version of the source files.

-- Example stats for a 12 lines file `my/file.lua`
-- that received hits on lines 3, 4, 9:
-- 
-- ["my/file.lua"] = {
--   [3] = 1,
--   [4] = 3,
--   [9] = 2,
--   max = 12,
--   max_hits = 3
-- }
--

local luacov_stats = require "luacov.stats"
local luacov_reporter = require "luacov.reporter"

local all_stats = {}


-- load parameters
local params = {...}
local base_path = params[1] or "./luacov-stats-out-"
local file_name = params[2] or "luacov.stats.out"
local output = params[3] or file_name


-- load stats - appends incremental index to base_path to load all the artifacts
local loaded_stats = {}
local index = 0
repeat
  index = index + 1
  local stats_file = base_path .. index .. "/" .. file_name
  local loaded = luacov_stats.load(stats_file)
  if loaded then
    loaded_stats[#loaded_stats + 1] = loaded
    print("loading file: " .. stats_file)
  end
until not loaded


-- aggregate stats by file name
for _, stat_data in ipairs(loaded_stats) do
  for f_name, f_data in pairs(stat_data) do
    if all_stats[f_name] then
      assert(
        all_stats[f_name].max == f_data.max,
        "number of lines in file " .. f_name .. " is inconsistent"
      )
      -- combine stats (add line hits)
      for i = 1, all_stats[f_name].max do
        if all_stats[f_name][i] or f_data[i] then
          all_stats[f_name][i] = (all_stats[f_name][i] or 0) + (f_data[i] or 0)
        end
      end
      all_stats[f_name].max_hits = math.max(all_stats[f_name].max_hits, f_data.max_hits)

    else
      all_stats[f_name] = f_data
    end
  end
end
luacov_stats.save(output, all_stats)

-- generate report
luacov_reporter.report()
