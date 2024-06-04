-- The test case 04-client_ipc_spec.lua will load this plugin and check its
-- generated error logs.

local DnsClientTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


local log = ngx.log
local ERR = ngx.ERR
local PRE = "dns-client-test:"


local function test()
  local phase = ""
  local host = "ipc.test"

  -- inject resolver.query
  require("resty.dns.resolver").query = function(self, name, opts)
    log(ERR, PRE, phase, "query:", name)
    return {{
      type = opts.qtype,
      address = "1.2.3.4",
      target = "1.2.3.4",
      class = 1,
      name = name,
      ttl = 0.1,
    }}
  end

  local dns_client = require("kong.tools.dns")()
  local cli = dns_client.new({})

  -- inject broadcast
  local orig_broadcast = cli.cache.broadcast
  cli.cache.broadcast = function(channel, data)
    log(ERR, PRE, phase, "broadcast:", data)
    orig_broadcast(channel, data)
  end

  -- inject lrucahce.delete
  local orig_delete = cli.cache.lru.delete
  cli.cache.lru.delete = function(self, key)
    log(ERR, PRE, phase, "lru delete:", key)
    orig_delete(self, key)
  end

  -- phase 1: two processes try to get answers and trigger only one query
  phase = "first:"
  local answers = cli:_resolve(host)
  log(ERR, PRE, phase, "answers:", answers[1].address)

  -- wait records to be stale
  ngx.sleep(0.5)

  -- phase 2: get the stale record and trigger only one stale-updating task,
  --          the stale-updating task will update the record and broadcast
  --          the lru cache invalidation event to other workers
  phase = "stale:"
  local answers = cli:_resolve(host)
  log(ERR, PRE, phase, "answers:", answers[1].address)

  -- tests end
  log(ERR, PRE, "DNS query completed")
end


function DnsClientTestHandler:init_worker()
  ngx.timer.at(0, test)
end


return DnsClientTestHandler
