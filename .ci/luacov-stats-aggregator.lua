-- Aggregates stats from multiple luacov stat files.
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
local luacov_runner = require "luacov.runner"
local lfs = require "lfs"


-- load parameters
local params = {...}
local stats_folders_prefix = params[1] or "luacov-stats-out-"
local file_name            = params[2] or "luacov.stats.out"
local strip_prefix         = params[3] or ""
local base_path            = "."


-- load stats from different folders named using the format:
-- luacov-stats-out-${timestamp}
local loaded_stats = {}
for folder in lfs.dir(base_path) do
  if folder:find(stats_folders_prefix, 1, true) then
    local stats_file = folder .. "/" .. file_name
    local loaded = luacov_stats.load(stats_file)
    if loaded then
      loaded_stats[#loaded_stats + 1] = loaded
      print("loading file: " .. stats_file)
    end
  end
end


-- aggregate
luacov_runner.load_config()
for _, stat_data in ipairs(loaded_stats) do
  -- make all paths relative to ensure file keys have the same format
  -- and avoid having separate counters for the same file
  local rel_stat_data = {}
  for f_name, data in pairs(stat_data) do
    if f_name:sub(0, #strip_prefix) == strip_prefix then
      f_name = f_name:sub(#strip_prefix + 1)
    end
    rel_stat_data[f_name] = data
  end

  luacov_runner.data = rel_stat_data
  luacov_runner.save_stats()
end


-- generate report
luacov_reporter.report()
