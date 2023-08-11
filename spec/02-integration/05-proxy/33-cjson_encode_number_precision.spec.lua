local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
    describe("cjson encode number with defalut(14) precision [#" .. strategy .. "]", function()
      local proxy_client
  
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "plugins",
          "routes",
          "services",
        })
  
        local service = assert(bp.services:insert({
            path = "/hello",
        }))
  
        local route = assert(bp.routes:insert({
            service = service,
            paths = { "/foo" }
        }))
  
        assert(bp.plugins:insert {
            route     = { id = route.id },
            name      = "request-termination",
            config    = {
                body = '{"key":1.234567891011121E16, "hello":" world"}',
                content_type = "application/json",
                echo = false,
                status_code = 200
              }
          })

        -- add response-transformer plugin to ensure the response body has been encoded by cjson
        -- so that 6.07526679167888E14 can be converted by cjson with precision
        assert(bp.plugins:insert {
            route     = { id = route.id },
            name      = "response-transformer",
            config    = {
                remove = {
                    json = {"hello"}
                }
              }
          })          
  
        helpers.start_kong({
          database = strategy,
          plugins = "bundled",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        })
      end)
  
      lazy_teardown(function()
        helpers.stop_kong()
      end)
  
      before_each(function()
        proxy_client = helpers.proxy_client()
      end)
  
      after_each(function()
        if proxy_client then
          proxy_client:close()
        end
      end)
  
      it("default precision of cjson encode number will round off data with more than 14 significant digits", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo",
        })
  
        local body = res:read_body()
        assert.res_status(200, res)
        assert.is_equal('{"key":1.2345678910111e+16}', body)
      end)
    end)

    describe("cjson encode number with 16 precision [#" .. strategy .. "]", function()
        local proxy_client
    
        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "plugins",
            "routes",
            "services",
          })
    
          local service = assert(bp.services:insert({
              path = "/hello",
          }))
    
          local route = assert(bp.routes:insert({
              service = service,
              paths = { "/foo" }
          }))
    
          assert(bp.plugins:insert {
              route     = { id = route.id },
              name      = "request-termination",
              config    = {
                  body = '{"key":1.234567891011121E16, "hello":" world"}',
                  content_type = "application/json",
                  echo = false,
                  status_code = 200
                }
            })
  
          -- add response-transformer plugin to ensure the response body has been encoded by cjson
          -- so that 1.234567891011121E16 can be converted by cjson with precision
          assert(bp.plugins:insert {
              route     = { id = route.id },
              name      = "response-transformer",
              config    = {
                  remove = {
                      json = {"hello"}
                  }
                }
            })          
    
          helpers.start_kong({
            database = strategy,
            plugins = "bundled",
            cjson_encode_number_precision = 16,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          })
        end)
    
        lazy_teardown(function()
          helpers.stop_kong()
        end)
    
        before_each(function()
          proxy_client = helpers.proxy_client()
        end)
    
        after_each(function()
          if proxy_client then
            proxy_client:close()
          end
        end)
    
        it("cjson encode number with 16 significant digits", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/foo",
          })
    
          local body = res:read_body()
          assert.res_status(200, res)
          assert.is_equal('{"key":1.234567891011121e+16}', body)
        end)
    end)
end
