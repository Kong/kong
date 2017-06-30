local lrucache = require "resty.lrucache"
local url      = require "socket.url"
local bit      = require "bit"


local re_match = ngx.re.match
local re_find  = ngx.re.find
local re_sub   = ngx.re.sub
local insert   = table.insert
local upper    = string.upper
local lower    = string.lower
local find     = string.find
local fmt      = string.format
local sub      = string.sub
local tonumber = tonumber
local ipairs   = ipairs
local pairs    = pairs
local type     = type
local next     = next
local band     = bit.band
local bor      = bit.bor
local ERR      = ngx.ERR
local log


do
  local ngx_log = ngx.log
  log = function(lvl, ...)
    ngx_log(lvl, "[router] ", ...)
  end
end


local MATCH_LRUCACHE_SIZE = 200


local MATCH_RULES = {
  HOST            = 0x01,
  URI             = 0x02,
  METHOD          = 0x04,
}

local CATEGORIES = {
  bor(MATCH_RULES.HOST,   MATCH_RULES.URI,     MATCH_RULES.METHOD),
  bor(MATCH_RULES.HOST,   MATCH_RULES.URI),
  bor(MATCH_RULES.HOST,   MATCH_RULES.METHOD),
  bor(MATCH_RULES.METHOD, MATCH_RULES.URI),
      MATCH_RULES.HOST,
      MATCH_RULES.URI,
      MATCH_RULES.METHOD,
}

local categories_len = #CATEGORIES

local CATEGORIES_LOOKUP = {}
for i = 1, categories_len do
  CATEGORIES_LOOKUP[CATEGORIES[i]] = i
end


local match_api
local reduce


local function marshall_api(api)
  local api_t             = {
    api                   = api,
    strip_uri             = api.strip_uri,
    preserve_host         = api.preserve_host,
    match_rules           = 0x00,
    hosts                 = {},
    wildcard_hosts        = {},
    uris                  = {},
    uris_prefixes_regexes = {},
    methods               = {},
    upstream              = {},
  }


  -- headers


  if api.headers then
    if type(api.headers) ~= "table" then
      return nil, "headers field must be a table"
    end

    for header_name in pairs(api.headers) do
      if lower(header_name) ~= "host" then
        return nil, "only 'Host' header is supported in headers field, " ..
                    "found: " .. header_name
      end
    end

    local host_values = api.headers["Host"] or api.headers["host"]
    if type(host_values) ~= "table" then
      return nil, "host field must be a table"
    end

    if #host_values > 0 then
      api_t.match_rules = bor(api_t.match_rules, MATCH_RULES.HOST)

      for _, host_value in ipairs(host_values) do
        if find(host_value, "*", nil, true) then
          -- wildcard host matching
          local wildcard_host_regex = host_value:gsub("%.", "\\.")
                                                :gsub("%*", ".+") .. "$"
          insert(api_t.wildcard_hosts, {
            value = host_value,
            regex = wildcard_host_regex
          })
        end

        api_t.hosts[host_value] = true
      end
    end
  end


  -- uris


  if api.uris then
    if type(api.uris) ~= "table" then
      return nil, "uris field must be a table"
    end

    if #api.uris > 0 then
      api_t.match_rules = bor(api_t.match_rules, MATCH_RULES.URI)

      for i, uri in ipairs(api.uris) do
        local escaped_uri = [[\Q]] .. uri .. [[\E]]
        local strip_regex = escaped_uri .. [[\/?(.*)]]

        api_t.uris[uri] = {
          strip_regex = strip_regex,
        }

        api_t.uris_prefixes_regexes[i] = {
          regex       = escaped_uri,
          strip_regex = strip_regex,
        }
      end
    end
  end


  -- methods


  if api.methods then
    if type(api.methods) ~= "table" then
      return nil, "methods field must be a table"
    end

    if #api.methods > 0 then
      api_t.match_rules = bor(api_t.match_rules, MATCH_RULES.METHOD)

      for _, method in ipairs(api.methods) do
        api_t.methods[upper(method)] = true
      end
    end
  end


  -- upstream_url parsing


  if api.upstream_url then
    local parsed = url.parse(api.upstream_url)

    api_t.upstream = {
      scheme       = parsed.scheme,
      host         = parsed.host,
      port         = tonumber(parsed.port),
    }

    if parsed.path then
      api_t.upstream.path = parsed.path
      api_t.upstream.file = sub(parsed.path, -1) == "/" and parsed.path ~= "/" and
                            sub(parsed.path,  1, -2)     or parsed.path
    end

    if not api_t.upstream.port then
      if parsed.scheme == "https" then
        api_t.upstream.port = 443

      else
        api_t.upstream.port = 80
      end
    end
  end


  return api_t
end


local function index_api_t(api_t, plain_indexes, uris_prefixes, wildcard_hosts)
  for host in pairs(api_t.hosts) do
    plain_indexes.hosts[host] = true
  end

  for uri in pairs(api_t.uris) do
    plain_indexes.uris[uri] = true
  end

  for method in pairs(api_t.methods) do
    plain_indexes.methods[method] = true
  end

  for _, wildcard_host in ipairs(api_t.wildcard_hosts) do
    insert(wildcard_hosts, wildcard_host)
  end

  api_t.wildcard_hosts = nil

  for _, uri_prefix_regex in ipairs(api_t.uris_prefixes_regexes) do
    insert(uris_prefixes, uri_prefix_regex.regex)
  end
end


local function categorize_api_t(api_t, categories)
  local category = categories[api_t.match_rules]
  if not category then
    category              = {
      apis_by_plain_hosts = {},
      apis_by_plain_uris  = {},
      apis_by_methods     = {},
      apis                = {},
    }

    categories[api_t.match_rules] = category
  end

  insert(category.apis, api_t)

  for host in pairs(api_t.hosts) do
    if not category.apis_by_plain_hosts[host] then
      category.apis_by_plain_hosts[host] = {}
    end

    insert(category.apis_by_plain_hosts[host], api_t)
  end

  for uri in pairs(api_t.uris) do
    if not category.apis_by_plain_uris[uri] then
      category.apis_by_plain_uris[uri] = {}
    end

    insert(category.apis_by_plain_uris[uri], api_t)
  end

  for method in pairs(api_t.methods) do
    if not category.apis_by_methods[method] then
      category.apis_by_methods[method] = {}
    end

    insert(category.apis_by_methods[method], api_t)
  end
end


do
  local matchers = {
    [MATCH_RULES.HOST] = function(api_t, _, _, host)
      if api_t.hosts[host] then
        return true
      end
    end,

    [MATCH_RULES.URI] = function(api_t, _, uri)
      if api_t.uris[uri] then
        if api_t.strip_uri then
          api_t.strip_uri_regex = api_t.uris[uri].strip_regex
        end

        return true
      end

      for i = 1, #api_t.uris_prefixes_regexes do
        local from, _, err = re_find(uri, api_t.uris_prefixes_regexes[i].regex, "ajo")
        if err then
          log(ERR, "could not search for URI prefix: ", err)
          return
        end

        if from then
          if api_t.strip_uri then
            api_t.strip_uri_regex = api_t.uris_prefixes_regexes[i].strip_regex
          end

          return true
        end
      end
    end,

    [MATCH_RULES.METHOD] = function(api_t, method)
      return api_t.methods[method]
    end
  }


  match_api = function(api_t, method, uri, host)
    -- run cached matcher
    if type(matchers[api_t.match_rules]) == "function" then
      return matchers[api_t.match_rules](api_t, method, uri, host)
    end

    -- build and cache matcher

    local matchers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(api_t.match_rules, bit_match_rule) ~= 0 then
        matchers_set[#matchers_set + 1] = matchers[bit_match_rule]
      end
    end

    matchers[api_t.match_rules] = function(api_t, method, uri, host)
      for i = 1, #matchers_set do
        if not matchers_set[i](api_t, method, uri, host) then
          return
        end
      end

      return true
    end

    return matchers[api_t.match_rules](api_t, method, uri, host)
  end
end


do
  local reducers = {
    [MATCH_RULES.HOST] = function(category, _, _, host)
      return category.apis_by_plain_hosts[host]
    end,

    [MATCH_RULES.URI] = function(category, _, uri)
      return category.apis_by_plain_uris[uri]
    end,

    [MATCH_RULES.METHOD] = function(category, method)
      return category.apis_by_methods[method]
    end,
  }


  reduce = function(category, bit_category, method, uri, host)
    -- run cached reducer
    if type(reducers[bit_category]) == "function" then
      return reducers[bit_category](category, method, uri, host), category.apis
    end

    -- build and cache reducer

    local reducers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(bit_category, bit_match_rule) ~= 0 then
        reducers_set[#reducers_set + 1] = reducers[bit_match_rule]
      end
    end

    reducers[bit_category] = function(category, method, uri, host)
      local min_len = 0
      local smallest_set

      for i = 1, #reducers_set do
        local candidates = reducers_set[i](category, method, uri, host)
        if candidates ~= nil and (not smallest_set or #candidates < min_len) then
          min_len = #candidates
          smallest_set = candidates
        end
      end

      return smallest_set, category.apis
    end

    return reducers[bit_category](category, method, uri, host)
  end
end


local _M = {}


function _M.new(apis)
  if type(apis) ~= "table" then
    return error("expected arg #1 apis to be a table")
  end


  local self = {}


  -- hash table for fast lookup of plain hosts, uris
  -- and methods from incoming requests
  local plain_indexes = {
    hosts             = {},
    uris              = {},
    methods           = {},
  }


  -- when hash lookup in plain_indexes fails, those are arrays
  -- of regexes for `uris` as prefixes and `hosts` as wildcards
  local uris_prefixes  = {}
  local wildcard_hosts = {}


  -- all APIs grouped by the category they belong to, to reduce
  -- iterations over sets of APIs per request
  local categories = {}


  local cache = lrucache.new(MATCH_LRUCACHE_SIZE)


  -- index APIs


  for i = 1, #apis do
    local api_t, err = marshall_api(apis[i])
    if not api_t then
      return nil, err
    end

    index_api_t(api_t, plain_indexes, uris_prefixes, wildcard_hosts)
    categorize_api_t(api_t, categories)
  end


  local function compare_uris_length(a, b, category_bit)
    if not band(category_bit, MATCH_RULES.URI) then
      return
    end

    local max_uri_a = 0
    local max_uri_b = 0

    for _, prefix in ipairs(a.uris_prefixes_regexes) do
      if #prefix.regex > max_uri_a then
        max_uri_a = #prefix.regex
      end
    end

    for _, prefix in ipairs(b.uris_prefixes_regexes) do
      if #prefix.regex > max_uri_b then
        max_uri_b = #prefix.regex
      end
    end

    return max_uri_a > max_uri_b
  end

  table.sort(uris_prefixes, function(a, b)
    return #a > #b
  end)

  for category_bit, category in pairs(categories) do
    table.sort(category.apis, function(a, b)
      return compare_uris_length(a, b, category_bit)
    end)

    for _, apis_by_method in pairs(category.apis_by_methods) do
      table.sort(apis_by_method, function(a, b)
        return compare_uris_length(a, b, category_bit)
      end)
    end

    for _, apis_by_host in pairs(category.apis_by_plain_hosts) do
      table.sort(apis_by_host, function(a, b)
        return compare_uris_length(a, b, category_bit)
      end)
    end
  end


  local grab_host = #wildcard_hosts > 0 or next(plain_indexes.hosts) ~= nil


  local function find_api(method, uri, host)
    if type(method) ~= "string" then
      return error("arg #1 method must be a string")
    end
    if type(uri) ~= "string" then
      return error("arg #2 uri must be a string")
    end
    if host and type(host) ~= "string" then
      return error("arg #3 host must be a string")
    end


    -- input sanitization


    method = upper(method)

    if host then
      -- strip port number if given
      local m, err = re_match(host, "([^:]+)", "ajo")
      if not m then
        log(ERR, "could not strip port from Host header: ", err)
      end

      if m[0] then
        host = m[0]
      end
    end


    -- cache lookup


    local cache_key = fmt("%s:%s:%s", method, uri, host)

    do
      local api_t_from_cache = cache:get(cache_key)
      if api_t_from_cache and match_api(api_t_from_cache, method, uri, host)
      then
        return api_t_from_cache
      end
    end


    -- router, router, which of these APIs is the fairest?
    --
    -- determine which category this request *might* be targeting


    local req_category = 0x00

    if plain_indexes.hosts[host] then
      req_category = bor(req_category, MATCH_RULES.HOST)

    elseif host then
      for i = 1, #wildcard_hosts do
        local from, _, err = re_find(host, wildcard_hosts[i].regex, "ajo")
        if err then
          log(ERR, "could not match wildcard host: ", err)
          return
        end

        if from then
          host = wildcard_hosts[i].value
          req_category = bor(req_category, MATCH_RULES.HOST)
          break
        end
      end
    end

    if plain_indexes.uris[uri] then
      req_category = bor(req_category, MATCH_RULES.URI)

    else
      for i = 1, #uris_prefixes do
        local from, _, err = re_find(uri, uris_prefixes[i], "ajo")
        if err then
          log(ERR, "could not search for URI prefix: ", err)
          return
        end

        if from then
          -- strip \Q...\E tokens
          uri = sub(uris_prefixes[i], 3, -3)
          req_category = bor(req_category, MATCH_RULES.URI)
          break
        end
      end
    end

    if plain_indexes.methods[method] then
      req_category = bor(req_category, MATCH_RULES.METHOD)
    end


    --print("highest potential category: ", req_category)

    -- iterate from the highest matching to the lowest category to
    -- find our API


    if req_category ~= 0x00 then
      local category_idx = CATEGORIES_LOOKUP[req_category]
      local matched_api

      while category_idx <= categories_len do
        local bit_category = CATEGORIES[category_idx]
        local category     = categories[bit_category]

        if category then
          local plain_candidates, apis_for_category = reduce(category,
                                                             bit_category,
                                                             method, uri, host)
          if plain_candidates then
            -- check for results from a set of reduced plain indexes
            -- this is our best case scenario with hash lookups only
            for i = 1, #plain_candidates do
              if match_api(plain_candidates[i], method, uri, host) then
                matched_api = plain_candidates[i]
                break
              end
            end
          end

          if not matched_api then
            -- must check for results from the full list of APIs from that
            -- category before checking a lower category
            for i = 1, #apis_for_category do
              if match_api(apis_for_category[i], method, uri, host) then
                matched_api = apis_for_category[i]
                break
              end
            end
          end

          if matched_api then
            cache:set(cache_key, matched_api)
            return matched_api
          end
        end

        -- check lower category
        category_idx = category_idx + 1
      end
    end

    -- no match :'(
  end


  self.select = find_api


  function self.exec(ngx)
    local method      = ngx.req.get_method()
    local request_uri = ngx.var.request_uri
    local uri         = request_uri


    do
      local s = find(uri, "?", 2, true)
      if s then
        uri = sub(uri, 1, s - 1)
      end
    end


    --print("grab host header: ", grab_host)


    local req_host

    if grab_host then
      req_host = ngx.var.http_host
    end


    local api_t = find_api(method, uri, req_host)
    if not api_t then
      return nil
    end

    local uri_root = request_uri == "/"

    if not uri_root and api_t.strip_uri_regex then
      local _, err
      uri, _, err = re_sub(uri, api_t.strip_uri_regex, "/$1", "ajo")
      if not uri then
        log(ERR, "could not strip URI: ", err)
        return
      end
    end


    local upstream = api_t.upstream
    if upstream.path and upstream.path ~= "/" then
      if uri ~= "/" then
        uri = upstream.file .. uri

      else
        if upstream.path ~= upstream.file then
          if uri_root or sub(request_uri, -1) == "/" then
            uri = upstream.path

          else
            uri = upstream.file
          end

        else
          if uri_root or sub(request_uri, -1) ~= "/" then
            uri = upstream.file

          else
            uri = upstream.file .. uri
          end
        end
      end
    end


    local host_header

    if api_t.preserve_host then
      host_header = req_host or ngx.var.http_host
    end


    if ngx.var.http_kong_debug then
      ngx.header["Kong-Api-Name"] = api_t.api.name
    end

    return api_t.api, api_t.upstream, host_header, uri
  end


  return self
end


return _M
