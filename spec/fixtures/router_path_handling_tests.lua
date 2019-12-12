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
  -- service_path    route_path   strip_path  path_handling  request_path     expected_path
  {  "/",            "/",         true,       "v0",          "/",             "/",                  },
  {  "/",            "/",         true,       "v1",          "/",             "/",                  },
  {  "/",            "/",         true,       "v0",          "/route",        "/route",             },
  {  "/",            "/",         true,       "v1",          "/route",        "/route",             },
  {  "/",            "/",         true,       "v0",          "/route/",       "/route/",            },
  {  "/",            "/",         true,       "v1",          "/route/",       "/route/",            },
  {  "/",            "/route",    true,       "v0",          "/route",        "/",                  },
  {  "/",            "/route",    true,       "v1",          "/route",        "/",                  },
  {  "/",            "/route",    true,       "v0",          "/route/",       "/",                  },
  {  "/",            "/route",    true,       "v1",          "/route/",       "/",                  },
  {  "/",            "/route/",   true,       "v0",          "/route/",       "/",                  },
  {  "/",            "/route/",   true,       "v1",          "/route/",       "/",                  },
  {  "/service",     "/",         true,       "v0",          "/",             "/service",           },
  {  "/service",     "/",         true,       "v1",          "/",             "/service",           },
  {  "/service",     "/",         true,       "v0",          "/route",        "/service/route",     },
  {  "/service",     "/",         true,       "v1",          "/route",        "/serviceroute",      }, -- !
  {  "/service",     "/",         true,       "v0",          "/route/",       "/service/route/",    },
  {  "/service",     "/",         true,       "v1",          "/route/",       "/serviceroute/",     }, -- !
  {  "/service",     "/route",    true,       "v0",          "/route",        "/service",           },
  {  "/service",     "/route",    true,       "v1",          "/route",        "/service",           },
  {  "/service",     "/route",    true,       "v0",          "/route/",       "/service/",          },
  {  "/service",     "/route",    true,       "v1",          "/route/",       "/service/",          },
  {  "/service",     "/route/",   true,       "v0",          "/route/",       "/service",           },
  {  "/service",     "/route/",   true,       "v1",          "/route/",       "/service",           },
  {  "/service/",    "/",         true,       "v0",          "/",             "/service",           },
  {  "/service/",    "/",         true,       "v1",          "/",             "/service/",          },
  {  "/service/",    "/",         true,       "v0",          "/route",        "/service/route",     },
  {  "/service/",    "/",         true,       "v1",          "/route",        "/service/route",     },
  {  "/service/",    "/",         true,       "v0",          "/route/",       "/service/route/",    },
  {  "/service/",    "/",         true,       "v1",          "/route/",       "/service/route/",    },
  {  "/service/",    "/route",    true,       "v0",          "/route",        "/service",           },
  {  "/service/",    "/route",    true,       "v1",          "/route",        "/service/",          },
  {  "/service/",    "/route",    true,       "v0",          "/route/",       "/service/",          },
  {  "/service/",    "/route",    true,       "v1",          "/route/",       "/service/",          },
  {  "/service/",    "/route/",   true,       "v0",          "/route/",       "/service",           },
  {  "/service/",    "/route/",   true,       "v1",          "/route/",       "/service/"           },
  {  "/srv",         "/rou",      true,       "v0",          "/roureq",       "/srv/req",           },
  {  "/srv",         "/rou",      true,       "v1",          "/roureq",       "/srvreq",            },
  {  "/srv/",        "/rou",      true,       "v0",          "/rou",          "/srv",               },
  {  "/srv/",        "/rou",      true,       "v1",          "/rou",          "/srv/",              },
  {  "/",            "/",         false,      "v0",          "/",             "/",                  },
  {  "/",            "/",         false,      "v1",          "/",             "/",                  },
  {  "/",            "/",         false,      "v0",          "/route",        "/route",             },
  {  "/",            "/",         false,      "v1",          "/route",        "/route",             },
  {  "/",            "/",         false,      "v0",          "/route/",       "/route/",            },
  {  "/",            "/",         false,      "v1",          "/route/",       "/route/",            },
  {  "/",            "/route",    false,      "v0",          "/route",        "/route",             },
  {  "/",            "/route",    false,      "v1",          "/route",        "/route",             },
  {  "/",            "/route",    false,      "v0",          "/route/",       "/route/",            },
  {  "/",            "/route",    false,      "v1",          "/route/",       "/route/",            },
  {  "/",            "/route/",   false,      "v0",          "/route/",       "/route/",            },
  {  "/",            "/route/",   false,      "v1",          "/route/",       "/route/",            },
  {  "/service",     "/",         false,      "v0",          "/",             "/service",           },
  {  "/service",     "/",         false,      "v1",          "/",             "/service",           },
  {  "/service",     "/",         false,      "v0",          "/route",        "/service/route",     },
  {  "/service",     "/",         false,      "v1",          "/route",        "/serviceroute",      },
  {  "/service",     "/",         false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service",     "/",         false,      "v1",          "/route/",       "/serviceroute/",     },
  {  "/service",     "/route",    false,      "v0",          "/route",        "/service/route",     },
  {  "/service",     "/route",    false,      "v1",          "/route",        "/serviceroute",      },
  {  "/service",     "/route",    false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service",     "/route",    false,      "v1",          "/route/",       "/serviceroute/",     },
  {  "/service",     "/route/",   false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service",     "/route/",   false,      "v1",          "/route/",       "/serviceroute/",     },
  {  "/service/",    "/",         false,      "v0",          "/",             "/service/",          },
  {  "/service/",    "/",         false,      "v1",          "/",             "/service/",          },
  {  "/service/",    "/",         false,      "v0",          "/route",        "/service/route",     },
  {  "/service/",    "/",         false,      "v1",          "/route",        "/service/route",     },
  {  "/service/",    "/",         false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service/",    "/",         false,      "v1",          "/route/",       "/service/route/",    },
  {  "/service/",    "/route",    false,      "v0",          "/route",        "/service/route",     },
  {  "/service/",    "/route",    false,      "v1",          "/route",        "/service/route",     },
  {  "/service/",    "/route",    false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service/",    "/route",    false,      "v1",          "/route/",       "/service/route/",    },
  {  "/service/",    "/route/",   false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service/",    "/route/",   false,      "v1",          "/route/",       "/service/route/",    },
  {  "/",            "/",         true,       "v0",          "/routereq",     "/routereq",          },
  {  "/",            "/",         true,       "v1",          "/routereq",     "/routereq",          },
  {  "/",            "/",         true,       "v0",          "/route/req",    "/route/req",         },
  {  "/",            "/",         true,       "v1",          "/route/req",    "/route/req",         },
  {  "/",            "/route",    true,       "v0",          "/routereq",     "/req",               },
  {  "/",            "/route",    true,       "v1",          "/routereq",     "/req",               },
  {  "/",            "/route/",   true,       "v0",          "/route/req",    "/req",               },
  {  "/",            "/route/",   true,       "v1",          "/route/req",    "/req",               },
  {  "/service",     "/",         true,       "v0",          "/routereq",     "/service/routereq",  },
  {  "/service",     "/",         true,       "v1",          "/routereq",     "/serviceroutereq",   }, -- !
  {  "/service",     "/",         true,       "v0",          "/route/req",    "/service/route/req", },
  {  "/service",     "/",         true,       "v1",          "/route/req",    "/serviceroute/req",  }, -- !
  {  "/service",     "/route",    true,       "v0",          "/routereq",     "/service/req",       },
  {  "/service",     "/route",    true,       "v1",          "/routereq",     "/servicereq",        }, -- !
  {  "/service",     "/route/",   true,       "v0",          "/route/req",    "/service/req",       },
  {  "/service",     "/route/",   true,       "v1",          "/route/req",    "/servicereq",        }, -- !
  {  "/service/",    "/",         true,       "v0",          "/routereq",     "/service/routereq",  },
  {  "/service/",    "/",         true,       "v1",          "/routereq",     "/service/routereq",  },
  {  "/service/",    "/",         true,       "v0",          "/route/req",    "/service/route/req", },
  {  "/service/",    "/",         true,       "v1",          "/route/req",    "/service/route/req", },
  {  "/service/",    "/route",    true,       "v0",          "/routereq",     "/service/req",       },
  {  "/service/",    "/route",    true,       "v1",          "/routereq",     "/service/req",       },
  {  "/service/",    "/route/",   true,       "v0",          "/route/req",    "/service/req",       },
  {  "/service/",    "/route/",   true,       "v1",          "/route/req",    "/service/req",       },
  {  "/",            "/",         false,      "v0",          "/routereq",     "/routereq",          },
  {  "/",            "/",         false,      "v1",          "/routereq",     "/routereq",          },
  {  "/",            "/",         false,      "v0",          "/route/req",    "/route/req",         },
  {  "/",            "/",         false,      "v1",          "/route/req",    "/route/req",         },
  {  "/",            "/route",    false,      "v0",          "/routereq",     "/routereq",          },
  {  "/",            "/route",    false,      "v1",          "/routereq",     "/routereq",          },
  {  "/",            "/route/",   false,      "v0",          "/route/req",    "/route/req",         },
  {  "/",            "/route/",   false,      "v1",          "/route/req",    "/route/req",         },
  {  "/service",     "/",         false,      "v0",          "/routereq",     "/service/routereq",  },
  {  "/service",     "/",         false,      "v1",          "/routereq",     "/serviceroutereq",   }, -- !
  {  "/service",     "/",         false,      "v0",          "/route/req",    "/service/route/req", },
  {  "/service",     "/",         false,      "v1",          "/route/req",    "/serviceroute/req",  }, -- !
  {  "/service",     "/route",    false,      "v0",          "/routereq",     "/service/routereq",  },
  {  "/service",     "/route",    false,      "v1",          "/routereq",     "/serviceroutereq",   }, -- !
  {  "/service",     "/route/",   false,      "v0",          "/route/req",    "/service/route/req", },
  {  "/service",     "/route/",   false,      "v1",          "/route/req",    "/serviceroute/req",  }, -- !
  {  "/service/",    "/",         false,      "v0",          "/routereq",     "/service/routereq",  },
  {  "/service/",    "/",         false,      "v1",          "/routereq",     "/service/routereq",  },
  {  "/service/",    "/",         false,      "v0",          "/route/req",    "/service/route/req", },
  {  "/service/",    "/",         false,      "v1",          "/route/req",    "/service/route/req", },
  {  "/service/",    "/route",    false,      "v0",          "/routereq",     "/service/routereq",  },
  {  "/service/",    "/route",    false,      "v1",          "/routereq",     "/service/routereq",  },
  {  "/service/",    "/route/",   false,      "v0",          "/route/req",    "/service/route/req", },
  {  "/service/",    "/route/",   false,      "v1",          "/route/req",    "/service/route/req", },
  {  "/",            nil,         false,      "v0",          "/",             "/",                  },
  {  "/",            nil,         false,      "v1",          "/",             "/",                  },
  {  "/",            nil,         false,      "v0",          "/route",        "/route",             },
  {  "/",            nil,         false,      "v1",          "/route",        "/route",             },
  {  "/",            nil,         false,      "v0",          "/route/",       "/route/",            },
  {  "/",            nil,         false,      "v1",          "/route/",       "/route/",            },
  {  "/service",     nil,         false,      "v0",          "/",             "/service",           },
  {  "/service",     nil,         false,      "v1",          "/",             "/service",           },
  {  "/service",     nil,         false,      "v0",          "/route",        "/service/route",     },
  {  "/service",     nil,         false,      "v1",          "/route",        "/serviceroute",      }, -- !
  {  "/service",     nil,         false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service",     nil,         false,      "v1",          "/route/",       "/serviceroute/",     }, -- !
  {  "/service/",    nil,         false,      "v0",          "/",             "/service/",          },
  {  "/service/",    nil,         false,      "v1",          "/",             "/service/",          },
  {  "/service/",    nil,         false,      "v0",          "/route",        "/service/route",     },
  {  "/service/",    nil,         false,      "v1",          "/route",        "/service/route",     },
  {  "/service/",    nil,         false,      "v0",          "/route/",       "/service/route/",    },
  {  "/service/",    nil,         false,      "v1",          "/route/",       "/service/route/",    },
  {  "/",            nil,         true,       "v0",          "/",             "/",                  },
  {  "/",            nil,         true,       "v1",          "/",             "/",                  },
  {  "/",            nil,         true,       "v0",          "/route",        "/route",             },
  {  "/",            nil,         true,       "v1",          "/route",        "/route",             },
  {  "/",            nil,         true,       "v0",          "/route/",       "/route/",            },
  {  "/",            nil,         true,       "v1",          "/route/",       "/route/",            },
  {  "/service",     nil,         true,       "v0",          "/",             "/service",           },
  {  "/service",     nil,         true,       "v1",          "/",             "/service",           },
  {  "/service",     nil,         true,       "v0",          "/route",        "/service/route",     },
  {  "/service",     nil,         true,       "v1",          "/route",        "/serviceroute",      }, -- !
  {  "/service",     nil,         true,       "v0",          "/route/",       "/service/route/",    },
  {  "/service",     nil,         true,       "v1",          "/route/",       "/serviceroute/",     }, -- !
  {  "/service/",    nil,         true,       "v0",          "/",             "/service",           },
  {  "/service/",    nil,         true,       "v1",          "/",             "/service/",          }, -- !
  {  "/service/",    nil,         true,       "v0",          "/route",        "/service/route",     },
  {  "/service/",    nil,         true,       "v1",          "/route",        "/service/route",     },
  {  "/service/",    nil,         true,       "v0",          "/route/",       "/service/route/",    },
  {  "/service/",    nil,         true,       "v1",          "/route/",       "/service/route/",    },
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
