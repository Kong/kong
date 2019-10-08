local helpers = require "spec.helpers"

describe("kong starts with proxy-cache-advanced plugin", function()

  setup(function()
    helpers.get_db_utils(nil, nil, {"proxy-cache-advanced"})
  end)

  before_each(function()
    helpers.stop_kong(nil, true)
  end)

  teardown(function()
    helpers.stop_kong(nil, true)
  end)

  it("starts with default conf", function()
    assert(helpers.start_kong({
      plugins = "bundled,proxy-cache-advanced",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  it("starts with stream listen", function()
    assert(helpers.start_kong({
      plugins = "bundled,proxy-cache-advanced",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      stream_listen = "0.0.0.0:5555",
    }))
  end)

end)

