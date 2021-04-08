local helpers = require "spec.helpers"

describe("SDK: kong.response", function()
  local proxy_client
  local bp, db

  before_each(function()
    bp, db = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, {
      "response-transformer",
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

  it("preserves underscores in headers", function()
    local service = bp.services:insert({
      protocol = helpers.mock_upstream_ssl_protocol,
      host     = helpers.mock_upstream_ssl_host,
      port     = helpers.mock_upstream_ssl_port,
    })
    local r = bp.routes:insert({
      service = service,
      protocols = { "https" },
      hosts = { "underscores_test.dev" }
    })

    bp.plugins:insert({
      name = "response-transformer",
      route = { id = r.id },
      config = {
        add = {
          headers = {
            "un_der_score:true"
          }
        }
      }
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_ssl_client()

    local res = proxy_client:get("/request", {
      headers = { Host = "underscores_test.dev" }
    })
    assert.status(200, res)
    assert.same("true", res.headers["un_der_score"])
  end)
end)
