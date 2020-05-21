local helpers = require "spec.helpers"


local function find_in_file(f, pat)
  local line = f:read("*l")

  while line do
    if line:match(pat) then
      return true
    end

    line = f:read("*l")
  end

  return nil, "the pattern '" .. pat .. "' could not be found " ..
         "in the correct order in the log file"
end


describe("SDK: kong.log", function()
  local proxy_client
  local bp, db

  before_each(function()
    bp, db = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, {
      "logger",
      "logger-last"
    })
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong()

    assert(db:truncate("routes"))
    assert(db:truncate("services"))
    db:truncate("plugins")
  end)

  it("namespaces the logs with the plugin name inside a plugin", function()
    local service = bp.services:insert({
      protocol = helpers.mock_upstream_ssl_protocol,
      host     = helpers.mock_upstream_ssl_host,
      port     = helpers.mock_upstream_ssl_port,
    })
    bp.routes:insert({
      service = service,
      protocols = { "https" },
      hosts = { "logger-plugin.com" }
    })

    bp.plugins:insert({
      name = "logger",
    })

    bp.plugins:insert({
      name = "logger-last",
    })

    assert(helpers.start_kong({
      plugins = "bundled,logger,logger-last",
      nginx_conf     = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_ssl_client()

    -- Do two requests
    for i = 1, 2 do
      local res = proxy_client:get("/request", {
        headers = { Host = "logger-plugin.com" }
      })
      assert.status(200, res)
    end

    -- wait for the second log phase to finish, otherwise it might not appear
    -- in the logs when executing this
    helpers.wait_until(function()
      local pl_file = require "pl.file"

      local cfg = helpers.test_conf
      local logs = pl_file.read(cfg.prefix .. "/" .. cfg.proxy_error_log)
      local _, count = logs:gsub([[executing plugin "logger%-last": log]], "")

      return count == 2
    end, 10)

    local phrases = {
      "%[logger%] init_worker phase",    "%[logger%-last%] init_worker phase",

      "%[logger%] certificate phase",    "%[logger%-last%] certificate phase",

      "%[logger%] rewrite phase",        "%[logger%-last%] rewrite phase",
      "%[logger%] access phase",         "%[logger%-last%] access phase",
      "%[logger%] header_filter phase",  "%[logger%-last%] header_filter phase",
      "%[logger%] body_filter phase",    "%[logger%-last%] body_filter phase",
      "%[logger%] log phase",            "%[logger%-last%] log phase",

      "%[logger%] rewrite phase",        "%[logger%-last%] rewrite phase",
      "%[logger%] access phase",         "%[logger%-last%] access phase",
      "%[logger%] header_filter phase",  "%[logger%-last%] header_filter phase",
      "%[logger%] body_filter phase",    "%[logger%-last%] body_filter phase",
      "%[logger%] log phase",            "%[logger%-last%] log phase",
    }

    -- test that the phrases are logged twice on the specific order
    -- in which they are listed above
    local cfg = helpers.test_conf
    local f = assert(io.open(cfg.prefix .. "/" .. cfg.proxy_error_log, "r"))

    for j = 1, #phrases do
      assert(find_in_file(f, phrases[j]))
    end

    f:close()
  end)
end)
