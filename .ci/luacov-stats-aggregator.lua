-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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


-- load parameters
local params = {...}
local base_path = params[1] or "./luacov-stats-out-"
local file_name = params[2] or "luacov.stats.out"
local path_prefix = params[3] or ""


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


-- aggregate
luacov_runner.load_config()
for _, stat_data in ipairs(loaded_stats) do
  -- make all paths relative to ensure file keys have the same format
  -- and avoid having separate counters for the same file
  local rel_stat_data = {}
  for f_name, data in pairs(stat_data) do
    if f_name:sub(0, #path_prefix) == path_prefix then
      f_name = f_name:sub(#path_prefix + 1)
    end
    rel_stat_data[f_name] = data
  end

  luacov_runner.data = rel_stat_data
  luacov_runner.save_stats()
end


-- generate report
luacov_reporter.report()
