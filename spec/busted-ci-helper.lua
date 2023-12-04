-- busted-log-failed.lua

-- Log which test files run by busted had failures or errors in a
-- file.  The file to use for logging is specified in the
-- FAILED_TEST_FILES_FILE environment variable.  This is used to
-- reduce test rerun times for flaky tests.

local busted = require 'busted'
local failed_files_file = assert(os.getenv("FAILED_TEST_FILES_FILE"),
        "FAILED_TEST_FILES_FILE environment variable not set")
local test_file_runtime_file = assert(os.getenv("TEST_FILE_RUNTIME_FILE"),
        "TEST_FILE_RUNTIME_FILE environment variable not set")
local test_suite = assert(os.getenv("TEST_SUITE"),
        "TEST_SUITE environment variable not set")
local FAILED_FILES = {}

local function element_file(element)
  assert(element.trace)
  local file = element.trace.source
  if file:sub(1, 1) == '@' then
    file = file:sub(2)
  end
  return file
end

busted.subscribe({ 'failure' }, function(element, parent, message, debug)
  FAILED_FILES[element_file(element)] = true
end)

busted.subscribe({ 'error' }, function(element, parent, message, debug)
  FAILED_FILES[element_file(element)] = true
end)

local FILE_START_TIME

busted.subscribe({ 'file', 'start' }, function()
  FILE_START_TIME = ngx.now()
end)

busted.subscribe({ 'file', 'end' }, function(file)
  local output = assert(io.open(test_file_runtime_file, "a"))
  output:write(test_suite, "\t", file.name, "\t", ngx.now() - FILE_START_TIME, "\n")
  output:close()
end)

busted.subscribe({ 'suite', 'end' }, function(suite, count, total)
  local output = assert(io.open(failed_files_file, "a"))
  for failed_file in pairs(FAILED_FILES) do
    assert(output:write(failed_file .. "\n"))
  end
  output:close()
end)
