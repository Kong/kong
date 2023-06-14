local _M = {}


local bit = require("bit")
local buffer = require("string.buffer")
local atc = require("kong.router.atc")
local tb_new = require("table.new")
local tb_nkeys = require("table.nkeys")

local is_empty_field  = atc.is_empty_field
local gen_for_field   = atc.gen_for_field


local type = type
local ipairs = ipairs


local ngx       = ngx
local ngx_log   = ngx.log
local ngx_ERR   = ngx.ERR


local OP_EQUAL    = "=="
local OP_IN       = "in"


local LOGICAL_OR  = atc.LOGICAL_OR
local LOGICAL_AND = atc.LOGICAL_AND


-- reuse buffer objects
local expr_buf = buffer.new(128)
local srcs_buf = buffer.new(64)
local dsts_buf = buffer.new(64)


local function buffer_append(buf, sep, str, idx)
  if #buf > 0 and
     (idx == nil or idx > 1)
  then
    buf:put(sep)
  end
  buf:put(str)
end


local function get_expression(route)
  local snis = route.snis
  local srcs = route.sources
  local dsts = route.destinations

  expr_buf:reset()

  local gen = gen_for_field("tls.sni", OP_EQUAL, snis, function(_, p)
    if #p > 1 and byte(p, -1) == DOT then
      -- last dot in FQDNs must not be used for routing
      return p:sub(1, -2)
    end

    return p
  end)
  if gen then
    buffer_append(expr_buf, LOGICAL_AND, gen)
  end

  if not is_empty_field(srcs) then
    srcs_buf:reset():put("(")

    for i, src in ipairs(srcs) do
      local ip = src.ip
      local port = src.port

      local op
      if string.find(ip, "/", 1, true) then
        op = OP_IN
      else
        op = OP_EQUAL
      end

      local expr = "net.src_ip " .. op .. " \"" .. ip .. "\""

      if port then
        expr = "(" .. expr .. LOGICAL_AND ..
               "net.src_port " .. OP_EQUAL .. " " .. port .. ")"
      end

      buffer_append(srcs_buf, LOGICAL_OR, expr, i)
    end   -- route.srcs

    buffer_append(expr_buf, LOGICAL_AND,
                  srcs_buf:put(")"):get())
  end

  if not is_empty_field(dsts) then
    dsts_buf:reset():put("(")

    for i, dst in ipairs(dsts) do
      local ip = dst.ip
      local port = dst.port

      local op
      if string.find(ip, "/", 1, true) then
        op = OP_IN
      else
        op = OP_EQUAL
      end

      local expr = "net.dst_ip " .. op .. " \"" .. ip .. "\""

      if port then
        expr = "(" .. expr .. LOGICAL_AND ..
               "net.dst_port " .. OP_EQUAL .. " " .. port .. ")"
      end

      buffer_append(dsts_buf, LOGICAL_OR, expr, i)
    end   -- route.dsts

    buffer_append(expr_buf, LOGICAL_AND,
                  dsts_buf:put(")"):get())
  end

  return expr_buf:get()
end


local function get_priority(route)
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
