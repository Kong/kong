-- The following tests are used by unit and integration tests
-- to test the router path handling. Putting them here avoids
-- copy-pasting them in several places.
--
-- The tests can obtain this table by requiring
-- "spec.fixtures.router_path_handling_tests"
--
-- Note that the tests are parsed into a hash form at the end
-- of this file before they are returned
--
-- All the tests where v1 differs from v0 are marked with !

local tests = {
  -- service_path    route_path   strip_path  path_handling  request_path    expected_path           --    0
  {  "/",            "/",         true,       "v0",          "/",            "/",                  },
  {  "/",            "/",         true,       "v1",          "/",            "/",                  },
  {  "/",            "/",         true,       "v0",          "/foo/bar",     "/foo/bar",           },
  {  "/",            "/",         true,       "v1",          "/foo/bar",     "/foo/bar",           },
  {  "/",            "/",         true,       "v0",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/",         true,       "v1",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/foo/bar",  true,       "v0",          "/foo/bar",     "/",                  },
  {  "/",            "/foo/bar",  true,       "v1",          "/foo/bar",     "/",                  },
  {  "/",            "/foo/bar",  true,       "v0",          "/foo/bar/",    "/",                  },
  {  "/",            "/foo/bar",  true,       "v1",          "/foo/bar/",    "/",                  }, --  10
  {  "/",            "/foo/bar/", true,       "v0",          "/foo/bar/",    "/",                  },
  {  "/",            "/foo/bar/", true,       "v1",          "/foo/bar/",    "/",                  },
  {  "/fee/bor",     "/",         true,       "v0",          "/",            "/fee/bor",           },
  {  "/fee/bor",     "/",         true,       "v1",          "/",            "/fee/bor",           },
  {  "/fee/bor",     "/",         true,       "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     "/",         true,       "v1",          "/foo/bar",     "/fee/borfoo/bar",    }, -- !
  {  "/fee/bor",     "/",         true,       "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     "/",         true,       "v1",          "/foo/bar/",    "/fee/borfoo/bar/",   }, -- !
  {  "/fee/bor",     "/foo/bar",  true,       "v0",          "/foo/bar",     "/fee/bor",           },
  {  "/fee/bor",     "/foo/bar",  true,       "v1",          "/foo/bar",     "/fee/bor",           }, --  20
  {  "/fee/bor",     "/foo/bar",  true,       "v0",          "/foo/bar/",    "/fee/bor/",          },
  {  "/fee/bor",     "/foo/bar",  true,       "v1",          "/foo/bar/",    "/fee/bor/",          },
  {  "/fee/bor",     "/foo/bar/", true,       "v0",          "/foo/bar/",    "/fee/bor",           },
  {  "/fee/bor",     "/foo/bar/", true,       "v1",          "/foo/bar/",    "/fee/bor",           },
  {  "/fee/bor/",    "/",         true,       "v0",          "/",            "/fee/bor",           },
  {  "/fee/bor/",    "/",         true,       "v1",          "/",            "/fee/bor/",          },
  {  "/fee/bor/",    "/",         true,       "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/",         true,       "v1",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/",         true,       "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/",         true,       "v1",          "/foo/bar/",    "/fee/bor/foo/bar/",  }, --  30
  {  "/fee/bor/",    "/foo/bar",  true,       "v0",          "/foo/bar",     "/fee/bor",           },
  {  "/fee/bor/",    "/foo/bar",  true,       "v1",          "/foo/bar",     "/fee/bor/",          }, -- !
  {  "/fee/bor/",    "/foo/bar",  true,       "v0",          "/foo/bar/",    "/fee/bor/",          },
  {  "/fee/bor/",    "/foo/bar",  true,       "v1",          "/foo/bar/",    "/fee/bor/",          },
  {  "/fee/bor/",    "/foo/bar/", true,       "v0",          "/foo/bar/",    "/fee/bor",           },
  {  "/fee/bor/",    "/foo/bar/", true,       "v1",          "/foo/bar/",    "/fee/bor/"           }, -- !
  {  "/fee",         "/foo",      true,       "v0",          "/foobar",      "/fee/bar",           },
  {  "/fee",         "/foo",      true,       "v1",          "/foobar",      "/feebar",            }, -- !
  {  "/fee/",        "/foo",      true,       "v0",          "/foo",         "/fee",               },
  {  "/fee/",        "/foo",      true,       "v1",          "/foo",         "/fee/",              }, -- !40
  {  "/",            "/",         false,      "v0",          "/",            "/",                  },
  {  "/",            "/",         false,      "v1",          "/",            "/",                  },
  {  "/",            "/",         false,      "v0",          "/foo/bar",     "/foo/bar",           },
  {  "/",            "/",         false,      "v1",          "/foo/bar",     "/foo/bar",           },
  {  "/",            "/",         false,      "v0",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/",         false,      "v1",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/foo/bar",  false,      "v0",          "/foo/bar",     "/foo/bar",           },
  {  "/",            "/foo/bar",  false,      "v1",          "/foo/bar",     "/foo/bar",           },
  {  "/",            "/foo/bar",  false,      "v0",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/foo/bar",  false,      "v1",          "/foo/bar/",    "/foo/bar/",          }, --  50
  {  "/",            "/foo/bar/", false,      "v0",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            "/foo/bar/", false,      "v1",          "/foo/bar/",    "/foo/bar/",          },
  {  "/fee/bor",     "/",         false,      "v0",          "/",            "/fee/bor",           },
  {  "/fee/bor",     "/",         false,      "v1",          "/",            "/fee/bor",           },
  {  "/fee/bor",     "/",         false,      "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     "/",         false,      "v1",          "/foo/bar",     "/fee/borfoo/bar",    },
  {  "/fee/bor",     "/",         false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     "/",         false,      "v1",          "/foo/bar/",    "/fee/borfoo/bar/",   },
  {  "/fee/bor",     "/foo/bar",  false,      "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     "/foo/bar",  false,      "v1",          "/foo/bar",     "/fee/borfoo/bar",    }, --  60
  {  "/fee/bor",     "/foo/bar",  false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     "/foo/bar",  false,      "v1",          "/foo/bar/",    "/fee/borfoo/bar/",   },
  {  "/fee/bor",     "/foo/bar/", false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     "/foo/bar/", false,      "v1",          "/foo/bar/",    "/fee/borfoo/bar/",   },
  {  "/fee/bor/",    "/",         false,      "v0",          "/",            "/fee/bor/",          },
  {  "/fee/bor/",    "/",         false,      "v1",          "/",            "/fee/bor/",          },
  {  "/fee/bor/",    "/",         false,      "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/",         false,      "v1",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/",         false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/",         false,      "v1",          "/foo/bar/",    "/fee/bor/foo/bar/",  }, --  70
  {  "/fee/bor/",    "/foo/bar",  false,      "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/foo/bar",  false,      "v1",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    "/foo/bar",  false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/foo/bar",  false,      "v1",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/foo/bar/", false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    "/foo/bar/", false,      "v1",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  -- the following block runs the same tests, but with a request path that is longer
  -- than the matched part, so either matches in the middle of a segment, or has an
  -- additional segment.
  {  "/",            "/",         true,       "v0",          "/foo/bars",    "/foo/bars",          },
  {  "/",            "/",         true,       "v1",          "/foo/bars",    "/foo/bars",          },
  {  "/",            "/",         true,       "v0",          "/foo/bar/s",   "/foo/bar/s",         },
  {  "/",            "/",         true,       "v1",          "/foo/bar/s",   "/foo/bar/s",         }, --  80
  {  "/",            "/foo/bar",  true,       "v0",          "/foo/bars",    "/s",                 },
  {  "/",            "/foo/bar",  true,       "v1",          "/foo/bars",    "/s",                 },
  {  "/",            "/foo/bar/", true,       "v0",          "/foo/bar/s",   "/s",                 },
  {  "/",            "/foo/bar/", true,       "v1",          "/foo/bar/s",   "/s",                 },
  {  "/fee/bor",     "/",         true,       "v0",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor",     "/",         true,       "v1",          "/foo/bars",    "/fee/borfoo/bars",   }, -- !
  {  "/fee/bor",     "/",         true,       "v0",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor",     "/",         true,       "v1",          "/foo/bar/s",   "/fee/borfoo/bar/s",  }, -- !
  {  "/fee/bor",     "/foo/bar",  true,       "v0",          "/foo/bars",    "/fee/bor/s",         },
  {  "/fee/bor",     "/foo/bar",  true,       "v1",          "/foo/bars",    "/fee/bors",          }, -- ! 90
  {  "/fee/bor",     "/foo/bar/", true,       "v0",          "/foo/bar/s",   "/fee/bor/s",         },
  {  "/fee/bor",     "/foo/bar/", true,       "v1",          "/foo/bar/s",   "/fee/bors",          }, -- !
  {  "/fee/bor/",    "/",         true,       "v0",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/",         true,       "v1",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/",         true,       "v0",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor/",    "/",         true,       "v1",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor/",    "/foo/bar",  true,       "v0",          "/foo/bars",    "/fee/bor/s",         },
  {  "/fee/bor/",    "/foo/bar",  true,       "v1",          "/foo/bars",    "/fee/bor/s",         },
  {  "/fee/bor/",    "/foo/bar/", true,       "v0",          "/foo/bar/s",   "/fee/bor/s",         },
  {  "/fee/bor/",    "/foo/bar/", true,       "v1",          "/foo/bar/s",   "/fee/bor/s",         }, -- 100
  {  "/",            "/",         false,      "v0",          "/foo/bars",    "/foo/bars",          },
  {  "/",            "/",         false,      "v1",          "/foo/bars",    "/foo/bars",          },
  {  "/",            "/",         false,      "v0",          "/foo/bar/s",   "/foo/bar/s",         },
  {  "/",            "/",         false,      "v1",          "/foo/bar/s",   "/foo/bar/s",         },
  {  "/",            "/foo/bar",  false,      "v0",          "/foo/bars",    "/foo/bars",          },
  {  "/",            "/foo/bar",  false,      "v1",          "/foo/bars",    "/foo/bars",          },
  {  "/",            "/foo/bar/", false,      "v0",          "/foo/bar/s",   "/foo/bar/s",         },
  {  "/",            "/foo/bar/", false,      "v1",          "/foo/bar/s",   "/foo/bar/s",         },
  {  "/fee/bor",     "/",         false,      "v0",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor",     "/",         false,      "v1",          "/foo/bars",    "/fee/borfoo/bars",   }, -- ! 110
  {  "/fee/bor",     "/",         false,      "v0",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor",     "/",         false,      "v1",          "/foo/bar/s",   "/fee/borfoo/bar/s",  }, -- !
  {  "/fee/bor",     "/foo/bar",  false,      "v0",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor",     "/foo/bar",  false,      "v1",          "/foo/bars",    "/fee/borfoo/bars",   }, -- !
  {  "/fee/bor",     "/foo/bar/", false,      "v0",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor",     "/foo/bar/", false,      "v1",          "/foo/bar/s",   "/fee/borfoo/bar/s",  }, -- !
  {  "/fee/bor/",    "/",         false,      "v0",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/",         false,      "v1",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/",         false,      "v0",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor/",    "/",         false,      "v1",          "/foo/bar/s",   "/fee/bor/foo/bar/s", }, -- 120
  {  "/fee/bor/",    "/foo/bar",  false,      "v0",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/foo/bar",  false,      "v1",          "/foo/bars",    "/fee/bor/foo/bars",  },
  {  "/fee/bor/",    "/foo/bar/", false,      "v0",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  {  "/fee/bor/",    "/foo/bar/", false,      "v1",          "/foo/bar/s",   "/fee/bor/foo/bar/s", },
  -- the following block matches on host, instead of path
  {  "/",            nil,         false,      "v0",          "/",            "/",                  },
  {  "/",            nil,         false,      "v1",          "/",            "/",                  },
  {  "/",            nil,         false,      "v0",          "/foo/bar",     "/foo/bar",           },
  {  "/",            nil,         false,      "v1",          "/foo/bar",     "/foo/bar",           },
  {  "/",            nil,         false,      "v0",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            nil,         false,      "v1",          "/foo/bar/",    "/foo/bar/",          }, -- 130
  {  "/fee/bor",     nil,         false,      "v0",          "/",            "/fee/bor",           },
  {  "/fee/bor",     nil,         false,      "v1",          "/",            "/fee/bor",           },
  {  "/fee/bor",     nil,         false,      "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     nil,         false,      "v1",          "/foo/bar",     "/fee/borfoo/bar",    }, -- !
  {  "/fee/bor",     nil,         false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     nil,         false,      "v1",          "/foo/bar/",    "/fee/borfoo/bar/",   }, -- !
  {  "/fee/bor/",    nil,         false,      "v0",          "/",            "/fee/bor/",          },
  {  "/fee/bor/",    nil,         false,      "v1",          "/",            "/fee/bor/",          },
  {  "/fee/bor/",    nil,         false,      "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    nil,         false,      "v1",          "/foo/bar",     "/fee/bor/foo/bar",   }, -- 140
  {  "/fee/bor/",    nil,         false,      "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    nil,         false,      "v1",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/",            nil,         true,       "v0",          "/",            "/",                  },
  {  "/",            nil,         true,       "v1",          "/",            "/",                  },
  {  "/",            nil,         true,       "v0",          "/foo/bar",     "/foo/bar",           },
  {  "/",            nil,         true,       "v1",          "/foo/bar",     "/foo/bar",           },
  {  "/",            nil,         true,       "v0",          "/foo/bar/",    "/foo/bar/",          },
  {  "/",            nil,         true,       "v1",          "/foo/bar/",    "/foo/bar/",          },
  {  "/fee/bor",     nil,         true,       "v0",          "/",            "/fee/bor",           },
  {  "/fee/bor",     nil,         true,       "v1",          "/",            "/fee/bor",           }, -- 150
  {  "/fee/bor",     nil,         true,       "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor",     nil,         true,       "v1",          "/foo/bar",     "/fee/borfoo/bar",    }, -- !
  {  "/fee/bor",     nil,         true,       "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor",     nil,         true,       "v1",          "/foo/bar/",    "/fee/borfoo/bar/",   }, -- !
  {  "/fee/bor/",    nil,         true,       "v0",          "/",            "/fee/bor",           },
  {  "/fee/bor/",    nil,         true,       "v1",          "/",            "/fee/bor/",          }, -- !
  {  "/fee/bor/",    nil,         true,       "v0",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    nil,         true,       "v1",          "/foo/bar",     "/fee/bor/foo/bar",   },
  {  "/fee/bor/",    nil,         true,       "v0",          "/foo/bar/",    "/fee/bor/foo/bar/",  },
  {  "/fee/bor/",    nil,         true,       "v1",          "/foo/bar/",    "/fee/bor/foo/bar/",  }, -- 160
}

local parsed_tests = {}
for i = 1, #tests do
  local test = tests[i]
  parsed_tests[i] = {
    service_path  = test[1],
    route_path    = test[2],
    strip_path    = test[3],
    path_handling = test[4],
    request_path  = test[5],
    expected_path = test[6],
  }
end

return parsed_tests
