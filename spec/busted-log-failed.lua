-- busted-log-failed.lua

-- Log which test files run by busted had failures or errors in a
-- file.  The file to use for logging is specified in the
-- FAILED_TEST_FILES_FILE environment variable.  This is used to
-- reduce test rerun times for flaky tests.

local busted = require 'busted'
local failed_files_file = assert(os.getenv("FAILED_TEST_FILES_FILE"),
        "FAILED_TEST_FILES_FILE environment variable not set")

local FAILED_FILES = {}

busted.subscribe({ 'failure' }, function(element, parent, message, debug)
  FAILED_FILES[element.trace.source] = true
  return nil, true --continue
end)

busted.subscribe({ 'error' }, function(element, parent, message, debug)
  FAILED_FILES[element.trace.source] = true
  return nil, true --continue
end)

busted.subscribe({ 'suite', 'end' }, function(suite, count, total)
  local output = assert(io.open(failed_files_file, "w"))
  if next(FAILED_FILES) then
    for failed_file in pairs(FAILED_FILES) do
      if failed_file:sub(1, 1) == '@' then
        failed_file = failed_file:sub(2)
      end
      assert(output:write(failed_file .. "\n"))
    end
  end
  output:close()
  return nil, true --continue
end)
