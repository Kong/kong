return {
  ["GET"] = {
    ["NGX_STUB"] = {
      req = {
        get_method = function() return "GET" end,
        http_version = function() return 1.1 end,
        get_headers = function() return {["Accept"]="/*/",["Host"]="mockbin.com"} end,
        get_uri_args = function() return {["hello"]="world",["foo"]="bar"} end,
        start_time = function() return 1429723321.026 end
      },
      resp = {
        get_headers = function() return {["Connection"]="close",["Content-Type"]="application/json",["Content-Length"]="934"} end
      },
      status = 200,
      var = {
        scheme = "http",
        host = "mockbin.com",
        uri = "/request",
        request_length = 123,
        bytes_sent = 934,
        remote_addr = "127.0.0.1"
      },
      ctx = {
        req_body = "request body",
        res_body = "response body"
      }
    },
    ["ENTRY"] = {
      clientIPAddress = "127.0.0.1",
      request = {
        bodySize = 0,
        content = {
          mimeType = "application/octet-stream",
          size = 123,
          text = ""
        },
        headers = { {
            name = "Accept",
            value = "/*/"
          }, {
            name = "Host",
            value = "mockbin.com"
          } },
        headersSize = 10,
        httpVersion = "HTTP/1.1",
        method = "GET",
        queryString = { {
            name = "foo",
            value = "bar"
          }, {
            name = "hello",
            value = "world"
          } },
        url = "http://mockbin.com/request"
      },
      response = {
        bodySize = 934,
        content = {
          mimeType = "application/json",
          size = 934,
          text = ""
        },
        headers = { {
            name = "Content-Length",
            value = "934"
          }, {
            name = "Content-Type",
            value = "application/json"
          }, {
            name = "Connection",
            value = "close"
          } },
        headersSize = 10,
        httpVersion = "",
        status = 200,
        statusText = ""
      },
      startedDateTime = "2015-04-22T17:22:01Z",
      time = 3,
      timings = {
        blocked = 0,
        connect = 0,
        dns = 0,
        receive = 1,
        send = 1,
        ssl = 0,
        wait = 1
      }
    }
  }
}