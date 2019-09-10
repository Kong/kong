local header_transformer = require "kong.plugins.response-transformer-advanced.header_transformer"


local CONTENT_LENGTH     = "content-length"


describe("Plugin: response-transformer-advanced", function()
  describe("execute_headers()", function()
    describe("remove", function()
      local conf  = {
        remove    = {
          headers = {"h1", "h2", "h3"}
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
        },
        whitelist    = {
          json = {}
        },
      }
      it("all the headers", function()
        local ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}}
        header_transformer.transform_headers(conf, ngx_headers)
        assert.same({}, ngx_headers)
      end)
      it("sets content-length nil", function()
        local ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}, [CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
        header_transformer.transform_headers(conf, ngx_headers)
        assert.is_nil(ngx_headers[CONTENT_LENGTH])
      end)
    end)
    describe("replace", function()
      local conf  = {
        remove    = {
          headers = {}
        },
        replace   = {
          headers = {"h1:v1", "h2:value:2"}  -- payload with colon to verify parsing
        },
        add       = {
          json    = {"p1:v1"},
          headers = {}
        },
        append    = {
          headers = {}
        },
        whitelist    = {
          json = {}
        },
      }
      it("header if the header only exists", function()
        local req_ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}}
        header_transformer.transform_headers(conf, req_ngx_headers)
        assert.same({h1 = "v1", h2 = "value:2"}, req_ngx_headers)
      end)
      it("does not add a new header if the header does not already exist", function()
        local req_ngx_headers = {h2 = {"value2a", "value2b"}}
        header_transformer.transform_headers(conf, req_ngx_headers)
        assert.same({h2 = "value:2"}, req_ngx_headers)
      end)
      it("sets content-length nil", function()
        local ngx_headers = {h1 = "value1", h2 = {"value2a", "value2b"}, [CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
        header_transformer.transform_headers(conf, ngx_headers)
        assert.is_nil(ngx_headers[CONTENT_LENGTH])
      end)
    end)
    describe("add", function()
      local conf  = {
        remove    = {
          headers = {}
        },
        replace   = {
          headers = {}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {"h2:v2"}
        },
        append    = {
          headers = {}
        },
        whitelist    = {
          json = {}
        },
      }
      it("header if the header does not exists", function()
        local req_ngx_headers = {h1 = "v1"}
        header_transformer.transform_headers(conf, req_ngx_headers)
        assert.same({h1 = "v1", h2 = "v2"}, req_ngx_headers)
      end)
      it("does not add a new header if the header already exist", function()
        local req_ngx_headers = {h1 = "v1", h2 = "v3"}
        header_transformer.transform_headers(conf, req_ngx_headers)
        assert.same({h1 = "v1", h2 = "v3"}, req_ngx_headers)
      end)
      it("sets content-length nil", function()
        local ngx_headers = {h1 = "v1", [CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
        header_transformer.transform_headers(conf, ngx_headers)
        assert.is_nil(ngx_headers[CONTENT_LENGTH])
      end)
    end)
    describe("append", function()
      local conf  = {
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
          headers = {"h1:v2"}
        },
        whitelist    = {
          json = {}
        },
      }
      it("header if the header does not exists", function()
        local req_ngx_headers = {}
        header_transformer.transform_headers(conf, req_ngx_headers)
        assert.same({"v2"}, req_ngx_headers["h1"])
      end)
      it("header if the header already exist", function()
        local req_ngx_headers = {h1 = "v1"}
        header_transformer.transform_headers(conf, req_ngx_headers)
        assert.same({h1 = {"v1", "v2"}}, req_ngx_headers)
      end)
      it("sets content-length nil", function()
        local ngx_headers = {h1 = "v1", [CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
        header_transformer.transform_headers(conf, ngx_headers)
        assert.is_nil(ngx_headers[CONTENT_LENGTH])
      end)
    end)
    describe("performing remove, replace, add, append together", function()
      local conf  = {
        remove    = {
          headers = {"h1:v1"}
        },
        replace   = {
          headers = {"h2:v3"}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {"h3:v3"}
        },
        append    = {
          headers = {"h3:v4"}
        },
        whitelist    = {
          json = {}
        },
      }
      it("transforms all headers", function()
        local req_ngx_headers = {h1 = "v1", h2 = "v2"}
        header_transformer.transform_headers(conf, req_ngx_headers)
        assert.same({h2 = "v3", h3 = {"v3", "v4"}}, req_ngx_headers)
      end)
      it("sets content-length nil", function()
        local ngx_headers = {h1 = "v1", [CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
        header_transformer.transform_headers(conf, ngx_headers)
        assert.is_nil(ngx_headers[CONTENT_LENGTH])
      end)
    end)
    describe("content-type json", function()
      describe("remove", function()
        local conf  = {
          remove    = {
            json    = {"p1"},
            headers = {"h1", "h2"}
          },
          replace   = {
            json    = {},
            headers = {}
          },
          add       = {
            json    = {},
            headers = {}
          },
          append    = {
            json    = {},
            headers = {}
          },
          whitelist    = {
            json = {}
          },
        }
        it("sets content-length nil if application/json passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("sets content-length nil if application/json and charset passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/x-www-form-urlencoded; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.remove.json = {}
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
      end)
      describe("replace", function()
        local conf  = {
          remove    = {
            json    = {},
            headers = {}
          },
          replace   = {
            json    = {"p1:v1", "p2:v1"},
            headers = {"h1:v1", "h2:v2"}
          },
          add       = {
            json    = {},
            headers = {}
          },
          append    = {
            json    = {},
            headers = {}
          },
          whitelist    = {
            json = {}
          },
        }
        it("sets content-length nil if application/json passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("sets content-length nil if application/json and charset passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/x-www-form-urlencoded; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.replace.json = {}
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
      end)
      describe("add", function()
        local conf  = {
          remove    = {
            json    = {},
            headers = {}
          },
          replace   = {
            json    = {},
            headers = {}
          },
          add       = {
            json    = {"p1:v1", "p2:v1"},
            headers = {"h1:v1", "h2:v2"}
          },
          append    = {
            json    = {},
            headers = {}
          },
          whitelist    = {
            json = {}
          },
        }
        it("set content-length nil if application/json passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("set content-length nil if application/json and charset passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/x-www-form-urlencoded; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.add.json = {}
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
      end)
      describe("append", function()
        local conf  = {
          remove    = {
            json    = {},
            headers = {}
          },
          replace   = {
            json    = {},
            headers = {}
          },
          add       = {
            json    = {},
            headers = {}
          },
          append    = {
            json    = {"p1:v1", "p2:v1"},
            headers = {"h1:v1", "h2:v2"}
          },
          whitelist    = {
            json = {}
          },
        }
        it("set content-length nil if application/json passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("set content-length nil if application/json and charset passed", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.is_nil(ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/x-www-form-urlencoded; charset=utf-8"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.append.json = {}
          local ngx_headers = {[CONTENT_LENGTH] = "100", ["content-type"] = "application/json"}
          header_transformer.transform_headers(conf, ngx_headers)
          assert.equals('100', ngx_headers[CONTENT_LENGTH])
        end)
      end)
    end)
  end)
end)
