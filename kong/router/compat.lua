local _M = {}


local atc = require("kong.router.atc")
local bit = require("bit")
local normalize = require("kong.tools.uri").normalize
local tb_new = require("table.new")
local tb_clear = require("table.clear")
local tb_nkeys = require("table.nkeys")


local atc_escape_str = atc.atc_escape_str
local gen_for_field = atc.gen_for_field
local split_host_port = atc.split_host_port


local tb_concat = table.concat
local tb_insert = table.insert
local tb_sort = table.sort
local byte = string.byte
local sub = string.sub
local pairs = pairs
local ipairs = ipairs
local max = math.max
local bor, band, lshift = bit.bor, bit.band, bit.lshift


local ngx       = ngx
local null      = ngx.null
local ngx_log   = ngx.log
local ngx_WARN  = ngx.WARN


local TILDE            = byte("~")
local ASTERISK         = byte("*")
local MAX_HEADER_COUNT = 255


-- reuse table objects
local atc_out_t           = tb_new(10, 0)
local atc_hosts_t         = tb_new(10, 0)
local atc_headers_t       = tb_new(10, 0)
local atc_single_header_t = tb_new(10, 0)


local function is_regex_magic(path)
  return byte(path) == TILDE
end


-- resort `paths` to move regex routes to the front of the array
local function paths_resort(paths)
  if not paths then
    return
  end

  tb_sort(paths, function(a, b)
    return is_regex_magic(a) and not is_regex_magic(b)
  end)
end


local OP_EQUAL    = "=="
local OP_PREFIX   = "^="
local OP_POSTFIX  = "=^"
local OP_REGEX    = "~"


local function get_expression(route)
  tb_clear(atc_out_t)
  local out = atc_out_t

  local gen = gen_for_field("http.method", OP_EQUAL, route.methods)
  if gen then
    tb_insert(out, gen)
  end

  local gen = gen_for_field("tls.sni", OP_EQUAL, route.snis)
  if gen then
    -- See #6425, if `net.protocol` is not `https`
    -- then SNI matching should simply not be considered
    gen = "net.protocol != \"https\" || " .. gen
    tb_insert(out, gen)
  end

  if route.hosts and route.hosts ~= null then
    tb_clear(atc_hosts_t)
    local hosts = atc_hosts_t

    for _, h in ipairs(route.hosts) do
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

      local atc = "http.host ".. op .. " \"" .. host .. "\""
      if not port then
        tb_insert(atc_hosts_t, atc)

      else
        tb_insert(atc_hosts_t, "(" .. atc ..
                               " && net.port ".. OP_EQUAL .. " " .. port .. ")")
      end
    end -- for route.hosts

    tb_insert(out, "(" .. tb_concat(hosts, " || ") .. ")")
  end

  -- move regex paths to the front
  if route.paths ~= null then
    paths_resort(route.paths)
  end

  local gen = gen_for_field("http.path", function(path)
    return is_regex_magic(path) and OP_REGEX or OP_PREFIX
  end, route.paths, function(op, p)
    if op == OP_REGEX then
      -- Rust only recognize form '?P<>'
      return sub(p, 2):gsub("?<", "?P<")
    end

    return normalize(p, true)
  end)
  if gen then
    tb_insert(out, gen)
  end

  if route.headers and route.headers ~= null then
    tb_clear(atc_headers_t)
    local headers = atc_headers_t

    for h, v in pairs(route.headers) do
      tb_clear(atc_single_header_t)
      local single_header = atc_single_header_t

      for _, ind in ipairs(v) do
        local name = "any(http.headers." .. h:gsub("-", "_"):lower() .. ")"
        local value = ind
        local op = OP_EQUAL
        if ind:sub(1, 2) == "~*" then
          value = ind:sub(3)
          op = OP_REGEX
        end

        tb_insert(single_header, name .. " " .. op .. " " .. atc_escape_str(value:lower()))
      end

      tb_insert(headers, "(" .. tb_concat(single_header, " || ") .. ")")
    end

    tb_insert(out, tb_concat(headers, " && "))
  end

  return tb_concat(out, " && ")
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


local PLAIN_HOST_ONLY_BIT = lshift(0x01ULL, 60)
local REGEX_URL_BIT       = lshift(0x01ULL, 51)


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
local function get_priority(r)
  local methods = r.methods
  local hosts   = r.hosts
  local paths   = r.paths
  local headers = r.headers
  local snis    = r.snis

  local match_weight = 0

  if methods and #methods > 0 then
    match_weight = match_weight + 1
  end

  if hosts and #hosts > 0 then
    match_weight = match_weight + 1
  end

  if paths and #paths > 0 then
    match_weight = match_weight + 1
  end

  local headers_count = headers and tb_nkeys(headers) or 0

  if headers_count > 0 then
    match_weight = match_weight + 1
  end

  if headers_count > MAX_HEADER_COUNT then
    ngx_log(ngx_WARN, "too many headers in route ", r.id,
                      " headers count capped at 255 when sorting")
    headers_count = MAX_HEADER_COUNT
  end

  if snis and #snis > 0 then
    match_weight = match_weight + 1
  end

  local plain_host_only = not not hosts

  if hosts then
    for _, h in ipairs(hosts) do
      if h:find("*", nil, true) then
        plain_host_only = false
        break
      end
    end
  end

  local max_uri_length = 0
  local regex_url = false

  if paths then
    for _, p in ipairs(paths) do
      if is_regex_magic(p) then
        regex_url = true

      else
        -- plain URI or URI prefix
        max_uri_length = max(max_uri_length, #p)
      end
    end
  end

  local match_weight = lshift_uint64(match_weight, 61)
  local headers_count = lshift_uint64(headers_count, 52)
  local regex_priority = lshift_uint64(regex_url and r.regex_priority or 0, 19)
  local max_length = band(max_uri_length, 0x7FFFF)

  local priority =  bor(match_weight,
                        plain_host_only and PLAIN_HOST_ONLY_BIT or 0,
                        regex_url and REGEX_URL_BIT or 0,
                        headers_count,
                        regex_priority,
                        max_length)

  return priority
end


local function get_exp_priority(route)
  local exp = get_expression(route)
  local priority = get_priority(route)

  return exp, priority
end


function _M.new(routes, cache, cache_neg, old_router)
  return atc.new(routes, cache, cache_neg, old_router, get_exp_priority)
end


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx
_M._get_expression = get_expression
_M._get_priority = get_priority


return _M
