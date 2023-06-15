local _M = {}


local buffer = require("string.buffer")
local atc = require("kong.router.atc")


local is_empty_field  = atc.is_empty_field
local gen_for_field   = atc.gen_for_field


local type = type
local ipairs = ipairs
local byte = string.byte


local ngx       = ngx
local ngx_log   = ngx.log
local ngx_ERR   = ngx.ERR


local DOT         = byte(".")


local OP_EQUAL    = "=="
local OP_IN       = "in"


local LOGICAL_OR  = atc.LOGICAL_OR
local LOGICAL_AND = atc.LOGICAL_AND


-- reuse buffer objects
local exp_buf  = buffer.new(128)
local nets_buf = buffer.new(64)


local function buffer_append(buf, sep, str, idx)
  if #buf > 0 and
     (idx == nil or idx > 1)
  then
    buf:put(sep)
  end
  buf:put(str)
end


local function gen_for_nets(ip_field, port_field, vals)
  if is_empty_field(vals) then
    return nil
  end

  nets_buf:reset():put("(")

  for i, v in ipairs(vals) do
    local ip = v.ip
    local port = v.port

    local exp_ip, exp_port

    if ip then
      exp_ip = ip_field .. " " ..
               (string.find(ip, "/", 1, true) and OP_IN or OP_EQUAL) ..
               " \"" .. ip .. "\""
    end

    if port then
      exp_port = port_field .. " " ..  OP_EQUAL .. " " .. port
    end

    if not ip then
      buffer_append(nets_buf, LOGICAL_OR, exp_port, i)

    elseif not port then
      buffer_append(nets_buf, LOGICAL_OR, exp_ip, i)

    else
      buffer_append(nets_buf, LOGICAL_OR,
                    "(" .. exp_ip .. LOGICAL_AND .. exp_port .. ")", i)
    end
  end   -- for

  return nets_buf:get()
end


local function get_expression(route)
  local snis = route.snis
  local srcs = route.sources
  local dsts = route.destinations

  exp_buf:reset()

  local gen = gen_for_field("tls.sni", OP_EQUAL, snis, function(_, p)
    if #p > 1 and byte(p, -1) == DOT then
      -- last dot in FQDNs must not be used for routing
      return p:sub(1, -2)
    end

    return p
  end)
  if gen then
    buffer_append(exp_buf, LOGICAL_AND, gen)
  end

  local gen = gen_for_nets("net.src_ip", "net.src_port", srcs)
  if gen then
    buffer_append(exp_buf, LOGICAL_AND, gen)
  end

  local gen = gen_for_nets("net.dst_ip", "net.dst_port", dsts)
  if gen then
    buffer_append(exp_buf, LOGICAL_AND, gen)
  end

  return exp_buf:get()
end


local function get_priority(route)
  return 100
end


local function get_exp_and_priority(route)
  if route.expression then
    ngx_log(ngx_ERR, "expecting a traditional route while expression is given. ",
                     "Likely it's a misconfiguration. Please check router_flavor")
  end

  local exp      = get_expression(route)
  local priority = get_priority(route)

  return exp, priority
end


function _M.new(routes_and_services, cache, cache_neg, old_router)
  -- route_and_service argument is a table with [route] and [service]
  if type(routes_and_services) ~= "table" then
    return error("expected arg #1 routes to be a table", 2)
  end

  return atc.new(routes_and_services, cache, cache_neg, old_router, get_exp_and_priority)
end


-- for schema validation and unit-testing
_M.get_expression = get_expression


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx
_M._get_priority = get_priority


return _M
