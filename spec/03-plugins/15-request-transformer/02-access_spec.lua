local helpers = require "spec.helpers"

describe("Plugin: request-transformer (access)", function()
  local client

  setup(function()
    local api1 = assert(helpers.dao.apis:insert { name = "api-1", hosts = { "test1.com" }, upstream_url = "http://mockbin.com"})
    local api2 = assert(helpers.dao.apis:insert { name = "api-2", hosts = { "test2.com" }, upstream_url = "http://httpbin.org"})
    local api3 = assert(helpers.dao.apis:insert { name = "api-3", hosts = { "test3.com" }, upstream_url = "http://mockbin.com"})
    local api4 = assert(helpers.dao.apis:insert { name = "api-4", hosts = { "test4.com" }, upstream_url = "http://mockbin.com"})
    local api5 = assert(helpers.dao.apis:insert { name = "api-5", hosts = { "test5.com" }, upstream_url = "http://mockbin.com"})
    local api6 = assert(helpers.dao.apis:insert { name = "api-6", hosts = { "test6.com" }, upstream_url = "http://mockbin.com"})
    local api7 = assert(helpers.dao.apis:insert { name = "api-7", hosts = { "test7.com" }, upstream_url = "http://mockbin.com"})
    local api8 = assert(helpers.dao.apis:insert { name = "api-8", hosts = { "test8.com" }, upstream_url = "http://mockbin.com"})
    local api9 = assert(helpers.dao.apis:insert { name = "api-9", hosts = { "test9.com" }, upstream_url = "http://mockbin.com"})
    local api10 = assert(helpers.dao.apis:insert { name = "api-10", hosts = { "test10.com" }, uris = { "/requests/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" }, upstream_url = "http://mockbin.com", strip_uri = false})
    local api11 = assert(helpers.dao.apis:insert { name = "api-11", hosts = { "test11.com" }, uris = { "/requests/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" }, upstream_url = "http://mockbin.com"})
    local api12 = assert(helpers.dao.apis:insert { name = "api-12", hosts = { "test12.com" }, uris = { "/requests/" }, upstream_url = "http://mockbin.com", strip_uri = false})
    local api13 = assert(helpers.dao.apis:insert { name = "api-13", hosts = { "test13.com" }, uris = { "/requests/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" }, upstream_url = "http://mockbin.com"})
    local api14 = assert(helpers.dao.apis:insert { name = "api-14", hosts = { "test14.com" }, uris = { "/user1/(?P<user1>\\w+)/user2/(?P<user2>\\S+)" }, upstream_url = "http://mockbin.com"})
    local api15 = assert(helpers.dao.apis:insert { name = "api-15", hosts = { "test15.com" }, uris = { "/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" }, upstream_url = "http://mockbin.com", strip_uri = false})
    local api16 = assert(helpers.dao.apis:insert { name = "api-16", hosts = { "test16.com" }, uris = { "/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" }, upstream_url = "http://mockbin.com", strip_uri = false})
    local api17 = assert(helpers.dao.apis:insert { name = "api-17", hosts = { "test17.com" }, uris = { "/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" }, upstream_url = "http://mockbin.com", strip_uri = false})
    local api18 = assert(helpers.dao.apis:insert { name = "api-18", hosts = { "test18.com" }, uris = { "/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" }, upstream_url = "http://mockbin.com", strip_uri = false})
    local api19 = assert(helpers.dao.apis:insert { name = "api-19", hosts = { "test19.com" }, uris = { "/requests/user1/(?<user1>\\w+)/user2/(?<user2>\\S+)" }, upstream_url = "http://mockbin.com", strip_uri = false})


    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "request-transformer",
      config = {
        add = {
          headers = {"h1:v1", "h2:value:2"}, -- payload containing a colon
          querystring = {"q1:v1"},
          body = {"p1:v1"}
        }
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "request-transformer",
      config = {
        add = {
          headers = {"host:mark"}
        }
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "request-transformer",
      config = {
        add = {
          headers = {"x-added:a1", "x-added2:b1", "x-added3:c2"},
          querystring = {"query-added:newvalue", "p1:anything:1"},   -- payload containing a colon
          body = {"newformparam:newvalue"}
        },
        remove = {
          headers = {"x-to-remove"},
          querystring = {"toremovequery"}
        },
        append = {
          headers = {"x-added:a2", "x-added:a3"},
          querystring = {"p1:a2", "p2:b1"}
        },
        replace = {
          headers = {"x-to-replace:false"},
          querystring = {"toreplacequery:no"}
        }
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api4.id,
      name = "request-transformer",
      config = {
        remove = {
          headers = {"x-to-remove"},
          querystring = {"q1"},
          body = {"toremoveform"}
        }
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api5.id,
      name = "request-transformer",
      config = {
        replace = {
          headers = {"h1:v1"},
          querystring = {"q1:v1"},
          body = {"p1:v1"}
        }
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api6.id,
      name = "request-transformer",
      config = {
        append = {
          headers = {"h1:v1", "h1:v2", "h2:v1",},
          querystring = {"q1:v1", "q1:v2", "q2:v1"},
          body = {"p1:v1", "p1:v2", "p2:value:1"}     -- payload containing a colon
        }
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api7.id,
      name = "request-transformer",
      config = {
        http_method = "POST"
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api8.id,
      name = "request-transformer",
      config = {
        http_method = "GET"
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api9.id,
      name = "request-transformer",
      config = {
        rename = {
          headers = {"x-to-rename:x-is-renamed"},
          querystring = {"originalparam:renamedparam"},
          body = {"originalparam:renamedparam"}
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api10.id,
      name = "request-transformer",
      config = {
        add = {
          querystring = {"uri_param1:$(uri_captures.user1)", "uri_param2[some_index][1]:$(uri_captures.user2)"},
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api11.id,
      name = "request-transformer",
      config = {
        replace = {
          uri = "/requests/user2/$(uri_captures.user2)/user1/$(uri_captures.user1)",
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api12.id,
      name = "request-transformer",
      config = {
        add = {
          querystring = {"uri_param1:$(uri_captures.user1 or 'default1')", "uri_param2:$(uri_captures.user2 or 'default2')"},
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api13.id,
      name = "request-transformer",
      config = {
        replace = {
          uri = "/requests/user2/$(10 * uri_captures.user1)",
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api14.id,
      name = "request-transformer",
      config = {
        replace = {
          uri = "/requests$(uri_captures[0])",
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api15.id,
      name = "request-transformer",
      config = {
        add = {
          querystring = {"uri_param1:$(uri_captures.user1)", "uri_param2:$(headers.host)"},
          headers = {"x-test-header:$(query_params.q1)"}
        },
        remove = {
          querystring = {"q1"},
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api16.id,
      name = "request-transformer",
      config = {
        replace = {
          querystring = {"q2:$(headers['x-remove-header'])"},
        },
        add = {
          querystring = {"q1:$(uri_captures.user1)"},
          headers = {"x-test-header:$(headers['x-remove-header'])"}
        },
        remove = {
          headers = {"x-remove-header"}
        },
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api17.id,
      name = "request-transformer",
      config = {
        replace = {
          querystring = {"q2:$(headers['x-replace-header'])"},
          headers = {"x-replace-header:the new value"}
        },
        add = {
          querystring = {"q1:$(uri_captures.user1)"},
          headers = {"x-test-header:$(headers['x-replace-header'])"}
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api18.id,
      name = "request-transformer",
      config = {
        add = {
          querystring = {[[q1:$('$(uri_captures.user1)')]]},
        }
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api19.id,
      name = "request-transformer",
      config = {
        add = {
          -- not inserting a value, but the `uri_captures` table itself to provoke a rendering error
          querystring = {[[q1:$(uri_captures)]]},
        }
      }
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("http method", function()
    it("changes the HTTP method from GET to POST", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request?hello=world&name=marco",
        headers = {
          host = "test7.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("POST", json.method)
      assert.equal("world", json.queryString.hello)
      assert.equal("marco", json.queryString.name)
    end)
    it("changes the HTTP method from POST to GET", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request?hello=world",
        body = {
          name = "marco"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test8.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("GET", json.method)
      assert.equal("marco", json.postData.params.name)
      assert.equal("world", json.queryString.hello)
      assert.equal("marco", json.queryString.name)
    end)
  end)
  describe("remove", function()
    it("specified header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test4.com",
          ["x-to-remove"] = "true",
          ["x-another-header"] = "true"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-remove")
      assert.request(r).has.header("x-another-header")
    end)
    it("parameters on url encoded form POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["toremoveform"] = "yes",
          ["nottoremove"] = "yes"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test4.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("toremoveform")
      local value = assert.request(r).has.formparam("nottoremove")
      assert.equals("yes", value)
    end)
    it("parameters from JSON body in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["toremoveform"] = "yes",
          ["nottoremove"] = "yes"
        },
        headers = {
          host = "test4.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json["toremoveform"])
      assert.equals("yes", json["nottoremove"])
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test4.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("malformed json body", json.postData.text)
    end)
    it("does not fail if body is empty and content type is application/json in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {},
        headers = {
          host = "test4.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals('{}', json.postData.text)
      assert.equals("2", json.headers["content-length"])
    end)
    it("does not fail if body is empty in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "test4.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.same({}, json.postData.params)
      assert.equal('', json.postData.text)
      local value = assert.request(r).has.header("content-length")
      assert.equal("0", value)
    end)
    it("parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["toremoveform"] = "yes",
          ["nottoremove"] = "yes"
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test4.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.is_nil(json.postData.params["toremoveform"])
      assert.equals("yes", json.postData.params["nottoremove"])
    end)
    it("queryString on GET if it exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          q1 = "v1",
          q2 = "v2",
        },
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test4.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("q1")
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
    end)
  end)

  describe("rename", function()
    it("specified header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test9.com",
          ["x-to-rename"] = "true",
          ["x-another-header"] = "true"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-rename")
      assert.request(r).has.header("x-is-renamed")
      assert.request(r).has.header("x-another-header")
    end)
    it("does not add as new header if header does not exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test9.com",
          ["x-a-header"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("renamedparam")
      local h_a_header = assert.request(r).has.header("x-a-header")
      assert.equals("true", h_a_header)
    end)
    it("specified parameters in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          originalparam = "yes",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("originalparam")
      local value = assert.request(r).has.formparam("renamedparam")
      assert.equals("yes", value)
    end)
    it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["x-a-header"] = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("renamedparam")
      local value = assert.request(r).has.formparam("x-a-header")
      assert.equals("true", value)
    end)
    it("parameters from JSON body in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          host = "test9.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json["originalparam"])
      assert.is_not_nil(json["renamedparam"])
      assert.equals("yes", json["renamedparam"])
      assert.equals("yes", json["nottorename"])
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test9.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("malformed json body", json.postData.text)
    end)
    it("parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.is_nil(json.postData.params["originalparam"])
      assert.is_not_nil(json.postData.params["renamedparam"])
      assert.equals("yes", json.postData.params["renamedparam"])
      assert.equals("yes", json.postData.params["nottorename"])
    end)
    it("queryString on GET if it exists", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          originalparam = "true",
          nottorename = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("originalparam")
      local value1 = assert.request(r).has.queryparam("renamedparam")
      assert.equals("true", value1)
      local value2 = assert.request(r).has.queryparam("nottorename")
      assert.equals("true", value2)
    end)
  end)

  describe("rename", function()
    it("specified header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test9.com",
          ["x-to-rename"] = "true",
          ["x-another-header"] = "true"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-rename")
      assert.request(r).has.header("x-is-renamed")
      assert.request(r).has.header("x-another-header")
    end)
    it("does not add as new header if header does not exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test9.com",
          ["x-a-header"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("renamedparam")
      local h_a_header = assert.request(r).has.header("x-a-header")
      assert.equals("true", h_a_header)
    end)
    it("specified parameters in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          originalparam = "yes",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.formparam("originalparam")
      local value = assert.request(r).has.formparam("renamedparam")
      assert.equals("yes", value)
    end)
    it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["x-a-header"] = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("renamedparam")
      local value = assert.request(r).has.formparam("x-a-header")
      assert.equals("true", value)
    end)
    it("parameters from JSON body in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          host = "test9.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json["originalparam"])
      assert.is_not_nil(json["renamedparam"])
      assert.equals("yes", json["renamedparam"])
      assert.equals("yes", json["nottorename"])
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test9.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("malformed json body", json.postData.text)
    end)
    it("parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          ["originalparam"] = "yes",
          ["nottorename"] = "yes"
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.is_nil(json.postData.params["originalparam"])
      assert.is_not_nil(json.postData.params["renamedparam"])
      assert.equals("yes", json.postData.params["renamedparam"])
      assert.equals("yes", json.postData.params["nottorename"])
    end)
    it("queryString on GET if it exists", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          originalparam = "true",
          nottorename = "true",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test9.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("originalparam")
      local value1 = assert.request(r).has.queryparam("renamedparam")
      assert.equals("true", value1)
      local value2 = assert.request(r).has.queryparam("nottorename")
      assert.equals("true", value2)
    end)
  end)

  describe("replace", function()
    it("specified header if it exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test5.com",
          h1 = "V",
          h2 = "v2",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.equals("v1", h_h1)
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("v2", h_h2)
    end)
    it("does not add as new header if header does not exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        body = {},
        headers = {
          host = "test5.com",
          h2 = "v2",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("h1")
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("v2", h_h2)
    end)
    it("specified parameters in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v",
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.formparam("p1")
      assert.equals("v1", value)
      local value = assert.request(r).has.formparam("p2")
      assert.equals("v1", value)
    end)
    it("does not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.com"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("p1")
      local value = assert.request(r).has.formparam("p2")
      assert.equals("v1", value)
    end)
    it("specified parameters in json body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v",
          p2 = "v1"
        },
        headers = {
          host = "test5.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.request(r).has.jsonbody()
      assert.equals("v1", json.p1)
      assert.equals("v1", json.p2)
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test5.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("malformed json body", json.postData.text)
    end)
    it("does not add as new parameter in json if parameter does not exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p2 = "v1",
        },
        headers = {
          host = "test5.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.request(r).has.jsonbody()
      assert.is_nil(json.p1)
      assert.equals("v1", json.p2)
    end)
    it("specified parameters on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v",
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test5.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("v1", json.postData.params.p1)
      assert.equals("v1", json.postData.params.p2)
    end)
    it("does not add as new parameter if parameter does not exist on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p2 = "v1",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test5.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.is_nil(json.postData.params.p1)
      assert.equals("v1", json.postData.params.p2)
    end)
    it("queryString on POST if it exist", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        query = {
          q1 = "v",
          q2 = "v2",
        },
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("v1", value)
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
    end)
    it("does not add new queryString on POST if it does not exist", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        query = {
          q2 = "v2",
        },
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test5.com"
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.queryparam("q1")
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
    end)
  end)

  describe("add", function()
    it("new headers", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.equals("v1", h_h1)
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("value:2", h_h2)
    end)
    it("does not change or append value if header already exists", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          h1 = "v3",
          host = "test1.com",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.equals("v3", h_h1)
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("value:2", h_h2)
    end)
    it("new parameter in url encoded body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.formparam("hello")
      assert.equals("world", value)
      local value = assert.request(r).has.formparam("p1")
      assert.equals("v1", value)
    end)
    it("does not change or append value to parameter in url encoded body on POST when parameter exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "should not change",
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.formparam("p1")
      assert.equals("should not change", value)
      local value = assert.request(r).has.formparam("hello")
      assert.equals("world", value)
    end)
    it("new parameter in JSON body on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/json",
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      local params = assert.request(r).has.jsonbody()
      assert.equals("world", params.hello)
      assert.equals("v1", params.p1)
    end)
    it("does not change or append value to parameter in JSON on POST when parameter exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "this should not change",
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/json",
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      local params = assert.request(r).has.jsonbody()
      assert.equals("world", params.hello)
      assert.equals("this should not change", params.p1)
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test1.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("malformed json body", json.postData.text)
    end)
    it("new parameter on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {},
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("v1", json.postData.params.p1)
    end)
    it("does not change or append value to parameter on multipart POST when parameter exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "this should not change",
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test1.com"
        },
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals("this should not change", json.postData.params.p1)
      assert.equals("world", json.postData.params.hello)
    end)
    it("new querystring on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          q2 = "v2",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v2", value)
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("v1", value)
    end)
    it("does not change or append value to querystring on GET if querystring exists", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          q1 = "v2",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test1.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("v2", value)
    end)
    it("should not change the host header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          ["Content-Type"] = "application/json",
          host = "test2.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      local value = assert.has.header("host", json)
      assert.equals("httpbin.org", value)
    end)
  end)

  describe("append ", function()
    it("new header if header does not exists", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test6.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h2 = assert.request(r).has.header("h2")
      assert.equals("v1", h_h2)
    end)
    it("values to existing headers", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test6.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local h_h1 = assert.request(r).has.header("h1")
      assert.equals("v1, v2", h_h1)
    end)
    it("new querystring if querystring does not exists", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q2")
      assert.equals("v1", value)
    end)
    it("values to existing querystring", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("q1")
      assert.are.same({"v1", "v2"}, value)
    end)
    it("new parameter in url encoded body on POST if it does not exist", function()
      local r = assert( client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.are.same({"v1", "v2"}, json.postData.params.p1)
      assert.are.same("value:1", json.postData.params.p2)
    end)
    it("values to existing parameter in url encoded body if parameter already exist on POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "v0",
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host = "test6.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.are.same({"v0", "v1", "v2"}, json.postData.params.p1)
      assert.are.same("value:1", json.postData.params.p2)
    end)
    it("does not fail if JSON body is malformed in POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = "malformed json body",
        headers = {
          host = "test6.com",
          ["content-type"] = "application/json"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("malformed json body", json.postData.text)
    end)
    it("does not change or append value to parameter on multipart POST", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          p1 = "This should not change",
        },
        headers = {
          ["Content-Type"] = "multipart/form-data",
          host = "test6.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.are.same("This should not change", json.postData.params.p1)
    end)
  end)

  describe("remove, replace, add and append ", function()
    it("removes a header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
          ["x-to-remove"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-remove")
    end)
    it("replaces value of header, if header exist", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
          ["x-to-replace"] = "true",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-to-replace")
      assert.equals("false", hval)
    end)
    it("does not add new header if to be replaced header does not exist", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.header("x-to-replace")
    end)
    it("add new header if missing", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-added2")
      assert.equals("b1", hval)
    end)
    it("does not add new header if it already exist", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
          ["x-added3"] = "c1",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-added3")
      assert.equals("c1", hval)
    end)
    it("appends values to existing headers", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      local hval = assert.request(r).has.header("x-added")
      assert.equals("a1, a2, a3", hval)
    end)
    it("adds new parameters on POST when query string key missing", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("p2")
      assert.equals("b1", value)
    end)
    it("removes parameters on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        query = {
          toremovequery = "yes",
          nottoremove = "yes",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.request(r).has.no.queryparam("toremovequery")
      local value = assert.request(r).has.queryparam("nottoremove")
      assert.equals("yes", value)
    end)
    it("replaces parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          toreplacequery = "yes",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("toreplacequery")
      assert.equals("no", value)
    end)
    it("does not add new parameter if to be replaced parameters does not exist on GET", function()
      local r = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.formparam("toreplacequery")
    end)
    it("adds parameters on GET if it does not exist", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("query-added")
      assert.equals("newvalue", value)
    end)
    it("does not add new parameter if to be added parameters already exist on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          ["query-added"] = "oldvalue",
        },
        headers = {
          host = "test3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("query-added")
      assert.equals("oldvalue", value)
    end)
    it("appends parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          q1 = "20",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("p1")
      assert.equals("anything:1", value[1])
      assert.equals("a2", value[2])
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("20", value)
    end)
  end)
  describe("request rewrite using template", function()
    it("template as querystring parameters on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        query = {
          q1 = "20",
        },
        body = {
          hello = "world",
        },
        headers = {
          host = "test10.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.queryparam("uri_param1")
      assert.equals("foo", value)
      value = assert.request(r).has.queryparam("uri_param2")
      assert.equals("bar", value.some_index[1])
    end)
    it("should update request path using hash", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        headers = {
          host = "test11.com",
        }
      })
      assert.response(r).has.status(200)
      local body = assert(assert.response(r).has.jsonbody())
      assert.equals("http://test11.com/requests/user2/bar/user1/foo", body.url)
    end)
    it("should not add querystring if hash missing", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/",
        query = {
          q1 = "20",
        },
        headers = {
          host = "test12.com",
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.queryparam("q1")
      local value = assert.request(r).has.queryparam("uri_param1")
      assert.equals("default1", value)
      value = assert.request(r).has.queryparam("uri_param2")
      assert.equals("default2", value)
    end)
    it("should fail when uri template is not a proper expression", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        headers = {
          host = "test13.com",
        }
      })
      assert.response(r).has.status(500)
    end)
    it("should not fail when uri template rendered using index", function()
      local r = assert(client:send {
        method = "GET",
        path = "/user1/foo/user2/bar",
        headers = {
          host = "test14.com",
        }
      })
      assert.response(r).has.status(200)
      local body = assert(assert.response(r).has.jsonbody())
      assert.equals("http://test14.com/requests/user1/foo/user2/bar", body.url)
    end)
    it("validate using headers/req_querystring for rendering templates",
      function()
        local r = assert(client:send {
          method = "GET",
          path = "/requests/user1/foo/user2/bar",
          query = {
            q1 = "20",
          },
          headers = {
            host = "test15.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(r).has.status(200)
        assert.request(r).has.no.queryparam("q1")
        local value = assert.request(r).has.queryparam("uri_param1")
        assert.equals("foo", value)
        value = assert.request(r).has.queryparam("uri_param2")
        assert.equals("test15.com", value)
        value = assert.request(r).has.header("x-test-header")
        assert.equals("20", value)
      end)
    it("validate that removed header can be used as template", function()
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        query = {
          q2 = "20",
        },
        headers = {
          host = "test16.com",
          ["x-remove-header"] = "its a test",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(200)
      assert.request(r).has.no.header("x-remove-header")
      local value = assert.request(r).has.queryparam("q1")
      assert.equals("foo", value)
      value = assert.request(r).has.queryparam("q2")
      assert.equals("its a test", value)
      value = assert.request(r).has.header("x-test-header")
      assert.equals("its a test", value)
    end)
    it("validate template will be rendered with old value of replaced header",
      function()
        local r = assert(client:send {
          method = "GET",
          path = "/requests/user1/foo/user2/bar",
          query = {
            q2 = "20",
          },
          headers = {
            host = "test17.com",
            ["x-replace-header"] = "the old value",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(r).has.status(200)
        local value = assert.request(r).has.queryparam("q1")
        assert.equals("foo", value)
        value = assert.request(r).has.queryparam("q2")
        assert.equals("the old value", value)
        value = assert.request(r).has.header("x-test-header")
        assert.equals("the old value", value)
        value = assert.request(r).has.header("x-replace-header")
        assert.equals("the new value", value)
      end)
    it("validate template can be escaped",
      function()
        local r = assert(client:send {
          method = "GET",
          path = "/requests/user1/foo/user2/bar",
          query = {
            q2 = "20",
          },
          headers = {
            host = "test18.com",
            ["x-replace-header"] = "the old value",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
        assert.response(r).has.status(200)
        local value = assert.request(r).has.queryparam("q1")
        assert.equals([[$(uri_captures.user1)]], value)
        value = assert.request(r).has.queryparam("q2")
        assert.equals("20", value)
      end)
    it("should fail when rendering errors out", function()
      -- FIXME: the engine is unsafe at render time until
      -- https://github.com/stevedonovan/Penlight/pull/256 is merged and released
      local r = assert(client:send {
        method = "GET",
        path = "/requests/user1/foo/user2/bar",
        query = {
          q2 = "20",
        },
        headers = {
          host = "test19.com",
          ["x-replace-header"] = "the old value",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        }
      })
      assert.response(r).has.status(500)
    end)
  end)
end)
