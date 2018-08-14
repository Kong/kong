local helpers = require "spec.helpers"
local cjson   = require "cjson"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end


describe("Admin API post-processing", function()
  local client
  local plugin

  setup(function()
    assert(helpers.dao:run_migrations())
    helpers.dao:truncate_table("plugins")
    assert(helpers.start_kong {
      plugins = "bundled, admin-api-post-process, dummy"
    })

    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)
  
  after_each(function()
    helpers.dao:truncate_table("plugins")
  end)

  before_each(function()
    plugin =  helpers.dao.plugins:insert({
      name = "admin-api-post-process",
    })
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
      local res = assert(client:send {
        method = "PATCH",
        path = "/plugins/" .. plugin.id .. "/post_processed",
        body = {
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
