local CONTENT_LENGTH = "Content-Length"
local CONTENT_TYPE = "Content-Type"
local JSON = "application/json"
local JSON_UTF8 = "application/json; charset=utf-8"
local FORM = "application/x-www-form-urlencoded; charset=utf-8"


local function get_headers(headers)
  _G.ngx.resp.get_headers = function()
    return headers
  end

  _G.ngx.header = headers

  return headers
end


describe("Plugin: response-transformer", function()
  local header_transformer

  setup(function()
    _G.ngx = {
      headers_sent = false,
      resp = {
      }
    }
    _G.kong = {
      response = require "kong.pdk.response".new(),
      ctx = {
        core = {
          phase = 0x00000200,
        }
      }
    }

    header_transformer = require "kong.plugins.response-transformer.header_transformer"
  end)
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
        }
      }
      it("all the headers", function()
        local headers = get_headers({ h1 = "value1", h2 = { "value2a", "value2b" } })
        header_transformer.transform_headers(conf, headers)
        assert.same({}, headers)
      end)
      it("sets content-length nil", function()
        local headers = get_headers({ h1 = "value1", h2 = {"value2a", "value2b"}, [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
        header_transformer.transform_headers(conf, headers)
        assert.is_nil(headers[CONTENT_LENGTH])
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
        }
      }
      it("header if the header only exists", function()
        local headers = get_headers({ h1 = "value1", h2 = { "value2a", "value2b" } })
        header_transformer.transform_headers(conf, headers)
        assert.same({h1 = "v1", h2 = "value:2"}, headers)
      end)
      it("does not add a new header if the header does not already exist", function()
        local headers = get_headers({ h2 = { "value2a", "value2b" } })
        header_transformer.transform_headers(conf, headers)
        assert.same({h2 = "value:2"}, headers)
      end)
      it("sets content-length nil", function()
        local headers = get_headers({ h1 = "value1", h2 = {"value2a", "value2b"}, [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
        header_transformer.transform_headers(conf, headers)
        assert.is_nil(headers[CONTENT_LENGTH])
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
        }
      }
      it("header if the header does not exists", function()
        local headers = get_headers({ h1 = "v1" })
        header_transformer.transform_headers(conf, headers)
        assert.same({h1 = "v1", h2 = "v2"}, headers)
      end)
      it("does not add a new header if the header already exist", function()
        local headers = get_headers({ h1 = "v1", h2 = "v3" })
        header_transformer.transform_headers(conf, headers)
        assert.same({h1 = "v1", h2 = "v3"}, headers)
      end)
      it("sets content-length nil", function()
        local headers = get_headers({ h1 = "v1", [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
        header_transformer.transform_headers(conf, headers)
        assert.is_nil(headers[CONTENT_LENGTH])
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
        }
      }
      it("header if the header does not exists", function()
        local headers = get_headers({})
        header_transformer.transform_headers(conf, headers)
        assert.same({"v2"}, headers["h1"])
      end)
      it("header if the header already exist", function()
        local headers = get_headers({ h1 = "v1" })
        header_transformer.transform_headers(conf, headers)
        assert.same({h1 = {"v1", "v2"}}, headers)
      end)
      it("sets content-length nil", function()
        local headers = get_headers({ h1 = "v1", [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
        header_transformer.transform_headers(conf, headers)
        assert.is_nil(headers[CONTENT_LENGTH])
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
        }
      }
      it("transforms all headers", function()
        local headers = get_headers({ h1 = "v1", h2 = "v2" })
        header_transformer.transform_headers(conf, headers)
        assert.same({h2 = "v3", h3 = {"v3", "v4"}}, headers)
      end)
      it("sets content-length nil", function()
        local headers = get_headers({ h1 = "v1", [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
        header_transformer.transform_headers(conf, headers)
        assert.is_nil(headers[CONTENT_LENGTH])
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
          }
        }
        it("sets content-length nil if application/json passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("sets content-length nil if application/json and charset passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON_UTF8 })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = FORM })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.remove.json = {}
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
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
          }
        }
        it("sets content-length nil if application/json passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("sets content-length nil if application/json and charset passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON_UTF8 })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = FORM })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.replace.json = {}
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
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
          }
        }
        it("set content-length nil if application/json passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("set content-length nil if application/json and charset passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON_UTF8 })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = FORM })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.add.json = {}
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
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
          }
        }
        it("set content-length nil if application/json passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("set content-length nil if application/json and charset passed", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON_UTF8 })
          header_transformer.transform_headers(conf, headers)
          assert.is_nil(headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if content-type not json", function()
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = FORM })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
        end)
        it("does not set content-length nil if any of json not set", function()
          conf.append.json = {}
          local headers = get_headers({ [CONTENT_LENGTH] = "100", [CONTENT_TYPE] = JSON })
          header_transformer.transform_headers(conf, headers)
          assert.equals('100', headers[CONTENT_LENGTH])
        end)
      end)
    end)
  end)
end)
