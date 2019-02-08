local helpers = require "spec.helpers"
local cjson   = require "cjson"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end

for _, strategy in helpers.each_strategy() do

describe("Admin API post-processing #" .. strategy, function()
  local client
  local plugin
  local db
  local bp

  lazy_setup(function()
    bp, db = helpers.get_db_utils(strategy, {
      "plugins",
    }, {
      "admin-api-post-process"
    })

    assert(helpers.start_kong {
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled, admin-api-post-process, dummy"
    })

    client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
    db.plugins:truncate()
  end)

  before_each(function()
    db:truncate("plugins")
    db:truncate("consumers")
    local client = helpers.admin_client()
    local res = assert(client:send {
      method = "POST",
      path = "/plugins",
      body = {
        name = "admin-api-post-process",
      },
      headers = { ["Content-Type"] = "application/json" },
    })

    helpers.register_consumer_relations(helpers.dao)
    bp.consumers:insert({
      username = "michael",
      custom_id = "landon",
    })
    local body = assert.res_status(201, res)
    plugin = cjson.decode(body)
    assert(client:close())
  end)

  it_content_types("post-processes paginated sets", function(content_type)
    return function()
      local res = assert(client:send {
        method = "GET",
        path = "/plugins/post_processed",
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body).data[1]
      assert.equal("ADMIN-API-POST-PROCESS", json.name)
    end
  end)

  it_content_types("post-processes crud.post", function(content_type)
    return function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins/post_processed",
        body = {
          name = "dummy",
        },
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.equal("DUMMY", json.name)
    end
  end)

  it_content_types("post-processes crud.get", function(content_type)
    return function()
      local res = assert(client:send {
        method = "GET",
        path = "/plugins/" .. plugin.id .. "/post_processed",
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("ADMIN-API-POST-PROCESS", json.name)
    end
  end)

  it_content_types("post-processes crud.patch", function(content_type)
    return function()
      if content_type == "multipart/form-data" then
        -- the client doesn't play well with this
        return
      end

      local res = assert(client:send {
        method = "PATCH",
        path = "/plugins/" .. plugin.id .. "/post_processed",
        body = {
          name = "admin-api-post-process",
          api = ngx.null,
          route = ngx.null,
          service = ngx.null,
          consumer = ngx.null,
          config = {
            foo = "potato"
          }
        },
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("POTATO", json.config.foo)
    end
  end)

  it_content_types("post-processes crud.put", function(content_type)
    return function()
      if content_type == "multipart/form-data" then
        -- the client doesn't play well with this
        return
      end

      local res = assert(client:send {
        method = "PUT",
        path = "/plugins/" .. plugin.id .. "/post_processed",
        body = {
          name = "admin-api-post-process",
          created_at = 1,
          config = {
            foo = "carrot",
          }
        },
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("CARROT", json.config.foo)
    end
  end)
end)

end
