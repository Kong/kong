-- busted-ci-helper.lua
local busted = require("busted")

local function cleanup()
  local prefix = assert(require("kong.conf_loader")(os.getenv("KONG_SPEC_TEST_CONF_PATH") or "spec/kong_tests.conf")).prefix
  os.remove(prefix .. "/worker_events.sock")
  os.remove(prefix .. "/stream_worker_events.sock")
  local pl_path = require "pl.path"
  local pl_dir = require "pl.dir"
  if pl_path.exists(prefix) and not pl_path.islink(prefix) then
    for root, _, files in pl_dir.walk(prefix, true) do
      if pl_path.islink(root) then
        os.remove(root)
      else
        for _, f in ipairs(files) do
          f = pl_path.join(root,f)
          os.remove(f)
        end
        pl_path.rmdir(root)
      end
    end
  end
  return nil, true --continue
end

busted.subscribe({ "file", "start" }, cleanup)

local busted_event_path = os.getenv("BUSTED_EVENT_PATH")
if not busted_event_path then
  return
end

local cjson = require("cjson")
local socket_unix = require("socket.unix")

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

local sock = assert(socket_unix())
assert(sock:connect(busted_event_path))

local events = {{ "suite", "reset" },
                { "suite", "start" },
                { "suite", "end" },
                { "file", "start" },
                { "file", "end" },
                { "test", "start" },
                { "test", "end" },
                { "pending" },
                { "failure", "it" },
                { "error", "it" },
                { "failure" },
                { "error" }}
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
