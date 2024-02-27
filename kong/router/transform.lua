local bit = require("bit")
local buffer = require("string.buffer")
local lrucache = require("resty.lrucache")
local utils = require("kong.router.utils")


local type = type
local assert = assert
local tonumber = tonumber
local ipairs = ipairs
local fmt = string.format
local byte = string.byte
local band, lshift, rshift = bit.band, bit.lshift, bit.rshift


local is_regex_magic  = utils.is_regex_magic
local replace_dashes_lower  = require("kong.tools.string").replace_dashes_lower


local is_empty_field
do
  local null    = ngx.null
  local isempty = require("table.isempty")

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


local parse_ip_addr
do
  local ipmatcher = require("resty.ipmatcher")


  parse_ip_addr = function(ip)
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
end


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

  local str = nets_buf:put(")"):get()

  -- returns a local variable instead of using a tail call
  -- to avoid NYI
  return str
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
      -- returns a local variable instead of using a tail call
      -- to avoid NYI
      local str = expr_buf:get()
      return str
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


return {
  LOGICAL_OR  = LOGICAL_OR,
  LOGICAL_AND = LOGICAL_AND,

  split_host_port = split_host_port,

  is_empty_field = is_empty_field,
  escape_str = escape_str,
  gen_for_field = gen_for_field,

  get_expression = get_expression,

  lshift_uint64 = lshift_uint64,
}

