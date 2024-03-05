local _M = {}


local bit = require("bit")
local buffer = require("string.buffer")
local atc = require("kong.router.atc")
local utils = require("kong.router.utils")
local tb_new = require("table.new")
local tb_nkeys = require("table.nkeys")
local uuid = require("resty.jit-uuid")


local shallow_copy          = require("kong.tools.utils").shallow_copy
local replace_dashes_lower  = require("kong.tools.string").replace_dashes_lower


local is_regex_magic  = utils.is_regex_magic
local parse_ip_addr   = utils.parse_ip_addr


local escape_str      = atc.escape_str
local is_empty_field  = atc.is_empty_field
local gen_for_field   = atc.gen_for_field
local split_host_port = atc.split_host_port


local type = type
local pairs = pairs
local ipairs = ipairs
local assert = assert
local tb_insert = table.insert
local byte = string.byte
local bor, band, lshift = bit.bor, bit.band, bit.lshift


local is_http = ngx.config.subsystem == "http"


local DOT              = byte(".")
local TILDE            = byte("~")
local ASTERISK         = byte("*")
local MAX_HEADER_COUNT = 255


-- reuse buffer objects
local expr_buf          = buffer.new(128)
local hosts_buf         = buffer.new(64)
local headers_buf       = buffer.new(128)
local single_header_buf = buffer.new(64)


-- sep: a seperator of expressions, like '&&'
-- idx: indicate whether or not to add 'sep'
--      for example, we should not add 'sep' for the first element in array
local function expression_append(buf, sep, str, idx)
  if #buf > 0 and
     (idx == nil or idx > 1)
  then
    buf:put(sep)
  end
  buf:put(str)
end


local OP_EQUAL    = "=="
local OP_PREFIX   = "^="
local OP_POSTFIX  = "=^"
local OP_REGEX    = "~"
local OP_IN       = "in"


local LOGICAL_OR  = atc.LOGICAL_OR
local LOGICAL_AND = atc.LOGICAL_AND


-- When splitting routes, we need to assign new UUIDs to the split routes.  We use uuid v5 to generate them from
-- the original route id and the path index so that incremental rebuilds see stable IDs for routes that have not
-- changed.
local uuid_generator = assert(uuid.factory_v5('7f145bf9-0dce-4f91-98eb-debbce4b9f6b'))


local function gen_for_nets(ip_field, port_field, vals)
  if is_empty_field(vals) then
    return nil
  end

  local nets_buf = buffer.new(64):put("(")

  for i = 1, #vals do
    local v = vals[i]

    if type(v) ~= "table" then
      ngx.log(ngx.ERR, "sources/destinations elements must be a table")
      return nil
    end

    if is_empty_field(v) then
      ngx.log(ngx.ERR, "sources/destinations elements must not be empty")
      return nil
    end

    local ip = v.ip
    local port = v.port

    local exp_ip, exp_port

    if ip then
      local addr, mask = parse_ip_addr(ip)

      if mask then  -- ip in cidr
        exp_ip = ip_field .. " " .. OP_IN ..  " " ..
                 addr .. "/" .. mask

      else          -- ip == addr
        exp_ip = ip_field .. " " .. OP_EQUAL .. " " ..
                 addr
      end
    end

    if port then
      exp_port = port_field .. " " .. OP_EQUAL .. " " .. port
    end

    if not ip then
      expression_append(nets_buf, LOGICAL_OR, exp_port, i)
      goto continue
    end

    if not port then
      expression_append(nets_buf, LOGICAL_OR, exp_ip, i)
      goto continue
    end

    expression_append(nets_buf, LOGICAL_OR,
                      "(" .. exp_ip .. LOGICAL_AND .. exp_port .. ")", i)

    ::continue::
  end   -- for

  return nets_buf:put(")"):get()
end


local function get_expression(route)
  local methods = route.methods
  local hosts   = route.hosts
  local paths   = route.paths
  local headers = route.headers
  local snis    = route.snis

  local srcs    = route.sources
  local dsts    = route.destinations

  expr_buf:reset()

  local gen = gen_for_field("tls.sni", OP_EQUAL, snis, function(_, p)
    if #p > 1 and byte(p, -1) == DOT then
      -- last dot in FQDNs must not be used for routing
      return p:sub(1, -2)
    end

    return p
  end)
  if gen then
    -- See #6425, if `net.protocol` is not `https`
    -- then SNI matching should simply not be considered
    if srcs or dsts then
      gen = "(net.protocol != r#\"tls\"#"   .. LOGICAL_OR .. gen .. ")"
    else
      gen = "(net.protocol != r#\"https\"#" .. LOGICAL_OR .. gen .. ")"
    end

    expression_append(expr_buf, LOGICAL_AND, gen)
  end

  -- stream expression

  do
    local src_gen = gen_for_nets("net.src.ip", "net.src.port", srcs)
    local dst_gen = gen_for_nets("net.dst.ip", "net.dst.port", dsts)

    if src_gen then
      expression_append(expr_buf, LOGICAL_AND, src_gen)
    end

    if dst_gen then
      expression_append(expr_buf, LOGICAL_AND, dst_gen)
    end

    if src_gen or dst_gen then
      return expr_buf:get()
    end
  end

  -- http expression

  local gen = gen_for_field("http.method", OP_EQUAL, methods)
  if gen then
    expression_append(expr_buf, LOGICAL_AND, gen)
  end

  if not is_empty_field(hosts) then
    hosts_buf:reset():put("(")

    for i, h in ipairs(hosts) do
      local host, port = split_host_port(h)

      local op = OP_EQUAL
      if byte(host) == ASTERISK then
        -- postfix matching
        op = OP_POSTFIX
        host = host:sub(2)

      elseif byte(host, -1) == ASTERISK then
        -- prefix matching
        op = OP_PREFIX
        host = host:sub(1, -2)
      end

      local exp = "http.host ".. op .. " \"" .. host .. "\""
      if port then
        exp = "(" .. exp .. LOGICAL_AND ..
              "net.port ".. OP_EQUAL .. " " .. port .. ")"
      end
      expression_append(hosts_buf, LOGICAL_OR, exp, i)
    end -- for route.hosts

    expression_append(expr_buf, LOGICAL_AND,
                      hosts_buf:put(")"):get())
  end

  gen = gen_for_field("http.path", function(path)
    return is_regex_magic(path) and OP_REGEX or OP_PREFIX
  end, paths, function(op, p)
    if op == OP_REGEX then
      -- 1. strip leading `~`
      -- 2. prefix with `^` to match the anchored behavior of the traditional router
      -- 3. update named capture opening tag for rust regex::Regex compatibility
      return "^" .. p:sub(2):gsub("?<", "?P<")
    end

    return p
  end)
  if gen then
    expression_append(expr_buf, LOGICAL_AND, gen)
  end

  if not is_empty_field(headers) then
    headers_buf:reset()

    for h, v in pairs(headers) do
      single_header_buf:reset():put("(")

      for i, value in ipairs(v) do
        local name = "any(http.headers." .. replace_dashes_lower(h) .. ")"
        local op = OP_EQUAL

        -- value starts with "~*"
        if byte(value, 1) == TILDE and byte(value, 2) == ASTERISK then
          value = value:sub(3)
          op = OP_REGEX
        end

        expression_append(single_header_buf, LOGICAL_OR,
                          name .. " " .. op .. " " .. escape_str(value:lower()), i)
      end

      expression_append(headers_buf, LOGICAL_AND,
                        single_header_buf:put(")"):get())
    end

    expression_append(expr_buf, LOGICAL_AND, headers_buf:get())
  end

  return expr_buf:get()
end


local lshift_uint64
do
  local ffi = require("ffi")
  local ffi_uint = ffi.new("uint64_t")

  lshift_uint64 = function(v, offset)
    ffi_uint = v
    return lshift(ffi_uint, offset)
  end
end


local stream_get_priority
do
  -- compatible with http priority
  local STREAM_SNI_BIT = lshift_uint64(0x01ULL, 61)

  -- IP > PORT > CIDR
  local IP_BIT         = lshift_uint64(0x01ULL, 3)
  local PORT_BIT       = lshift_uint64(0x01ULL, 2)
  local CIDR_BIT       = lshift_uint64(0x01ULL, 0)

  local function calc_ip_weight(ips)
    local weight = 0x0ULL

    if is_empty_field(ips) then
      return weight
    end

    for i = 1, #ips do
      local ip   = ips[i].ip
      local port = ips[i].port

      if ip then
        if ip:find("/", 1, true) then
          weight = bor(weight, CIDR_BIT)

        else
          weight = bor(weight, IP_BIT)
        end
      end

      if port then
        weight = bor(weight, PORT_BIT)
      end
    end

    return weight
  end

  stream_get_priority = function(snis, srcs, dsts)
    local match_weight = 0x0ULL

    -- [sni] has higher priority than [src] or [dst]
    if not is_empty_field(snis) then
      match_weight = STREAM_SNI_BIT
    end

    -- [src] + [dst] has higher priority than [sni]
    if not is_empty_field(srcs) and
       not is_empty_field(dsts)
    then
      match_weight = STREAM_SNI_BIT
    end

    local src_bits = calc_ip_weight(srcs)
    local dst_bits = calc_ip_weight(dsts)

    local priority = bor(match_weight,
                         lshift(src_bits, 4),
                         dst_bits)

    return priority
  end
end


local PLAIN_HOST_ONLY_BIT = lshift_uint64(0x01ULL, 60)
local REGEX_URL_BIT       = lshift_uint64(0x01ULL, 51)


-- convert a route to a priority value for use in the ATC router
-- priority must be a 64-bit non negative integer
-- format (big endian):
--  0                   1                   2                   3
--  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
-- +-----+-+---------------+-+-------------------------------------+
-- | W   |P| Header        |R|  Regex                              |
-- | G   |L|               |G|  Priority                           |
-- | T   |N| Count         |X|                                     |
-- +-----+-+-----------------+-------------------------------------+
-- |  Regex Priority         |   Max Length                        |
-- |  (cont)                 |                                     |
-- |                         |                                     |
-- +-------------------------+-------------------------------------+
local function get_priority(route)
  local snis = route.snis
  local srcs = route.sources
  local dsts = route.destinations

  -- stream expression

  if not is_empty_field(srcs) or
     not is_empty_field(dsts)
  then
    return stream_get_priority(snis, srcs, dsts)
  end

  -- http expression

  local methods = route.methods
  local hosts   = route.hosts
  local paths   = route.paths
  local headers = route.headers

  local match_weight = 0  -- 0x0ULL

  if not is_empty_field(methods) then
    match_weight = match_weight + 1
  end

  if not is_empty_field(hosts) then
    match_weight = match_weight + 1
  end

  local headers_count = is_empty_field(headers) and 0 or tb_nkeys(headers)

  if headers_count > 0 then
    match_weight = match_weight + 1

    if headers_count > MAX_HEADER_COUNT then
      ngx.log(ngx.WARN, "too many headers in route ", route.id,
                        " headers count capped at ", MAX_HEADER_COUNT,
                        " when sorting")
      headers_count = MAX_HEADER_COUNT
    end
  end

  if not is_empty_field(snis) then
    match_weight = match_weight + 1
  end

  local plain_host_only = type(hosts) == "table"

  if plain_host_only then
    for _, h in ipairs(hosts) do
      if h:find("*", nil, true) then
        plain_host_only = false
        break
      end
    end
  end

  local uri_length = 0
  local regex_url = false

  if not is_empty_field(paths) then
    match_weight = match_weight + 1

    local p = paths[1]

    if is_regex_magic(p) then
      regex_url = true

    else
      uri_length = #p
    end

    for i = 2, #paths do
      p = paths[i]

      if regex_url then
        assert(is_regex_magic(p),
               "cannot mix regex and non-regex paths in get_priority()")

      else
        assert(#p == uri_length,
               "cannot mix different length prefixes in get_priority()")
      end
    end
  end

  local match_weight   = lshift_uint64(match_weight, 61)
  local headers_count  = lshift_uint64(headers_count, 52)

  local regex_priority = lshift_uint64(regex_url and route.regex_priority or 0, 19)
  local max_length     = band(uri_length, 0x7FFFF)

  local priority = bor(match_weight,
                       plain_host_only and PLAIN_HOST_ONLY_BIT or 0,
                       regex_url and REGEX_URL_BIT or 0,
                       headers_count,
                       regex_priority,
                       max_length)

  return priority
end


local function get_exp_and_priority(route)
  if route.expression then
    ngx.log(ngx.ERR, "expecting a traditional route while it's not (probably an expressions route). ",
                     "Likely it's a misconfiguration. Please check the 'router_flavor' config in kong.conf")
  end

  local exp      = get_expression(route)
  local priority = get_priority(route)

  return exp, priority
end


-- group array-like table t by the function f, returning a table mapping from
-- the result of invoking f on one of the elements to the actual elements.
local function group_by(t, f)
  local result = {}
  for _, value in ipairs(t) do
    local key = f(value)
    if result[key] then
      tb_insert(result[key], value)
    else
      result[key] = { value }
    end
  end
  return result
end

-- split routes into multiple routes, one for each prefix length and one for all
-- regular expressions
local function split_route_by_path_into(route_and_service, routes_and_services_split)
  local original_route = route_and_service.route

  if is_empty_field(original_route.paths) or #original_route.paths == 1 then
    tb_insert(routes_and_services_split, route_and_service)
    return
  end

  -- make sure that route_and_service contains only the two expected entries, route and service
  assert(tb_nkeys(route_and_service) == 1 or tb_nkeys(route_and_service) == 2)

  local grouped_paths = group_by(
    original_route.paths,
    function(path)
      return is_regex_magic(path) or #path
    end
  )
  for index, paths in pairs(grouped_paths) do
    local cloned_route = {
      route = shallow_copy(original_route),
      service = route_and_service.service,
    }

    cloned_route.route.original_route = original_route
    cloned_route.route.paths = paths
    cloned_route.route.id = uuid_generator(original_route.id .. "#" .. tostring(index))

    tb_insert(routes_and_services_split, cloned_route)
  end
end


local function split_routes_and_services_by_path(routes_and_services)
  local count = #routes_and_services
  local routes_and_services_split = tb_new(count, 0)

  for i = 1, count do
    split_route_by_path_into(routes_and_services[i], routes_and_services_split)
  end

  return routes_and_services_split
end


function _M.new(routes_and_services, cache, cache_neg, old_router)
  -- route_and_service argument is a table with [route] and [service]
  if type(routes_and_services) ~= "table" then
    return error("expected arg #1 routes to be a table", 2)
  end

  if is_http then
    routes_and_services = split_routes_and_services_by_path(routes_and_services)
  end

  return atc.new(routes_and_services, cache, cache_neg, old_router, get_exp_and_priority)
end


-- for schema validation and unit-testing
_M.get_expression = get_expression


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx
_M._get_priority = get_priority


return _M
