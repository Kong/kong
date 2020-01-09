local header_transformer = require "kong.plugins.response-transformer-advanced.header_transformer"


describe("Plugin: response-transformer-advanced", function()
  describe("execute_headers()", function()
    describe("remove", function()
      local conf_skip = {
        remove    = {
          headers = {
            "h1", "h2",
            "h3:v1",
            "h4:v1", "h4:v2",
            "h5:v1",
            "h6:v1",
            "h7:v1",
            "h8:v1",
            "h9:v1",
            "h10:v1",
            "h10:v2",
            "h11:v1",
            "h12:v1",
            "h13:v1",
            "h14:/JSESSIONID=.*/",
            "h15://status/$/",
            "h16:/^/begin//",
            "h17:/JSESSIONID=.*/",
            "h18://status/$/",
            "h19:/^/begin//",
            "h20:v22",
            "h21:/v2^/",
            "h22:v2",
            "h23:/v2/",
            "Set-Cookie:/JSESSIONID=.*/",
            "h24:v1",
            "h25:/v1/"
          },
            if_status = {"201-300", "500"}
        },
        replace   = {
          headers = {}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {}
        },
        append    = {
          headers = {}
        }
      }
      it("skips removing headers if response code doesn't match", function()
        local ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}}
        local ngx_headers_copy = {h1 = "value1", h2 = {"value2a", "value2b"}}
        header_transformer.transform_headers(conf_skip, ngx_headers, 200)
        assert.same(ngx_headers, ngx_headers_copy)
      end)

      it("removes headers if response code is in given range", function()
        local ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}}
        local ngx_headers_copy = {h1 = "value1", h2 = {"value2a", "value2b"}}
        header_transformer.transform_headers(conf_skip, ngx_headers, 201)
        assert.is_not.same(ngx_headers, ngx_headers_copy)
      end)
      it("specific header value", function()
        local req_ngx_headers = {
          h1 = {"v1", "v2", "v3"},
          h2 = {"v2"},
          h3 = {"v1"},
          h4 = {"v1", "v2", "v3"},
          h5 = {"v1", "v2"},
          h6 = {"v2"},
          h7 = "v1",
          h8 = "v2",
          h9 = "v1,v2",
          h10 = "v1,v2,v3",
          h11 = "v1, v2, v3",
          h12 = "v1;v2;v3",
          h13 = "v1; v2; v3",
          h14 = "JSESSIONID=1876832,path=/,COOKIE2",
          h15 = "/match/status/,/status/no-match/",
          h16 = "/begin/match/,/no-match/begin/",
          h17 = {"JSESSIONID=1876832", "path=/", "COOKIE2"},
          h18 = {"/match/status/","/status/no-match/"},
          h19 = {"/begin/match/","/no-match/begin/"},
          h20 = "v2",
          h21 = "v22",
          h22 = "v22",
          h23 = "v22",
          ["Set-Cookie"] = "JSESSIONID=12345,path=/",
          h24 = "v1,v2,v3",
          h25 = "v1;v2;v3",
        }

        header_transformer.transform_headers(conf_skip, req_ngx_headers, 201)
        assert.same({
          h4 = {"v3"},
          h5 = {"v2"},
          h6 = {"v2"},
          h8 = "v2",
          h9 = "v2",
          h10 = "v3",
          h11 = " v2, v3",
          h12 = "v1;v2;v3",
          h13 = "v1; v2; v3",
          h14 = "path=/,COOKIE2",
          h15 = "/status/no-match/",
          h16 = "/no-match/begin/",
          h17 = {"path=/", "COOKIE2"},
          h18 = {"/status/no-match/"},
          h19 = {"/no-match/begin/"},
          h20 = "v2",
          h21 = "v22",
          h22 = "v22",
          ["Set-Cookie"] = "path=/",
          h24 = "v2,v3",
        }, req_ngx_headers)
      end)
    end)
    describe("replace", function()
      local conf_skip  = {
        remove    = {
          headers = {}
        },
        replace   = {
          headers = {"h1:v1", "h2:value:2"},  -- payload with colon to verify parsing
          if_status = {"201-300", "500"}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {}
        },
        append    = {
          headers = {}
        }
      }
      it("is skipped if response code doesn't match", function()
        local req_ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}}
        local req_ngx_headers_copy = {h1 = "value1", h2 = {"value2a", "value2b"}}
        header_transformer.transform_headers(conf_skip, req_ngx_headers, 200)
        assert.same(req_ngx_headers, req_ngx_headers_copy)
      end)

      it("is not skipped if response code is in range", function()
        local req_ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}}
        local req_ngx_headers_copy = {h1 = "value1", h2 = {"value2a", "value2b"}}
        header_transformer.transform_headers(conf_skip, req_ngx_headers, 205)
        assert.is_not.same(req_ngx_headers, req_ngx_headers_copy)
      end)
    end)
    describe("add", function()
      local conf_skip  = {
        remove    = {
          headers = {}
        },
        replace   = {
          headers = {}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {"h2:v2"},
          if_status = {"201-300", "500"}
        },
        append    = {
          headers = {}
        }
      }
      it("is skipped if response code doesn't match", function()
        local req_ngx_headers = {h1 = "v1"}
        local req_ngx_headers_copy = {h1 = "v1"}
        header_transformer.transform_headers(conf_skip, req_ngx_headers, 200)
        assert.same(req_ngx_headers, req_ngx_headers_copy)
      end)

      it("is not skipped if response code is in range", function()
        local req_ngx_headers = {h1 = "v1"}
        local req_ngx_headers_copy = {h1 = "v1"}
        header_transformer.transform_headers(conf_skip, req_ngx_headers, 201)
        assert.is_not.same(req_ngx_headers, req_ngx_headers_copy)
      end)
    end)
    describe("append", function()
      local conf_skip = {
        remove    = {
          headers = {}
        },
        replace   = {
          headers = {}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {}
        },
        append    = {
          headers = {"h1:v2"},
          if_status = {"201-300", "500"}
        }
      }
      it("is skipped if response code doesn't match", function()
        local req_ngx_headers = {}
        header_transformer.transform_headers(conf_skip, req_ngx_headers, 200)
        assert.same({}, req_ngx_headers)
      end)
      it("is not skipped if response code is in range", function()
        local req_ngx_headers = {}
        header_transformer.transform_headers(conf_skip, req_ngx_headers, 205)
        assert.is_not.same({}, req_ngx_headers)
      end)
    end)
    describe("performing remove, replace, add, append together", function()
      local conf_skip = {
        remove    = {
          headers = {"h1:v1"},
          if_status = {500}
        },
        replace   = {
          headers = {"h2:v3"},
          if_status = {500}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {"h3:v3"},
          if_status = {500}
        },
        append    = {
          headers = {"h3:v4"},
          if_status = {500}
        }
      }
      it("transforms all headers is skipped if response code doesn't match", function()
        local req_ngx_headers = {h1 = "v1", h2 = "v2"}
        local req_ngx_headers_copy = {h1 = "v1", h2 = "v2"}
        header_transformer.transform_headers(conf_skip, req_ngx_headers, 200)
        assert.same(req_ngx_headers, req_ngx_headers_copy)
      end)
    end)
  end)
end)
