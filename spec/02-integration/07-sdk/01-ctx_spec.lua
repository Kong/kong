local helpers = require "spec.helpers"


describe("SDK: kong.ctx", function()
  local proxy_client
  local bp, db

  before_each(function()
    bp, db = helpers.get_db_utils(nil, {
      "routes",
      "plugins",
    }, {
      "ctx-checker",
      "ctx-checker-last",
    })
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong()

    assert(db:truncate("routes"))
    db:truncate("plugins")
  end)

  it("isolates kong.ctx.plugin per-plugin", function()
    local route = bp.routes:insert({
      hosts = { "ctx-plugin.com" }
    })

    bp.plugins:insert({
      name     = "ctx-checker",
      route    = { id = route.id },
      config   = {
        ctx_kind        = "kong.ctx.plugin",
        ctx_set_field   = "secret",
        ctx_set_value   = "plugin-a",
        ctx_check_field = "secret",
        ctx_check_value = "plugin-a",
        ctx_throw_error = true,
      },
    })

    bp.plugins:insert({
      name     = "ctx-checker-last",
      route    = { id = route.id },
      config   = {
        ctx_kind        = "kong.ctx.plugin",
        ctx_set_field   = "secret",
        ctx_set_value   = "plugin-b",
        ctx_check_field = "secret",
        ctx_check_value = "plugin-b",
        ctx_throw_error = true,
      },
    })

    assert(helpers.start_kong({
      plugins = "bundled,ctx-checker,ctx-checker-last",
      nginx_conf     = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_client()

    local res = proxy_client:get("/request", {
      headers = { Host = "ctx-plugin.com" }
    })

    assert.status(200, res)
    local plugin_a_value = assert.header("ctx-checker-secret", res)
    local plugin_b_value = assert.header("ctx-checker-last-secret", res)
    assert.equals("plugin-a", plugin_a_value)
    assert.equals("plugin-b", plugin_b_value)
  end)

  it("can share values using kong.ctx.shared", function()
    local route = bp.routes:insert({
      hosts = { "ctx-shared.com" }
    })

    bp.plugins:insert({
      name     = "ctx-checker",
      route    = { id = route.id },
      config   = {
        ctx_kind        = "kong.ctx.shared",
        ctx_set_field   = "shared-field",
        ctx_throw_error = true,
      },
    })

    bp.plugins:insert({
      name     = "ctx-checker-last",
      route    = { id = route.id },
      config   = {
        ctx_kind        = "kong.ctx.shared",
        ctx_check_field = "shared-field",
        ctx_throw_error = true,
      },
    })

    assert(helpers.start_kong({
      plugins = "bundled,ctx-checker,ctx-checker-last",
      nginx_conf     = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_client()

    local res = proxy_client:get("/request", {
      headers = { Host = "ctx-shared.com" }
    })

    assert.status(200, res)
    assert.header("ctx-checker-last-shared-field", res)
  end)
end)
