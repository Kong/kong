-- busted-log-failed.lua

-- Log which test files run by busted had failures or errors in a
-- file.  The file to use for logging is specified in the
-- FAILED_TEST_FILES_FILE environment variable.  This is used to
-- reduce test rerun times for flaky tests.

local busted = require 'busted'
local cjson = require 'cjson'
local socket_unix = require 'socket.unix'

local busted_event_path = os.getenv("BUSTED_EVENT_PATH")

-- Function to recursively copy a table, skipping keys associated with functions
local function copyTable(original, copied)
  copied = copied or {}

  for key, value in pairs(original) do
    if type(value) == "table" then
      copied[key] = copyTable(value, {})
    elseif type(value) ~= "function" then
      copied[key] = value
    end
  end

  return copied
end

if busted_event_path then
  local sock = assert(socket_unix())
  assert(sock:connect(busted_event_path))

  local events = {{ 'suite', 'reset' },
                  { 'suite', 'start' },
                  { 'suite', 'end' },
                  { 'file', 'start' },
                  { 'file', 'end' },
                  { 'test', 'start' },
                  { 'test', 'end' },
                  { 'pending' },
                  { 'failure', 'it' },
                  { 'error', 'it' },
                  { 'failure' },
                  { 'error' }}
  for _, event in ipairs(events) do
    busted.subscribe(event, function (...)
      local args = {}
      for i, original in ipairs{...} do
        if type(original) == "table" then
          args[i] = copyTable(original)
        elseif type(original) ~= "function" then
          args[i] = original
        end
      end

      sock:send(cjson.encode({ event = event[1] .. (event[2] and ":" .. event[2] or ""), args = args }) .. "\n")
    end)
  end
end
