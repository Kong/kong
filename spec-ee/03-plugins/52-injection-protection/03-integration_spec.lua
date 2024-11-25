-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local url_encode    = ngx.escape_uri

-- All enabled except xpath (tested separately)
local conf_all_on = {
  injection_types = {
    "sql",
    "js",
    "ssi",
    "java_exception",
  },
  locations = {
    "headers",
    "path_and_query",
    "body",
  },
  custom_injections = {
    {
      name = "custom",
      regex = "matchthis",
    }
  },
  enforcement_mode = "block",
  error_status_code = 400,
  error_message = "Bad Request",
}

local conf_all_on_log_only = {
  injection_types = {
    "sql",
    "js",
    "ssi",
    "java_exception",
  },
  locations = {
    "headers",
    "path_and_query",
    "body",
  },
  custom_injections = {
    {
      name = "custom",
      regex = "matchthis",
    }
  },
  enforcement_mode = "log_only",
  error_status_code = 400,
  error_message = "Bad Request",
}

local conf_xpath_abbreviated = {
  injection_types = {
    "xpath_abbreviated",
  },
  locations = {
    "path_and_query",
    "body",
  },
  enforcement_mode = "block",
}

local conf_xpath_abbreviated_log_only = {
  injection_types = {
    "xpath_abbreviated",
  },
  locations = {
    "path_and_query",
    "body",
  },
  enforcement_mode = "log_only",
}

local conf_xpath_extended = {
  injection_types = {
    "xpath_extended",
  },
  locations = {
    "headers",
    "path_and_query",
    "body",
  },
  enforcement_mode = "block",
}

local conf_xpath_extended_log_only = {
  injection_types = {
    "xpath_extended",
  },
  locations = {
    "headers",
    "path_and_query",
    "body",
  },
  enforcement_mode = "log_only",
}

local injections = {
  sql = "insert into test",
  js = "<script>foo.bar()</script>",
  ssi = "<!--#include virtual=\"/etc/passwd\"-->",
  xpath_abbreviated = "/@foo",
  xpath_extended = "/descendant::node()",
  java_exception = "Exception in thread \"main\"",
  custom = "it should matchthis",
}

-- Payload is a table with (one of) header, body, path_and_query
local function post_request(client, payload, log_only, host)

  local headers = {
    ["Host"] = host,
  }

  if log_only then
    headers["X-Log-Only"] = "1"
  end

  local req

  if payload.header then 
    headers["X-Test-Header"] = payload.header
    req = client:post("/request", {
      headers = headers,
    })
  end
  
  if payload.body then
    req = client:post("/request", {
      headers = headers,
      body = payload.body
    })
  end

  if payload.path_and_query then
    local escaped_query = url_encode(payload.path_and_query)
    req = client:post("/request?foo=" .. escaped_query, {
      headers = headers,
    })
  end

  return req
end

local helpers = require "spec.helpers"

for _, strategy in helpers.all_strategies() do

  describe("check_injections #" .. strategy, function()

    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        }, { "injection-protection"}
      )

      local route1 = bp.routes:insert({
        hosts = { "example.com" },
      })

      local route2 = bp.routes:insert({
        hosts = { "example.com" },
        headers = {
          ["X-Log-Only"] = {"1"},
        },
      })


      local route3 = bp.routes:insert({
        hosts = { "abbreviated.example.com" },
      })

      local route4 = bp.routes:insert({
        hosts = { "abbreviated.example.com" },
        headers = {
          ["X-Log-Only"] = {"1"},
        },
      })

      local route5 = bp.routes:insert({
        hosts = { "extended.example.com" },
      })

      local route6 = bp.routes:insert({
        hosts = { "extended.example.com" },
        headers = {
          ["X-Log-Only"] = {"1"},
        },
      })



      bp.plugins:insert({
        name = "injection-protection",
        route = { id = route1.id },
        config = conf_all_on,
      })

      bp.plugins:insert({
        name = "injection-protection",
        route = { id = route2.id },
        config = conf_all_on_log_only,
      })

      bp.plugins:insert({
        name = "injection-protection",
        route = { id = route3.id },
        config = conf_xpath_abbreviated,
      })

      bp.plugins:insert({
        name = "injection-protection",
        route = { id = route4.id },
        config = conf_xpath_abbreviated_log_only,
      })

      bp.plugins:insert({
        name = "injection-protection",
        route = { id = route5.id },
        config = conf_xpath_extended,
      })

      bp.plugins:insert({
        name = "injection-protection",
        route = { id = route6.id },
        config = conf_xpath_extended_log_only,
      })


      assert(helpers.start_kong({
        database   = strategy,
        plugins = "injection-protection",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)
  
    before_each(function()
      client = helpers.proxy_client()
    end)
  
    after_each(function()
      helpers.clean_logfile()
      if client then
        client:close()
      end
    end)

    for injection_name, injection_value in pairs(injections) do
      for _,location in ipairs( { "header", "body", "path_and_query" } ) do
        -- run if not xpath abbreviated in header
        if not (injection_name == "xpath_abbreviated" or injection_name == "xpath_extended") then 

          it("should find " .. injection_name .. " injection in " .. location, function()

            local req = post_request(client, {
              [location] = injection_value,
            }, false, "example.com")

            assert.response(req).has.status(400)
            -- kong.log.warn("threat detected: '", name, "', action taken: ", action, ", found in ", location, ", ", details)
            assert.logfile().has.line("threat detected: '" .. injection_name .. "', action taken: block, found in " .. location)
          end)
        elseif injection_name == "xpath_abbreviated" and location ~= "header"  then -- don't check header because it matches headers with a slash like "application/json"

          it("should find " .. injection_name .. " injection in " .. location, function()

          local req = post_request(client, {
            [location] = injection_value,
          }, false, "abbreviated.example.com")

          assert.response(req).has.status(400)
          assert.logfile().has.line("threat detected: '" .. injection_name .. "', action taken: block, found in " .. location)
        end)
          
        elseif injection_name == "xpath_extended"  then
          it("should find " .. injection_name .. " injection in " .. location, function()

            local req = post_request(client, {
              [location] = injection_value,
            }, false, "extended.example.com")

            assert.response(req).has.status(400)
            assert.logfile().has.line("threat detected: '" .. injection_name .. "', action taken: block, found in " .. location)
          end)
      end
    end
  end


    for injection_name, injection_value in pairs(injections) do
      for _,location in ipairs( { "header", "body", "path_and_query" } ) do
        -- run if not xpath abbreviated in header
        if not (injection_name == "xpath_abbreviated" or injection_name == "xpath_extended") then -- disabled for now because it matches headers with a slash like "application/json"

          it("should find " .. injection_name .. " injection in " .. location .. " but log only", function()

            local req = post_request(client, {
              [location] = injection_value,
            }, true, "example.com")

            assert.response(req).has.status(200)
            assert.logfile().has.line("threat detected: '" .. injection_name .. "', action taken: log_only, found in " .. location)

          end)
        elseif injection_name == "xpath_abbreviated" and location ~= "header" then -- don't check header because it matches headers with a slash like "application/json"
          it("should find " .. injection_name .. " injection in " .. location .. " but log only", function()

            local req = post_request(client, {
              [location] = injection_value,
            }, true, "abbreviated.example.com")

            assert.response(req).has.status(200)
            assert.logfile().has.line("threat detected: '" .. injection_name .. "', action taken: log_only, found in " .. location)

          end)
        elseif injection_name == "xpath_extended" then
          it("should find " .. injection_name .. " injection in " .. location .. " but log only", function()

            local req = post_request(client, {
              [location] = injection_value,
            }, true, "extended.example.com")

            assert.response(req).has.status(200)
            assert.logfile().has.line("threat detected: '" .. injection_name .. "', action taken: log_only, found in " .. location)

          end)
        end
      end
    end

  it("should allow requests if they don't contain injections", function()
    local req = client:post("/request", {
      headers = {
        ["Host"] = "example.com",
        -- ["Content-Type"] = "application/json",
      },
      body = '{"foo": "bar"}'
    })
    assert.response(req).has.status(200)

  end)

end)

end

