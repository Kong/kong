-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ws      = require "spec-ee.fixtures.websocket"
local session = require "spec-ee.fixtures.websocket.session"
local action  = require "spec-ee.fixtures.websocket.action"
local admin   = require "spec.fixtures.admin_api"

local fmt = string.format

local UPDATE_FREQUENCY = 0.1

for _, strategy in helpers.each_strategy({"postgres"}) do
for _, consistency in ipairs({ "strict", "eventual" }) do

describe("WebSocket admin API #" .. strategy .. " (worker_consistency = " .. consistency .. ")", function()
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
      "consumers",
      "upstreams",
      "targets",
    })

    assert(helpers.start_kong({
      database = strategy,
      plugins = "pre-function,post-function",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      worker_consistency = consistency,
      worker_state_update_frequency = UPDATE_FREQUENCY,
      db_update_frequency = UPDATE_FREQUENCY,
      -- using a single worker greatly simplifies the mid-connection plugin
      -- iterator test
      nginx_main_worker_processes = 1,
    }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))

    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("#validation", function()
    local count = 0

    local function req(entity)
      return {
        body = entity,
        headers = {
          ["content-type"] = "application/json",
        },
      }
    end

    local function create(typ, entity)
      count = count + 1
      entity.name = "test-" .. tostring(count)

      if typ == "routes" then
        entity.hosts = { entity.name }

      elseif typ == "services" then
        entity.host = entity.name
      end

      local res, err = admin_client:post("/" .. typ, req(entity))

      if not res then
        return nil, err
      end

      local body = assert.response(res).has.jsonbody()

      if res.status ~= 201 then
        return nil, body
      end

      return body
    end

    local function update(typ, id, patch)
      local path = "/" .. typ .. "/" .. id
      local res, err = admin_client:patch(path, req(patch))

      if not res then
        return nil, err
      end

      local body = assert.response(res).has.jsonbody()
      if res.status >= 300 then
        return nil, body
      end

      return body
    end

    it("doesn't allow attaching a non-WS route to a WS service", function()
      local service = assert(create("services", { protocol = "ws" }))

      local route, err = create("routes", {
        protocols = { "http", "https" },
        service = service,
      })

      assert.is_nil(route)
      assert.not_nil(err)
      assert.same({ protocols = "route/service protocol mismatch" },
                  err.fields)

    end)

    it("does not attaching a route with empty protocols to a WS service", function()
      local service = assert(create("services", { protocol = "ws" }))

      local route, err = create("routes", {
        service = service,
      })

      assert.is_nil(route)
      assert.not_nil(err)
      assert.same({ protocols = "route/service protocol mismatch" },
                  err.fields)
    end)

    it("doesn't allow attaching a WS route to a non-WS service", function()
      local service = assert(create("services", { protocol = "http" }))

      local route, err = create("routes", {
        protocols = { "ws", "wss" },
        service = service,
      })

      assert.is_nil(route)
      assert.not_nil(err)
      assert.same({ protocols = "route/service protocol mismatch" },
                  err.fields)
    end)

    it("doesn't allow updating a non-WS route to WS protocols", function()
      local service = assert(create("services", { protocol = "http" }))

      local route = assert(create("routes", {
        protocols = { "http" },
        service = service,
      }))

      local patched, err = update("routes", route.id, { protocols = { "ws" } })
      assert.is_nil(patched)
      assert.not_nil(err)
      assert.same({ protocols = "route/service protocol mismatch" },
                  err.fields)
    end)

    it("doesn't allow updating a WS route to non-WS protocols", function()
      local service = assert(create("services", { protocol = "wss" }))

      local route = assert(create("routes", {
        protocols = { "wss" },
        service = service,
      }))

      local patched, err = update("routes", route.id, { protocols = { "http" } })
      assert.is_nil(patched)
      assert.not_nil(err)
      assert.same({ protocols = "route/service protocol mismatch" },
                  err.fields)
    end)

    it("doesn't allow creation of WS routes without a service", function()
      local route, err = create("routes", { protocols = { "wss" } })
      assert.is_nil(route)
      assert.not_nil(err)
      assert.same({ service = "WebSocket routes must be attached to a service" },
                  err.fields)
    end)

    it("doesn't allow updating service protocol from WS to non-WS", function()
      local service = assert(create("services", { protocol = "ws" }))
      local patched, err = update("services", service.id, { protocol = "http" })
      assert.is_nil(patched)
      assert.not_nil(err)
      assert.same(
        { protocol = 'cannot change WebSocket protocol to non-WebSocket protocol' },
        err.fields
      )
    end)

    it("doesn't allow updating service protocol from non-WS to WS", function()
      local service = assert(create("services", { protocol = "https" }))
      local patched, err = update("services", service.id, { protocol = "ws" })
      assert.is_nil(patched)
      assert.not_nil(err)
      assert.same(
        { protocol = 'cannot change non-WebSocket protocol to WebSocket protocol' },
        err.fields
      )
    end)

    it("doesn't allow route.methods", function()
      local service = assert(create("services", { protocol = "ws" }))
      local route, err = create("routes", {
        protocols = { "ws" },
        service = service,
        methods = { "POST", "PUT" },
      })

      assert.is_nil(route)
      assert.same({ methods = "cannot set 'methods' when 'protocols' is 'ws' or 'wss'" },
                  err.fields)

    end)

    it("allows setting service.path after creation", function()
      local service = assert(create("services", { protocol = "ws" }))
      local patched, err = update("services", service.id, { path = "/test" })
      assert.is_nil(err)
      assert.equals("/test", patched.path)
    end)

    it("allows updating service.path after creation", function()
      local service = assert(create("services", { protocol = "ws", path = "/old" }))
      local patched, err = update("services", service.id, { path = "/new" })
      assert.is_nil(err)
      assert.equals("/new", patched.path)
    end)
  end)

  describe("making changes mid-connection", function()
    local name = "mid-conn.test"
    local service
    local sessions = {}
    local client, server = action.client, action.server

    local count = 0
    local function new_session()
      count = count + 1
      local host = fmt("session-%s.%s", count, name)
      return assert(session({
        host = host,
        idle_timeout = 60000,
        timeout = 100000,
      }))
    end

    lazy_setup(function()
      service = admin.services:insert({
        name = name,
        port = ws.const.ports.ws,
        host = helpers.mock_upstream_host,
        protocol = "ws",
      })

      admin.routes:insert({
        name = name,
        service = { id = service.id },
        hosts = { name, "*." .. name },
        protocols = { "ws" },
      })

      helpers.wait_for_all_config_update()
    end)

    lazy_teardown(function()
      for _, session in ipairs(sessions) do
        session:close()
      end
    end)

    it("plugin updates don't affect in-flight requests", function()
      -- Methodology
      --
      -- 1. Establish a WS connection
      -- 2. Make a plugin change
      -- 3. Establish a new connection
      -- 4. Assert that the connection from #3 is affected
      -- 5. Assert that the connection from #1 is unaffected
      -- 6. Rinse
      -- 7. Repeat

      -- no plugins active yet
      sessions[1] = new_session()
      sessions[1]:assert({
        client.send.text("session #1"),
        server.recv.text("session #1"),

        server.send.text("session #1"),
        client.recv.text("session #1"),
      })

      -- add a pre-function decorator
      local pre = admin.plugins:insert({
        name = "pre-function",
        protocols = { "ws", "wss" },
        service = { id = service.id },
        config = {
          ws_client_frame = {[[
            local ws = kong.websocket.client
            local data = ws.get_frame()
            ws.set_frame_data(data .. " + client-pre")
          ]]},
          ws_upstream_frame = {[[
            local ws = kong.websocket.upstream
            local data = ws.get_frame()
            ws.set_frame_data(data .. " + upstream-pre")
          ]]},
        },
      })

      helpers.wait_for_all_config_update()

      sessions[2] = new_session()
      sessions[2]:assert({
        client.send.text("session #2"),
        server.recv.text("session #2" .. " + client-pre"),

        server.send.text("session #2"),
        client.recv.text("session #2" .. " + upstream-pre"),
      })

      -- session #1 is unchanged with 0 plugins
      sessions[1]:assert({
        client.send.text("session #1"),
        server.recv.text("session #1"),

        server.send.text("session #1"),
        client.recv.text("session #1"),
      })

      -- add a post-function decorator
      local post = admin.plugins:insert({
        name = "post-function",
        protocols = { "ws", "wss" },
        service = { id = service.id },
        config = {
          ws_client_frame = {[[
            local ws = kong.websocket.client
            local data = ws.get_frame()
            ws.set_frame_data(data .. " + client-post")
          ]]},
          ws_upstream_frame = {[[
            local ws = kong.websocket.upstream
            local data = ws.get_frame()
            ws.set_frame_data(data .. " + upstream-post")
          ]]},
        },
      })

      helpers.wait_for_all_config_update()

      sessions[3] = new_session()
      sessions[3]:assert({
        client.send.text("session #3"),
        server.recv.text("session #3" .. " + client-pre + client-post"),

        server.send.text("session #3"),
        client.recv.text("session #3" .. " + upstream-pre + upstream-post"),
      })

      sessions[2]:assert({
        client.send.text("session #2"),
        server.recv.text("session #2" .. " + client-pre"),

        server.send.text("session #2"),
        client.recv.text("session #2" .. " + upstream-pre"),
      })

      sessions[1]:assert({
        client.send.text("session #1"),
        server.recv.text("session #1"),

        server.send.text("session #1"),
        client.recv.text("session #1"),
      })


      -- patch/upsert
      admin.plugins:update(post.id, {
        config = {
          ws_client_frame = {[[
            local ws = kong.websocket.client
            local data = ws.get_frame()
            ws.set_frame_data(data .. " + upsert")
          ]]},
          ws_upstream_frame = {[[
            local ws = kong.websocket.upstream
            local data = ws.get_frame()
            ws.set_frame_data(data .. " + upsert")
          ]]},
        },
      })

      helpers.wait_for_all_config_update()

      sessions[4] = new_session()
      sessions[4]:assert({
        client.send.text("session #4"),
        server.recv.text("session #4" .. " + client-pre + upsert"),

        server.send.text("session #4"),
        client.recv.text("session #4" .. " + upstream-pre + upsert"),
      })

      sessions[3]:assert({
        client.send.text("session #3"),
        server.recv.text("session #3" .. " + client-pre + client-post"),

        server.send.text("session #3"),
        client.recv.text("session #3" .. " + upstream-pre + upstream-post"),
      })

      sessions[2]:assert({
        client.send.text("session #2"),
        server.recv.text("session #2" .. " + client-pre"),

        server.send.text("session #2"),
        client.recv.text("session #2" .. " + upstream-pre"),
      })

      sessions[1]:assert({
        client.send.text("session #1"),
        server.recv.text("session #1"),

        server.send.text("session #1"),
        client.recv.text("session #1"),
      })

      -- finally, delete
      admin.plugins:remove(pre)

      helpers.wait_for_all_config_update()

      sessions[5] = new_session()
      sessions[5]:assert({
        client.send.text("session #5"),
        server.recv.text("session #5" .. " + upsert"),

        server.send.text("session #5"),
        client.recv.text("session #5" .. " + upsert"),
      })

      sessions[4]:assert({
        client.send.text("session #4"),
        server.recv.text("session #4" .. " + client-pre + upsert"),

        server.send.text("session #4"),
        client.recv.text("session #4" .. " + upstream-pre + upsert"),
      })

      sessions[3]:assert({
        client.send.text("session #3"),
        server.recv.text("session #3" .. " + client-pre + client-post"),

        server.send.text("session #3"),
        client.recv.text("session #3" .. " + upstream-pre + upstream-post"),
      })

      sessions[2]:assert({
        client.send.text("session #2"),
        server.recv.text("session #2" .. " + client-pre"),

        server.send.text("session #2"),
        client.recv.text("session #2" .. " + upstream-pre"),
      })

      sessions[1]:assert({
        client.send.text("session #1"),
        server.recv.text("session #1"),

        server.send.text("session #1"),
        client.recv.text("session #1"),
      })
    end)
  end)
end)
end -- consistency
end -- strategy
