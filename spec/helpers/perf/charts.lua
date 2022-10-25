local math = require "math"
local utils = require("spec.helpers.perf.utils")
local logger = require("spec.helpers.perf.logger")
local cjson = require "cjson"
local tablex = require "pl.tablex"

local fmt = string.format
local my_logger = logger.new_logger("[charts]")

math.randomseed(ngx.now())

local options
local current_test_element
local enabled = true
local unsaved_results_lookup = {}
local unsaved_results = {}

local function gen_plots(results, fname, opts)
  opts = opts or options

  if not results or not next(results) then
    my_logger.warn("no result found, skipping plot generation")
    return
  end

  os.execute("mkdir -p output")

  local output_data = {
    options = opts,
    data = results,
  }

  local f = io.open(fmt("output/%s.data.json", fname), "w")
  f:write(cjson.encode(output_data))
  f:close()
  my_logger.info(fmt("parsed result saved to output/%s.json", fname))

  return true
end

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

local function on_file_end(file)
  if not enabled then
    return true
  end

  local results = unsaved_results
  unsaved_results = {}

  local fname = file.name:gsub("[:/]", "#"):gsub("[ ,]", "_"):gsub("__", "_")
  return gen_plots(results, fname, options)
end

local function ingest_combined_results(ver, results, suite_name)
  if not suite_name then
    local desc = utils.get_test_descriptor(false, current_test_element)
    -- escape lua patterns
    local pattern = ver:gsub([=[[%[%(%)%.%%%+%-%*%?%[%^%$%]]]=], "%%%1")
    -- remove version and surround string from title
    suite_name = desc:gsub("%s?"..pattern, ""):gsub(pattern.."%s?", "")
  end

  if not unsaved_results_lookup[suite_name] then
    unsaved_results_lookup[suite_name] = {}

  elseif unsaved_results_lookup[suite_name][ver] then
    my_logger.warn(fmt("version %s for \"%s\" already has results, current result will be discarded",
                    ver, suite_name))
    return false
  end

  local row = tablex.deepcopy(results)
  row.version = ver
  row.suite = suite_name

  -- save as ordered-array
  table.insert(unsaved_results, row)

  return true
end

local function register_busted_hook(opts)
  local busted = require("busted")

  busted.subscribe({'file', 'end' }, on_file_end)
  busted.subscribe({'test', 'start'}, on_test_start)
  busted.subscribe({'test', 'end'}, on_test_end)
end

return {
  gen_plots = gen_plots,
  register_busted_hook = register_busted_hook,
  ingest_combined_results = ingest_combined_results,
  on = function() enabled = true end,
  off = function() enabled = false end,
  options = function(opts)
    options = opts
  end,
}
