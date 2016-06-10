local helpers = require "spec.helpers"
local cjson = require "cjson"

local STUB_GET_URL = helpers.STUB_GET_URL
local STUB_POST_URL = helpers.STUB_POST_URL

describe("Request Transformer", function()
  local client
  local api1, api2, api3, api4, api5, api6, pi1, pi2, pi3, pi4, pi5, pi6
  
  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf"
    assert(helpers.prepare_prefix())

    api1 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-1", request_host = "test1.com", upstream_url = "http://mockbin.com"})
    api2 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-2", request_host = "test2.com", upstream_url = "http://httpbin.org"})
    api3 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-3", request_host = "test3.com", upstream_url = "http://mockbin.com"})
    api4 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-4", request_host = "test4.com", upstream_url = "http://mockbin.com"})
    api5 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-5", request_host = "test5.com", upstream_url = "http://mockbin.com"})
    api6 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-6", request_host = "test6.com", upstream_url = "http://mockbin.com"})
    
    pi1 = assert(helpers.dao.plugins:insert {
          api_id = api1.id, 
          name = "request-transformer",
          config = {
            add = {
              headers = {"h1:v1", "h2:v2"},
              querystring = {"q1:v1"},
              body = {"p1:v1"}
            }
          }
        })
        
    pi2 = assert(helpers.dao.plugins:insert {
          api_id = api2.id, 
          name = "request-transformer",
          config = {
            add = {
              headers = {"host:mark"}
            }
          }
        })

    pi3 = assert(helpers.dao.plugins:insert {
          api_id = api3.id, 
          name = "request-transformer",
          config = {
            add = {
              headers = {"x-added:a1", "x-added2:b1", "x-added3:c2"},
              querystring = {"query-added:newvalue", "p1:a1"},
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

    pi4 = assert(helpers.dao.plugins:insert {
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

    pi5 = assert(helpers.dao.plugins:insert {
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

    pi6 = assert(helpers.dao.plugins:insert {
          api_id = api6.id, 
          name = "request-transformer",
          config = {
            append = {
              headers = {"h1:v1", "h1:v2", "h2:v1",},
              querystring = {"q1:v1", "q1:v2", "q2:v1"},
              body = {"p1:v1", "p1:v2", "p2:v1"}
            }
          }
        })

    assert(helpers.start_kong())
  end)

  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.proxy_port))
  end)
  
  after_each(function()
    if client then
      client:close()
    end
  end)
  

  describe("Test remove", function()

    it("should remove specified header", function()
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test4.com", 
          ["x-to-remove"] = "true", 
          ["x-another-header"] = "true"
        }
      })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.has.no.header("x-to-remove", json)
      assert.has.header("x-another-header", json)
    end)

    it("should remove parameters on url encoded form POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.postData.params["toremoveform"])
      assert.equal("yes", json.postData.params["nottoremove"])
    end)

    it("should remove parameters from JSON body in POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local params = cjson.decode(json.postData.text)
      assert.is.Nil(params["toremoveform"])
      assert.are.equal("yes", params["nottoremove"])
    end)

    it("should not fail if JSON body is malformed in POST", function()
      local response = assert(client:send {
          method = "POST",
          path = "/request",
          body = "malformed json body", 
          headers = {
            host = "test4.com", 
            ["content-type"] = "application/json"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.equal("malformed json body", json.postData.text)
    end)

    it("should not fail if body is empty and content type is application/json in POST", function()
      local response = assert(client:send {
          method = "POST",
          path = "/request",
          body = {},
          headers = {
            host = "test4.com", 
            ["content-type"] = "application/json"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.equal('{}', json.postData.text)
      assert.equal("2", json.headers["content-length"])
    end)

    it("should not fail if body is empty in POST", function()
      local response = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "test4.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.same({}, json.postData.params)
      assert.equal('', json.postData.text)
      local value = assert.has.header("content-length", json)
      assert.equal("0", value)
    end)
  
    it("should remove parameters on multipart POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.postData.params["toremoveform"])
      assert.are.equal("yes", json.postData.params["nottoremove"])
    end)
  
    it("should remove queryString on GET if it exist", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.queryString["q1"])
      assert.are.equal("v2", json.queryString["q2"])
    end)
  end)

  describe("Test replace", function()
    
    it("should replace specified header if it exist", function()
      local response = assert( client:send {
          method = "GET",
          path = "/request",
          body = {}, 
          headers = {
            host = "test5.com", 
            h1 = "V", 
            h2 = "v2",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local h_h1 = assert.has.header("h1", json)
      assert.are.equal("v1", h_h1)
      local h_h2 = assert.has.header("h2", json)
      assert.are.equal("v2", h_h2)
    end)
    
    it("should not add as new header if header does not exist", function()
      local response = assert( client:send {
          method = "GET",
          path = "/request",
          body = {}, 
          headers = {
            host = "test5.com", 
            h2 = "v2",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local h_h1 = assert.has.no.header("h1", json)
      local h_h2 = assert.has.header("h2", json)
      assert.are.equal("v2", h_h2)
    end)

    it("should replace specified parameters in url encoded body on POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("v1", json.postData.params.p1)
      assert.are.equal("v1", json.postData.params.p2)
    end)

    it("should not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.postData.params.p1)
      assert.are.equal("v1", json.postData.params.p2)
    end)

    it("should replace specified parameters in json body on POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local params = cjson.decode(json.postData.text)
      assert.are.equal("v1", params.p1)
      assert.are.equal("v1", params.p2)
    end)

    it("should not fail if JSON body is malformed in POST", function()
      local response = assert(client:send {
          method = "POST",
          path = "/request",
          body = "malformed json body", 
          headers = {
            host = "test5.com", 
            ["content-type"] = "application/json"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.equal("malformed json body", json.postData.text)
    end)
    
    it("should not add as new parameter in json if parameter does not exist on POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local params = cjson.decode(json.postData.text)
      assert.is.Nil(params.p1)
      assert.are.equal("v1", params.p2)
    end)

    it("should replace specified parameters on multipart POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("v1", json.postData.params.p1)
      assert.are.equal("v1", json.postData.params.p2)
    end)

    it("should not add as new parameter if parameter does not exist on multipart POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.postData.params.p1)
      assert.are.equal("v1", json.postData.params.p2)
    end)

    it("should replace queryString on POST if it exist", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("v1", json.queryString.q1)
      assert.are.equal("v2", json.queryString.q2)
    end)

    it("should not add new queryString on POST if it does not exist", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.queryString.q1)
      assert.are.equal("v2", json.queryString.q2)
    end)

  end)

  describe("Test add", function()

    it("should add new headers", function()
      local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test1.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local h_h1 = assert.has.header("h1", json)
      assert.are.equal("v1", h_h1)
      local h_h2 = assert.has.header("h2", json)
      assert.are.equal("v2", h_h2)
    end)

    it("should not change or append value if header already exists", function()
      local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            h1 = "v3",
            host = "test1.com",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local h_h1 = assert.has.header("h1", json)
      assert.are.equal("v3", h_h1)
      local h_h2 = assert.has.header("h2", json)
      assert.are.equal("v2", h_h2)
    end)

    it("should add new parameter in url encoded body on POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("world", json.postData.params.hello)
      assert.are.equal("v1", json.postData.params.p1)
    end)

    it("should not change or append value to parameter in url encoded body on POST when parameter exists", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("world", json.postData.params.hello)
      assert.are.equal("should not change", json.postData.params.p1)
    end)

    it("should add new parameter in JSON body on POST", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local params = cjson.decode(json.postData.text)
      assert.are.equal("world", params.hello)
      assert.are.equal("v1", params.p1)
    end)

    it("should not change or append value to parameter in JSON on POST when parameter exists", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local params = cjson.decode(json.postData.text)
      assert.are.equal("world", params.hello)
      assert.are.equal("this should not change", params.p1)
    end)

    it("should not fail if JSON body is malformed in POST", function()
      local response = assert(client:send {
          method = "POST",
          path = "/request",
          body = "malformed json body", 
          headers = {
            host = "test1.com", 
            ["content-type"] = "application/json"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.equal("malformed json body", json.postData.text)
    end)

    it("should add new parameter on multipart POST", function()
      local response = assert(client:send {
          method = "POST",
          path = "/request",
          body = {},
          headers = {
            ["Content-Type"] = "multipart/form-data",
            host = "test1.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("v1", json.postData.params.p1)
    end)

    it("#only should not change or append value to parameter on multipart POST when parameter exists", function()
      local response = assert(client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("this should not change", json.postData.params.p1)
      assert.are.equal("world", json.postData.params.hello)
    end)

    it("should add new querystring on GET", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("v2", json.queryString.q2)
      assert.are.equal("v1", json.queryString.q1)
    end)

    it("should not change or append value to querystring on GET if querystring exists", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("v2", json.queryString.q1)
    end)

    it("should not change the host header", function()
      local response = assert( client:send {
          method = "GET",
          path = "/get",
          headers = {
            ["Content-Type"] = "application/json",
            host = "test2.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local host = assert.has.header("host", json)
      assert.are.equal("httpbin.org", host)
    end)

  end)

  describe("Test append ", function()

    it("should add a new header if header does not exists", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test6.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local h_h2 = assert.has.header("h2", json)
      assert.are.equal("v1", h_h2)
    end)

    it("should append values to existing headers", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test6.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local h_h1 = assert.has.header("h1", json)
      assert.are.equal("v1, v2", h_h1)
    end)

    it("should add new querystring if querystring does not exists", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("v1", json.queryString.q2)
    end)

    it("should append values to existing querystring", function()
      local response = assert( client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host = "test6.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.same({"v1", "v2"}, json.queryString.q1)
    end)

    it("should add new parameter in url encoded body on POST if it does not exist", function()
      local response = assert( client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host = "test6.com"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.same({"v1", "v2"}, json.postData.params.p1)
      assert.are.same("v1", json.postData.params.p2)
    end)

    it("should append values to existing parameter in url encoded body if parameter already exist on POST", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.same({"v0", "v1", "v2"}, json.postData.params.p1)
      assert.are.same("v1", json.postData.params.p2)
    end)

    it("should not fail if JSON body is malformed in POST", function()
      local response = assert(client:send {
          method = "POST",
          path = "/request",
          body = "malformed json body", 
          headers = {
            host = "test6.com", 
            ["content-type"] = "application/json"
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.equal("malformed json body", json.postData.text)
    end)

    it("should not change or append value to parameter on multipart POST", function()
      local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.same("This should not change", json.postData.params.p1)
    end)

  end)

  describe("Test for remove, replace, add and append ", function()

    it("should remove a header", function()
          local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
            ["x-to-remove"] = "true",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.has.no.header("x-to-remove", json)
    end)

    it("should replace value of header, if header exist", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
            ["x-to-replace"] = "true",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local hval = assert.has.header("x-to-replace", json)
      assert.are.equal("false", hval)
    end)

    it("should not add new header if to be replaced header does not exist", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.has.no.header("x-to-replace", json)
    end)

    it("should add new header if missing", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local hval = assert.has.header("x-added2", json)
      assert.are.equal("b1", hval)
    end)

    it("should not add new header if it already exist", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
            ["x-added3"] = "c1",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local hval = assert.has.header("x-added3", json)
      assert.are.equal("c1", hval)
    end)

    it("should append values to existing headers", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      local hval = assert.has.header("x-added", json)
      assert.are.equal("a1, a2, a3", hval)
    end)

    it("should add new parameters on POST when query string key missing", function()
        local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("b1", json.queryString.p2)
    end)

    it("should remove parameters on GET", function()
        local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.queryString.toremovequery)
      assert.are.equal("yes", json.queryString.nottoremove)
    end)

    it("should replace parameters on GET", function()
        local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("no", json.queryString.toreplacequery)
    end)

    it("should not add new parameter if to be replaced parameters does not exist on GET", function()
        local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.queryString.toreplacequery)
    end)
    
    it("should add parameters on GET if it does not exist", function()
          local response = assert( client:send {
          method = "GET",
          path = "/request",
          headers = {
            host = "test3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          }
        })
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("newvalue", json.queryString["query-added"])
    end)

    it("should not add new parameter if to be added parameters already exist on GET", function()
        local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("oldvalue", json.queryString["query-added"])
    end)
    
    it("should append parameters on GET", function()
        local response = assert( client:send {
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
      local body = assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.are.equal("a1", json.queryString.p1[1])
      assert.are.equal("a2", json.queryString.p1[2])
      assert.are.equal("20", json.queryString.q1)
    end)

  end)

end)
