-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local u = helpers.unindent


local PLUGIN_NAME = "xml-threat-protection"


for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. " [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })


      local route1 = bp.routes:insert({
        hosts = { "namespaced.test" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          checked_content_types = { "application/xml" },
          allowed_content_types = { "application/json" },
          namespace_aware = true,
        },
      }

      local route2 = bp.routes:insert({
        hosts = { "plain.test" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          checked_content_types = { "application/xml" },
          allowed_content_types = { "application/json" },
          namespace_aware = false,
        },
      }

      local route3 = bp.routes:insert({
        hosts = { "dtd.test" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route3.id },
        config = {
          checked_content_types = { "application/xml" },
          allowed_content_types = { "application/json" },
          namespace_aware = true,
          text = 1024 * 1024 * 1024 * 1024, -- big enough to make BLA fail first
          allow_dtd = true,
        },
      }

      -- start kong
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)


    lazy_teardown(function()
      helpers.stop_kong()
    end)


    before_each(function()
      client = helpers.proxy_client()
    end)


    after_each(function()
      if client then client:close() end
    end)



    for _, bdt in ipairs { "small", "cached" } do

      describe(bdt.." body size", function()

        local childTag
        setup(function()
          if bdt == "small" then
            -- small to keep in-memory
            childTag="<child>hello world</child>"
          else
            -- large, that gets cached to disk by nginx
            childTag="<child>"..("a"):rep(1024*512).."</child>" -- 0.5mb, should pass 1mb buffer size, and 1mb text size limits
            childTag=childTag:rep(10) -- 10 * 0.5mb = 5mb total
          end
        end)



        it("valid xml passes", function()
          helpers.clean_logfile()
          local r = client:get("/request", {
            headers = {
              ["host"] = "namespaced.test",
              ["Content-Type"] = "application/xml",
            },
            body = "<root>"..childTag.."</root>"
          })
          assert.response(r).has.status(200)

          -- verify the request was actually (not) cached based on scenario
          local debug_message = "body was cached to disk, reading it back in 1mb chunks"
          if bdt == "small" then
            assert.logfile().has.no.line(debug_message, true, 10)
          else
            assert.logfile().has.line(debug_message, true, 10)
          end
        end)



        describe("fails on", function()

          it("oversized xml", function()
            local tag = ("a"):rep(2048) -- max is 1024 for a tag name
            local r = client:get("/request", {
              headers = {
                ["host"] = "namespaced.test",
                ["Content-Type"] = "application/xml",
              },
              body = "<"..tag..">"..childTag.."</"..tag..">"
            })
            assert.response(r).has.status(400)
          end)


          it("incomplete xml", function()
            local r = client:get("/request", {
              headers = {
                ["host"] = "namespaced.test",
                ["Content-Type"] = "application/xml",
              },
              body = "<root>"..childTag -- missing closed tag
            })
            assert.response(r).has.status(400)
          end)


          it("invalid xml", function()
            local r = client:get("/request", {
              headers = {
                ["host"] = "namespaced.test",
                ["Content-Type"] = "application/xml",
              },
              body = "<root>"..childTag.."</rootabc>" -- mismatched closing tag
            })
            assert.response(r).has.status(400)
          end)


          it("amplified xml", function()
            helpers.clean_logfile()
            local r = client:get("/request", {
              headers = {
                ["host"] = "dtd.test",
                ["Content-Type"] = "application/xml",
              },
              body = u[[
                <?xml version="1.0"?>
                <!DOCTYPE lolz [
                 <!ENTITY lol "lol">
                 <!ELEMENT lolz (#PCDATA)>
                 <!ENTITY lol1 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
                 <!ENTITY lol2 "&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;">
                 <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
                 <!ENTITY lol4 "&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;">
                 <!ENTITY lol5 "&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;">
                 <!ENTITY lol6 "&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;">
                 <!ENTITY lol7 "&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;">
                 <!ENTITY lol8 "&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;">
                 <!ENTITY lol9 "&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;">
                 <!ENTITY lola "&lol9;&lol9;&lol9;&lol9;&lol9;&lol9;&lol9;&lol9;&lol9;&lol9;">
                 <!ENTITY lolb "&lola;&lola;&lola;&lola;&lola;&lola;&lola;&lola;&lola;&lola;">
                ]>
                <lolz>&lolb;</lolz>
              ]]
            })
            assert.response(r).has.status(400)
            assert.logfile().has.line("limit on input amplification factor (from DTD and entities) breached", true)
          end)

        end)

      end)

    end



    describe("content-types:", function()

      it("doesn't allow unknown content-type", function()
        local r = client:get("/request", {
          headers = {
            ["host"] = "namespaced.test",
            ["Content-Type"] = "something/unknown",
          }
        })
        assert.response(r).has.status(400)
      end)


      it("allows 'allowed' content-type", function()
        local r = client:get("/request", {
          headers = {
            ["host"] = "namespaced.test",
            ["Content-Type"] = "application/json",
          }
        })
        assert.response(r).has.status(200)
      end)


      it("checks 'checked' content-type", function()
        local r = client:get("/request", {
          headers = {
            ["host"] = "namespaced.test",
            ["Content-Type"] = "application/xml",
          },
          body = "<root>bad closing tag</rootabc>"
        })
        assert.response(r).has.status(400)
      end)

    end)

  end)
end
