local cjson = require("cjson.safe")
local utils = require("kong.dns.utils")
local stats = require("kong.dns.stats")
local mlcache = require("kong.resty.mlcache")
local resolver = require("resty.dns.resolver")

local now = ngx.now
local log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN
local NOTICE = ngx.NOTICE
local DEBUG = ngx.DEBUG
local ALERT = ngx.ALERT
local timer_at = ngx.timer.at
local worker_id = ngx.worker.id

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local setmetatable = setmetatable

local math_min = math.min
local math_floor = math.floor
local string_lower = string.lower
local table_insert = table.insert
local table_isempty = require("table.isempty")

local is_srv = utils.is_srv
local parse_hosts = utils.parse_hosts
local ipv6_bracket = utils.ipv6_bracket
local search_names = utils.search_names
local parse_resolv_conf = utils.parse_resolv_conf
local get_next_round_robin_answer = utils.get_next_round_robin_answer
local get_next_weighted_round_robin_answer = utils.get_next_weighted_round_robin_answer

local req_dyn_hook_run_hook = require("kong.dynamic_hook").run_hook


-- Constants and default values

local PREFIX = "[dns_client] "

local DEFAULT_ERROR_TTL = 1     -- unit: second
local DEFAULT_STALE_TTL = 3600
-- long-lasting TTL of 10 years for hosts or static IP addresses in cache settings
local LONG_LASTING_TTL = 10 * 365 * 24 * 60 * 60

local DEFAULT_FAMILY = { "SRV", "A", "AAAA" }

local TYPE_SRV = resolver.TYPE_SRV
local TYPE_A = resolver.TYPE_A
local TYPE_AAAA = resolver.TYPE_AAAA
local TYPE_A_OR_AAAA = -1  -- used to resolve IP addresses for SRV targets

local TYPE_TO_NAME = {
  [TYPE_SRV] = "SRV",
  [TYPE_A] = "A",
  [TYPE_AAAA] = "AAAA",
  [TYPE_A_OR_AAAA] = "A/AAAA",
}

local HIT_L3 = 3 -- L1 lru, L2 shm, L3 callback, L4 stale

local HIT_LEVEL_TO_NAME = {
  [1] = "hit_lru",
  [2] = "hit_shm",
  [3] = "miss",
  [4] = "hit_stale",
}

-- client specific error
local CACHE_ONLY_ERROR_CODE = 100
local CACHE_ONLY_ERROR_MESSAGE = "cache only lookup failed"
local CACHE_ONLY_ANSWERS = {
  errcode = CACHE_ONLY_ERROR_CODE,
  errstr = CACHE_ONLY_ERROR_MESSAGE,
}

local EMPTY_RECORD_ERROR_CODE = 101
local EMPTY_RECORD_ERROR_MESSAGE = "empty record received"


-- APIs

local _M = {
  TYPE_SRV = TYPE_SRV,
  TYPE_A = TYPE_A,
  TYPE_AAAA = TYPE_AAAA,
}
local _MT = { __index = _M, }


local _TRIES_MT = { __tostring = cjson.encode, }


local init_hosts do
  local function insert_answer_into_cache(cache, hosts_cache, address, name, qtype)
    local answers = {
      ttl = LONG_LASTING_TTL,
      expire = now() + LONG_LASTING_TTL,
      {
        name = name,
        type = qtype,
        address = address,
        class = 1,
        ttl = LONG_LASTING_TTL,
      },
    }

    hosts_cache[name .. ":" .. qtype] = answers
    hosts_cache[name .. ":" .. TYPE_A_OR_AAAA] = answers
  end

  -- insert hosts into cache
  function init_hosts(cache, path)
    local hosts = parse_hosts(path)
    local hosts_cache = {}

    for name, address in pairs(hosts) do
      name = string_lower(name)

      if address.ipv6 then
        insert_answer_into_cache(cache, hosts_cache, address.ipv6, name, TYPE_AAAA)
      end

      if address.ipv4 then
        insert_answer_into_cache(cache, hosts_cache, address.ipv4, name, TYPE_A)
      end
    end

    return hosts, hosts_cache
  end
end


-- distinguish the worker_events sources registered by different new() instances
local ipc_counter = 0

function _M.new(opts)
  opts = opts or {}

  local enable_ipv4, enable_ipv6, enable_srv

  for _, typstr in ipairs(opts.family or DEFAULT_FAMILY) do
    typstr = typstr:upper()

    if typstr == "A" then
      enable_ipv4 = true

    elseif typstr == "AAAA" then
      enable_ipv6 = true

    elseif typstr == "SRV" then
      enable_srv = true

    else
      return nil, "Invalid dns type in dns_family array: " .. typstr
    end
  end

  log(NOTICE, PREFIX, "supported types: ", enable_srv and "srv " or "",
              enable_ipv4 and "ipv4 " or "", enable_ipv6 and "ipv6 " or "")

  -- parse resolv.conf
  local resolv, err = parse_resolv_conf(opts.resolv_conf, opts.enable_ipv6)
  if not resolv then
    log(WARN, PREFIX, "Invalid resolv.conf: ", err)
    resolv = { options = {} }
  end

  -- init the resolver options for lua-resty-dns
  local nameservers = (opts.nameservers and not table_isempty(opts.nameservers))
                      and opts.nameservers
                      or resolv.nameservers

  if not nameservers or table_isempty(nameservers) then
    log(WARN, PREFIX, "Invalid configuration, no nameservers specified")
  end

  local no_random

  if opts.random_resolver == nil then
    no_random = not resolv.options.rotate
  else
    no_random = not opts.random_resolver
  end

  local r_opts = {
    retrans = opts.retrans or resolv.options.attempts or 5,
    timeout = opts.timeout or resolv.options.timeout or 2000, -- ms
    no_random = no_random,
    nameservers = nameservers,
  }

  -- init the mlcache

  -- maximum timeout for the underlying r:query() operation to complete
  -- socket timeout * retrans * 2 calls for send and receive + 1s extra delay
  local lock_timeout = r_opts.timeout / 1000 * r_opts.retrans * 2 + 1 -- s

  local resty_lock_opts = {
    timeout = lock_timeout,
    exptimeout = lock_timeout + 1,
  }

  -- TODO: convert the ipc a module constant, currently we need to use the
  --       ipc_source to distinguish sources of different DNS client events.
  ipc_counter = ipc_counter + 1
  local ipc_source = "dns_client_mlcache#" .. ipc_counter
  local ipc = {
    register_listeners = function(events)
      -- The DNS client library will be required in globalpatches before Kong
      -- initializes worker_events.
      if not kong or not kong.worker_events then
        return
      end

      local cwid = worker_id() or -1
      for _, ev in pairs(events) do
        local handler = function(data, event, source, wid)
          if cwid ~= wid then -- Current worker has handled this event.
            ev.handler(data)
          end
        end

        kong.worker_events.register(handler, ipc_source, ev.channel)
      end
    end,

    -- @channel: event channel name, such as "mlcache:invalidate:dns_cache"
    -- @data: mlcache's key name, such as "<qname>:<qtype>"
    broadcast = function(channel, data)
      if not kong or not kong.worker_events then
        return
      end

      local ok, err = kong.worker_events.post(ipc_source, channel, data)
      if not ok then
        log(ERR, PREFIX, "failed to post event '", ipc_source, "', '", channel, "': ", err)
      end
    end,
  }

  local cache, err = mlcache.new("dns_cache", "kong_dns_cache", {
    ipc = ipc,
    neg_ttl = opts.error_ttl or DEFAULT_ERROR_TTL,
    -- 10000 is a reliable and tested value from the original library.
    lru_size = opts.cache_size or 10000,
    shm_locks = ngx.shared.kong_locks and "kong_locks",
    resty_lock_opts = resty_lock_opts,
  })

  if not cache then
    return nil, "could not create mlcache: " .. err
  end

  if opts.cache_purge then
    cache:purge(true)
  end

  -- parse hosts
  local hosts, hosts_cache = init_hosts(cache, opts.hosts)

  return setmetatable({
    cache = cache,
    stats = stats.new(),
    hosts = hosts,
    r_opts = r_opts,
    resolv = opts._resolv or resolv,
    valid_ttl = opts.valid_ttl,
    error_ttl = opts.error_ttl or DEFAULT_ERROR_TTL,
    stale_ttl = opts.stale_ttl or DEFAULT_STALE_TTL,
    enable_srv = enable_srv,
    enable_ipv4 = enable_ipv4,
    enable_ipv6 = enable_ipv6,
    hosts_cache = hosts_cache,

    -- TODO: Make the table readonly. But if `string.buffer.encode/decode` and
    -- `pl.tablex.readonly` are called on it, it will become empty table.
    --
    -- quickly accessible constant empty answers
    EMPTY_ANSWERS = {
      errcode = EMPTY_RECORD_ERROR_CODE,
      errstr = EMPTY_RECORD_ERROR_MESSAGE,
      ttl = opts.error_ttl or DEFAULT_ERROR_TTL,
    },
  }, _MT)
end


local function process_answers(self, qname, qtype, answers)
  local errcode = answers.errcode
  if errcode then
    answers.ttl = self.error_ttl
    return answers
  end

  local processed_answers = {}

  -- 0xffffffff for maximum TTL value
  local ttl = math_min(self.valid_ttl or 0xffffffff, 0xffffffff)

  for _, answer in ipairs(answers) do
    answer.name = string_lower(answer.name)

    if self.valid_ttl then
      answer.ttl = self.valid_ttl
    else
      ttl = math_min(ttl, answer.ttl)
    end

    local answer_type = answer.type

    if answer_type == qtype then
      -- compatible with balancer, see https://github.com/Kong/kong/pull/3088
      if answer_type == TYPE_AAAA then
        answer.address = ipv6_bracket(answer.address)

      elseif answer_type == TYPE_SRV then
        answer.target = ipv6_bracket(answer.target)
      end

      table_insert(processed_answers, answer)
    end
  end

  if table_isempty(processed_answers) then
    log(DEBUG, PREFIX, "processed ans:empty")
    return self.EMPTY_ANSWERS
  end

  log(DEBUG, PREFIX, "processed ans:", #processed_answers)

  processed_answers.expire = now() + ttl
  processed_answers.ttl = ttl

  return processed_answers
end


local function resolve_query(self, name, qtype, tries)
  local key = name .. ":" .. qtype

  local stats = self.stats

  stats:incr(key, "query")

  local r, err = resolver:new(self.r_opts)
  if not r then
    return nil, "failed to instantiate the resolver: " .. err
  end

  local start = now()

  local answers, err = r:query(name, { qtype = qtype })
  r:destroy()

  local duration = math_floor((now() - start) * 1000)

  stats:set(key, "query_last_time", duration)

  log(DEBUG, PREFIX, "r:query(", key, ") ans:", answers and #answers or "-",
                     " t:", duration, " ms")

  -- network error or malformed DNS response
  if not answers then
    stats:incr(key, "query_fail_nameserver")
    err = "DNS server error: " .. tostring(err) .. ", took " .. duration .. " ms"

    -- TODO: make the error more structured, like:
    --       { qname = name, qtype = qtype, error = err, } or something similar
    table_insert(tries, { name .. ":" .. TYPE_TO_NAME[qtype], err })

    return nil, err
  end

  answers = process_answers(self, name, qtype, answers)

  stats:incr(key, answers.errstr and
                  "query_fail:" .. answers.errstr or
                  "query_succ")

  -- DNS response error
  if answers.errcode then
    err = ("dns %s error: %s %s"):format(
            answers.errcode < CACHE_ONLY_ERROR_CODE and "server" or "client",
            answers.errcode, answers.errstr)
    table_insert(tries, { name .. ":" .. TYPE_TO_NAME[qtype], err })
  end

  return answers
end


-- resolve all `name`s and return first usable answers
local function resolve_query_names(self, names, qtype, tries)
  local answers, err

  for _, qname in ipairs(names) do
    answers, err = resolve_query(self, qname, qtype, tries)

    -- severe error occurred
    if not answers then
      return nil, err
    end

    if not answers.errcode then
      return answers, nil, answers.ttl
    end
  end

  -- not found in the search iteration
  return answers, nil, answers.ttl
end


local function resolve_query_types(self, name, qtype, tries)
  local names = search_names(name, self.resolv, self.hosts)
  local answers, err, ttl

  -- the specific type
  if qtype ~= TYPE_A_OR_AAAA then
    return resolve_query_names(self, names, qtype, tries)
  end

  -- query A or AAAA
  if self.enable_ipv4 then
    answers, err, ttl = resolve_query_names(self, names, TYPE_A, tries)
    if not answers or not answers.errcode then
      return answers, err, ttl
    end
  end

  if self.enable_ipv6 then
    answers, err, ttl = resolve_query_names(self, names, TYPE_AAAA, tries)
  end

  return answers, err, ttl
end


local function stale_update_task(premature, self, key, name, qtype)
  if premature then
    return
  end

  local tries = setmetatable({}, _TRIES_MT)
  local answers = resolve_query_types(self, name, qtype, tries)
  if not answers or answers.errcode then
    log(DEBUG, PREFIX, "failed to update stale DNS records: ", tostring(tries))
    return
  end

  log(DEBUG, PREFIX, "update stale DNS records: ", #answers)
  self.cache:set(key, { ttl = answers.ttl }, answers)
end


local function start_stale_update_task(self, key, name, qtype)
  self.stats:incr(key, "stale")

  local ok, err = timer_at(0, stale_update_task, self, key, name, qtype)
  if not ok then
    log(ALERT, PREFIX, "failed to start a timer to update stale DNS records: ", err)
  end
end


local function check_and_get_ip_answers(name)
  -- TODO: use is_valid_ipv4 from kong/tools/ip.lua instead
  if name:match("^%d+%.%d+%.%d+%.%d+$") then  -- IPv4
    return {
      { name = name, class = 1, type = TYPE_A, address = name },
    }
  end

  if name:find(":", 1, true) then             -- IPv6
    return {
      { name = name, class = 1, type = TYPE_AAAA, address = ipv6_bracket(name) },
    }
  end

  return nil
end


local function resolve_callback(self, name, qtype, cache_only, tries)
  -- check if name is ip address
  local answers = check_and_get_ip_answers(name)
  if answers then -- domain name is IP literal
    answers.ttl = LONG_LASTING_TTL
    answers.expire = now() + answers.ttl
    return answers, nil, answers.ttl
  end

  -- check if this key exists in the hosts file (it maybe evicted from cache)
  local key = name .. ":" .. qtype
  local answers = self.hosts_cache[key]
  if answers then
    return answers, nil, answers.ttl
  end

  -- `:peek(stale=true)` verifies if the expired key remains in L2 shm, then
  -- initiates an asynchronous background updating task to refresh it.
  local ttl, _, answers = self.cache:peek(key, true)

  if answers and not answers.errcode and self.stale_ttl and ttl then

    -- `_expire_at` means the final expiration time of stale records
    if not answers._expire_at then
      answers._expire_at = answers.expire + self.stale_ttl
    end

    -- trigger the update task by the upper caller every 60 seconds
    local remaining_stale_ttl = math_min(answers._expire_at - now(), 60)

    if remaining_stale_ttl > 0 then
      log(DEBUG, PREFIX, "start stale update task ", key,
                         " remaining_stale_ttl:", remaining_stale_ttl)

      -- mlcache's internal lock mechanism ensures concurrent control
      start_stale_update_task(self, key, name, qtype)
      answers.ttl = remaining_stale_ttl
      answers.expire = remaining_stale_ttl + now()

      return answers, nil, remaining_stale_ttl
    end
  end

  if cache_only then
    return CACHE_ONLY_ANSWERS, nil, -1
  end

  log(DEBUG, PREFIX, "cache miss, try to query ", key)

  return resolve_query_types(self, name, qtype, tries)
end


local function resolve_all(self, name, qtype, cache_only, tries, has_timing)
  name = string_lower(name)
  tries = setmetatable(tries or {}, _TRIES_MT)

  if not qtype then
    qtype = ((self.enable_srv and is_srv(name)) and TYPE_SRV or TYPE_A_OR_AAAA)
  end

  local key = name .. ":" .. qtype

  log(DEBUG, PREFIX, "resolve_all ", key)

  local stats = self.stats

  stats:incr(key, "runs")

  local answers, err, hit_level = self.cache:get(key, nil, resolve_callback,
                                                 self, name, qtype, cache_only,
                                                 tries)
  -- check for runtime errors in the callback
  if err and err:sub(1, 8) == "callback" then
    log(ALERT, PREFIX, err)
  end

  local hit_str = hit_level and HIT_LEVEL_TO_NAME[hit_level] or "fail"
  stats:incr(key, hit_str)

  log(DEBUG, PREFIX, "cache lookup ", key, " ans:", answers and #answers or "-",
                     " hlv:", hit_str)

  if has_timing then
    req_dyn_hook_run_hook("timing", "dns:cache_lookup",
                          (hit_level and hit_level < HIT_L3))
  end

  if answers and answers.errcode then
    err = ("dns %s error: %s %s"):format(
            answers.errcode < CACHE_ONLY_ERROR_CODE and "server" or "client",
            answers.errcode, answers.errstr)
    return nil, err, tries
  end

  return answers, err, tries
end


function _M:resolve(name, qtype, cache_only, tries)
  return resolve_all(self, name, qtype, cache_only, tries,
                     ngx.ctx and ngx.ctx.has_timing)
end


function _M:resolve_address(name, port, cache_only, tries)
  local has_timing = ngx.ctx and ngx.ctx.has_timing

  local answers, err, tries = resolve_all(self, name, nil, cache_only, tries,
                                          has_timing)

  if answers and answers[1] and answers[1].type == TYPE_SRV then
    local answer = get_next_weighted_round_robin_answer(answers)
    port = answer.port ~= 0 and answer.port or port
    answers, err, tries = resolve_all(self, answer.target, TYPE_A_OR_AAAA,
                                      cache_only, tries, has_timing)
  end

  if not answers then
    return nil, err, tries
  end

  return get_next_round_robin_answer(answers).address, port, tries
end


-- compatible with original DNS client library
-- These APIs will be deprecated if fully replacing the original one.
local dns_client

function _M.init(opts)
  log(DEBUG, PREFIX, "(re)configuring dns client")

  local client, err = _M.new(opts)
  if not client then
    return nil, err
  end

  dns_client = client
  return true
end


-- New and old libraries have the same function name.
_M._resolve = _M.resolve

function _M.resolve(name, r_opts, cache_only, tries)
  return dns_client:_resolve(name, r_opts and r_opts.qtype, cache_only, tries)
end


function _M.toip(name, port, cache_only, tries)
  return dns_client:resolve_address(name, port, cache_only, tries)
end


-- "_ldap._tcp.example.com:33" -> "_ldap._tcp.example.com|SRV"
local function format_key(key)
  local qname, qtype = key:match("^(.+):(%-?%d+)$")  -- match "(qname):(qtype)"
  return qtype and qname .. "|" .. (TYPE_TO_NAME[tonumber(qtype)] or qtype)
               or  key
end


function _M.stats()
  return dns_client.stats:emit(format_key)
end


-- For testing

if package.loaded.busted then
  function _M.getobj()
    return dns_client
  end

  function _M.getcache()
    return {
      set = function(self, k, v, ttl)
        self.cache:set(k, {ttl = ttl or 0}, v)
      end,

      delete = function(self, k)
        self.cache:delete(k)
      end,

      cache = dns_client.cache,
    }
  end
end


return _M
