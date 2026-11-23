local rpc_utils = require("kong.clustering.rpc.utils")


describe("kong.clustering.rpc.utils.get_header", function()
  it("returns the value for an exact key match", function()
    assert.equal("kong.meta.v1", rpc_utils.get_header({
      sec_websocket_protocol = "kong.meta.v1",
    }, "sec_websocket_protocol"))
  end)

  it("matches header names case-insensitively", function()
    assert.equal("kong.meta.v1", rpc_utils.get_header({
      ["Sec-WebSocket-Protocol"] = "kong.meta.v1",
    }, "sec_websocket_protocol"))
  end)

  it("matches hyphen and underscore forms", function()
    assert.equal("kong.meta.v1", rpc_utils.get_header({
      ["sec-websocket-protocol"] = "kong.meta.v1",
    }, "sec_websocket_protocol"))
  end)

  it("returns nil when the header is absent", function()
    assert.is_nil(rpc_utils.get_header({}, "sec_websocket_protocol"))
    assert.is_nil(rpc_utils.get_header(nil, "sec_websocket_protocol"))
  end)
end)
