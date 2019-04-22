local cjson = require "cjson"


local tcp = ngx.socket.tcp
local udp = ngx.socket.udp
local concat = table.concat
local insert = table.insert


local function wire_serialize(t)
  return cjson.encode(t) .. "\n"
end


local parse_socket_endpoint
do
  local socket_endpoint

  parse_socket_endpoint = function(endpoint)
    if socket_endpoint then
      return socket_endpoint[1], socket_endpoint[2]
    end

    local p, q
    p = endpoint:find(":", 1, true)
    q = p + 1

    socket_endpoint = { endpoint:sub(1, p - 1), endpoint:sub(q) }

    return socket_endpoint[1], socket_endpoint[2]
  end
end


local flushers = {

  file = function(traces, endpoint)
    local pl_sort = require "pl.tablex".sort

    local f = assert(io.open(endpoint, "a"))

    for _, trace in ipairs(traces) do
      assert(f:write(string.rep("=", 35) .. "\n"))

      for k, v in pl_sort(trace) do
        if k ~= "data" then
          assert(f:write(k .. ": " .. tostring(v) .. "\n"))
        end
      end

      if trace.data and next(trace.data) then
        assert(f:write(tostring(trace.data) .. "\n"))
      end

      assert(f:write(string.rep("=", 35) .. "\n"))
    end

    f:close()
  end,

  file_raw = function(traces, endpoint)
    local f = assert(io.open(endpoint, "a"))

    f:write(wire_serialize(traces))

    f:close()
  end,

  tcp = function(traces, endpoint)
    local sock = tcp()

    assert(sock:connect(parse_socket_endpoint(endpoint)))
    assert(sock:send(wire_serialize(traces)))
    assert(sock:setkeepalive())
  end,

  tls = function(traces, endpoint)
    local sock = tcp()

    assert(sock:connect(parse_socket_endpoint(endpoint)))
    assert(sock:sslhandshake())
    assert(sock:send(wire_serialize(traces)))
    assert(sock:setkeepalive())
  end,

  udp = function(traces, endpoint)
    local sock = udp()

    assert(sock:setpeername(parse_socket_endpoint(endpoint)))
    assert(sock:send(wire_serialize(traces)))
    assert(sock:close())
  end,

}


local writers = setmetatable({

  file = function(trace, endpoint)
    local pl_sort = require "pl.tablex".sort

    local f = assert(io.open(endpoint, "a"))

    f:write(string.rep("=", 35) .. "\n")

    for k, v in pl_sort(trace) do
      if k ~= "data" then
        f:write(k .. ": " .. v .. "\n")
      end
    end

    if trace.data and next(trace.data) then
      f:write(tostring(trace.data) .. "\n")
    end

    f:write(string.rep("=", 35) .. "\n")
    f:close()
  end,

}, {
  __index = function(_, k)
    return flushers[k]
  end,
})


local function file_tostring(t)
  local nt = {}

  for k, v in pairs(t) do
    insert(nt, k .. ": " .. tostring(v))
  end

  return concat(nt, "\n\n")
end


local function add_http_strategy()
  flushers.http = function(traces, endpoint)
    local http = require "resty.http"

    local c = http.new()

    local res, err = c:request_uri(endpoint, {
      method  = "POST",
      headers = {
        ["Content-Type"] = "application/json",
      },
      body = wire_serialize(traces)
    })
    assert(not err, err)

    assert(res.status >= 200 and res.status < 300, res.status)
  end
end


return {
  writers = writers,
  flushers = flushers,
  file_tostring = file_tostring,
  add_http_strategy = add_http_strategy,
}
