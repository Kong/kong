-- busted-ci-helper.lua

local busted = require 'busted'
local cjson = require 'cjson'
local socket_unix = require 'socket.unix'

local busted_event_path = os.getenv("BUSTED_EVENT_PATH")

-- Function to recursively copy a table, skipping keys associated with functions
local function copyTable(original, copied, cache, max_depth, current_depth)
  copied        = copied or {}
  cache         = cache  or {}
  max_depth     = max_depth or 5
  current_depth = current_depth or 1

  if cache[original] then return cache[original] end
  cache[original] = copied

  for key, value in pairs(original) do
    if type(value) == "table" then
      if current_depth < max_depth then
        copied[key] = copyTable(value, {}, cache, max_depth, current_depth + 1)
      end
    elseif type(value) == "userdata" then
      copied[key] = tostring(value)
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
        elseif type(original) == "userdata" then
          args[i] = tostring(original)
        elseif type(original) ~= "function" then
          args[i] = original
        end
      end

      sock:send(cjson.encode({ event = event[1] .. (event[2] and ":" .. event[2] or ""), args = args }) .. "\n")
      return nil, true --continue
    end)
  end
end
