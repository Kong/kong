--- test helper methods for DNS and load-balancers
-- @module spec.helpers.dns

local _M = {}


if ngx then
  _M.gettime = ngx.now
  _M.sleep = ngx.sleep
else
  local socket = require("socket")
  _M.gettime = socket.gettime
  _M.sleep = socket.sleep
end
local gettime = _M.gettime


--- Iterator over different balancer types.
-- returns; consistent-hash, round-robin, least-conn
-- @return `algorithm_name`, `balancer_module`
function _M.balancer_types()
  local b_types = {
    -- algorithm             name
    { "consistent-hashing", "consistent_hashing" },
    { "round-robin",        "round_robin" },
    { "least-connections",  "least_connections" },
  }
  local i = 0
  return function()
           i = i + 1
           if b_types[i] then
             return b_types[i][1], require("resty.dns.balancer." .. b_types[i][2])
           end
         end
end


--- Expires a record now.
-- @param record a DNS record previously created
function _M.dnsExpire(client, record)
  local dnscache = client.getcache()
  dnscache:delete(record[1].name .. ":" .. record[1].type)
  dnscache:delete(record[1].name .. ":-1")  -- A/AAAA
  record.expire = gettime() - 1
end


--- Creates an SRV record in the cache.
-- @tparam dnsclient client the dns client in which cache it is to be stored
-- @tparam table records a single entry, or a list of entries for the hostname
-- @tparam[opt=4] number staleTtl the staleTtl to use for the record TTL (see Kong config reference for description)
-- @usage
-- local host = "konghq.com"  -- must be the same for all entries obviously...
-- local rec = dnsSRV(dnsCLient, {
--   -- defaults: weight = 10, priority = 20, ttl = 600
--   { name = host, target = "20.20.20.20", port = 80, weight = 10, priority = 20, ttl = 600 }, 
--   { name = host, target = "50.50.50.50", port = 80, weight = 10, priority = 20, ttl = 600 },
-- })
function _M.dnsSRV(client, records, staleTtl)
  local dnscache = client.getcache()
  -- if single table, then insert into a new list
  if not records[1] then records = { records } end

  for _, record in ipairs(records) do
    record.type = client.TYPE_SRV

    -- check required input
    assert(record.target, "target field is required for SRV record")
    assert(record.name, "name field is required for SRV record")
    assert(record.port, "port field is required for SRV record")
    record.name = record.name:lower()

    -- optionals, insert defaults
    record.weight = record.weight or 10
    record.ttl = record.ttl or 600
    record.priority = record.priority or 20
    record.class = record.class or 1
  end
  -- set timeouts
  records.touch = gettime()
  records.expire = gettime() + records[1].ttl
  records.ttl = records[1].ttl

  -- create key, and insert it

  -- for orignal dns client
  local key = records[1].type..":"..records[1].name
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))
  -- insert last-succesful lookup type
  dnscache:set(records[1].name, records[1].type)

  -- for new dns client
  local key = records[1].name..":"..records[1].type
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))

  return records
end


--- Creates an A record in the cache.
-- @tparam dnsclient client the dns client in which cache it is to be stored
-- @tparam table records a single entry, or a list of entries for the hostname
-- @tparam[opt=4] number staleTtl the staleTtl to use for the record TTL (see Kong config reference for description)
-- @usage
-- local host = "konghq.com"  -- must be the same for all entries obviously...
-- local rec = dnsSRV(dnsCLient, {
--   -- defaults: ttl = 600
--   { name = host, address = "20.20.20.20", ttl = 600 },
--   { name = host, address = "50.50.50.50", ttl = 600 },
-- })
function _M.dnsA(client, records, staleTtl)
  local dnscache = client.getcache()
  -- if single table, then insert into a new list
  if not records[1] then records = { records } end

  for _, record in ipairs(records) do
    record.type = client.TYPE_A

    -- check required input
    assert(record.address, "address field is required for A record")
    assert(record.name, "name field is required for A record")
    record.name = record.name:lower()

    -- optionals, insert defaults
    record.ttl = record.ttl or 600
    record.class = record.class or 1
  end
  -- set timeouts
  records.touch = gettime()
  records.expire = gettime() + records[1].ttl
  records.ttl = records[1].ttl

  -- create key, and insert it

  -- for original dns client
  local key = records[1].type..":"..records[1].name
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))
  -- insert last-succesful lookup type
  dnscache:set(records[1].name, records[1].type)

  -- for new dns client
  local key = records[1].name..":"..records[1].type
  dnscache:set(key, records, records[1].ttl)
  key = records[1].name..":-1"  -- A/AAAA
  dnscache:set(key, records, records[1].ttl)

  return records
end


--- Creates an AAAA record in the cache.
-- @tparam dnsclient client the dns client in which cache it is to be stored
-- @tparam table records a single entry, or a list of entries for the hostname
-- @tparam[opt=4] number staleTtl the staleTtl to use for the record TTL (see Kong config reference for description)
-- @usage
-- local host = "konghq.com"  -- must be the same for all entries obviously...
-- local rec = dnsSRV(dnsCLient, {
--   -- defaults: ttl = 600
--   { name = host, address = "::1", ttl = 600 },
-- })
function _M.dnsAAAA(client, records, staleTtl)
  local dnscache = client.getcache()
  -- if single table, then insert into a new list
  if not records[1] then records = { records } end

  for _, record in ipairs(records) do
    record.type = client.TYPE_AAAA

    -- check required input
    assert(record.address, "address field is required for AAAA record")
    assert(record.name, "name field is required for AAAA record")
    record.name = record.name:lower()

    -- optionals, insert defaults
    record.ttl = record.ttl or 600
    record.class = record.class or 1
  end
  -- set timeouts
  records.touch = gettime()
  records.expire = gettime() + records[1].ttl
  records.ttl = records[1].ttl

  -- create key, and insert it

  -- for orignal dns client
  local key = records[1].type..":"..records[1].name
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))
  -- insert last-succesful lookup type
  dnscache:set(records[1].name, records[1].type)

  -- for new dns client
  local key = records[1].name..":"..records[1].type
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))
  key = records[1].name..":-1" -- A/AAAA
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))

  return records
end


return _M
