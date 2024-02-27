-- vim: ts=4 sts=4 sw=4 et:

local utils = require("kong.resty.dns_client.utils")
local mlcache = require("kong.resty.mlcache")
local resolver = require("resty.dns.resolver")

local now = ngx.now
local log = ngx.log
local WARN = ngx.WARN
local ALERT = ngx.ALERT
local math_min = math.min
local timer_at = ngx.timer.at
local table_insert = table.insert
local ipv6_bracket = utils.ipv6_bracket

-- debug
--[[
local json = require("cjson").encode
local logt = table_insert
local logt = function (...) end
]]

-- Constants and default values
local DEFAULT_ERROR_TTL = 1     -- unit: second
local DEFAULT_STALE_TTL = 4
local DEFAULT_EMPTY_TTL = 30

local DEFAULT_ORDER = { "LAST", "SRV", "A", "AAAA", "CNAME" }

local TYPE_SRV      = resolver.TYPE_SRV
local TYPE_A        = resolver.TYPE_A
local TYPE_AAAA     = resolver.TYPE_AAAA
local TYPE_CNAME    = resolver.TYPE_CNAME
local TYPE_LAST     = -1

local valid_type_names = {
    SRV     = TYPE_SRV,
    A       = TYPE_A,
    AAAA    = TYPE_AAAA,
    CNAME   = TYPE_CNAME,
    LAST    = TYPE_LAST,
}

local hitstrs = {
    [1] = "hit_lru",
    [2] = "hit_shm",
}

local errstrs = {     -- client specific errors
    [100] = "cache only lookup failed",
    [101] = "no available records",
}

local EMPTY_ANSWERS = { errcode = 3, errstr = "name error" }


-- APIs
local _M = {}
local mt = { __index = _M }

-- copy TYPE_*
for k,v in pairs(resolver) do
    if type(k) == "string" and k:sub(1,5) == "TYPE_" then
        _M[k] = v
    end
end
_M.TYPE_LAST = -1


local function stats_init(stats, name)
    if not stats[name] then
        stats[name] = {}
    end
end


local function stats_count(stats, name, key)
    stats[name][key] = (stats[name][key] or 0) + 1
end


-- lookup or set TYPE_LAST (the DNS record type from the last successful query)
local valid_types = {
    [ TYPE_SRV ] = true,
    [ TYPE_A ] = true,
    [ TYPE_AAAA ] = true,
    [ TYPE_CNAME ] = true,
}


local function insert_last_type(cache, name, qtype)
    if valid_types[qtype] then
        cache:set("last:" .. name, { ttl = 0 }, qtype)
    end
end


local function get_last_type(cache, name)
    return cache:get("last:" .. name)
end


-- insert hosts into cache
local function init_hosts(cache, path, preferred_ip_type)
    local hosts, err = utils.parse_hosts(path)
    if not hosts then
        log(WARN, "Invalid hosts file: ", err)
        hosts = {}
    end

    if not hosts.localhost then
        hosts.localhost = {
          ipv4 = "127.0.0.1",
          ipv6 = "[::1]",
        }
    end

    local function insert_answer(name, qtype, address)
        if not address then
            return
        end

        local ttl = 10 * 365 * 24 * 60 * 60 -- 10 years ttl for hosts entries

        local key = name .. ":" .. qtype
        local answers = {
            ttl = ttl,
            expire = now() + ttl,
            {
                name = name,
                type = qtype,
                address = address,
                class = 1,
                ttl = ttl,
            },
        }
        cache:set(key, { ttl = ttl }, answers)
    end

    for name, address in pairs(hosts) do
        name = name:lower()
        if address.ipv4 then
            insert_answer(name, TYPE_A, address.ipv4)
            insert_last_type(cache, name, TYPE_A)
        end
        if address.ipv6 then
            insert_answer(name, TYPE_AAAA, address.ipv6)
            if not address.ipv4 or preferred_ip_type == TYPE_AAAA then
                insert_last_type(cache, name, TYPE_AAAA)
            end
        end
    end

    return hosts
end


function _M.new(opts)
    if not opts then
        return nil, "no options table specified"
    end

    local enable_ipv6 = opts.enable_ipv6

    -- parse resolv.conf
    local resolv, err = utils.parse_resolv_conf(opts.resolv_conf, enable_ipv6)
    if not resolv then
        log(WARN, "Invalid resolv.conf: ", err)
        resolv = { options = {} }
    end

	-- init the resolver options for lua-resty-dns
    local nameservers = (opts.nameservers and #opts.nameservers > 0) and
                        opts.nameservers or resolv.nameservers
    if not nameservers or #nameservers == 0 then
        log(WARN, "Invalid configuration, no nameservers specified")
    end

    local r_opts = {
        nameservers = nameservers,
        retrans = opts.retrans or resolv.options.attempts or 5,
        timeout = opts.timeout or resolv.options.timeout or 2000,   -- ms
        no_random = opts.no_random or not resolv.options.rotate,
    }

    -- init the mlcache
    local lock_timeout = r_opts.timeout / 1000 * r_opts.retrans + 1 -- s

    local cache, err = mlcache.new("dns_cache", "kong_dns_cache", {
        lru_size = opts.cache_size or 10000,
        ipc_shm = "kong_dns_cache_ipc",
        resty_lock_opts = {
            timeout = lock_timeout,
            exptimeout = lock_timeout + 1,
        },
        -- miss cache
        shm_miss = "kong_dns_cache_miss",
        neg_ttl = opts.empty_ttl or DEFAULT_EMPTY_TTL,
    })
    if not cache then
        return nil, "could not create mlcache: " .. err
    end

    if opts.cache_purge then
        cache:purge(true)
    end

    -- TODO: add an async task to call cache:update() to update L1/LRU-cache
    -- for the inserted value from other workers

    -- parse order
    local search_types = {}
    local order = opts.order or DEFAULT_ORDER
    local preferred_ip_type
    for _, typstr in ipairs(order) do
        local qtype = valid_type_names[typstr:upper()]
        if not qtype then
            return nil, "Invalid dns record type in order array: " .. typstr
        end
        table_insert(search_types, qtype)
        if (qtype == TYPE_A or qtype == TYPE_AAAA) and not preferred_ip_type then
            preferred_ip_type = qtype
        end
    end
    preferred_ip_type = preferred_ip_type or TYPE_A

    if #search_types == 0 then
        return nil, "Invalid order array: empty record types"
    end

    -- parse hosts
    local hosts = init_hosts(cache, opts.hosts, preferred_ip_type)

    return setmetatable({
        r_opts = r_opts,
        cache = cache,
        valid_ttl = opts.valid_ttl,
        error_ttl = opts.error_ttl or DEFAULT_ERROR_TTL,
        stale_ttl = opts.stale_ttl or DEFAULT_STALE_TTL,
        empty_ttl = opts.empty_ttl or DEFAULT_EMPTY_TTL,
        resolv = opts._resolv or resolv,
        hosts = hosts,
        enable_ipv6 = enable_ipv6,
        search_types = search_types,
        stats = {}
    }, mt)
end


local function process_answers(self, qname, qtype, answers)
    local errcode = answers.errcode
    if errcode then
        answers.ttl = errcode == 3 and self.empty_ttl or self.error_ttl
        -- For compatibility, the balancer subsystem needs to use this field.
        answers.expire = now() + answers.ttl
        return answers
    end

    local processed_answers = {}
    local cname_answer

    local ttl = self.valid_ttl or 0xffffffff

    for _, answer in ipairs(answers) do
        answer.name = answer.name:lower()

        if answer.type == TYPE_CNAME then
            cname_answer = answer   -- use the last one as the real cname

        elseif answer.type == qtype then
            -- A compromise regarding https://github.com/Kong/kong/pull/3088
            if answer.type == TYPE_AAAA then
                answer.address = ipv6_bracket(answer.address)
            elseif answer.type == TYPE_SRV then
                answer.target = ipv6_bracket(answer.target)
            end

            table.insert(processed_answers, answer)
        end

        if self.valid_ttl then
            answer.ttl = self.valid_ttl
        else
            ttl = math_min(ttl, answer.ttl)
        end
    end

    if #processed_answers == 0 then
        if not cname_answer then
            return {
                errcode = 101,
                errstr = errstrs[101],
                ttl = self.empty_ttl,
                --expire = now() + self.empty_ttl,
            }
        end

        table_insert(processed_answers, cname_answer)
    end

    processed_answers.ttl = ttl
    processed_answers.expire = now() + ttl

    return processed_answers
end


local function resolve_query(self, name, qtype, tries)
    -- logt(tries, "query")

    local key = name .. ":" .. qtype
    stats_count(self.stats, key, "query")

    local r, err = resolver:new(self.r_opts)
    if not r then
        return nil, "failed to instantiate the resolver: " .. err
    end

    local options = { additional_section = true, qtype = qtype }
    local answers, err = r:query(name, options)
    if r.destroy then
        r:destroy()
    end

    if not answers then
        stats_count(self.stats, key, "query_fail")
        return nil, "DNS server error: " .. (err or "unknown")
    end

    answers = process_answers(self, name, qtype, answers)

    stats_count(self.stats, key, answers.errstr and
                                 "query_err:" .. answers.errstr or "query_succ")

    -- logt(tries, answers.errstr or #answers)

    return answers, nil, answers.ttl
end


local function start_stale_update_task(self, key, name, qtype)
    stats_count(self.stats, key, "stale")

    timer_at(0, function (premature)
        if premature then return end

        local answers = resolve_query(self, name, qtype, {})
        if answers and (not answers.errcode or answers.errcode == 3) then
            self.cache:set(key, { ttl = answers.ttl },
                           answers.errcode == 3 and nil or answers)
            insert_last_type(self.cache, name, qtype)
        end
    end)
end


local function resolve_name_type_callback(self, name, qtype, opts, tries)
    local key = name .. ":" .. qtype

    local ttl, _, answers = self.cache:peek(key, true)
    if answers and ttl and not answers.expired then
        ttl = ttl + self.stale_ttl
        if ttl > 0 then
            start_stale_update_task(self, key, name, qtype)
            answers.expire = now() + ttl
            answers.expired = true
            answers.ttl = ttl
            return answers, nil, ttl
        end
    end

    if opts.cache_only then
        return { errcode = 100, errstr = errstrs[100] }, nil, -1
    end

    local answers, err, ttl = resolve_query(self, name, qtype, tries)

    if answers and answers.errcode == 3 then
        return nil  -- empty record for shm_miss cache
    end

    return answers, err, ttl
end


local function detect_recursion(opts, key)
    local rn = opts.resolved_names
    if not rn then
        rn = {}
        opts.resolved_names = rn
    end
    local detected = rn[key]
    -- TODO delete
    if detected then
        log(ALERT, "detect recursion for name:", key)
    end
    rn[key] = true
    return detected
end


local function resolve_name_type(self, name, qtype, opts, tries)
    local key = name .. ":" .. qtype

    stats_init(self.stats, key)
    -- logt(tries, key)

    if detect_recursion(opts, key) then
        stats_count(self.stats, key, "fail_recur")
        return nil, "recursion detected for name: " .. key
    end

    local answers, err, hit_level = self.cache:get(key, nil,
                                                resolve_name_type_callback,
                                                self, name, qtype, opts, tries)
    if err and err:sub(1, #"callback") == "callback" then
        log(ALERT, err)
    end

    if not answers and not err then
        answers = EMPTY_ANSWERS
    end

    if hit_level and hit_level < 3 then
        stats_count(self.stats, key, hitstrs[hit_level])
        -- logt(tries, hitstrs[hit_level])
    end

    if err or answers.errcode then
        err = err or ("dns server error: %s %s"):format(answers.errcode, answers.errstr)
        table_insert(tries, { name, qtype, err })
    end

    return answers, err
end


local function get_search_types(self, name, qtype)
    local input_types = qtype and { qtype } or self.search_types
    local checked_types = {}
    local types = {}

    for _, qtype in ipairs(input_types) do
        if qtype == TYPE_LAST then
            qtype = get_last_type(self.cache, name)
        end
        if qtype and not checked_types[qtype] then
            table.insert(types, qtype)
            checked_types[qtype] = true
        end
    end

    return types
end


local function check_and_get_ip_answers(name)
    if name:match("^%d+%.%d+%.%d+%.%d+$") then  -- IPv4
        return {{ name = name, class = 1, type = TYPE_A, address = name }}
    end

    if name:match(":") then                     -- IPv6
        return {{ name = name, class = 1, type = TYPE_AAAA, address = ipv6_bracket(name) }}
    end

    return nil
end


local function resolve_names_and_types(self, name, opts, tries)
    local answers = check_and_get_ip_answers(name)
    if answers then
        answers.ttl = 10 * 365 * 24 * 60 * 60
        answers.expire = now() + answers.ttl
        return answers, nil, tries
    end

    local types = get_search_types(self, name, opts.qtype)
    local names = utils.search_names(name, self.resolv, self.hosts)

    local err
    for _, qtype in ipairs(types) do
        for _, qname in ipairs(names) do
            answers, err = resolve_name_type(self, qname, qtype, opts, tries)

            -- severe error occurred
            if not answers then
                return nil, err, tries
            end

            if not answers.errcode then
                insert_last_type(self.cache, qname, qtype) -- cache TYPE_LAST
                return answers, nil, tries
            end
        end
    end

    -- not found in the search iteration
    return nil, err, tries
end


local function resolve_all(self, name, opts, tries)
    local key = "short:" .. name .. ":" .. (opts.qtype or "all")
    -- logt(tries, key)

    stats_init(self.stats, name)
    stats_count(self.stats, name, "runs")

    if detect_recursion(opts, key) then
        stats_count(self.stats, name, "fail_recur")
        return nil, "recursion detected for name: " .. name
    end

    -- lookup fastly with the key `short:<qname>:<qtype>/all`
    local answers, err, hit_level = self.cache:get(key)
    if not answers or answers.expired then
        stats_count(self.stats, name, "miss")

        answers, err, tries = resolve_names_and_types(self, name, opts, tries)
        if not opts.cache_only and answers then
            --assert(answers.ttl)
            --assert(answers.expire)
            self.cache:set(key, { ttl = answers.ttl }, answers)
        end

    else
        stats_count(self.stats, name, hitstrs[hit_level])
        -- logt(tries, hitstrs[hit_level])
    end

    -- dereference CNAME
    if opts.qtype ~= TYPE_CNAME and answers and answers[1].type == TYPE_CNAME then
        -- logt(tries, "cname")
        stats_count(self.stats, name, "cname")
        return resolve_all(self, answers[1].cname, opts, tries)
    end

    stats_count(self.stats, name, answers and "succ" or "fail")

    return answers, err, tries
end


-- resolve all `name`s and `type`s combinations and return first usable answers
--   `name`s: produced by resolv.conf options: `search`, `ndots` and `domain`
--   `type`s: SRV, A, AAAA, CNAME
--
-- @opts:
--   `return_random`: default `false`, return only one random IP address
--   `cache_only`: default `false`, retrieve data only from the internal cache
--   `qtype`: specified query type instead of its own search types
function _M:resolve(name, opts, tries)
    name = name:lower()
    opts = opts or {}
    tries = tries or {}

    local answers, err, tries = resolve_all(self, name, opts, tries)
    if not answers or not opts.return_random then
        return answers, err, tries
    end

    -- option: return_random
    if answers[1].type == TYPE_SRV then
        local answer = utils.get_wrr_ans(answers)
        opts.port = answer.port ~= 0 and answer.port or opts.port
        -- TODO: SRV recursive name and target how to handle
        return self:resolve(answer.target, opts, tries)
    end

    return utils.get_rr_ans(answers).address, opts.port, tries
end


-- compatible with original DNS client library
-- These APIs will be deprecated if fully replacing the original one.
local dns_client

function _M.init(opts)
    opts = opts or {}
    opts.valid_ttl = opts.validTtl
    opts.error_ttl = opts.badTtl
    opts.stale_ttl = opts.staleTtl
    opts.cache_size = opts.cacheSize

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
    local opts = { cache_only = cache_only }
    return dns_client:_resolve(name, opts, tries)
end


function _M.toip(name, port, cache_only, tries)
    local opts = { cache_only = cache_only, return_random = true , port = port }
    return dns_client:_resolve(name, opts, tries)
end


-- For testing

if package.loaded.busted then
    function _M.getobj()
        return dns_client
    end
    function _M.getcache()
        return {
            set = function (self, k, v, ttl)
                self.cache:set(k, {ttl = ttl or 0}, v)
            end,
            cache = dns_client.cache,
        }
    end
    function _M:insert_last_type(name, qtype)
        insert_last_type(self.cache, name, qtype)
    end
    function _M:get_last_type(name)
        return get_last_type(self.cache, name)
    end
    _M._init = _M.init
    function _M.init(opts)
        opts = opts or {}
        opts.cache_purge = true
        return _M._init(opts)
    end
end


return _M
