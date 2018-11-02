local lrucache      = require "resty.lrucache"
local utils         = require "kong.tools.utils"
local bit           = require "bit"


local hostname_type = utils.hostname_type
local re_match      = ngx.re.match
local re_find       = ngx.re.find
local null          = ngx.null
local insert        = table.insert
local sort          = table.sort
local upper         = string.upper
local lower         = string.lower
local find          = string.find
local fmt           = string.format
local sub           = string.sub
local ipairs        = ipairs
local pairs         = pairs
local error         = error
local type          = type
local band          = bit.band
local bor           = bit.bor


local ERR      = ngx.ERR


local clear_tab
local log
do
  local ngx_log = ngx.log
  log = function(lvl, ...)
    ngx_log(lvl, "[router] ", ...)
  end

  local ok
  ok, clear_tab = pcall(require, "table.clear")
  if not ok then
    clear_tab = function(tab)
      for k in pairs(tab) do
        tab[k] = nil
      end
    end
  end
end


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 5 MiBs

LRU size must be: (5 * 2^20) / 1024 = 5120
Floored: 5000 items should be a good default
--]]
local MATCH_LRUCACHE_SIZE = 5e3


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


local match_route
local reduce


local function has_capturing_groups(subj)
  local s =      find(subj, "[^\\]%(.-[^\\]%)")
        s = s or find(subj, "^%(.-[^\\]%)")
        s = s or find(subj, "%(%)")

  return s ~= nil
end


local function marshall_route(r)
  local route    = r.route          or null
  local service  = r.service        or null
  local headers  = r.headers        or null
  local paths    = route.paths      or null
  local methods  = route.methods    or null
  local protocol = service.protocol or null

  if not (headers ~= null or methods ~= null or paths ~= null) then
    return nil, "could not categorize route"
  end

  local route_t    = {
    route          = route,
    service        = service,
    strip_uri      = route.strip_path    == true,
    preserve_host  = route.preserve_host == true,
    match_rules    = 0x00,
    hosts          = {},
    uris           = {},
    methods        = {},
    upstream_url_t = {},
  }


  -- headers


  if headers ~= null then
    if type(headers) ~= "table" then
      return nil, "headers field must be a table"
    end

    for header_name in pairs(headers) do
      if lower(header_name) ~= "host" then
        return nil, "only 'Host' header is supported in headers field, " ..
                    "found: " .. header_name
      end
    end

    local host_values = headers["Host"] or headers["host"]
    if type(host_values) ~= "table" then
      return nil, "host field must be a table"
    end

    route_t.headers = headers

    if #host_values > 0 then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.HOST)

      for _, host_value in ipairs(host_values) do
        if find(host_value, "*", nil, true) then
          -- wildcard host matching
          local wildcard_host_regex = host_value:gsub("%.", "\\.")
                                                :gsub("%*", ".+") .. "$"
          insert(route_t.hosts, {
            wildcard = true,
            value    = host_value,
            regex    = wildcard_host_regex,
          })

        else
          insert(route_t.hosts, {
            value = host_value,
          })
        end

        route_t.hosts[host_value] = host_value
      end
    end
  end


  -- paths


  if paths ~= null then
    if type(paths) ~= "table" then
      return nil, "paths field must be a table"
    end

    if #paths > 0 then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.URI)

      for _, path in ipairs(paths) do
        if re_find(path, [[^[a-zA-Z0-9\.\-_~/%]*$]]) then
          -- plain URI or URI prefix

          local uri_t = {
            is_prefix = true,
            value     = path,
          }

          route_t.uris[path] = uri_t
          insert(route_t.uris, uri_t)

        else
          -- regex URI
          local strip_regex  = path .. [[/?(?<stripped_uri>.*)]]
          local has_captures = has_capturing_groups(path)

          local uri_t    = {
            is_regex     = true,
            value        = path,
            regex        = path,
            has_captures = has_captures,
            strip_regex  = strip_regex,
          }

          route_t.uris[path] = uri_t
          insert(route_t.uris, uri_t)
        end
      end
    end
  end


  -- methods


  if methods ~= null then
    if type(methods) ~= "table" then
      return nil, "methods field must be a table"
    end

    if #methods > 0 then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.METHOD)

      for _, method in ipairs(methods) do
        route_t.methods[upper(method)] = true
      end
    end
  end


  -- upstream_url parsing

  if protocol ~= null then
    route_t.upstream_url_t.scheme = protocol
  end

  local host = service.host or null
  if host ~= null then
    route_t.upstream_url_t.host = host
    route_t.upstream_url_t.type = hostname_type(host)

  else
    route_t.upstream_url_t.type = hostname_type("")
  end

  local port = service.port or null
  if port ~= null then
    route_t.upstream_url_t.port = port

  else
    if protocol == "https" then
      route_t.upstream_url_t.port = 443

    else
      route_t.upstream_url_t.port = 80
    end
  end

  -- TODO: service.path is not supported in new model
  local path = service.path or null
  local file = path
  if path ~= null then
    if sub(path, -1) == "/" and path ~= "/" then
      file = sub(path,  1, -2)
    end

  else
    path = "/"
    file = "/"
  end

  route_t.upstream_url_t.path = path
  route_t.upstream_url_t.file = file

  return route_t
end


local function index_route_t(route_t, plain_indexes, prefix_uris, regex_uris,
                             wildcard_hosts)
  for _, host_t in ipairs(route_t.hosts) do
    if host_t.wildcard then
      insert(wildcard_hosts, host_t)

    else
      plain_indexes.hosts[host_t.value] = true
    end
  end

  for _, uri_t in ipairs(route_t.uris) do
    if uri_t.is_prefix then
      plain_indexes.uris[uri_t.value] = true
      insert(prefix_uris, uri_t)

    else
      insert(regex_uris, uri_t)
    end
  end

  for method in pairs(route_t.methods) do
    plain_indexes.methods[method] = true
  end
end


local function categorize_route_t(route_t, bit_category, categories)
  local category = categories[bit_category]
  if not category then
    category            = {
      routes_by_hosts   = {},
      routes_by_uris    = {},
      routes_by_methods = {},
      all               = {},
    }

    categories[bit_category] = category
  end

  insert(category.all, route_t)

  for _, host_t in ipairs(route_t.hosts) do
    if not category.routes_by_hosts[host_t.value] then
      category.routes_by_hosts[host_t.value] = {}
    end

    insert(category.routes_by_hosts[host_t.value], route_t)
  end

  for _, uri_t in ipairs(route_t.uris) do
    if not category.routes_by_uris[uri_t.value] then
      category.routes_by_uris[uri_t.value] = {}
    end

    insert(category.routes_by_uris[uri_t.value], route_t)
  end

  for method in pairs(route_t.methods) do
    if not category.routes_by_methods[method] then
      category.routes_by_methods[method] = {}
    end

    insert(category.routes_by_methods[method], route_t)
  end
end


do
  local matchers = {
    [MATCH_RULES.HOST] = function(route_t, ctx)
      local host = route_t.hosts[ctx.hits.host or ctx.req_host]
      if host then
        ctx.matches.host = host

        return true
      end
    end,

    [MATCH_RULES.URI] = function(route_t, ctx)
      do
        local uri_t = route_t.uris[ctx.hits.uri or ctx.req_uri]

        if uri_t then
          if uri_t.is_regex then
            local m, err = re_match(ctx.req_uri, uri_t.strip_regex, "ajo")
            if err then
              log(ERR, "could not evaluate URI prefix/regex: ", err)
              return
            end

            if m then
              if m.stripped_uri then
                ctx.matches.stripped_uri = "/" .. m.stripped_uri
                -- remove the stripped_uri group
                m[#m]          = nil
                m.stripped_uri = nil
              end

              if uri_t.has_captures then
                ctx.matches.uri_captures = m
              end

              ctx.matches.uri = uri_t.value

              return true
            end
          end

          -- plain or prefix match from the index
          if route_t.strip_uri then
            local stripped_uri = sub(ctx.req_uri, #uri_t.value + 1)
            if sub(stripped_uri, 1, 1) ~= "/" then
              stripped_uri = "/" .. stripped_uri
            end

            ctx.matches.stripped_uri = stripped_uri
          end

          ctx.matches.uri = uri_t.value

          return true
        end
      end

      for i = 1, #route_t.uris do
        local uri_t = route_t.uris[i]

        if uri_t.is_regex then
          local m, err = re_match(ctx.req_uri, uri_t.strip_regex, "ajo")
          if err then
            log(ERR, "could not evaluate URI prefix/regex: ", err)
            return
          end

          if m then
            if m.stripped_uri then
              ctx.matches.stripped_uri = "/" .. m.stripped_uri
              -- remove the stripped_uri group
              m[#m]          = nil
              m.stripped_uri = nil
            end

            if uri_t.has_captures then
              ctx.matches.uri_captures = m
            end

            ctx.matches.uri = uri_t.value

            return true
          end

        else
          -- plain or prefix match (not from the index)
          local from, to = find(ctx.req_uri, uri_t.value, nil, true)
          if from == 1 then
            ctx.matches.uri = sub(ctx.req_uri, 1, to)

            if route_t.strip_uri then
              local stripped_uri = sub(ctx.req_uri, to + 1)
              if sub(stripped_uri, 1, 1) ~= "/" then
                stripped_uri = "/" .. stripped_uri
              end

              ctx.matches.stripped_uri = stripped_uri
            end

            ctx.matches.uri = uri_t.value

            return true
          end
        end
      end
    end,

    [MATCH_RULES.METHOD] = function(route_t, ctx)
      local method = route_t.methods[ctx.req_method]
      if method then
        ctx.matches.method = ctx.req_method

        return true
      end
    end
  }


  match_route = function(route_t, ctx)
    -- run cached matcher
    if type(matchers[route_t.match_rules]) == "function" then
      clear_tab(ctx.matches)
      return matchers[route_t.match_rules](route_t, ctx)
    end

    -- build and cache matcher

    local matchers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(route_t.match_rules, bit_match_rule) ~= 0 then
        matchers_set[#matchers_set + 1] = matchers[bit_match_rule]
      end
    end

    matchers[route_t.match_rules] = function(route_t, ctx)
      -- clear matches context for this try on this route
      clear_tab(ctx.matches)

      for i = 1, #matchers_set do
        if not matchers_set[i](route_t, ctx) then
          return
        end
      end

      return true
    end

    return matchers[route_t.match_rules](route_t, ctx)
  end
end


do
  local reducers = {
    [MATCH_RULES.HOST] = function(category, ctx)
      return category.routes_by_hosts[ctx.hits.host]
    end,

    [MATCH_RULES.URI] = function(category, ctx)
      return category.routes_by_uris[ctx.hits.uri or ctx.req_uri]
    end,

    [MATCH_RULES.METHOD] = function(category, ctx)
      return category.routes_by_methods[ctx.req_method]
    end,
  }


  reduce = function(category, bit_category, ctx)
    -- run cached reducer
    if type(reducers[bit_category]) == "function" then
      return reducers[bit_category](category, ctx), category.all
    end

    -- build and cache reducer

    local reducers_set = {}

    for _, bit_match_rule in pairs(MATCH_RULES) do
      if band(bit_category, bit_match_rule) ~= 0 then
        reducers_set[#reducers_set + 1] = reducers[bit_match_rule]
      end
    end

    reducers[bit_category] = function(category, ctx)
      local min_len = 0
      local smallest_set

      for i = 1, #reducers_set do
        local candidates = reducers_set[i](category, ctx)
        if candidates ~= nil and (not smallest_set or #candidates < min_len)
        then
          min_len = #candidates
          smallest_set = candidates
        end
      end

      return smallest_set
    end

    return reducers[bit_category](category, ctx), category.all
  end
end


local _M = {}


_M.has_capturing_groups = has_capturing_groups


function _M.new(routes)
  if type(routes) ~= "table" then
    return error("expected arg #1 routes to be a table")
  end


  local self = {}


  local ctx = {
    hits    = {},
    matches = {},
  }


  -- hash table for fast lookup of plain hosts, uris
  -- and methods from incoming requests
  local plain_indexes = {
    hosts             = {},
    uris              = {},
    methods           = {},
  }


  -- when hash lookup in plain_indexes fails, those are arrays
  -- of regexes for `uris` as prefixes and `hosts` as wildcards
  local prefix_uris    = {} -- will be sorted by length
  local regex_uris     = {}
  local wildcard_hosts = {}


  -- all routes grouped by the category they belong to, to reduce
  -- iterations over sets of routes per request
  local categories = {}


  local cache = lrucache.new(MATCH_LRUCACHE_SIZE)


  -- index routes


  for i = 1, #routes do
    local route_t, err = marshall_route(routes[i])
    if not route_t then
      return nil, err
    end

    categorize_route_t(route_t, route_t.match_rules, categories)
    index_route_t(route_t, plain_indexes, prefix_uris, regex_uris,
                wildcard_hosts)
  end


  sort(prefix_uris, function(p1, p2)
    return #p1.value > #p2.value
  end)


  local function find_route(req_method, req_uri, req_host, ngx)
    if type(req_method) ~= "string" then
      return error("arg #1 method must be a string")
    end
    if type(req_uri) ~= "string" then
      return error("arg #2 uri must be a string")
    end
    if type(req_host) ~= "string" then
      return error("arg #3 host must be a string")
    end

    -- cache lookup

    local cache_key = fmt("%s:%s:%s", req_method, req_uri, req_host)

    do
      local match_t = cache:get(cache_key)
      if match_t then
        return match_t
      end
    end

    -- input sanitization for matchers

    local raw_req_host = req_host

    req_method = upper(req_method)

    if req_host then
      -- strip port number if given because matching ignores ports
      local idx = find(req_host, ":", 2, true)
      if idx then
        req_host = sub(req_host, 1, idx - 1)
      end
    end

    local hits         = ctx.hits
    local req_category = 0x00

    ctx.req_method = req_method
    ctx.req_uri    = req_uri
    ctx.req_host   = req_host

    clear_tab(hits)

    -- router, router, which of these routes is the fairest?
    --
    -- determine which category this request *might* be targeting

    -- host match

    if plain_indexes.hosts[req_host] then
      req_category = bor(req_category, MATCH_RULES.HOST)

    elseif req_host then
      for i = 1, #wildcard_hosts do
        local from, _, err = re_find(req_host, wildcard_hosts[i].regex, "ajo")
        if err then
          log(ERR, "could not match wildcard host: ", err)
          return
        end

        if from then
          hits.host    = wildcard_hosts[i].value
          req_category = bor(req_category, MATCH_RULES.HOST)
          break
        end
      end
    end

    -- uri match

    if plain_indexes.uris[req_uri] then
      req_category = bor(req_category, MATCH_RULES.URI)

    else
      for i = 1, #prefix_uris do
        if find(req_uri, prefix_uris[i].value, nil, true) == 1 then
          hits.uri     = prefix_uris[i].value
          req_category = bor(req_category, MATCH_RULES.URI)
          break
        end
      end

      for i = 1, #regex_uris do
        local from, _, err = re_find(req_uri, regex_uris[i].regex, "ajo")
        if err then
          log(ERR, "could not evaluate URI regex: ", err)
          return
        end

        if from then
          hits.uri     = regex_uris[i].value
          req_category = bor(req_category, MATCH_RULES.URI)
          break
        end
      end
    end

    -- method match

    if plain_indexes.methods[req_method] then
      req_category = bor(req_category, MATCH_RULES.METHOD)
    end

    --print("highest potential category: ", req_category)

    -- iterate from the highest matching to the lowest category to
    -- find our route

    if req_category ~= 0x00 then
      local category_idx = CATEGORIES_LOOKUP[req_category]
      local matched_route

      while category_idx <= categories_len do
        local bit_category = CATEGORIES[category_idx]
        local category     = categories[bit_category]

        if category then
          local reduced_candidates, category_candidates = reduce(category,
                                                                 bit_category,
                                                                 ctx)
          if reduced_candidates then
            -- check against a reduced set of routes that is a strong candidate
            -- for this request, instead of iterating over all the routes of
            -- this category
            for i = 1, #reduced_candidates do
              if match_route(reduced_candidates[i], ctx) then
                matched_route = reduced_candidates[i]
                break
              end
            end
          end

          if not matched_route then
            -- no result from the reduced set, must check for results from the
            -- full list of routes from that category before checking a lower
            -- category
            for i = 1, #category_candidates do
              if match_route(category_candidates[i], ctx) then
                matched_route = category_candidates[i]
                break
              end
            end
          end

          if matched_route then
            local upstream_host
            local upstream_uri   = req_uri
            local upstream_url_t = matched_route.upstream_url_t
            local matches        = ctx.matches

            -- URI stripping logic

            local uri_root = req_uri == "/"

            if not uri_root and matched_route.strip_uri
               and matches.stripped_uri
            then
              upstream_uri = matches.stripped_uri
            end

            -- uri trailing slash logic

            local upstream_url_path = upstream_url_t.path
            local upstream_url_file = upstream_url_t.file

            if upstream_url_path and upstream_url_path ~= "/" then
              if upstream_uri ~= "/" then
                upstream_uri = upstream_url_file .. upstream_uri

              else
                if upstream_url_path ~= upstream_url_file then
                  if uri_root or sub(req_uri, -1) == "/" then
                    upstream_uri = upstream_url_path

                  else
                    upstream_uri = upstream_url_file
                  end

                else
                  if uri_root or sub(req_uri, -1) ~= "/" then
                    upstream_uri = upstream_url_file

                  else
                    upstream_uri = upstream_url_file .. upstream_uri
                  end
                end
              end
            end

            -- preserve_host header logic

            if matched_route.preserve_host then
              upstream_host = raw_req_host or ngx.var.http_host
            end

            local match_t     = {
              route           = matched_route.route,
              service         = matched_route.service,
              headers         = matched_route.headers,
              upstream_url_t  = upstream_url_t,
              upstream_scheme = upstream_url_t.scheme,
              upstream_uri    = upstream_uri,
              upstream_host   = upstream_host,
              matches         = {
                uri_captures  = matches.uri_captures,
                uri           = matches.uri,
                host          = matches.host,
                method        = matches.method,
              }
            }

            cache:set(cache_key, match_t)

            return match_t
          end
        end

        -- check lower category
        category_idx = category_idx + 1
      end
    end

    -- no match :'(
  end


  self.select = find_route


  function self.exec(ngx)
    local req_method = ngx.req.get_method()
    local req_uri    = ngx.var.request_uri
    local req_host   = ngx.var.http_host or ""

    do
      local idx = find(req_uri, "?", 2, true)
      if idx then
        req_uri = sub(req_uri, 1, idx - 1)
      end
    end

    local match_t = find_route(req_method, req_uri, req_host, ngx)
    if not match_t then
      return nil
    end

    -- debug HTTP request header logic

    if ngx.var.http_kong_debug then
      ngx.header["Kong-Route-Id"]   = match_t.route.id
      ngx.header["Kong-Service-Id"] = match_t.service.id

      if match_t.service.name then
        ngx.header["Kong-Service-Name"] = match_t.service.name
      end
    end

    return match_t
  end


  return self
end


return _M
