-- test helper methods

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


-- iterator over different balancer types
-- @return algorithm_name, balancer_module
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


-- expires a record now
function _M.dnsExpire(record)
  record.expire = gettime() - 1
end


-- creates an SRV record in the cache
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

  -- create key, and insert it
  local key = records[1].type..":"..records[1].name
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))
  -- insert last-succesful lookup type
  dnscache:set(records[1].name, records[1].type)
  return records
end


-- creates an A record in the cache
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

  -- create key, and insert it
  local key = records[1].type..":"..records[1].name
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))
  -- insert last-succesful lookup type
  dnscache:set(records[1].name, records[1].type)
  return records
end


-- creates an AAAA record in the cache
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

  -- create key, and insert it
  local key = records[1].type..":"..records[1].name
  dnscache:set(key, records, records[1].ttl + (staleTtl or 4))
  -- insert last-succesful lookup type
  dnscache:set(records[1].name, records[1].type)
  return records
end


return _M
