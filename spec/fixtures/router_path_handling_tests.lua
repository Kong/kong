local utils = require "kong.tools.utils"

-- The following tests are used by unit and integration tests
-- to test the router path handling. Putting them here avoids
-- copy-pasting them in several places.
--
-- The tests can obtain this table by requiring
-- "spec.fixtures.router_path_handling_tests"
--
-- The rows are sorted by service_path, route_path, strip_path, path_handling and request_path.
--
-- Notes:
-- * The tests are parsed into a hash form at the end
--   of this file before they are returned.
-- * Before a test can be executed, it needs to be "expanded".
--   For example, a test with {"v0", "v1"} must be converted
--   into two tests, one with "v0" and one with "v1". Each line
--   can be expanded using the `line:expand()` method.

local tests = {
  -- service_path    route_path  strip_path     path_handling  request_path     expected_path
  {  "/",            "/",        {false, true}, {"v0", "v1"},  "/",             "/",                  },
  {  "/",            "/",        {false, true}, {"v0", "v1"},  "/route",        "/route",             },
  {  "/",            "/",        {false, true}, {"v0", "v1"},  "/route/",       "/route/",            },
  {  "/",            "/",        {false, true}, {"v0", "v1"},  "/routereq",     "/routereq",          },
  {  "/",            "/",        {false, true}, {"v0", "v1"},  "/route/req",    "/route/req",         },
  -- 5
  {  "/",            "/route",   false,         {"v0", "v1"},  "/route",        "/route",             },
  {  "/",            "/route",   false,         {"v0", "v1"},  "/route/",       "/route/",            },
  {  "/",            "/route",   false,         {"v0", "v1"},  "/routereq",     "/routereq",          },
  {  "/",            "/route",   true,          {"v0", "v1"},  "/route",        "/",                  },
  {  "/",            "/route",   true,          {"v0", "v1"},  "/route/",       "/",                  },
  {  "/",            "/route",   true,          {"v0", "v1"},  "/routereq",     "/req",               },
  -- 11
  {  "/",            "/route/",  false,         {"v0", "v1"},  "/route/",       "/route/",            },
  {  "/",            "/route/",  false,         {"v0", "v1"},  "/route/req",    "/route/req",         },
  {  "/",            "/route/",  true,          {"v0", "v1"},  "/route/",       "/",                  },
  {  "/",            "/route/",  true,          {"v0", "v1"},  "/route/req",    "/req",               },
  -- 15
  {  "/srv",         "/rou",     false,         "v0",          "/roureq",       "/srv/roureq",        },
  {  "/srv",         "/rou",     false,         "v1",          "/roureq",       "/srvroureq",         },
  {  "/srv",         "/rou",     true,          "v0",          "/roureq",       "/srv/req",           },
  {  "/srv",         "/rou",     true,          "v1",          "/roureq",       "/srvreq",            },
  -- 19
  {  "/srv/",        "/rou",     false,         {"v0", "v1"},  "/rou",          "/srv/rou",           },
  {  "/srv/",        "/rou",     true,          "v0",          "/rou",          "/srv",               },
  {  "/srv/",        "/rou",     true,          "v1",          "/rou",          "/srv/",              },
  -- 22
  {  "/service",     "/",        {false, true}, {"v0", "v1"},  "/",             "/service",           },
  {  "/service",     "/",        {false, true}, "v0",          "/route",        "/service/route",     },
  {  "/service",     "/",        {false, true}, "v1",          "/route",        "/serviceroute",      },
  {  "/service",     "/",        {false, true}, "v0",          "/route/",       "/service/route/",    },
  {  "/service",     "/",        {false, true}, "v1",          "/route/",       "/serviceroute/",     },
  -- 27
  {  "/service",     "/",        {false, true}, "v0",          "/routereq",     "/service/routereq",  },
  {  "/service",     "/",        {false, true}, "v1",          "/routereq",     "/serviceroutereq",   },
  {  "/service",     "/",        {false, true}, "v0",          "/route/req",    "/service/route/req", },
  {  "/service",     "/",        {false, true}, "v1",          "/route/req",    "/serviceroute/req",  },
  -- 31
  {  "/service",     "/route",   false,         "v0",          "/route",        "/service/route",     },
  {  "/service",     "/route",   false,         "v1",          "/route",        "/serviceroute",      },
  {  "/service",     "/route",   false,         "v0",          "/route/",       "/service/route/",    },
  {  "/service",     "/route",   false,         "v1",          "/route/",       "/serviceroute/",     },
  {  "/service",     "/route",   false,         "v0",          "/routereq",     "/service/routereq",  },
  {  "/service",     "/route",   false,         "v1",          "/routereq",     "/serviceroutereq",   },
  {  "/service",     "/route",   true,          {"v0", "v1"},  "/route",        "/service",           },
  {  "/service",     "/route",   true,          {"v0", "v1"},  "/route/",       "/service/",          },
  {  "/service",     "/route",   true,          "v0",          "/routereq",     "/service/req",       },
  {  "/service",     "/route",   true,          "v1",          "/routereq",     "/servicereq",        },
  -- 41
  {  "/service",     "/route/",  false,         "v0",          "/route/",       "/service/route/",    },
  {  "/service",     "/route/",  false,         "v1",          "/route/",       "/serviceroute/",     },
  {  "/service",     "/route/",  false,         "v0",          "/route/req",    "/service/route/req", },
  {  "/service",     "/route/",  false,         "v1",          "/route/req",    "/serviceroute/req",  },
  {  "/service",     "/route/",  true,          "v0",          "/route/",       "/service/",          },
  {  "/service",     "/route/",  true,          "v1",          "/route/",       "/service",           },
  {  "/service",     "/route/",  true,          "v0",          "/route/req",    "/service/req",       },
  {  "/service",     "/route/",  true,          "v1",          "/route/req",    "/servicereq",        },
  -- 49
  {  "/service/",    "/",        {false, true}, "v0",          "/route/",       "/service/route/",    },
  {  "/service/",    "/",        {false, true}, "v1",          "/route/",       "/service/route/",    },
  {  "/service/",    "/",        {false, true}, {"v0", "v1"},  "/",             "/service/",          },
  {  "/service/",    "/",        {false, true}, {"v0", "v1"},  "/route",        "/service/route",     },
  {  "/service/",    "/",        {false, true}, {"v0", "v1"},  "/routereq",     "/service/routereq",  },
  {  "/service/",    "/",        {false, true}, {"v0", "v1"},  "/route/req",    "/service/route/req", },
  -- 55
  {  "/service/",    "/route",   false,         {"v0", "v1"},  "/route",        "/service/route",      },
  {  "/service/",    "/route",   false,         {"v0", "v1"},  "/route/",       "/service/route/",     },
  {  "/service/",    "/route",   false,         {"v0", "v1"},  "/routereq",     "/service/routereq",   },
  {  "/service/",    "/route",   true,          "v0",          "/route",        "/service",            },
  {  "/service/",    "/route",   true,          "v1",          "/route",        "/service/",           },
  {  "/service/",    "/route",   true,          {"v0", "v1"},  "/route/",       "/service/",           },
  {  "/service/",    "/route",   true,          {"v0", "v1"},  "/routereq",     "/service/req",        },
  -- 62
  {  "/service/",    "/route/",  false,         {"v0", "v1"},  "/route/",       "/service/route/",     },
  {  "/service/",    "/route/",  false,         {"v0", "v1"},  "/route/req",    "/service/route/req",  },
  {  "/service/",    "/route/",  true,          {"v0", "v1"},  "/route/",       "/service/",           },
  {  "/service/",    "/route/",  true,          {"v0", "v1"},  "/route/req",    "/service/req",        },
  -- 66
  -- The following cases match on host (not paths)
  {  "/",            nil,        {false, true}, {"v0", "v1"},  "/",             "/",                  },
  {  "/",            nil,        {false, true}, {"v0", "v1"},  "/route",        "/route",             },
  {  "/",            nil,        {false, true}, {"v0", "v1"},  "/route/",       "/route/",            },
  -- 69
  {  "/service",     nil,        {false, true}, {"v0", "v1"},  "/",             "/service",           },
  {  "/service",     nil,        {false, true}, "v0",          "/route",        "/service/route",     },
  {  "/service",     nil,        {false, true}, "v1",          "/route",        "/serviceroute",      },
  {  "/service",     nil,        {false, true}, "v0",          "/route/",       "/service/route/",    },
  {  "/service",     nil,        {false, true}, "v1",          "/route/",       "/serviceroute/",     },
  -- 74
  {  "/service/",    nil,        {false, true}, {"v0", "v1"},  "/",             "/service/",          },
  {  "/service/",    nil,        {false, true}, {"v0", "v1"},  "/route",        "/service/route",     },
  {  "/service/",    nil,        {false, true}, {"v0", "v1"},  "/route/",       "/service/route/",    },
}


local function expand(root_test)
  local expanded_tests = { root_test }

  for _, field_name in ipairs({ "strip_path", "path_handling" }) do
    local new_tests = {}
    for _, test in ipairs(expanded_tests) do
      if type(test[field_name]) == "table" then
        for _, field_value in ipairs(test[field_name]) do
          local et = utils.deep_copy(test)
          et[field_name] = field_value
          new_tests[#new_tests + 1] = et
        end

      else
        new_tests[#new_tests + 1] = test
      end
    end
    expanded_tests = new_tests
  end

  return expanded_tests
end


local tests_mt = {
  __index = {
    expand = expand
  }
}


local parsed_tests = {}
for i = 1, #tests do
  local test = tests[i]
  parsed_tests[i] = setmetatable({
    service_path  = test[1],
    route_path    = test[2],
    strip_path    = test[3],
    path_handling = test[4],
    request_path  = test[5],
    expected_path = test[6],
  }, tests_mt)
end

return parsed_tests
