-- The following tests are used by unit and integration tests
-- to test the router path handling. Putting them here avoids
-- copy-pasting them in several places.
--
-- The tests can obtain this table by requiring
-- "spec.fixtures.router_path_handling_tests"
--
-- Note that the tests are parsed into a hash form at the end
-- of this file before they are returned

local tests = {
  -- service_path    route_path   strip_path  request_path    expected_path
  {  "/",            "/",         true,       "/",            "/",                  }, -- 1
  {  "/",            "/",         true,       "/foo/bar",     "/foo/bar",           },
  {  "/",            "/",         true,       "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/foo/bar",  true,       "/foo/bar",     "/",                  },
  {  "/",            "/foo/bar",  true,       "/foo/bar/",    "/",                  },
  {  "/",            "/foo/bar/", true,       "/foo/bar/",    "/",                  },
  {  "/fee/bor",     "/",         true,       "/",            "/fee/bor",           },
  {  "/fee/bor",     "/",         true,       "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     "/",         true,       "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     "/foo/bar",  true,       "/foo/bar",     "/fee/bor",           }, -- 10
  {  "/fee/bor",     "/foo/bar",  true,       "/foo/bar/",    "/fee/bor/",          },
  {  "/fee/bor",     "/foo/bar/", true,       "/foo/bar/",    "/fee/bor",           },
  {  "/fee/bor/",    "/",         true,       "/",            "/fee/bor",           },
  {  "/fee/bor/",    "/",         true,       "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/",         true,       "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/foo/bar",  true,       "/foo/bar",     "/fee/bor",           },
  {  "/fee/bor/",    "/foo/bar",  true,       "/foo/bar/",    "/fee/bor/",          },
  {  "/fee/bor/",    "/foo/bar/", true,       "/foo/bar/",    "/fee/bor",           },
  {  "/fee",         "/foo",      true,       "/foobar",      "/fee/bar",           }, -- 20
  {  "/fee/",        "/foo",      true,       "/foo",         "/fee",               },
  {  "/",            "/",         false,      "/",            "/",                  },
  {  "/",            "/",         false,      "/foo/bar",     "/foo/bar",           },
  {  "/",            "/",         false,      "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/foo/bar",  false,      "/foo/bar",     "/foo/bar",           },
  {  "/",            "/foo/bar",  false,      "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/foo/bar/", false,      "/foo/bar/",    "/foo/bar/",          },
  {  "/fee/bor",     "/",         false,      "/",            "/fee/bor",           },
  {  "/fee/bor",     "/",         false,      "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     "/",         false,      "/foo/bar/",    "/fee/bor/foo/bar/",  }, -- 30
  {  "/fee/bor",     "/foo/bar",  false,      "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     "/foo/bar",  false,      "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     "/foo/bar/", false,      "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/",         false,      "/",            "/fee/bor/",          },
  {  "/fee/bor/",    "/",         false,      "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/",         false,      "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/foo/bar",  false,      "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/foo/bar",  false,      "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/foo/bar/", false,      "/foo/bar/",    "/fee/bor/foo/bar/",  },
  -- the following block runs the same tests, but with a request path that is longer
  -- than the matched part, so either matches in the middle of a segment, or has an
  -- additional segment.
  {  "/",            "/",         true,       "/foo/bars",    "/foo/bars",          }, -- 40
  {  "/",            "/",         true,       "/foo/bar/s",   "/foo/bar/s",         },
  {  "/",            "/foo/bar",  true,       "/foo/bars",    "/s",                 },
  {  "/",            "/foo/bar/", true,       "/foo/bar/s",   "/s",                 },
  {  "/fee/bor",     "/",         true,       "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor",     "/",         true,       "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor",     "/foo/bar",  true,       "/foo/bars",    "/fee/bor/s",         },
  {  "/fee/bor",     "/foo/bar/", true,       "/foo/bar/s",   "/fee/bor/s",         },
  {  "/fee/bor/",    "/",         true,       "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/",         true,       "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor/",    "/foo/bar",  true,       "/foo/bars",    "/fee/bor/s",         }, -- 50
  {  "/fee/bor/",    "/foo/bar/", true,       "/foo/bar/s",   "/fee/bor/s",         },
  {  "/",            "/",         false,      "/foo/bars",    "/foo/bars",          },
  {  "/",            "/",         false,      "/foo/bar/s",   "/foo/bar/s",         },
  {  "/",            "/foo/bar",  false,      "/foo/bars",    "/foo/bars",          },
  {  "/",            "/foo/bar/", false,      "/foo/bar/s",   "/foo/bar/s",         },
  {  "/fee/bor",     "/",         false,      "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor",     "/",         false,      "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor",     "/foo/bar",  false,      "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor",     "/foo/bar/", false,      "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor/",    "/",         false,      "/foo/bars",    "/fee/bor/foo/bars",  }, -- 60
  {  "/fee/bor/",    "/",         false,      "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor/",    "/foo/bar",  false,      "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/foo/bar/", false,      "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  -- the following block matches on host, instead of path
  {  "/",            nil,         false,      "/",            "/",                  },
  {  "/",            nil,         false,      "/foo/bar",     "/foo/bar",           },
  {  "/",            nil,         false,      "/foo/bar/",    "/foo/bar/",          },
  {  "/fee/bor",     nil,         false,      "/",            "/fee/bor",           },
  {  "/fee/bor",     nil,         false,      "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     nil,         false,      "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    nil,         false,      "/",            "/fee/bor/",          }, -- 70
  {  "/fee/bor/",    nil,         false,      "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    nil,         false,      "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/",            nil,         true,       "/",            "/",                  },
  {  "/",            nil,         true,       "/foo/bar",     "/foo/bar",           },
  {  "/",            nil,         true,       "/foo/bar/",    "/foo/bar/",          },
  {  "/fee/bor",     nil,         true,       "/",            "/fee/bor",           },
  {  "/fee/bor",     nil,         true,       "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     nil,         true,       "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    nil,         true,       "/",            "/fee/bor",           },
  {  "/fee/bor/",    nil,         true,       "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    nil,         true,       "/foo/bar/",    "/fee/bor/foo/bar/",  }, -- 80
}

local parsed_tests = {}
for i = 1, #tests do
  local test = tests[i]
  parsed_tests[i] = {
    service_path  = test[1],
    route_path    = test[2],
    strip_path    = test[3],
    request_path  = test[4],
    expected_path = test[5],
  }
end

return parsed_tests
