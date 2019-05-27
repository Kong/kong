local Router = require "kong.router"
local build_upstream_uri = require("kong.runloop.handler")._build_upstream_uri

local spy_stub = {
  nop = function() end
}

local function mock_ngx(method, request_uri, headers)
  local _ngx
  _ngx = {
    re = ngx.re,
    var = setmetatable({
      request_uri = request_uri,
      http_kong_debug = headers.kong_debug
    }, {
      __index = function(_, key)
        if key == "http_host" then
          spy_stub.nop()
          return headers.host
        end
      end
    }),
    req = {
      get_method = function()
        return method
      end,
      get_headers = function()
        return headers
      end
    }
  }

  return _ngx
end


describe("build_upstream_uri", function()
  local checks = {
    -- upstream url    paths           request path    expected path           strip uri
    {  "/",            "/",            "/",            "/",                    true      }, -- 1
    {  "/",            "/",            "/foo/bar",     "/foo/bar",             true      },
    {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            true      },
    {  "/",            "/foo/bar",     "/foo/bar",     "/",                    true      },
    {  "/",            "/foo/bar",     "/foo/bar/",    "/",                    true      },
    {  "/",            "/foo/bar/",    "/foo/bar/",    "/",                    true      },
    {  "/fee/bor",     "/",            "/",            "/fee/bor",             true      },
    {  "/fee/bor",     "/",            "/foo/bar",     "/fee/borfoo/bar",      true      },
    {  "/fee/bor",     "/",            "/foo/bar/",    "/fee/borfoo/bar/",     true      },
    {  "/fee/bor",     "/foo/bar",     "/foo/bar",     "/fee/bor",             true      }, -- 10
    {  "/fee/bor",     "/foo/bar",     "/foo/bar/",    "/fee/bor/",            true      },
    {  "/fee/bor",     "/foo/bar/",    "/foo/bar/",    "/fee/bor",             true      },
    {  "/fee/bor/",    "/",            "/",            "/fee/bor/",            true      },
    {  "/fee/bor/",    "/",            "/foo/bar",     "/fee/bor/foo/bar",     true      },
    {  "/fee/bor/",    "/",            "/foo/bar/",    "/fee/bor/foo/bar/",    true      },
    {  "/fee/bor/",    "/foo/bar",     "/foo/bar",     "/fee/bor/",            true      },
    {  "/fee/bor/",    "/foo/bar",     "/foo/bar/",    "/fee/bor/",            true      },
    {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/",    "/fee/bor/",            true      },
    {  "/",            "/",            "/",            "/",                    false     },
    {  "/",            "/",            "/foo/bar",     "/foo/bar",             false     }, -- 20
    {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            false     },
    {  "/",            "/foo/bar",     "/foo/bar",     "/foo/bar",             false     },
    {  "/",            "/foo/bar",     "/foo/bar/",    "/foo/bar/",            false     },
    {  "/",            "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            false     },
    {  "/fee/bor",     "/",            "/",            "/fee/bor",             false     },
    {  "/fee/bor",     "/",            "/foo/bar",     "/fee/borfoo/bar",      false     },
    {  "/fee/bor",     "/",            "/foo/bar/",    "/fee/borfoo/bar/",     false     },
    {  "/fee/bor",     "/foo/bar",     "/foo/bar",     "/fee/borfoo/bar",      false     },
    {  "/fee/bor",     "/foo/bar",     "/foo/bar/",    "/fee/borfoo/bar/",     false     },
    {  "/fee/bor",     "/foo/bar/",    "/foo/bar/",    "/fee/borfoo/bar/",     false     }, -- 30
    {  "/fee/bor/",    "/",            "/",            "/fee/bor/",            false     },
    {  "/fee/bor/",    "/",            "/foo/bar",     "/fee/bor/foo/bar",     false     },
    {  "/fee/bor/",    "/",            "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
    {  "/fee/bor/",    "/foo/bar",     "/foo/bar",     "/fee/bor/foo/bar",     false     },
    {  "/fee/bor/",    "/foo/bar",     "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
    {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
    -- the following block runs the same tests, but with a request path that is longer
    -- than the matched part, so either matches in the middle of a segment, or has an
    -- additional segment.
    {  "/",            "/",            "/foo/bars",    "/foo/bars",            true      },
    {  "/",            "/",            "/foo/bar/s",   "/foo/bar/s",           true      },
    {  "/",            "/foo/bar",     "/foo/bars",    "/s",                   true      },
    {  "/",            "/foo/bar/",    "/foo/bar/s",   "/s",                   true      }, -- 40
    {  "/fee/bor",     "/",            "/foo/bars",    "/fee/borfoo/bars",     true      },
    {  "/fee/bor",     "/",            "/foo/bar/s",   "/fee/borfoo/bar/s",    true      },
    {  "/fee/bor",     "/foo/bar",     "/foo/bars",    "/fee/bors",            true      },
    {  "/fee/bor",     "/foo/bar/",    "/foo/bar/s",   "/fee/bors",            true      },
    {  "/fee/bor/",    "/",            "/foo/bars",    "/fee/bor/foo/bars",    true      },
    {  "/fee/bor/",    "/",            "/foo/bar/s",   "/fee/bor/foo/bar/s",   true      },
    {  "/fee/bor/",    "/foo/bar",     "/foo/bars",    "/fee/bor/s",           true      },
    {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/s",   "/fee/bor/s",           true      },
    {  "/",            "/",            "/foo/bars",    "/foo/bars",            false     },
    {  "/",            "/",            "/foo/bar/s",   "/foo/bar/s",           false     }, -- 50
    {  "/",            "/foo/bar",     "/foo/bars",    "/foo/bars",            false     },
    {  "/",            "/foo/bar/",    "/foo/bar/s",   "/foo/bar/s",           false     },
    {  "/fee/bor",     "/",            "/foo/bars",    "/fee/borfoo/bars",     false     },
    {  "/fee/bor",     "/",            "/foo/bar/s",   "/fee/borfoo/bar/s",    false     },
    {  "/fee/bor",     "/foo/bar",     "/foo/bars",    "/fee/borfoo/bars",     false     },
    {  "/fee/bor",     "/foo/bar/",    "/foo/bar/s",   "/fee/borfoo/bar/s",    false     },
    {  "/fee/bor/",    "/",            "/foo/bars",    "/fee/bor/foo/bars",    false     },
    {  "/fee/bor/",    "/",            "/foo/bar/s",   "/fee/bor/foo/bar/s",   false     },
    {  "/fee/bor/",    "/foo/bar",     "/foo/bars",    "/fee/bor/foo/bars",    false     },
    {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/s",   "/fee/bor/foo/bar/s",   false     }, -- 60
    -- the following block matches on host, instead of path
    {  "/",            nil,            "/",            "/",                    false     },
    {  "/",            nil,            "/foo/bar",     "/foo/bar",             false     },
    {  "/",            nil,            "/foo/bar/",    "/foo/bar/",            false     },
    {  "/fee/bor",     nil,            "/",            "/fee/bor",             false     },
    {  "/fee/bor",     nil,            "/foo/bar",     "/fee/borfoo/bar",      false     },
    {  "/fee/bor",     nil,            "/foo/bar/",    "/fee/borfoo/bar/",     false     },
    {  "/fee/bor/",    nil,            "/",            "/fee/bor/",            false     },
    {  "/fee/bor/",    nil,            "/foo/bar",     "/fee/bor/foo/bar",     false     },
    {  "/fee/bor/",    nil,            "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
    {  "/",            nil,            "/",            "/",                    true      }, -- 70
    {  "/",            nil,            "/foo/bar",     "/foo/bar",             true      },
    {  "/",            nil,            "/foo/bar/",    "/foo/bar/",            true      },
    {  "/fee/bor",     nil,            "/",            "/fee/bor",             true      },
    {  "/fee/bor",     nil,            "/foo/bar",     "/fee/borfoo/bar",      true      },
    {  "/fee/bor",     nil,            "/foo/bar/",    "/fee/borfoo/bar/",     true      },
    {  "/fee/bor/",    nil,            "/",            "/fee/bor/",            true      },
    {  "/fee/bor/",    nil,            "/foo/bar",     "/fee/bor/foo/bar",     true      },
    {  "/fee/bor/",    nil,            "/foo/bar/",    "/fee/bor/foo/bar/",    true      },
  }

  for i, args in ipairs(checks) do

    local config
    if args[5] == true then
      config = "(strip = on, plain)"
    else
      config = "(strip = off, plain)"
    end

    local description
    if args[2] then
      description = string.format("(%d) (%s) %s with uri %s when requesting %s",
        i, config, args[1], args[2], args[3])
    else
      description = string.format("(%d) (%s) %s with host %s when requesting %s",
        i, config, args[1], "localbin-" .. i .. ".com", args[3])
    end

    it(description, function()
      local use_case_routes = {
        {
          service      = {
            protocol   = "http",
            name       = "service-invalid",
            path       = args[1],
          },
          route        = {
            strip_path = args[5],
            paths      = { args[2] },
          },
          headers      = {
            -- only add the header is no path is provided
            host       = args[2] == nil and nil or { "localbin-" .. i .. ".com" },
          },
        }
      }

      local router = assert(Router.new(use_case_routes) )
      local _ngx = mock_ngx("GET", args[3], { host = "localbin-" .. i .. ".com" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.same(use_case_routes[1].route, match_t.route)
      assert.equal(args[1], match_t.upstream_url_t.path)
      local uri = {
        request_uri      = args[3],
        strip_path       = use_case_routes[1].route.strip_path,
        upstream_prefix  = use_case_routes[1].service.path,
        upstream_postfix = match_t.upstream_uri_postfix,
      }
      local upstream_uri = build_upstream_uri(uri, "")
      assert.equal(args[4], upstream_uri)
    end)
  end

  -- this is identical to the tests above, except that for the path we match
  -- with an injected regex sequence, effectively transforming the path
  -- match into a regex match
  local function make_a_regex(path)
    return "/[0]?" .. path:sub(2, -1)
  end

  for i, args in ipairs(checks) do
    local config
    if args[5] == true then
      config = "(strip = on, regex)"
    else
      config = "(strip = off, regex)"
    end

    if args[2] then -- skip test cases which match on host
      local description = string.format("(%d) (%s) %s with uri %s when requesting %s",
                                        i, config, args[1], make_a_regex(args[2]), args[3])

      it(description, function()


        local use_case_routes = {
          {
            service      = {
              protocol   = "http",
              name       = "service-invalid",
              path       = args[1],
            },
            route        = {
              strip_path = args[5],
              paths      = { make_a_regex(args[2]) },
            },
            headers      = {
              -- only add the header is no path is provided
              host       = args[2] == nil and nil or { "localbin-" .. i .. ".com" },
            },
          }
        }

        local router = assert(Router.new(use_case_routes) )
        local _ngx = mock_ngx("GET", args[3], { host = "localbin-" .. i .. ".com" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal(args[1], match_t.upstream_url_t.path)
        local uri = {
          request_uri      = args[3],
          strip_path       = use_case_routes[1].route.strip_path,
          upstream_prefix  = use_case_routes[1].service.path,
          upstream_postfix = match_t.upstream_uri_postfix,
        }
        local upstream_uri = build_upstream_uri(uri, "")
        assert.equal(args[4], upstream_uri)
      end)
    end
  end
end)
