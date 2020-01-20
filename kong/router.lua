local constants     = require "kong.constants"
local lrucache      = require "resty.lrucache"
local utils         = require "kong.tools.utils"
local px            = require "resty.mediador.proxy"
local bit           = require "bit"


local hostname_type = utils.hostname_type
local subsystem     = ngx.config.subsystem
local get_method    = ngx.req.get_method
local get_headers   = ngx.req.get_headers
local re_match      = ngx.re.match
local re_find       = ngx.re.find
local header        = ngx.header
local var           = ngx.var
local ngx_log       = ngx.log
local insert        = table.insert
local sort          = table.sort
local byte          = string.byte
local upper         = string.upper
local lower         = string.lower
local find          = string.find
local format        = string.format
local sub           = string.sub
local tonumber      = tonumber
local ipairs        = ipairs
local pairs         = pairs
local error         = error
local type          = type
local max           = math.max
local band          = bit.band
local bor           = bit.bor

local SLASH         = byte("/")

local ERR           = ngx.ERR
local WARN          = ngx.WARN


local clear_tab
local log
do
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


local split_port
do
  local ZERO, NINE, LEFTBRACKET, RIGHTBRACKET = ("09[]"):byte(1, -1)


  local function safe_add_port(host, port)
    if not port then
      return host
    end

    return host .. ":" .. port
  end


  local function onlydigits(s, begin)
    for i = begin or 1, #s do
      local c = byte(s, i)
      if c < ZERO or c > NINE then
        return false
      end
    end
    return true
  end


  --- Splits an optional ':port' section from a hostname
  -- the port section must be decimal digits only.
  -- brackets ('[]') are peeled off the hostname if present.
  -- if there's more than one colon and no brackets, no split is possible.
  -- on non-parseable input, returns name unchanged,
  -- every string input produces at least one string output.
  -- @tparam string name the string to split.
  -- @tparam number default_port default port number
  -- @treturn string hostname without port
  -- @treturn string hostname with port
  -- @treturn boolean true if input had a port number
  local function l_split_port(name, default_port)
    if byte(name, 1) == LEFTBRACKET then
      if byte(name, -1) == RIGHTBRACKET then
        return sub(name, 2, -2), safe_add_port(name, default_port), false
      end

      local splitpos = find(name, "]:", 2, true)
      if splitpos then
        if splitpos == #name - 1 then
          return sub(name, 2, splitpos - 1), name .. (default_port or ""), false
        end

        if onlydigits(name, splitpos + 2) then
          return sub(name, 2, splitpos - 1), name, true
        end
      end

      return name, safe_add_port(name, default_port), false
    end

    local firstcolon = find(name, ":", 1, true)
    if not firstcolon then
      return name, safe_add_port(name, default_port), false
    end

    if firstcolon == #name then
      local host = sub(name, 1, firstcolon - 1)
      return host, safe_add_port(host, default_port), false
    end

    if not onlydigits(name, firstcolon + 1) then
      if default_port then
        return name, format("[%s]:%s", name, default_port), false
      end

      return name, name, false
    end

    return sub(name, 1, firstcolon - 1), name, true
  end


  -- split_port is a pure function, so we can memoize it.
  local memo_h = setmetatable({}, { __mode = "k" })
  local memo_hp = setmetatable({}, { __mode = "k" })
  local memo_p = setmetatable({}, { __mode = "k" })


  split_port = function(name, default_port)
    local k = name .. "#" .. (default_port or "")
    local h, hp, p = memo_h[k], memo_hp[k], memo_p[k]
    if not h then
      h, hp, p = l_split_port(name, default_port)
      memo_h[k], memo_hp[k], memo_p[k] = h, hp, p
    end

    return h, hp, p
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
  HOST            = 0x00000040,
  HEADER          = 0x00000020,
  URI             = 0x00000010,
  METHOD          = 0x00000008,
  SNI             = 0x00000004,
  SRC             = 0x00000002,
  DST             = 0x00000001,
}

local SORTED_MATCH_RULES = {}

for _, v in pairs(MATCH_RULES) do
  insert(SORTED_MATCH_RULES, v)
end

sort(SORTED_MATCH_RULES, function(a, b)
  return a > b
end)

local MATCH_SUBRULES = {
  HAS_REGEX_URI          = 0x01,
  PLAIN_HOSTS_ONLY       = 0x02,
  HAS_WILDCARD_HOST_PORT = 0x04,
}

local EMPTY_T = {}
local MAX_REQ_HEADERS = 100


local match_route
local reduce


local function _set_ngx(mock_ngx)
  if type(mock_ngx) ~= "table" then
    return
  end

  if mock_ngx.header then
    header = mock_ngx.header
  end

  if mock_ngx.var then
    var = mock_ngx.var
  end

  if mock_ngx.log then
    ngx_log = mock_ngx.log
  end

  if mock_ngx.ERR then
    ERR = mock_ngx.ERR
  end

  if type(mock_ngx.req) == "table" then
    if mock_ngx.req.get_method then
      get_method = mock_ngx.req.get_method
    end

    if mock_ngx.req.get_headers then
      get_headers = mock_ngx.req.get_headers
    end
  end

  if type(mock_ngx.config) == "table" then
    if mock_ngx.config.subsystem then
      subsystem = mock_ngx.config.subsystem
    end
  end

  if type(mock_ngx.re) == "table" then
    if mock_ngx.re.match then
      re_match = mock_ngx.re.match
    end

    if mock_ngx.re.find then
      re_find = mock_ngx.re.find
    end
  end
end


local function has_capturing_groups(subj)
  local s =      find(subj, "[^\\]%(.-[^\\]%)")
        s = s or find(subj, "^%(.-[^\\]%)")
        s = s or find(subj, "%(%)")

  return s ~= nil
end


local protocol_subsystem = constants.PROTOCOLS_WITH_SUBSYSTEM


local function marshall_route(r)
  local route        = r.route
  local service      = r.service
  local hosts        = route.hosts
  local headers      = route.headers
  local paths        = route.paths
  local methods      = route.methods
  local snis         = route.snis
  local sources      = route.sources
  local destinations = route.destinations

  local protocol
  if service then
    protocol = service.protocol
  end

  if not (hosts or headers or methods or paths or snis or sources
          or destinations)
  then
    return nil, "could not categorize route"
  end

  local route_t    = {
    type           = protocol_subsystem[protocol],
    route          = route,
    service        = service,
    strip_uri      = route.strip_path    == true,
    preserve_host  = route.preserve_host == true,
    match_rules    = 0x00,
    match_weight   = 0,
    submatch_weight = 0,
    max_uri_length = 0,
    hosts          = {},
    headers        = {},
    uris           = {},
    methods        = {},
    sources        = {},
    destinations   = {},
    snis           = {},
    upstream_url_t = {},
  }


  -- hosts


  if hosts then
    if type(hosts) ~= "table" then
      return nil, "hosts field must be a table"
    end

    local has_host_wildcard
    local has_host_plain
    local has_port

    for _, host in ipairs(hosts) do
      if type(host) ~= "string" then
        return nil, "hosts values must be strings"
      end

      if find(host, "*", nil, true) then
        -- wildcard host matching
        has_host_wildcard = true

        local wildcard_host_regex = host:gsub("%.", "\\.")
                                        :gsub("%*", ".+") .. "$"

        _, _, has_port = split_port(host)
        if not has_port then
          wildcard_host_regex = wildcard_host_regex:gsub("%$$", [[(?::\d+)?$]])
        end

        insert(route_t.hosts, {
          wildcard = true,
          value    = host,
          regex    = wildcard_host_regex,
        })

      else
        -- plain host matching
        has_host_plain = true

        route_t.hosts[host] = host

        insert(route_t.hosts, {
          value = host,
        })
      end
    end

    if has_host_plain or has_host_wildcard then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.HOST)
      route_t.match_weight = route_t.match_weight + 1
    end

    if not has_host_wildcard then
      route_t.submatch_weight = bor(route_t.submatch_weight,
                                    MATCH_SUBRULES.PLAIN_HOSTS_ONLY)
    end

    if has_port then
      route_t.submatch_weight = bor(route_t.submatch_weight,
                                    MATCH_SUBRULES.HAS_WILDCARD_HOST_PORT)
    end
  end


  -- headers


  if headers then
    if type(headers) ~= "table" then
      return nil, "headers field must be a table"
    end

    local has_header_plain

    for header_name, header_values in pairs(headers) do
      if type(header_values) ~= "table" then
        return nil, "header values must be a table for header '" ..
                    header_name .. "'"
      end

      header_name = lower(header_name)

      if header_name ~= "host" then
        -- plain header matching
        has_header_plain = true

        local header_values_map = {}
        for i, header_value in ipairs(header_values) do
          header_values_map[lower(header_value)] = true
        end

        insert(route_t.headers, {
          name = header_name,
          values_map = header_values_map,
        })
      end
    end

    if has_header_plain then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.HEADER)
      route_t.match_weight = route_t.match_weight + 1
    end
  end


  -- paths


  if paths then
    if type(paths) ~= "table" then
      return nil, "paths field must be a table"
    end

    if #paths > 0 then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.URI)
      route_t.match_weight = route_t.match_weight + 1

      for _, path in ipairs(paths) do
        if re_find(path, [[^[a-zA-Z0-9\.\-_~/%]*$]]) then
          -- plain URI or URI prefix

          local uri_t = {
            is_prefix = true,
            value     = path,
          }

          route_t.uris[path] = uri_t
          insert(route_t.uris, uri_t)
          route_t.max_uri_length = max(route_t.max_uri_length, #path)

        else
          -- regex URI
          local strip_regex  = path .. [[(?<uri_postfix>.*)]]
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

          route_t.submatch_weight = bor(route_t.submatch_weight,
                                        MATCH_SUBRULES.HAS_REGEX_URI)
        end
      end
    end
  end


  -- methods


  if methods then
    if type(methods) ~= "table" then
      return nil, "methods field must be a table"
    end

    if #methods > 0 then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.METHOD)
      route_t.match_weight = route_t.match_weight + 1

      for _, method in ipairs(methods) do
        route_t.methods[upper(method)] = true
      end
    end
  end


  -- sources


  if sources then
    if type(sources) ~= "table" then
      return nil, "sources field must be a table"
    end

    if #sources > 0 then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.SRC)
      route_t.match_weight = route_t.match_weight + 1

      for _, source in ipairs(sources) do
        if type(source) ~= "table" then
          return nil, "sources elements must be tables"
        end

        local range_f

        if source.ip and find(source.ip, "/", nil, true) then
          range_f = px.compile(source.ip)
        end

        insert(route_t.sources, {
          ip = source.ip,
          port = source.port,
          range_f = range_f,
        })
      end
    end
  end


  -- destinations


  if destinations then
    if type(destinations) ~= "table" then
      return nil, "destinations field must be a table"
    end

    if #destinations > 0 then
      route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.DST)
      route_t.match_weight = route_t.match_weight + 1

      for _, destination in ipairs(destinations) do
        if type(destination) ~= "table" then
          return nil, "destinations elements must be tables"
        end

        local range_f

        if destination.ip and find(destination.ip, "/", nil, true) then
          range_f = px.compile(destination.ip)
        end

        insert(route_t.destinations, {
          ip = destination.ip,
          port = destination.port,
          range_f = range_f,
        })
      end
    end
  end


  -- snis


  if snis then
    if type(snis) ~= "table" then
      return nil, "snis field must be a table"
    end

    if #snis > 0 then
      for _, sni in ipairs(snis) do
        if type(sni) ~= "string" then
          return nil, "sni elements must be strings"
        end

        route_t.match_rules = bor(route_t.match_rules, MATCH_RULES.SNI)
        route_t.match_weight = route_t.match_weight + 1
        route_t.snis[sni] = sni
      end
    end
  end


  -- upstream_url parsing


  if protocol then
    route_t.upstream_url_t.scheme = protocol
  end

  local s = service or EMPTY_T

  local host = s.host
  if host then
    route_t.upstream_url_t.host = host
    route_t.upstream_url_t.type = hostname_type(host)

  else
    route_t.upstream_url_t.type = hostname_type("")
  end

  local port = s.port
  if port then
    route_t.upstream_url_t.port = port

  else
    if protocol == "https" then
      route_t.upstream_url_t.port = 443

    elseif protocol == "http" then
      route_t.upstream_url_t.port = 80
    end
  end

  if route_t.type == "http" then
    route_t.upstream_url_t.path = s.path or "/"
  end

  return route_t
end


local function index_route_t(route_t, plain_indexes, prefix_uris, regex_uris,
                             wildcard_hosts, src_trust_funcs, dst_trust_funcs)
  for _, host_t in ipairs(route_t.hosts) do
    if host_t.wildcard then
      insert(wildcard_hosts, host_t)

    else
      plain_indexes.hosts[host_t.value] = true
    end
  end

  for _, header_t in ipairs(route_t.headers) do
    if not plain_indexes.headers[header_t.name] then
      plain_indexes.headers[header_t.name] = true
      insert(plain_indexes.headers, header_t.name)
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

  for _, src_t in ipairs(route_t.sources) do
    if src_t.ip then
      plain_indexes.sources[src_t.ip] = true

      if src_t.range_f then
        insert(src_trust_funcs, src_t.range_f)
      end
    end

    if src_t.port then
      plain_indexes.sources[src_t.port] = true
    end
  end

  for _, dst_t in ipairs(route_t.destinations) do
    if dst_t.ip then
      plain_indexes.destinations[dst_t.ip] = true

      if dst_t.range_f then
        insert(dst_trust_funcs, dst_t.range_f)
      end
    end

    if dst_t.port then
      plain_indexes.destinations[dst_t.port] = true
    end
  end

  for sni in pairs(route_t.snis) do
    plain_indexes.snis[sni] = true
  end
end


local function categorize_route_t(route_t, bit_category, categories)
  local category = categories[bit_category]
  if not category then
    category                 = {
      match_weight           = route_t.match_weight,
      routes_by_hosts        = {},
      routes_by_headers      = {},
      routes_by_uris         = {},
      routes_by_methods      = {},
      routes_by_sources      = {},
      routes_by_destinations = {},
      routes_by_sni          = {},
      all                    = {},
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

  for _, header_t in ipairs(route_t.headers) do
    if not category.routes_by_headers[header_t.name] then
      category.routes_by_headers[header_t.name] = {}
    end

    insert(category.routes_by_headers[header_t.name], route_t)
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

  for _, src_t in ipairs(route_t.sources) do
    if src_t.ip then
      if not category.routes_by_sources[src_t.ip] then
        category.routes_by_sources[src_t.ip] = {}
      end

      insert(category.routes_by_sources[src_t.ip], route_t)
    end

    if src_t.port then
      if not category.routes_by_sources[src_t.port] then
        category.routes_by_sources[src_t.port] = {}
      end

      insert(category.routes_by_sources[src_t.port], route_t)
    end
  end

  for _, dst_t in ipairs(route_t.destinations) do
    if dst_t.ip then
      if not category.routes_by_destinations[dst_t.ip] then
        category.routes_by_destinations[dst_t.ip] = {}
      end

      insert(category.routes_by_destinations[dst_t.ip], route_t)
    end

    if dst_t.port then
      if not category.routes_by_destinations[dst_t.port] then
        category.routes_by_destinations[dst_t.port] = {}
      end

      insert(category.routes_by_destinations[dst_t.port], route_t)
    end
  end

  for sni in pairs(route_t.snis) do
    if not category.routes_by_sni[sni] then
      category.routes_by_sni[sni] = {}
    end

    insert(category.routes_by_sni[sni], route_t)
  end
end


do
  local matchers = {
    [MATCH_RULES.HOST] = function(route_t, ctx)
      local req_host = ctx.hits.host or ctx.req_host
      local host = route_t.hosts[req_host] or route_t.hosts[ctx.host_no_port]
      if host then
        ctx.matches.host = host
        return true
      end

      for i = 1, #route_t.hosts do
        local host_t = route_t.hosts[i]

        if host_t.wildcard then
          local from, _, err = re_find(ctx.host_with_port, host_t.regex, "ajo")
          if err then
            log(ERR, "could not evaluate wildcard host regex: ", err)
            return
          end

          if from then
            ctx.matches.host = host_t.value
            return true
          end
        end
      end
    end,

    [MATCH_RULES.HEADER] = function(route_t, ctx)
      ctx.matches.headers = {}

      for _, header_t in ipairs(route_t.headers) do
        local found_in_req
        local req_header = ctx.req_headers[header_t.name]

        if type(req_header) == "table" then
          for _, req_header_val in ipairs(req_header) do
            req_header_val = lower(req_header_val)
            if header_t.values_map[req_header_val] then
              found_in_req = true
              ctx.matches.headers[header_t.name] = req_header_val
              break
            end
          end

        elseif req_header then -- string
          req_header = lower(req_header)
          if header_t.values_map[req_header] then
            found_in_req = true
            ctx.matches.headers[header_t.name] = req_header
          end
        end

        if not found_in_req then
          return
        end
      end

      return true
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
              ctx.matches.uri_postfix = m.uri_postfix
              ctx.matches.uri = uri_t.value

              if m.uri_postfix then
                -- remove the uri_postfix group
                m[#m]          = nil
                m.uri_postfix = nil
              end

              if uri_t.has_captures then
                ctx.matches.uri_captures = m
              end

              return true
            end
          end

          -- plain or prefix match from the index
          ctx.matches.uri_postfix = sub(ctx.req_uri, #uri_t.value + 1)
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
            ctx.matches.uri_postfix = m.uri_postfix
            ctx.matches.uri = uri_t.value

            if m.uri_postfix then
              -- remove the uri_postfix group
              m[#m]          = nil
              m.uri_postfix = nil
            end

            if uri_t.has_captures then
              ctx.matches.uri_captures = m
            end

            return true
          end

        else
          -- plain or prefix match (not from the index)
          local from, to = find(ctx.req_uri, uri_t.value, nil, true)
          if from == 1 then
            ctx.matches.uri_postfix = sub(ctx.req_uri, to + 1)
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
    end,

    [MATCH_RULES.SRC] = function(route_t, ctx)
      for _, src_t in ipairs(route_t.sources) do
        local ip_ok
        local port_ok

        if not src_t.ip then
          ip_ok = true
        elseif src_t.range_f then
          ip_ok = src_t.range_f(ctx.src_ip)
        else
          ip_ok = src_t.ip == ctx.src_ip
        end

        if not src_t.port or (src_t.port == ctx.src_port) then
          port_ok = true
        end

        if ip_ok and port_ok then
          ctx.matches.src_ip = src_t.ip
          ctx.matches.src_port = src_t.port
          return true
        end
      end
    end,

    [MATCH_RULES.DST] = function(route_t, ctx)
      for _, dst_t in ipairs(route_t.destinations) do
        local ip_ok
        local port_ok

        if not dst_t.ip then
          ip_ok = true
        elseif dst_t.range_f then
          ip_ok = dst_t.range_f(ctx.dst_ip)
        else
          ip_ok = dst_t.ip == ctx.dst_ip
        end

        if not dst_t.port or (dst_t.port == ctx.dst_port) then
          port_ok = true
        end

        if ip_ok and port_ok then
          ctx.matches.dst_ip = dst_t.ip
          ctx.matches.dst_port = dst_t.port
          return true
        end
      end
    end,

    [MATCH_RULES.SNI] = function(route_t, ctx)
      local sni = route_t.snis[ctx.sni]
      if sni then
        ctx.matches.sni = ctx.sni
        return true
      end
    end,
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
      return category.routes_by_hosts[ctx.hits.host or ctx.req_host]
    end,

    [MATCH_RULES.HEADER] = function(category, ctx)
      return category.routes_by_headers[ctx.hits.header_name]
    end,

    [MATCH_RULES.URI] = function(category, ctx)
      -- no ctx.req_uri indexing since regex URIs have a higher priority than
      -- plain URIs
      return category.routes_by_uris[ctx.hits.uri]
    end,

    [MATCH_RULES.METHOD] = function(category, ctx)
      return category.routes_by_methods[ctx.req_method]
    end,

    [MATCH_RULES.SRC] = function(category, ctx)
      local routes = category.routes_by_sources[ctx.src_ip]
      if routes then
        return routes
      end

      routes = category.routes_by_sources[ctx.src_port]
      if routes then
        return routes
      end
    end,

    [MATCH_RULES.DST] = function(category, ctx)
      local routes = category.routes_by_destinations[ctx.dst_ip]
      if routes then
        return routes
      end

      routes = category.routes_by_destinations[ctx.dst_port]
      if routes then
        return routes
      end
    end,

    [MATCH_RULES.SNI] = function(category, ctx)
      return category.routes_by_sni[ctx.sni]
    end,
  }


  reduce = function(category, bit_category, ctx)
    -- run cached reducer
    if type(reducers[bit_category]) == "function" then
      return reducers[bit_category](category, ctx), category.all
    end

    -- build and cache reducer

    local reducers_set = {}

    for _, bit_match_rule in ipairs(SORTED_MATCH_RULES) do
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


-- for unit-testing purposes only
_M._set_ngx = _set_ngx
_M.split_port = split_port


function _M.new(routes)
  if type(routes) ~= "table" then
    return error("expected arg #1 routes to be a table")
  end


  local self = {}


  local ctx = {
    hits    = {},
    matches = {},
  }


  -- hash table for fast lookup of plain properties
  -- incoming requests/connections
  local plain_indexes = {
    hosts             = {},
    headers           = {},
    uris              = {},
    methods           = {},
    sources           = {},
    destinations      = {},
    snis              = {},
  }


  -- when hash lookup in plain_indexes fails, those are arrays
  -- of regexes for `uris` as prefixes and `hosts` as wildcards
  -- or IP ranges comparison functions
  local prefix_uris    = {} -- will be sorted by length
  local regex_uris     = {}
  local wildcard_hosts = {}
  local src_trust_funcs = {}
  local dst_trust_funcs = {}


  -- all routes grouped by the category they belong to, to reduce
  -- iterations over sets of routes per request
  local categories = {}


  local cache = lrucache.new(MATCH_LRUCACHE_SIZE)


  -- index routes

  do
    local marshalled_routes = {}

    for i = 1, #routes do

      local paths = routes[i].route.paths
      if paths ~= nil and #paths > 1 then
        -- split routes by paths to sort properly
        for j = 1, #paths do
          local route = routes[i]
          local index = #marshalled_routes + 1
          local err

          route.route.paths = { paths[j] }
          marshalled_routes[index], err = marshall_route(route)
          if not marshalled_routes[index] then
            return nil, err
          end
        end

      else
        local index = #marshalled_routes + 1
        local err

        marshalled_routes[index], err = marshall_route(routes[i])
        if not marshalled_routes[index] then
          return nil, err
        end
      end

    end

    -- sort wildcard hosts and uri regexes since those rules
    -- don't have their own matching category
    --
    -- * plain hosts > wildcard hosts
    -- * more plain headers > less plain headers
    -- * regex uris > plain uris
    -- * longer plain URIs > shorter plain URIs

    sort(marshalled_routes, function(r1, r2)
      if r1.submatch_weight ~= r2.submatch_weight then
        return r1.submatch_weight > r2.submatch_weight
      end

      do
        local r1_n_headers = #r1.headers
        local r2_n_headers = #r2.headers

        if r1_n_headers ~= r2_n_headers then
          return r1_n_headers > r2_n_headers
        end
      end

      do
        local rp1 = r1.route.regex_priority or 0
        local rp2 = r2.route.regex_priority or 0

        if rp1 ~= rp2 then
          return rp1 > rp2
        end
      end

      if r1.max_uri_length ~= r2.max_uri_length then
        return r1.max_uri_length > r2.max_uri_length
      end

      if r1.route.created_at ~= nil and r2.route.created_at ~= nil then
        return r1.route.created_at < r2.route.created_at
      end
    end)

    for i = 1, #marshalled_routes do
      local route_t = marshalled_routes[i]

      categorize_route_t(route_t, route_t.match_rules, categories)
      index_route_t(route_t, plain_indexes, prefix_uris, regex_uris,
                    wildcard_hosts, src_trust_funcs, dst_trust_funcs)
    end
  end


  -- a sorted array of all categories bits (from the most significant
  -- matching-wise, to the least significant)
  local categories_weight_sorted = {}


  -- a lookup array to get the category_idx from a category_bit. The
  -- idx will be a categories_weight_sorted index
  local categories_lookup = {}


  for category_bit, category in pairs(categories) do
    insert(categories_weight_sorted, {
      category_bit = category_bit,
      match_weight = category.match_weight,
    })
  end

  sort(categories_weight_sorted, function(c1, c2)
    if c1.match_weight ~= c2.match_weight then
      return c1.match_weight > c2.match_weight
    end

    return c1.category_bit > c2.category_bit
  end)

  for i, c in ipairs(categories_weight_sorted) do
    categories_lookup[c.category_bit] = i
  end

  -- the number of categories to iterate on for this instance of the router
  local categories_len = #categories_weight_sorted

  sort(prefix_uris, function(p1, p2)
    return #p1.value > #p2.value
  end)

  for _, category in pairs(categories) do
    for _, routes in pairs(category.routes_by_sources) do
      sort(routes, function(r1, r2)
        for _, source in ipairs(r1.sources) do
          if source.ip and source.port then
            return true
          end
        end
      end)
    end

    for _, routes in pairs(category.routes_by_destinations) do
      sort(routes, function(r1, r2)
        for _, destination in ipairs(r1.destinations) do
          if destination.ip and destination.port then
            return true
          end
        end
      end)
    end
  end

  local grab_req_headers = #plain_indexes.headers > 0

  local function find_route(req_method, req_uri, req_host, req_scheme,
                            src_ip, src_port,
                            dst_ip, dst_port,
                            sni, req_headers)
    if req_method and type(req_method) ~= "string" then
      error("method must be a string", 2)
    end
    if req_uri and type(req_uri) ~= "string" then
      error("uri must be a string", 2)
    end
    if req_host and type(req_host) ~= "string" then
      error("host must be a string", 2)
    end
    if req_scheme and type(req_scheme) ~= "string" then
      error("scheme must be a string", 2)
    end
    if src_ip and type(src_ip) ~= "string" then
      error("src_ip must be a string", 2)
    end
    if src_port and type(src_port) ~= "number" then
      error("src_port must be a number", 2)
    end
    if dst_ip and type(dst_ip) ~= "string" then
      error("dst_ip must be a string", 2)
    end
    if dst_port and type(dst_port) ~= "number" then
      error("dst_port must be a number", 2)
    end
    if sni and type(sni) ~= "string" then
      error("sni must be a string", 2)
    end
    if req_headers and type(req_headers) ~= "table" then
      error("headers must be a table", 2)
    end

    req_method = req_method or ""
    req_uri = req_uri or ""
    req_host = req_host or ""
    req_headers = req_headers or EMPTY_T

    ctx.req_method     = req_method
    ctx.req_uri        = req_uri
    ctx.req_host       = req_host
    ctx.req_headers    = req_headers
    ctx.src_ip         = src_ip or ""
    ctx.src_port       = src_port or ""
    ctx.dst_ip         = dst_ip or ""
    ctx.dst_port       = dst_port or ""
    ctx.sni            = sni or ""

    -- input sanitization for matchers

    -- hosts

    local raw_req_host = req_host

    req_method = upper(req_method)

    -- req_host might have port or maybe not, host_no_port definitely doesn't
    -- if there wasn't a port, req_port is assumed to be the default port
    -- according the protocol scheme
    local host_no_port, host_with_port = split_port(req_host,
                                                    req_scheme == "https"
                                                    and 443 or 80)

    ctx.host_with_port = host_with_port
    ctx.host_no_port   = host_no_port

    local hits         = ctx.hits
    local req_category = 0x00

    clear_tab(hits)

    -- router, router, which of these routes is the fairest?
    --
    -- determine which category this request *might* be targeting

    -- header match

    for _, header_name in ipairs(plain_indexes.headers) do
      if req_headers[header_name] then
        req_category = bor(req_category, MATCH_RULES.HEADER)
        hits.header_name = header_name
        break
      end
    end

    -- cache lookup (except for headers-matched Routes)
    -- if trigger headers match rule, ignore routes cache

    local cache_key = req_method .. "|" .. req_uri .. "|" .. req_host ..
                      "|" .. ctx.src_ip .. "|" .. ctx.src_port ..
                      "|" .. ctx.dst_ip .. "|" .. ctx.dst_port ..
                      "|" .. ctx.sni

    do
      local match_t = cache:get(cache_key)
      if match_t and hits.header_name == nil then
        return match_t
      end
    end

    -- host match

    if plain_indexes.hosts[host_with_port]
      or plain_indexes.hosts[host_no_port]
    then
      req_category = bor(req_category, MATCH_RULES.HOST)

    elseif ctx.req_host then
      for i = 1, #wildcard_hosts do
        local from, _, err = re_find(host_with_port, wildcard_hosts[i].regex,
                                     "ajo")
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

    if not hits.uri then
      if plain_indexes.uris[req_uri] then
        hits.uri     = req_uri
        req_category = bor(req_category, MATCH_RULES.URI)

      else
        for i = 1, #prefix_uris do
          if find(req_uri, prefix_uris[i].value, nil, true) == 1 then
            hits.uri     = prefix_uris[i].value
            req_category = bor(req_category, MATCH_RULES.URI)
            break
          end
        end
      end
    end

    -- method match

    if plain_indexes.methods[req_method] then
      req_category = bor(req_category, MATCH_RULES.METHOD)
    end

    -- src match

    if plain_indexes.sources[ctx.src_ip] then
      req_category = bor(req_category, MATCH_RULES.SRC)

    elseif plain_indexes.sources[ctx.src_port] then
      req_category = bor(req_category, MATCH_RULES.SRC)

    else
      for i = 1, #src_trust_funcs do
        if src_trust_funcs[i](ctx.src_ip) then
          req_category = bor(req_category, MATCH_RULES.SRC)
          break
        end
      end
    end

    -- dst match

    if plain_indexes.destinations[ctx.dst_ip] then
      req_category = bor(req_category, MATCH_RULES.DST)

    elseif plain_indexes.destinations[ctx.dst_port] then
      req_category = bor(req_category, MATCH_RULES.DST)

    else
      for i = 1, #dst_trust_funcs do
        if dst_trust_funcs[i](ctx.dst_ip) then
          req_category = bor(req_category, MATCH_RULES.DST)
          break
        end
      end
    end

    -- sni match

    if plain_indexes.snis[ctx.sni] then
      req_category = bor(req_category, MATCH_RULES.SNI)
    end

    --print("highest potential category: ", req_category)

    -- iterate from the highest matching to the lowest category to
    -- find our route

    if req_category ~= 0x00 then
      local category_idx = categories_lookup[req_category] or 1
      local matched_route

      while category_idx <= categories_len do
        local bit_category = categories_weight_sorted[category_idx].category_bit
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
            local upstream_uri
            local upstream_url_t = matched_route.upstream_url_t
            local matches        = ctx.matches

            -- Path construction

            if matched_route.type == "http" then
              -- if we do not have a path-match, then the postfix is simply the
              -- incoming path, without the initial slash
              local request_postfix = matches.uri_postfix or sub(req_uri, 2, -1)
              local upstream_base = upstream_url_t.path or "/"

              if matched_route.route.path_handling == "v1" then
                if matched_route.strip_uri then
                  -- we drop the matched part, replacing it with the upstream path
                  if byte(upstream_base, -1) == SLASH and
                     byte(request_postfix, 1) == SLASH then
                    -- double "/", so drop the first
                    upstream_uri = sub(upstream_base, 1, -2) .. request_postfix

                  else
                    upstream_uri = upstream_base .. request_postfix
                  end

                else
                  -- we retain the incoming path, just prefix it with the upstream
                  -- path, but skip the initial slash
                  upstream_uri = upstream_base .. sub(req_uri, 2, -1)
                end

              else -- matched_route.route.path_handling == "v0"
                if byte(upstream_base, -1) == SLASH then
                  -- ends with / and strip_uri = true
                  if matched_route.strip_uri then
                    if request_postfix == "" then
                      if upstream_base == "/" then
                        upstream_uri = "/"
                      elseif byte(req_uri, -1) == SLASH then
                        upstream_uri = upstream_base
                      else
                        upstream_uri = sub(upstream_base, 1, -2)
                      end
                    elseif byte(request_postfix, 1, 1) == SLASH then
                      -- double "/", so drop the first
                      upstream_uri = sub(upstream_base, 1, -2) .. request_postfix
                    else -- ends with / and strip_uri = true, no double slash
                      upstream_uri = upstream_base .. request_postfix
                    end

                  else -- ends with / and strip_uri = false
                    -- we retain the incoming path, just prefix it with the upstream
                    -- path, but skip the initial slash
                    upstream_uri = upstream_base .. sub(req_uri, 2)
                  end

                else -- does not end with /
                  -- does not end with / and strip_uri = true
                  if matched_route.strip_uri then
                    if request_postfix == "" then
                      if #req_uri > 1 and byte(req_uri, -1) == SLASH then
                        upstream_uri = upstream_base .. "/"
                      else
                        upstream_uri = upstream_base
                      end
                    elseif byte(request_postfix, 1, 1) == SLASH then
                      upstream_uri = upstream_base .. request_postfix
                    else
                      upstream_uri = upstream_base .. "/" .. request_postfix
                    end

                  else -- does not end with / and strip_uri = false
                    if req_uri == "/" then
                      upstream_uri = upstream_base
                    else
                      upstream_uri = upstream_base .. req_uri
                    end
                  end
                end
              end

              -- preserve_host header logic

              if matched_route.preserve_host then
                upstream_host = raw_req_host or var.http_host
              end
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
                headers       = matches.headers,
                method        = matches.method,
                src_ip        = matches.src_ip,
                src_port      = matches.src_port,
                dst_ip        = matches.dst_ip,
                dst_port      = matches.dst_port,
                sni           = matches.sni,
              }
            }

            if band(matched_route.match_rules, MATCH_RULES.HEADER) == 0 then
              cache:set(cache_key, match_t)
            end

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
  self._set_ngx = _set_ngx

  if subsystem == "http" then
    function self.exec()
      local req_method = get_method()
      local req_uri = var.request_uri
      local req_host = var.http_host or ""
      local req_scheme = var.scheme
      local sni = var.ssl_server_name

      local headers
      local err

      if grab_req_headers then
        headers, err = get_headers(MAX_REQ_HEADERS)
        if err == "truncated" then
          log(WARN, "retrieved ", MAX_REQ_HEADERS, " headers for evaluation ",
                    "(max) but request had more; other headers will be ignored")
        end

        headers["host"] = nil
      end

      do
        local idx = find(req_uri, "?", 2, true)
        if idx then
          req_uri = sub(req_uri, 1, idx - 1)
        end
      end

      local match_t = find_route(req_method, req_uri, req_host, req_scheme,
                                 nil, nil, -- src_ip, src_port
                                 nil, nil, -- dst_ip, dst_port
                                 sni, headers)
      if not match_t then
        return nil
      end

      -- debug HTTP request header logic

      if var.http_kong_debug then
        if match_t.route then
          if match_t.route.id then
            header["Kong-Route-Id"] = match_t.route.id
          end

          if match_t.route.name then
            header["Kong-Route-Name"] = match_t.route.name
          end
        end

        if match_t.service then
          if match_t.service.id then
            header["Kong-Service-Id"] = match_t.service.id
          end

          if match_t.service.name then
            header["Kong-Service-Name"] = match_t.service.name
          end
        end
      end

      return match_t
    end

  else -- stream
    function self.exec(ctx)
      local src_ip = var.remote_addr
      local src_port = tonumber(var.remote_port, 10)
      local dst_ip = var.server_addr
      local dst_port = tonumber(var.server_port, 10)
      local sni = ctx.sni_server_name

      return find_route(nil, nil, nil, nil,
                        src_ip, src_port,
                        dst_ip, dst_port,
                        sni)
    end
  end

  return self
end


return _M
