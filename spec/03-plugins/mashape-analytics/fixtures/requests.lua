local EMPTY_ARRAY_PLACEHOLDER = "__empty_array_placeholder__"

return {
  ["GET"] = {
    ["NGX_STUB"] = {
      req = {
        start_time = function() return 1432844571.623 end,
        get_method = function() return "GET" end,
        http_version = function() return 1.1 end,
        get_headers = function() return {["Accept"] = "/*/", ["Host"] = "mockbin.com"} end,
        get_uri_args = function() return {["hello"] = "world", ["foo"] = "bar", ["number"] = 2} end
      },
      resp = {
        get_headers = function() return {["Connection"] = "close", ["Content-Type"] = "application/json", ["Content-Length"] = "934"} end
      },
      status = 200,
      var = {
        scheme = "http",
        host = "mockbin.com",
        request_uri = "/request",
        request_length = 123,
        body_bytes_sent = 934,
        remote_addr = "127.0.0.1"
      },
      ctx = {
        KONG_PROXY_LATENCY = 22,
        KONG_WAITING_TIME = 236,
        KONG_RECEIVE_TIME = 177,
        analytics = {
          req_body = "hello=world&hello=earth",
          res_body = "{\"message\":\"response body\"}",
          req_post_args = {["hello"] = {"world", "earth"}}
        }
      }
    },
    ["ENTRY"] = {
      cache = {},
      request = {
        bodySize = 23,
        cookies = {EMPTY_ARRAY_PLACEHOLDER},
        headers = {
          {name = "Accept", value = "/*/"},
          {name = "Host", value = "mockbin.com"}
        },
        headersSize = 24,
        httpVersion = "HTTP/1.1",
        method = "GET",
        postData = {
          mimeType = "application/octet-stream",
          params = {
            {name = "hello", value = "world"},
            {name = "hello", value = "earth"}
          },
          text = "base64_hello=world&hello=earth"
        },
        queryString = {
          {name = "foo", value = "bar"},
          {name = "hello", value = "world"},
          {name = "hello", value = "2"}
        },
        url = "http://mockbin.com/request"
      },
      response = {
        bodySize = 934,
        content = {
          mimeType = "application/json",
          size = 934,
          text = "base64_{\"message\":\"response body\"}"
        },
        cookies = {EMPTY_ARRAY_PLACEHOLDER},
        headers = {
          {name = "Content-Length", value = "934"},
          {name = "Content-Type", value = "application/json"},
          {name = "Connection", value = "close"}
        },
        headersSize = 60,
        httpVersion = "",
        redirectURL = "",
        status = 200,
        statusText = ""
      },
      startedDateTime = "2015-05-28T20:22:51Z",
      time = 435,
      timings = {
        blocked = -1,
        connect = -1,
        dns = -1,
        receive = 177,
        send = 22,
        ssl = -1,
        wait = 236
      }
    }
  },
  ["MULTIPLE_UPSTREAMS"] = {
    ["NGX_STUB"] = {
      req = {
        start_time = function() return 1432844571.623 end,
        get_method = function() return "GET" end,
        http_version = function() return 1.1 end,
        get_headers = function() return {["Accept"] = "/*/", ["Host"] = "mockbin.com"} end,
        get_uri_args = function() return {["hello"] = "world", ["foo"] = "bar"} end
      },
      resp = {
        get_headers = function() return {["Connection"] = "close", ["Content-Type"] = "application/json", ["Content-Length"] = "934"} end
      },
      status = 200,
      var = {
        scheme = "http",
        host = "mockbin.com",
        request_uri = "/request",
        request_length = 123,
        body_bytes_sent = 934,
        remote_addr = "127.0.0.1"
      },
      ctx = {
        KONG_PROXY_LATENCY = 10,
        KONG_WAITING_TIME = 236,
        KONG_RECEIVE_TIME = 1,
        analytics = {
          req_body = "hello=world&hello=earth",
          res_body = "{\"message\":\"response body\"}",
          req_post_args = {["hello"] = {"world", "earth"}}
        }
      }
    },
    ["ENTRY"] = {
      cache = {},
      request = {
        bodySize = 23,
        cookies = {EMPTY_ARRAY_PLACEHOLDER},
        headers = {
          {name = "Accept", value = "/*/"},
          {name = "Host", value = "mockbin.com"}
        },
        headersSize = 24,
        httpVersion = "HTTP/1.1",
        method = "GET",
        postData = {
          mimeType = "application/octet-stream",
          params = {
            {name = "hello", value = "world"},
            {name = "hello", value = "earth"}
          },
          text = "base64_hello=world&hello=earth"
        },
        queryString = {
          {name = "foo", value = "bar"},
          {name = "hello", value = "world"}
        },
        url = "http://mockbin.com/request"
      },
      response = {
        bodySize = 934,
        content = {
          mimeType = "application/json",
          size = 934,
          text = "base64_{\"message\":\"response body\"}"
        },
        cookies = {EMPTY_ARRAY_PLACEHOLDER},
        headers = {
          {name = "Content-Length", value = "934"},
          {name = "Content-Type", value = "application/json"},
          {name = "Connection", value = "close"}
        },
        headersSize = 60,
        httpVersion = "",
        redirectURL = "",
        status = 200,
        statusText = ""
      },
      startedDateTime = "2015-05-28T20:22:51Z",
      time = 247,
      timings = {
        blocked = -1,
        connect = -1,
        dns = -1,
        receive = 1,
        send = 10,
        ssl = -1,
        wait = 236
      }
    }
  },
  ["MULTIPLE_HEADERS"] = {
    ["NGX_STUB"] = {
      req = {
        start_time = function() return 1432844571.623 end,
        get_method = function() return "GET" end,
        http_version = function() return 1.1 end,
        get_headers = function() return {["Accept"] = "/*/", ["Host"] = "mockbin.com", ["Content-Type"] = {"application/json", "application/www-form-urlencoded"}} end,
        get_uri_args = function() return {["hello"] = "world", ["foo"] = "bar"} end
      },
      resp = {
        get_headers = function() return {["Connection"] = "close", ["Content-Type"] = {"application/json", "application/www-form-urlencoded"}, ["Content-Length"] = "934"} end
      },
      status = 200,
      var = {
        scheme = "http",
        host = "mockbin.com",
        request_uri = "/request",
        request_length = 123,
        body_bytes_sent = 934,
        remote_addr = "127.0.0.1"
      },
      ctx = {
        KONG_PROXY_LATENCY = 10,
        KONG_WAITING_TIME = 236,
        KONG_RECEIVE_TIME = 1,
        analytics = {
          req_body = "hello=world&hello=earth",
          res_body = "{\"message\":\"response body\"}",
          req_post_args = {["hello"] = {"world", "earth"}}
        }
      }
    },
    ["ENTRY"] = {
      cache = {},
      request = {
        bodySize = 23,
        cookies = {EMPTY_ARRAY_PLACEHOLDER},
        headers = {
          {name = "Accept", value = "/*/"},
          {name = "Host", value = "mockbin.com"},
          {name = "Content-Type", value = "application/json"},
          {name = "Content-Type", value = "application/www-form-urlencoded"}
        },
        headersSize = 95,
        httpVersion = "HTTP/1.1",
        method = "GET",
        postData = {
          mimeType = "application/www-form-urlencoded",
          params = {
            {name = "hello", value = "world"},
            {name = "hello", value = "earth"}
          },
          text = "base64_hello=world&hello=earth"
        },
        queryString = {
          {name = "foo", value = "bar"},
          {name = "hello", value = "world"}
        },
        url = "http://mockbin.com/request"
      },
      response = {
        bodySize = 934,
        content = {
          mimeType = "application/www-form-urlencoded",
          size = 934,
          text = "base64_{\"message\":\"response body\"}"
        },
        cookies = {EMPTY_ARRAY_PLACEHOLDER},
        headers = {
          {name = "Content-Length", value = "934"},
          {name = "Content-Type", value = "application/json"},
          {name = "Content-Type", value = "application/www-form-urlencoded"},
          {name = "Connection", value = "close"}
        },
        headersSize = 103,
        httpVersion = "",
        redirectURL = "",
        status = 200,
        statusText = ""
      },
      startedDateTime = "2015-05-28T20:22:51Z",
      time = 247,
      timings = {
        blocked = -1,
        connect = -1,
        dns = -1,
        receive = 1,
        send = 10,
        ssl = -1,
        wait = 236
      }
    }
  }
}
