-- Mock for the underlying 'resty.dns.resolver' library
-- (so NOT the Kong dns client)

-- this file should be in the Kong working directory (prefix)
local MOCK_RECORD_FILENAME = "dns_mock_records.json"


local LOG_PREFIX = "[mock_dns_resolver] "
local cjson = require "cjson.safe"

-- first thing is to get the original (non-mock) resolver
local resolver
do
  local function get_source_path()
    -- find script path remember to strip off the starting @
    -- should be like: 'spec/fixtures/mocks/lua-resty-dns/resty/dns/resolver.lua'
    return debug.getinfo(2, "S").source:sub(2)  --only works in a function, hence the wrapper
  end
  local path = get_source_path()

  -- module part is like: 'resty.dns.resolver'
  local module_part = select(1,...)

  -- create the packagepath part, like: 'spec/fixtures/mocks/lua-resty-dns/?.lua'
  path = path:gsub(module_part:gsub("%.", "/"), "?") .. ";" -- prefix path, so semi-colon at end

  -- grab current paths
  local old_paths = package.path

  -- drop the element that picked this mock from the path
  local s, e = old_paths:find(path, 1, true)
  package.path = old_paths:sub(1, s-1) .. old_paths:sub(e + 1, -1)

  -- With the mock out of the path, require the module again to get the original.
  -- Problem is that package.loaded contains a userdata now, because we're in
  -- the middle of loading that same module name. So swap it.
  local swap
  swap, package.loaded[module_part] = package.loaded[module_part], nil
  resolver = require(module_part)
  package.loaded[module_part] = swap

  -- restore the package path
  package.path = old_paths
end


-- load and cache the mock-records
local get_mock_records
do
  local mock_file
  get_mock_records = function()
    if mock_file then
      return mock_file.records, mock_file.mocks_only
    end

    local is_file = require("pl.path").isfile
    local prefix = ((kong or {}).configuration or {}).prefix
    if not prefix then
      -- we might be invoked before the Kong config was loaded, so exit early
      -- and do not set _mock_records yet.
      return {}
    end

    local filename = prefix .. "/" .. MOCK_RECORD_FILENAME

    mock_file = {}
    if not is_file(filename) then
      -- no mock records set up, return empty default
      ngx.log(ngx.DEBUG, LOG_PREFIX, "bypassing mock, no mock records found")
      return mock_file
    end

    -- there is a file with mock records available, go load it
    local f = assert(io.open(filename))
    local json_file = assert(f:read("*a"))
    f:close()

    mock_file = assert(cjson.decode(json_file))
    return mock_file.records, mock_file.mocks_only
  end
end


-- patch the actual query method
local old_query = resolver.query
resolver.query = function(self, name, options, tries)
  local mock_records, mocks_only = get_mock_records()
  local qtype = (options or {}).qtype or resolver.TYPE_A

  local answer = (mock_records[qtype] or {})[name]
  if answer then
    -- we actually have a mock answer, return it
    ngx.log(ngx.DEBUG, LOG_PREFIX, "serving '", name, "' from mocks")
    return answer, nil, tries
  end

  if not mocks_only then
    -- no mock, so invoke original resolver
    local a, b, c = old_query(self, name, options, tries)
    return a, b, c
  end
end

-- do
--   local semaphore = require "ngx.semaphore"
--   local old_post = semaphore.post
--   function semaphore.post(self, n)
--     old_post(self, n)
--     ngx.sleep(0)
--   end
-- end


return resolver
