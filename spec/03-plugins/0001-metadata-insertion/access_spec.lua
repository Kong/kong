local helpers = require "spec.helpers"
local client
local admin_client
local cjson = require "cjson"
local consumer
 local debug = require "kong.plugins.metadata-insertion.tool.debug"

local function setConsumerDummyData()

  -- SETUP DUMMY DATA
  consumer = assert(helpers.dao.consumers:insert {
    username = "bob"
  })

  assert(helpers.dao.keyauth_credentials:insert {
    consumer_id = consumer.id,
    key = "bob-api-key"
  })

  assert(helpers.dao.metadata_keyvaluestore:insert {
    consumer_id = consumer.id,
    key = "location",
    value = "europe"
  })

  assert(helpers.dao.metadata_keyvaluestore:insert {
    consumer_id = consumer.id,
    key = "third_party_api_key",
    value = "some-generic-api-key"
  })
end

describe("Metadata-Insertion Plugin", function()

  teardown(function()
    if client then client:close() end
    if admin_client then admin_client:close() end
  end)

  before_each(function()
    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
    client = helpers.proxy_client()
  end)

  after_each(function()
    assert(helpers.stop_kong())
    if client then client:close() end
    if admin_client then admin_client:close() end
  end)

  describe("Response", function()

    it("Should return metadata previously created", function()

      setConsumerDummyData()

      local res = admin_client:send {
        method = "GET",
        path = "/consumers/bob/metadata",
        headers = {
          ["Content-Type"] = "application/json"
        }
      }

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert(json.data[1].key == "location", "Invalid parameter name")
      assert(json.data[1].value == "europe", "Invalid value")
      assert(json.data[2].key == "third_party_api_key", "Invalid parameter name")
      assert(json.data[2].value == "some-generic-api-key", "Invalid value")
    end)

    it("Should return metadata previously created with crud API access point", function()

      -- SETUP DUMMY DATA
      consumer = assert(helpers.dao.consumers:insert {
        username = "bob"
      })

      assert(helpers.dao.keyauth_credentials:insert {
        consumer_id = consumer.id,
        key = "bob-api-key"
      })

      assert(admin_client:send {
        method = "POST",
        path = "/consumers/" .. consumer.id .. "/metadata/",
        body = {
          key = "some-field",
          value = "some-value"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      if admin_client then admin_client:close() end
      admin_client = helpers.admin_client()

      local res = admin_client:send {
        method = "GET",
        path = "/consumers/bob/metadata",
        headers = {
          ["Content-Type"] = "application/json"
        }
      }

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert(json.data[1].key == "some-field", "Metadata added with POST request seems to be missing")
      assert(json.data[1].value == "some-value", "Metadata added with POST request seems to be missing")

      local api1 = assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://www.mockbin.com"
      })

      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api1.id,
        config = {
          hide_credentials = true
        }
      })

      assert(helpers.dao.plugins:insert {
        api_id = api1.id,
        name = "metadata-insertion",
        config = {
          add = {
            querystring = {
              "location: %some-field%"
            },
            headers = {
              "location: %some-field%"
            }
          }
        }
      })

      local res = assert(client:send({
        method = "GET",
        path = "/request?apikey=bob-api-key",
        headers = {
          ["Host"] = "mockbin.com"
        }
      }))

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert(json.headers.location == "some-value", "Metadata added with POST request seems to not work properly")
      assert(json.queryString.location == "some-value", "Metadata added with POST request seems to not work properly")
    end)

    it("Should transform request with consumer metadata", function()

      setConsumerDummyData()

      local api1 = assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://www.mockbin.com"
      })

      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api1.id,
        config = {
          hide_credentials = true
        }
      })

      assert(helpers.dao.plugins:insert {
        api_id = api1.id,
        name = "metadata-insertion",
        config = {
          add = {
            querystring = {
              "location: %location%",
              "apikey: %third_party_api_key%"
            },
            headers = {
              "user_country: %location%",
            }
          }
        }
      })

      local res = assert(client:send({
        method = "GET",
        path = "/request?apikey=bob-api-key",
        headers = {
          ["Host"] = "mockbin.com"
        }
      }))

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert(json.headers.user_country == "europe", "Invalid user_country in headers")
      assert(json.queryString.apikey == "some-generic-api-key", "Invalid api key in Querystring")
      assert(json.queryString.location == "europe", "Invalid location in QueryString")
    end)

    it("Should throw error when trying to access an API without the proper metadata available", function()

      consumer = assert(helpers.dao.consumers:insert {
        username = "empty-user"
      })

      assert(helpers.dao.keyauth_credentials:insert {
        consumer_id = consumer.id,
        key = "empty-user-api-key"
      })

      local api1 = assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://www.mockbin.com"
      })

      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api1.id,
        config = {
          hide_credentials = true
        }
      })

      assert(helpers.dao.plugins:insert {
        api_id = api1.id,
        name = "metadata-insertion",
        config = {
          add = {
            querystring = {
              "location: %location%",
              "apikey: %third_party_api_key%"
            },
            headers = {
              "user_country: %location%",
            }
          }
        }
      })

      local res = assert(client:send({
        method = "GET",
        path = "/request?apikey=empty-user-api-key",
        headers = {
          ["Host"] = "mockbin.com"
        }
      }))

      assert.res_status(400, res)
    end)

    it("Should replace value from headers and querystring", function()

      setConsumerDummyData()

      local api1 = assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://www.mockbin.com"
      })

      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api1.id,
        config = {
          hide_credentials = true
        }
      })

      assert(helpers.dao.plugins:insert {
        api_id = api1.id,
        name = "metadata-insertion",
        config = {
          replace = {
            querystring = {
              "location: %location%"
            },
            headers = {
              "third-party-api-key: %third_party_api_key%"
            }
          }
        }
      })

      local res = assert(client:send({
        method = "GET",
        path = "/request?apikey=bob-api-key&location=bob_location_will_be_overwritten",
        headers = {
          ["Host"] = "mockbin.com",
          ["third-party-api-key"] = "will_be_overwritten"
        }
      }))

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert(json.queryString.location == "europe", "Invalid location in QueryString")
      assert(json.headers["third-party-api-key"] == "some-generic-api-key", "Invalid third-party-api-key in headers")
    end)

    it("Should remove value from headers and querystring", function()

      setConsumerDummyData()

      local api1 = assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://www.mockbin.com"
      })

      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api1.id,
        config = {
          hide_credentials = true
        }
      })

      assert(helpers.dao.plugins:insert {
        api_id = api1.id,
        name = "metadata-insertion",
        config = {
          remove = {
            querystring = {
              "location"
            },
            headers = {
              "third-party-api-key"
            }
          }
        }
      })

      local res = assert(client:send({
        method = "GET",
        path = "/request?apikey=bob-api-key&location=will_be_removed",
        headers = {
          ["Host"] = "mockbin.com",
          ["third-party-api-key"] = "will_be_removed"
        }
      }))

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert(json.queryString.location == nil, "Location in querystring should be nil")
      assert(json.headers["third-party-api-key"] == nil, "Invalid third-party-api-key in headers should be nil")
    end)

    it("Should trigger forbidden access when no user is authenticated", function()
      local api1 = assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://www.mockbin.com"
      })

      assert(helpers.dao.plugins:insert {
        api_id = api1.id,
        name = "metadata-insertion",
        config = {
          replace = {
            querystring = {
              "whatever: %whatever%"
            }
          }
        }
      })

      local res = assert(client:send({
        method = "GET",
        path = "/status",
        headers = {
          ["Host"] = "mockbin.com"
        }
      }))

      assert.res_status(401, res)
    end)

    it("Should transform request with consumer metadata but prioritise value from metadata transitory store", function()

      -- must re-init the kong instance with new parameters
      assert(helpers.stop_kong())
      if client then client:close() end
      if admin_client then admin_client:close() end

      assert(helpers.start_kong({
        custom_plugins = "metadata-insertion,metadata-transitory-store",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua"
      }))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      local api1 = assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://www.mockbin.com"
      })

      setConsumerDummyData()

      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api1.id,
        config = {
          hide_credentials = true
        }
      })

      assert(helpers.dao.plugins:insert {
        api_id = api1.id,
        name = "metadata-insertion",
        config = {
          add = {
            querystring = {
              "location: %location%",
              "apikey: %third_party_api_key%",
              "field_only_available_in_transitory_store: %field_only_available_in_transitory_store%"
            },
            headers = {
              "user_country: %location%",
              "field_only_available_in_transitory_store: %field_only_available_in_transitory_store%"
            }
          }
        }
      })

      assert(admin_client:send {
        method = "POST",
        path = "/apis/" .. api1.id .. "/plugins/",
        body = {
          name = "metadata-transitory-store"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local res = assert(client:send({
        method = "GET",
        path = "/request?apikey=bob-api-key",
        headers = {
          ["Host"] = "mockbin.com"
        }
      }))

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert(json.headers.user_country == "location-from-transitory", "Invalid user_country in headers")
      assert(json.queryString.apikey == "api-key-from-transitory", "Invalid apikey in QueryString")
      assert(json.queryString.location == "location-from-transitory", "Invalid location in QueryString")
      assert(json.queryString.field_only_available_in_transitory_store == "field_only_available_in_transitory_store", "Exclusive field in transitory store not added to metadata")
    end)
  end)
end)