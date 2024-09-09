------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local cjson = require("cjson.safe")


----------------
-- DNS-record mocking.
-- These function allow to create mock dns records that the test Kong instance
-- will use to resolve names. The created mocks are injected by the `start_kong`
-- function.
-- @usage
-- -- Create a new DNS mock and add some DNS records
-- local fixtures = {
--   dns_mock = helpers.dns_mock.new { mocks_only = true }
-- }
--
-- fixtures.dns_mock:SRV {
--   name = "my.srv.test.com",
--   target = "a.my.srv.test.com",
--   port = 80,
-- }
-- fixtures.dns_mock:SRV {
--   name = "my.srv.test.com",     -- adding same name again: record gets 2 entries!
--   target = "b.my.srv.test.com", -- a.my.srv.test.com and b.my.srv.test.com
--   port = 8080,
-- }
-- fixtures.dns_mock:A {
--   name = "a.my.srv.test.com",
--   address = "127.0.0.1",
-- }
-- fixtures.dns_mock:A {
--   name = "b.my.srv.test.com",
--   address = "127.0.0.1",
-- }
-- @section DNS-mocks


local dns_mock = {}


dns_mock.__index = dns_mock
dns_mock.__tostring = function(self)
  -- fill array to prevent json encoding errors
  local out = {
    mocks_only = self.mocks_only,
    records = {}
  }
  for i = 1, 33 do
    out.records[i] = self[i] or {}
  end
  local json = assert(cjson.encode(out))
  return json
end


local TYPE_A, TYPE_AAAA, TYPE_CNAME, TYPE_SRV = 1, 28, 5, 33


--- Creates a new DNS mock.
-- The options table supports the following fields:
--
-- - `mocks_only`: boolean, if set to `true` then only mock records will be
--   returned. If `falsy` it will fall through to an actual DNS lookup.
-- @function dns_mock.new
-- @param options table with mock options
-- @return dns_mock object
-- @usage
-- local mock = helpers.dns_mock.new { mocks_only = true }
function dns_mock.new(options)
  return setmetatable(options or {}, dns_mock)
end


--- Adds an SRV record to the DNS mock.
-- Fields `name`, `target`, and `port` are required. Other fields get defaults:
--
-- * `weight`; 20
-- * `ttl`; 600
-- * `priority`; 20
-- @param rec the mock DNS record to insert
-- @return true
function dns_mock:SRV(rec)
  if self == dns_mock then
    error("can't operate on the class, you must create an instance", 2)
  end
  if getmetatable(self or {}) ~= dns_mock then
    error("SRV method must be called using the colon notation", 2)
  end
  assert(rec, "Missing record parameter")
  local name = assert(rec.name, "No name field in SRV record")

  self[TYPE_SRV] = self[TYPE_SRV] or {}
  local query_answer = self[TYPE_SRV][name]
  if not query_answer then
    query_answer = {}
    self[TYPE_SRV][name] = query_answer
  end

  table.insert(query_answer, {
    type = TYPE_SRV,
    name = name,
    target = assert(rec.target, "No target field in SRV record"),
    port = assert(rec.port, "No port field in SRV record"),
    weight = rec.weight or 10,
    ttl = rec.ttl or 600,
    priority = rec.priority or 20,
    class = rec.class or 1
  })
  return true
end


--- Adds an A record to the DNS mock.
-- Fields `name` and `address` are required. Other fields get defaults:
--
-- * `ttl`; 600
-- @param rec the mock DNS record to insert
-- @return true
function dns_mock:A(rec)
  if self == dns_mock then
    error("can't operate on the class, you must create an instance", 2)
  end
  if getmetatable(self or {}) ~= dns_mock then
    error("A method must be called using the colon notation", 2)
  end
  assert(rec, "Missing record parameter")
  local name = assert(rec.name, "No name field in A record")

  self[TYPE_A] = self[TYPE_A] or {}
  local query_answer = self[TYPE_A][name]
  if not query_answer then
    query_answer = {}
    self[TYPE_A][name] = query_answer
  end

  table.insert(query_answer, {
    type = TYPE_A,
    name = name,
    address = assert(rec.address, "No address field in A record"),
    ttl = rec.ttl or 600,
    class = rec.class or 1
  })
  return true
end


--- Adds an AAAA record to the DNS mock.
-- Fields `name` and `address` are required. Other fields get defaults:
--
-- * `ttl`; 600
-- @param rec the mock DNS record to insert
-- @return true
function dns_mock:AAAA(rec)
  if self == dns_mock then
    error("can't operate on the class, you must create an instance", 2)
  end
  if getmetatable(self or {}) ~= dns_mock then
    error("AAAA method must be called using the colon notation", 2)
  end
  assert(rec, "Missing record parameter")
  local name = assert(rec.name, "No name field in AAAA record")

  self[TYPE_AAAA] = self[TYPE_AAAA] or {}
  local query_answer = self[TYPE_AAAA][name]
  if not query_answer then
    query_answer = {}
    self[TYPE_AAAA][name] = query_answer
  end

  table.insert(query_answer, {
    type = TYPE_AAAA,
    name = name,
    address = assert(rec.address, "No address field in AAAA record"),
    ttl = rec.ttl or 600,
    class = rec.class or 1
  })
  return true
end


--- Adds a CNAME record to the DNS mock.
-- Fields `name` and `cname` are required. Other fields get defaults:
--
-- * `ttl`; 600
-- @param rec the mock DNS record to insert
-- @return true
function dns_mock:CNAME(rec)
  if self == dns_mock then
    error("can't operate on the class, you must create an instance", 2)
  end
  if getmetatable(self or {}) ~= dns_mock then
    error("CNAME method must be called using the colon notation", 2)
  end
  assert(rec, "Missing record parameter")
  local name = assert(rec.name, "No name field in CNAME record")

  self[TYPE_CNAME] = self[TYPE_CNAME] or {}
  local query_answer = self[TYPE_CNAME][name]
  if not query_answer then
    query_answer = {}
    self[TYPE_CNAME][name] = query_answer
  end

  table.insert(query_answer, {
    type = TYPE_CNAME,
    name = name,
    cname = assert(rec.cname, "No cname field in CNAME record"),
    ttl = rec.ttl or 600,
    class = rec.class or 1
  })
  return true
end


return dns_mock
