local cjson = require "cjson.safe"
local ai_shared = require "kong.llm.drivers.shared"
local ai_ctx = require "kong.llm.plugin.ctx"
local driver = require "kong.llm.drivers.minimax"
local parse_request = require "kong.llm.plugin.shared-filters.parse-request"
local normalize_request = require "kong.llm.plugin.shared-filters.normalize-request"
local service_request = require("kong.pdk.service.request").new()


describe("ai-proxy: MiniMax serialized requests", function()
  local saved_kong, saved_ctx
  local conf, incoming, sent
  local read_body, set_body_data, set_header, http_request

  before_each(function()
    saved_kong = _G.kong
    saved_ctx = ngx.ctx.ai_namespaced_ctx
    ngx.ctx.ai_namespaced_ctx = nil
    conf = {
      route_type = "llm/v1/chat",
      model = { provider = "minimax", options = {} },
    }
    incoming = { messages = { { role = "user", content = "Hello" } } }
    sent = { headers = {} }

    read_body = stub(ngx.req, "read_body")
    set_body_data = stub(ngx.req, "set_body_data", function(body)
      sent.body = body
    end)
    set_header = stub(ngx.req, "set_header", function(name, value)
      sent.headers[name] = value
    end)
    http_request = stub(ai_shared, "http_request", function(url, body, method, headers)
      sent.url, sent.body, sent.method, sent.headers = url, body, method, headers
      return { status = 200, body = '{"choices":[]}' }
    end)

    _G.kong = {
      log = { debug = function() end, info = function() end, err = function() end },
      request = {
        get_header = function() return nil end,
        get_body = function() return incoming end,
        get_path = function() return "/custom/native" end,
      },
      response = {
        exit = function(status, body)
          sent.status, sent.error = status, body.error.message
        end,
      },
      service = {
        set_target = function(host, port) sent.host, sent.port = host, port end,
        request = {
          -- Use the actual PDK JSON encoder and capture the outgoing nginx bytes.
          set_body = service_request.set_body,
          enable_buffering = function() end,
          set_header = function(name, value) sent.headers[name] = value end,
          set_path = function(path) sent.path = path end,
          set_scheme = function(scheme) sent.scheme = scheme end,
        },
      },
    }
  end)

  after_each(function()
    read_body:revert()
    set_body_data:revert()
    set_header:revert()
    http_request:revert()
    _G.kong = saved_kong
    ngx.ctx.ai_namespaced_ctx = saved_ctx
  end)

  local function proxy_request()
    assert.is_true(parse_request:run(conf))
    assert.is_true(normalize_request:run(conf))
    assert.is_nil(sent.status, sent.error)
    return assert(cjson.decode(sent.body))
  end

  for _, region in ipairs({ "global", "cn", "custom" }) do
    for _, stream in ipairs({ false, true }) do
      it("defaults to Flash through the " .. region .. " proxy, stream=" .. tostring(stream), function()
        local host = "api.minimax.io"
        if region == "cn" then
          host = "api.minimaxi.com"
        elseif region == "custom" then
          host = "gateway.example.test"
        end
        if region ~= "global" then
          conf.model.options.upstream_url = "https://" .. host .. "/v1/chat/completions"
        end
        incoming.stream = stream
        local body = proxy_request()
        assert.equal("MiniMax-M3.1-Flash", body.model)
        assert.equal(stream, body.stream)
        assert.same(incoming.messages, body.messages)
        assert.is_nil(body.thinking)
        assert.is_nil(body.reasoning_effort)
        assert.is_nil(body.service_tier)
        assert.is_nil(body.reasoning_split)
        assert.equal(host, sent.host)
        assert.equal(443, sent.port)
        assert.equal("https", sent.scheme)
        assert.equal("/v1/chat/completions", sent.path)
        assert.equal("MiniMax-M3.1-Flash", ai_ctx.get_request_model_table_inuse().name)
        assert.is_nil(conf.model.name)
        assert.is_nil(incoming.model)
      end)
    end
  end

  for _, model in ipairs({ "MiniMax-M3.1-Flash", "MiniMax-M3", "MiniMax-M2.7", "custom-model" }) do
    for _, source in ipairs({ "configuration", "request" }) do
      it("preserves " .. model .. " from " .. source, function()
        if source == "configuration" then
          conf.model.name = model
        else
          incoming.model = model
        end
        assert.equal(model, proxy_request().model)
      end)
    end
  end

  it("keeps configured model mismatch rejection", function()
    conf.model.name = "MiniMax-M3"
    incoming.model = "MiniMax-M3.1-Flash"
    parse_request:run(conf)
    normalize_request:run(conf)
    assert.equal(400, sent.status)
    assert.equal("cannot use own model - must be: MiniMax-M3", sent.error)
    assert.is_nil(sent.body)
  end)

  for _, effort in ipairs({ "low", "medium", "high", "xhigh", "max" }) do
    it("preserves Flash adaptive thinking and " .. effort .. " effort", function()
      incoming.thinking = { type = "adaptive" }
      incoming.reasoning_effort = effort
      local body = proxy_request()
      assert.same(incoming.thinking, body.thinking)
      assert.equal(effort, body.reasoning_effort)
    end)
  end

  it("preserves M3 disabled thinking", function()
    incoming.model = "MiniMax-M3"
    incoming.thinking = { type = "disabled" }
    assert.same(incoming.thinking, proxy_request().thinking)
  end)

  it("preserves tool, reasoning, image and video history", function()
    incoming.messages = {
      { role = "user", content = {
        { type = "text", text = "Describe these" },
        { type = "image_url", image_url = { url = "https://example.test/image.png" } },
        { type = "video_url", video_url = { url = "mm_file://fixture" } },
      } },
      { role = "assistant", content = "<think>Keep this reasoning</think>",
        reasoning_content = "Keep separate reasoning too",
        tool_calls = { { id = "call_fixture", type = "function",
          ["function"] = { name = "lookup", arguments = "{}" } } } },
      { role = "tool", tool_call_id = "call_fixture", content = "result" },
    }
    incoming.tools = { { type = "function", ["function"] = { name = "lookup" } } }
    local body = proxy_request()
    assert.same(incoming.messages, body.messages)
    assert.same(incoming.tools, body.tools)
  end)

  it("leaves preserve requests untouched", function()
    conf.route_type = "preserve"
    conf.model.options.upstream_url = "https://gateway.example.test/custom/native"
    incoming = { input = "native request", previous_response_id = "fixture" }
    parse_request:run(conf)
    normalize_request:run(conf)
    assert.is_nil(sent.status)
    assert.is_nil(sent.body)
    assert.is_nil(ai_ctx.get_request_model_table_inuse().name)
    assert.equal("/custom/native", sent.path)
    assert.same(incoming, driver.to_format(incoming, conf.model, "preserve"))
  end)

  it("retains the missing-model error for other providers", function()
    conf.model.provider = "openai"
    parse_request:run(conf)
    normalize_request:run(conf)
    assert.equal(400, sent.status)
    assert.equal("model parameter not found in request, nor in gateway configuration", sent.error)
    assert.is_nil(sent.body)
  end)

  it("does not apply the chat default to legacy completion requests", function()
    conf.route_type = "llm/v1/completions"
    incoming = { prompt = "Hello" }
    parse_request:run(conf)
    normalize_request:run(conf)
    assert.equal(400, sent.status)
    assert.is_nil(sent.body)
  end)

  for _, model in ipairs({ "MiniMax-M3", "MiniMax-M2.7", "custom-model" }) do
    for _, source in ipairs({ "configuration", "request" }) do
      it("serializes internal " .. model .. " from " .. source, function()
        if source == "configuration" then
          conf.model.name = model
        else
          incoming.model = model
        end
        local body = assert(driver.to_format(incoming, conf.model, conf.route_type))
        local _, status, err = driver.subrequest(body, conf, {}, false)
        assert.is_nil(err)
        assert.equal(200, status)
        assert.equal(model, assert(cjson.decode(sent.body)).model)
      end)
    end
  end

  for _, region in ipairs({ "global", "cn" }) do
    it("serializes the default internal subrequest for " .. region, function()
      if region == "cn" then
        conf.model.options.upstream_url = "https://api.minimaxi.com/v1/chat/completions"
      end
      local body, _, err = driver.to_format(incoming, conf.model, conf.route_type)
      assert.is_nil(err)
      local _, status, err = driver.subrequest(body, conf, {}, false)
      assert.is_nil(err)
      assert.equal(200, status)
      assert.equal("POST", sent.method)
      assert.equal(conf.model.options.upstream_url or "https://api.minimax.io:443/v1/chat/completions", sent.url)
      assert.equal("application/json", sent.headers["Content-Type"])
      assert.equal("MiniMax-M3.1-Flash", assert(cjson.decode(sent.body)).model)
    end)
  end
end)
