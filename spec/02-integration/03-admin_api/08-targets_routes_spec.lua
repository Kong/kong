local helpers = require "spec.helpers"
--local cjson = require "cjson"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title.." with application/www-form-urlencoded", test_form_encoded)
  it(title.." with application/json", test_json)
end

local upstream_name = "my_upstream"

describe("Admin API", function()
  
  local client, upstream
  local weight_default, weight_min, weight_max = 100, 0, 1000
  local default_port = 8000
  
  before_each(function()
    assert(helpers.start_kong())
    client = assert(helpers.admin_client())
    
    upstream = assert(helpers.dao.upstreams:insert {
      name = upstream_name,
      slots = 10,
      orderlist = { 1,2,3,4,5,6,7,8,9,10 }
    })
  end)
  
  after_each(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("/upstreams/{upstream}/targets/", function()
    describe("POST", function()
      it_content_types("creates a target with defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/"..upstream_name.."/targets/",
            body = {
              target = "mashape.com",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("mashape.com:"..default_port, json.target)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(weight_default, json.weight)
        end
      end)
      it_content_types("creates a target without defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/"..upstream_name.."/targets/",
            body = {
              target = "mashape.com:123",
              weight = 99,
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("mashape.com:123", json.target)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(99, json.weight)
        end
      end)
      it("cleans up old target entries", function()
        -- count to 12; 10 old ones, 1 active one, and then nr 12 to
        -- trigger the cleanup
        for i = 1, 12 do
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams/"..upstream_name.."/targets/",
            body = {
              target = "mashape.com:123",
              weight = 99,
            },
            headers = {
              ["Content-Type"] = "application/json"
            },
          })
          assert.response(res).has.status(201)
        end
        local history = assert(helpers.dao.targets:find_all {
          upstream_id = upstream.id,
        })
        -- there should be 2 left; 1 from the cleanup, and the final one 
        -- inserted that triggered the cleanup
        assert.equal(2, #history)
      end)
      
      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = assert(client:request {
            method = "POST",
            path = "/upstreams/"..upstream_name.."/targets/",
            body = '{"hello": "world"',
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.response(res).has.status(400)
          assert.equal('{"message":"Cannot parse JSON body"}', body)
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams/"..upstream_name.."/targets/",
              body = {
                weight = weight_min,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.response(res).has.status(400)
            assert.equal([[{"target":"target is required"}]], body)

            -- Invalid target parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams/"..upstream_name.."/targets/",
              body = {
                target = "some invalid host name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.response(res).has.status(400)
            assert.equal([[{"message":"Invalid target; not a valid hostname or ip address"}]], body)
            
            -- Invalid weight parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams/"..upstream_name.."/targets/",
              body = {
                target = "mashape.com",
                weight = weight_max + 1,
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.response(res).has.status(400)
            assert.equal([[{"message":"weight must be from 0 to 1000"}]], body)
          end
        end)
        
        for _, method in ipairs({"PUT", "PATCH", "DELETE"}) do
          it_content_types("returns 405 on "..method, function(content_type)
            return function()
              local res = assert(client:send {
                method = method,
                path = "/upstreams/"..upstream_name.."/targets/",
                body = {
                  target = "mashape.com",
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.response(res).has.status(405)
            end
          end)
        end
      end)
    end)

    describe("GET", function()
      before_each(function()
        for i = 1, 10 do
          assert(helpers.dao.targets:insert {
            target = "api-"..i..":80",
            weight = 100,
            upstream_id = upstream.id,
          })
        end
      end)
    
      it("retrieves the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/upstreams/"..upstream_name.."/targets/",
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(10, #json.data)
        assert.equal(10, json.total)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/"..upstream_name.."/targets/",
            query = {size = 3, offset = offset}
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.equal(10, json.total)

          if i < 4 then
            assert.equal(3, #json.data)
          else
            assert.equal(1, #json.data)
          end

          if i > 1 then
            -- check all pages are different
            assert.not_same(pages[i-1], json)
          end

          offset = json.offset
          pages[i] = json
        end
      end)
      it("handles invalid filters", function()
        local res = assert(client:send {
          method = "GET",
          path = "/upstreams/"..upstream_name.."/targets/",
          query = {foo = "bar"},
        })
        local body = assert.response(res).has.status(400)
        assert.equal([[{"foo":"unknown field"}]], body)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/upstreams/"..upstream_name.."/targets/",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.response(res).has.status(200)
      end)

      describe("empty results", function()
        local upstream_name2 = "getkong.org"
        
        before_each(function()
          assert(helpers.dao.upstreams:insert {
            name = upstream_name2,
            slots = 10,
            orderlist = { 1,2,3,4,5,6,7,8,9,10 }
          })
        end)
        
        it("data property is an empty array", function()
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams/"..upstream_name2.."/targets/",
          })
          local body = assert.response(res).has.status(200)
          assert.equal([[{"data":[],"total":0}]], body)
        end)
      end)
    end)
  end)
end)
