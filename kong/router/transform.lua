local bit = require("bit")
local buffer = require("string.buffer")
local tb_new = require("table.new")
local tb_nkeys = require("table.nkeys")
local uuid = require("resty.jit-uuid")
local lrucache = require("resty.lrucache")
local ipmatcher = require("resty.ipmatcher")
local utils = require("kong.router.utils")


local type = type
local assert = assert
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tb_insert = table.insert
local fmt = string.format
local byte = string.byte
local bor, band, lshift, rshift = bit.bor, bit.band, bit.lshift, bit.rshift


local is_regex_magic  = utils.is_regex_magic
local replace_dashes_lower  = require("kong.tools.string").replace_dashes_lower
local shallow_copy = require("kong.tools.table").shallow_copy


local is_null
local is_empty_field
do
  local null    = ngx.null
  local isempty = require("table.isempty")

  is_null = function(v)
    return v == nil or v == null
  end

  is_empty_field = function(f)
    return f == nil or f == null or isempty(f)
  end
end


local function escape_str(str)
  -- raw string
  if not str:find([["#]], 1, true) then
    return "r#\"" .. str .. "\"#"
  end

  -- standard string escaping (unlikely case)
  if str:find([[\]], 1, true) then
    str = str:gsub([[\]], [[\\]])
  end

  if str:find([["]], 1, true) then
    str = str:gsub([["]], [[\"]])
  end

  return "\"" .. str .. "\""
end


-- split port in host, ignore form '[...]'
-- example.com:123 => example.com, 123
-- example.*:123 => example.*, 123
local split_host_port
do
  local tonumber = tonumber

  local DEFAULT_HOSTS_LRUCACHE_SIZE = utils.DEFAULT_MATCH_LRUCACHE_SIZE

  local memo_hp = lrucache.new(DEFAULT_HOSTS_LRUCACHE_SIZE)

  split_host_port = function(key)
    if not key then
      return nil, nil
    end

    local m = memo_hp:get(key)

    if m then
      return m[1], m[2]
    end

    local p = key:find(":", nil, true)
    if not p then
      memo_hp:set(key, { key, nil })
      return key, nil
    end

    local port = tonumber(key:sub(p + 1))

    if not port then
      memo_hp:set(key, { key, nil })
      return key, nil
    end

    local host = key:sub(1, p - 1)

    memo_hp:set(key, { host, port })

    return host, port
  end
end


local LOGICAL_OR  = " || "
local LOGICAL_AND = " && "


local OP_EQUAL    = "=="
local OP_PREFIX   = "^="
local OP_POSTFIX  = "=^"
local OP_REGEX    = "~"
local OP_IN       = "in"


local DOT              = byte(".")
local TILDE            = byte("~")
local ASTERISK         = byte("*")


-- reuse buffer objects
local values_buf        = buffer.new(64)
local nets_buf          = buffer.new(64)
local expr_buf          = buffer.new(64)
local hosts_buf         = buffer.new(64)
local headers_buf       = buffer.new(64)
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


local function gen_for_field(name, op, vals, val_transform)
  if is_empty_field(vals) then
    return nil
  end

  local vals_n = #vals
  assert(vals_n > 0)

  values_buf:reset():put("(")

  for i = 1, vals_n do
    local p = vals[i]
    local op = (type(op) == "string") and op or op(p)

    local expr = fmt("%s %s %s", name, op,
                    escape_str(val_transform and val_transform(op, p) or p))

    expression_append(values_buf, LOGICAL_OR, expr, i)
  end

  -- consume the whole buffer
  -- returns a local variable instead of using a tail call
  -- to avoid NYI
  local str = values_buf:put(")"):get()

  return str
end


local function parse_ip_addr(ip)
  local addr, mask = ipmatcher.split_ip(ip)

  if not mask then
    return addr
  end

  local ipv4 = ipmatcher.parse_ipv4(addr)

  -- FIXME: support ipv6
  if not ipv4 then
    return addr, mask
  end

  local cidr = lshift(rshift(ipv4, 32 - mask), 32 - mask)

  local n1 = band(       cidr     , 0xff)
  local n2 = band(rshift(cidr,  8), 0xff)
  local n3 = band(rshift(cidr, 16), 0xff)
  local n4 = band(rshift(cidr, 24), 0xff)

  return n4 .. "." .. n3 .. "." .. n2 .. "." .. n1, mask
end


local function gen_for_nets(ip_field, port_field, vals)
  if is_empty_field(vals) then
    return nil
  end

  nets_buf:reset():put("(")

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

    if not is_null(ip) then
      local addr, mask = parse_ip_addr(ip)

      if mask then  -- ip in cidr
        exp_ip = ip_field .. " " .. OP_IN ..  " " ..
                 addr .. "/" .. mask

      else          -- ip == addr
        exp_ip = ip_field .. " " .. OP_EQUAL .. " " ..
                 addr
      end
    end

    if not is_null(port) then
      exp_port = port_field .. " " .. OP_EQUAL .. " " .. port
    end

    -- only add port expression
    if is_null(ip) then
      expression_append(nets_buf, LOGICAL_OR, exp_port, i)
      goto continue
    end

    -- only add ip address expression
    if is_null(port) then
      expression_append(nets_buf, LOGICAL_OR, exp_ip, i)
      goto continue
    end

    -- add port and ip address expression with '()'
    expression_append(nets_buf, LOGICAL_OR,
                      "(" .. exp_ip .. LOGICAL_AND .. exp_port .. ")", i)

    ::continue::
  end   -- for

  local str = nets_buf:put(")"):get()

  -- returns a local variable instead of using a tail call
  -- to avoid NYI
  return str
end


local is_stream_route
do
  local is_stream_protocol = {
    tcp = true,
    udp = true,
    tls = true,
    tls_passthrough = true,
  }

  is_stream_route = function(r)
    if not r.protocols then
      return false
    end

    return is_stream_protocol[r.protocols[1]]
  end
end


local function sni_val_transform(_, p)
  if #p > 1 and byte(p, -1) == DOT then
    -- last dot in FQDNs must not be used for routing
    return p:sub(1, -2)
  end

  return p
end


local function path_op_transform(path)
  return is_regex_magic(path) and OP_REGEX or OP_PREFIX
end


local function path_val_transform(op, p)
  if op == OP_REGEX then
    -- 1. strip leading `~`
    -- 2. prefix with `^` to match the anchored behavior of the traditional router
    -- 3. update named capture opening tag for rust regex::Regex compatibility
    return "^" .. p:sub(2):gsub("?<", "?P<")
  end

  return p
end


local function get_expression(route)
  -- we perfer the field 'expression', reject others
  if not is_null(route.expression) then
    return route.expression
  end

  -- transform other fields (methods/hosts/paths/...) to expression

  local methods = route.methods
  local hosts   = route.hosts
  local paths   = route.paths
  local headers = route.headers
  local snis    = route.snis

  local srcs    = route.sources
  local dsts    = route.destinations

  expr_buf:reset()

  local gen = gen_for_field("tls.sni", OP_EQUAL, snis, sni_val_transform)
  if gen then
    -- See #6425, if `net.protocol` is not `https`
    -- then SNI matching should simply not be considered
    if is_stream_route(route) then
      gen = "(net.protocol != r#\"tls\"#"   .. LOGICAL_OR .. gen .. ")"
    else
      gen = "(net.protocol != r#\"https\"#" .. LOGICAL_OR .. gen .. ")"
    end

    expression_append(expr_buf, LOGICAL_AND, gen)
  end

  -- now http route support net.src.* and net.dst.*

  local src_gen = gen_for_nets("net.src.ip", "net.src.port", srcs)
  local dst_gen = gen_for_nets("net.dst.ip", "net.dst.port", dsts)

  if src_gen then
    expression_append(expr_buf, LOGICAL_AND, src_gen)
  end

  if dst_gen then
    expression_append(expr_buf, LOGICAL_AND, dst_gen)
  end

  -- stream expression, protocol = tcp/udp/tls/tls_passthrough

  if is_stream_route(route) then
    -- returns a local variable instead of using a tail call
    -- to avoid NYI
    local str = expr_buf:get()
    return str
  end

  -- http expression, protocol = http/https/grpc/grpcs

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

      local exp = "http.host ".. op .. " r#\"" .. host .. "\"#"
      if port then
        exp = "(" .. exp .. LOGICAL_AND ..
              "net.dst.port ".. OP_EQUAL .. " " .. port .. ")"
      end
      expression_append(hosts_buf, LOGICAL_OR, exp, i)
    end -- for route.hosts

    expression_append(expr_buf, LOGICAL_AND,
                      hosts_buf:put(")"):get())
  end

  gen = gen_for_field("http.path", path_op_transform, paths, path_val_transform)
  if gen then
    expression_append(expr_buf, LOGICAL_AND, gen)
  end

  if not is_empty_field(headers) then
    headers_buf:reset()

    for h, v in pairs(headers) do
      single_header_buf:reset():put("(")

      for i, value in ipairs(v) do
        local name = "any(lower(http.headers." .. replace_dashes_lower(h) .. "))"
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

  local str = expr_buf:get()

  -- returns a local variable instead of using a tail call
  -- to avoid NYI
  return str
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

      if not is_null(ip) then
        if ip:find("/", 1, true) then
          weight = bor(weight, CIDR_BIT)

        else
          weight = bor(weight, IP_BIT)
        end
      end

      if not is_null(port) then
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
                         lshift_uint64(src_bits, 4),
                         dst_bits)

    return priority
  end
end


local MAX_HEADER_COUNT = 255


local PLAIN_HOST_ONLY_BIT = lshift_uint64(0x01ULL, 60)
local REGEX_URL_BIT       = lshift_uint64(0x01ULL, 51)


-- expression only route has higher priority than traditional route
local EXPRESSION_ONLY_BIT = lshift_uint64(0xFFULL, 56)


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
  -- we perfer the fields 'expression' and 'priority'
  if not is_null(route.expression) then
    return bor(EXPRESSION_ONLY_BIT, route.priority or 0)
  end

  -- transform other fields (methods/hosts/paths/...) to expression priority

  local snis = route.snis
  local srcs = route.sources
  local dsts = route.destinations

  -- stream expression

  if is_stream_route(route) then
    return stream_get_priority(snis, srcs, dsts)
  end

  -- http expression

  local methods = route.methods
  local hosts   = route.hosts
  local paths   = route.paths
  local headers = route.headers

  local match_weight = 0  -- 0x0ULL

  if not is_empty_field(srcs) then
    match_weight = match_weight + 1
  end

  if not is_empty_field(dsts) then
    match_weight = match_weight + 1
  end

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


-- When splitting routes, we need to assign new UUIDs to the split routes.  We use uuid v5 to generate them from
-- the original route id and the path index so that incremental rebuilds see stable IDs for routes that have not
-- changed.
local uuid_generator = assert(uuid.factory_v5('7f145bf9-0dce-4f91-98eb-debbce4b9f6b'))


local function sort_by_regex_or_length(path)
  return is_regex_magic(path) or #path
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

  if is_empty_field(original_route.paths) or #original_route.paths == 1 or
     not is_null(original_route.expression) -- expression will ignore paths
  then
    tb_insert(routes_and_services_split, route_and_service)
    return
  end

  -- make sure that route_and_service contains only the two expected entries, route and service
  assert(tb_nkeys(route_and_service) == 1 or tb_nkeys(route_and_service) == 2)

  local grouped_paths = group_by(
    original_route.paths, sort_by_regex_or_length
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


return {
  OP_EQUAL    = OP_EQUAL,

  LOGICAL_OR  = LOGICAL_OR,
  LOGICAL_AND = LOGICAL_AND,

  split_host_port = split_host_port,

  is_null = is_null,
  is_empty_field = is_empty_field,

  gen_for_field = gen_for_field,

  get_expression = get_expression,
  get_priority = get_priority,

  split_routes_and_services_by_path = split_routes_and_services_by_path,
}

