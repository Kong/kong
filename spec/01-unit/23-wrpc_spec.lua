local wrpc = require "kong.tools.wrpc"

local _mock_buffs = {}
local function clear_mock_buffers()
  _mock_buffs.send = {head = 0, tail = 0}
  _mock_buffs.receive = {head = 0, tail = 0}
  _mock_buffs.encode = {head = 0, tail = 0}
  _mock_buffs.decode = {head = 0, tail = 0}
end

local function mock_buffer_add(bufname, d)
  local buf = assert(_mock_buffs[bufname])
  buf[buf.head] = d
  buf.head = buf.head + 1
end

local function mock_buff_pop(bufname)
  local buf = assert(_mock_buffs[bufname])
  if buf.head > buf.tail then
    local d = buf[buf.tail]
    buf.tail = buf.tail + 1
    return d
  end

  ngx.sleep(0)
  return nil, "empty"
end

local function mock_encode(type, d)
  mock_buffer_add("encode", {type=type, data=d})
  return d
end

local function mock_decode(type, d)
  mock_buffer_add("decode", {type=type, data=d})
  return d
end

local function mock_send(_, d)
  return mock_buffer_add("send", d)
end

local function mock_receive()
  return mock_buff_pop("receive")
end


describe("wRPC tools", function()
  it("loads service definition", function()
    local srv = wrpc.new_service()
    srv:add("kong.services.config.v1.config")

    local ping_method = srv:get_method("ConfigService.PingCP")

    assert.is_table(ping_method)
    assert.same("ConfigService.PingCP", ping_method.name)
    assert.is_string(ping_method.input_type)
    assert.is_string(ping_method.output_type)
    --assert.equals(srv.service_id, ping_method.service_id)
    assert.equals(srv:get_method(ping_method.service_id, ping_method.rpc_id), ping_method)
  end)

  it("rpc call", function()
    clear_mock_buffers()
    local req_data = {
      version = 2,
      config = {
        format_version = "0.1a",
      }
    }

    local srv = wrpc.new_service()
    srv:add("kong.services.config.v1.config")
    local peer = wrpc.new_peer(nil, srv, {
    encode = mock_encode,
    decode = mock_decode,
    send = mock_send,
    receive = mock_receive,
    })

    local call_id = assert.not_nil(peer:call("ConfigService.SyncConfig", req_data))

    assert.same({type = ".kong.services.config.v1.SyncConfigRequest", data = req_data}, mock_buff_pop("encode"))
    assert.same({type = "wrpc.WebsocketPayload", data = {
      version = "PAYLOAD_VERSION_V1",
      payload = {
        svc_id = 1,
        rpc_id = 2,
        seq = 1,
        mtype = "MESSAGE_TYPE_RPC",
        deadline = ngx.now() + 10,
        payload_encoding = "ENCODING_PROTO3",
        payloads = { req_data },
      },
    }}, mock_buff_pop("encode"))
    assert.same({
      version = "PAYLOAD_VERSION_V1",
      payload = {
        svc_id = 1,
        rpc_id = 2,
        seq = 1,
        mtype = "MESSAGE_TYPE_RPC",
        deadline = ngx.now() + 10,
        payload_encoding = "ENCODING_PROTO3",
        payloads = { req_data },
      },
    }, mock_buff_pop("send"))

    peer:step()
    local response, err = peer:get_response(call_id)
    assert.is_nil(response)
    assert.equal("no response", err)

    mock_buffer_add("receive", {
      version = "PAYLOAD_VERSION_V1",
      payload = {
        mtype = "MESSAGE_TYPE_RPC",
        svc_id = 1, -- ConfigService
        rpc_id = 2, -- SyncConfig
        seq = 67,
        ack = call_id,
        deadline = math.huge,
        payload_encoding = "ENCODING_PROTO3",
        payloads = { { accepted = true } }
      }
    })
    peer:step()
    response, err = peer:get_response(call_id)
    assert.is_nil(err)
    assert.same({ { accepted = true } }, response)

  end)
end)
