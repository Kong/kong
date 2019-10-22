local declarative_config = require "kong.db.schema.others.declarative_config"
local MetaSchema = require "kong.db.schema.metaschema"
local helpers = require "spec.helpers"
local lyaml = require "lyaml"


assert:set_parameter("TableFormatLevel", 10)


describe("declarative config: validate", function()
  local DeclarativeConfig
  local DeclarativeConfig_def

  lazy_setup(function()
    local _
    DeclarativeConfig, _, DeclarativeConfig_def = assert(declarative_config.load(helpers.test_conf.loaded_plugins))
  end)

  pending("metaschema", function()
    it("is a valid schema definition", function()
      -- almost valid!... this fails because we abuse the "any" type for the _ignore field
      -- and because _with_tags is nested
      assert(MetaSchema:validate(DeclarativeConfig_def))
    end)
  end)

  describe("_format_version", function()
    it("requires version 1.1", function()

      local ok, err = DeclarativeConfig:validate(lyaml.load([[
        _format_version: 1.1
      ]]))
      assert.falsy(ok)
      assert.same({
        ["_format_version"] = "expected a string"
      }, err)

      ok, err = DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.2"
      ]]))
      assert.falsy(ok)
      assert.same({
        ["_format_version"] = "value must be 1.1"
      }, err)

      assert(DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
      ]])))
    end)
  end)

  describe("_comment", function()
    it("accepts a string", function()

      local ok, err = DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _comment: 1234
      ]]))
      assert.falsy(ok)
      assert.same({
        ["_comment"] = "expected a string"
      }, err)

      assert(DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _comment: "1234" # this is how yaml works!
      ]])))

      ok, err = DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _comment:
          foo: bar
      ]]))
      assert.falsy(ok)
      assert.same({
        ["_comment"] = "expected a string"
      }, err)

      assert(DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _comment: I am a happy comment!
      ]])))
    end)
  end)

  describe("_ignore", function()
    it("accepts an array of anything", function()

      local ok, err = DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _ignore: 1234
      ]]))
      assert.falsy(ok)
      assert.same({
        ["_ignore"] = "expected an array"
      }, err)

      assert(DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _ignore:
        - 1234
      ]])))

      ok, err = DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _ignore:
          foo: bar
          bla: 123
      ]]))
      assert.falsy(ok)
      assert.same({
        ["_ignore"] = "expected an array"
      }, err)

      assert(DeclarativeConfig:validate(lyaml.load([[
        _format_version: "1.1"
        _ignore:
        - foo: bar
          bla: 123
        - "Hello, world"
        - 1234
      ]])))
    end)
  end)

  describe("core entities", function()
    describe("services:", function()
      it("accepts an empty list", function()
        assert(DeclarativeConfig:validate(lyaml.load([[
          _format_version: "1.1"
          services:
        ]])))
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
            host: example.com
            protocol: https
            _comment: my comment
            _ignore:
            - foo: bar
          - name: bar
            host: example.test
            port: 3000
            _comment: my comment
            _ignore:
            - foo: bar
        ]]))
        assert(DeclarativeConfig:validate(config))
      end)

      it("verifies required fields", function()
        local ok, err = DeclarativeConfig:validate(lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
        ]]))
        assert.falsy(ok)
        assert.same({
          ["services"] = {
            {
              ["host"] = "required field missing"
            }
          }
        }, err)
      end)

      it("performs regular validations", function()
        local ok, err = DeclarativeConfig:validate(lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
            retries: -1
            protocol: foo
            host: 1234
            port: 99999
            path: /foo//bar/
        ]]))
        assert.falsy(ok)
        assert.same({
          ["services"] = {
            {
              ["host"] = "expected a string",
              ["path"] = "must not have empty segments",
              ["port"] = "value should be between 0 and 65535",
              ["protocol"] = "expected one of: grpc, grpcs, http, https, tcp, tls",
              ["retries"] = "value should be between 0 and 32767",
            }
          }
        }, err)
      end)

      it("allows url shorthand", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
            # url shorthand also works, and expands into multiple fields
            url: https://example.com:8000/hello/world
        ]])

        assert(DeclarativeConfig:validate(config))
      end)
    end)

    describe("plugins:", function()
      it("accepts an empty list", function()
        assert(DeclarativeConfig:validate(lyaml.load([[
          _format_version: "1.1"
          plugins:
        ]])))
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          plugins:
            - name: key-auth
              _comment: my comment
              _ignore:
              - foo: bar
            - name: http-log
              config:
                http_endpoint: https://example.com
              _comment: my comment
              _ignore:
              - foo: bar
        ]]))
        assert(DeclarativeConfig:validate(config))
      end)

      it("allows foreign relationships as strings", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          plugins:
            - name: key-auth
              route: foo
            - name: http-log
              service: svc1
              consumer: my-consumer
              config:
                http_endpoint: https://example.com
        ]])

        assert(DeclarativeConfig:validate(config))
      end)
    end)

    describe("nested relationships:", function()
      describe("plugins in services", function()
        it("accepts an empty list", function()
          assert(DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              plugins: []
              host: example.com
          ]])))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              _comment: my comment
              _ignore:
              - foo: bar
              plugins:
                - name: key-auth
                  _comment: my comment
                  _ignore:
                  - foo: bar
                - name: http-log
                  config:
                    http_endpoint: https://example.com
            - name: bar
              host: example.test
              port: 3000
              plugins:
              - name: basic-auth
              - name: tcp-log
                config:
                  host: 127.0.0.1
                  port: 10000
          ]]))
          assert(DeclarativeConfig:validate(config))
        end)

        it("verifies required fields", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              plugins:
              - enabled: true
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["plugins"] = {
                  {
                    ["name"] = "required field missing"
                  }
                }
              }
            }
          }, err)
        end)

        it("performs regular validations", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              plugins:
              - name: foo
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["plugins"] = {
                  {
                    ["name"] = "plugin 'foo' not enabled; add it to the 'plugins' configuration property"
                  }
                }
              }
            }
          }, err)
        end)

        it("does not accept additional foreign keys", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              plugins:
              - name: key-auth
                consumer: foo
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["plugins"] = {
                  {
                    ["consumer"] = "value must be null"
                  }
                }
              }
            }
          }, err)
        end)
      end)

      describe("routes in services", function()
        it("accepts an empty list", function()
          assert(DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              routes: []
              host: example.com
          ]])))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
                - paths:
                  - /path
                - hosts:
                  - example.com
                - methods: ["GET", "POST"]
            - name: bar
              host: example.test
              port: 3000
              routes:
                - paths:
                  - /path
                  hosts:
                  - example.com
                  methods: ["GET", "POST"]
          ]]))
          assert(DeclarativeConfig:validate(config))
        end)

        it("verifies required fields", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              routes:
              - preserve_host: true
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["routes"] = {
                  {
                    ["@entity"] = {
                      "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https'",
                    }
                  }
                }
              }
            }
          }, err)
        end)

        it("performs regular validations", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              routes:
              - name: foo
                paths:
                - bla
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["routes"] = {
                  {
                    ["paths"] = {
                      "should start with: /"
                    }
                  }
                }
              }
            }
          }, err)
        end)
      end)

      describe("plugins in routes in services", function()
        it("accepts an empty list", function()
          assert(DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              routes:
              - name: foo
                methods: ["GET"]
                plugins: []
          ]])))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
              - name: foo
                methods: ["GET"]
                plugins:
                  - name: key-auth
                  - name: http-log
                    config:
                      http_endpoint: https://example.com
            - name: bar
              host: example.test
              port: 3000
              routes:
              - name: bar
                paths:
                - /
                plugins:
                - name: basic-auth
                - name: tcp-log
                  config:
                    host: 127.0.0.1
                    port: 10000
          ]]))
          assert(DeclarativeConfig:validate(config))
        end)

        it("verifies required fields", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              routes:
              - paths:
                - /
                plugins:
                - enabled: true
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["routes"] = {
                  {
                    ["plugins"] = {
                      {
                        ["name"] = "required field missing"
                      }
                    }
                  }
                }
              }
            }
          }, err)
        end)

        it("performs regular validations", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              routes:
              - paths:
                - /
                plugins:
                - name: foo
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["routes"] = {
                  {
                    ["plugins"] = {
                      {
                        ["name"] = "plugin 'foo' not enabled; add it to the 'plugins' configuration property"
                      }
                    }
                  }
                }
              }
            }
          }, err)
        end)

        it("does not accept additional foreign keys", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              url: https://example.com
              routes:
              - paths:
                - /
                plugins:
                - name: key-auth
                  route: foo
          ]]))
          assert.falsy(ok)
          assert.same({
            ["services"] = {
              {
                ["routes"] = {
                  {
                    ["plugins"] = {
                      {
                        ["route"] = "value must be null"
                      }
                    }
                  }
                }
              }
            }
          }, err)
        end)
      end)

    end)
  end)

  describe("custom entities", function()
    describe("oauth2_credentials:", function()
      it("accepts an empty list", function()
        assert(DeclarativeConfig:validate(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
        ]])))
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
          - name: my-credential
            consumer: foo
            redirect_uris:
            - https://example.com
          - name: another-credential
            consumer: foo
            redirect_uris:
            - https://example.test
        ]]))

        assert(DeclarativeConfig:validate(config))
      end)

      it("verifies required fields", function()
        local ok, err = DeclarativeConfig:validate(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
          - consumer: foo
        ]]))
        assert.falsy(ok)
        assert.same({
          ["oauth2_credentials"] = {
            {
              ["name"] = "required field missing",
            }
          }
        }, err)
      end)

      it("performs regular validations", function()
        local ok, err = DeclarativeConfig:validate(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
          - name: my-credential
            redirect_uris:
            - https://example.com
            - foobar
          - name: my-credential
            consumer: 1234
            redirect_uris:
            - foobar
            - https://example.com
        ]]))
        assert.falsy(ok)
        assert.same({
          ["oauth2_credentials"] = {
            {
              ["consumer"] = "required field missing",
              ["redirect_uris"] = {
                [2] = "cannot parse 'foobar'",
              }
            },
            {
              ["consumer"] = "expected a string",
              ["redirect_uris"] = {
                [1] = "cannot parse 'foobar'",
              }
            }
          }
        }, err)
      end)
    end)

    describe("nested relationships:", function()
      describe("oauth2_credentials in consumers", function()
        it("accepts an empty list", function()
          assert(DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
              oauth2_credentials:
          ]])))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
              oauth2_credentials:
              - name: my-credential
                redirect_uris:
                - https://example.com
              - name: another-credential
                redirect_uris:
                - https://example.test
          ]]))

          assert(DeclarativeConfig:validate(config))
        end)

        it("performs regular validations", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
              oauth2_credentials:
              - name: my-credential
                redirect_uris:
                - https://example.com
                - foobar
              - name: my-credential
                redirect_uris:
                - foobar
                - https://example.com
          ]]))
          assert.falsy(ok)
          assert.same({
            ["consumers"] = {
              {
                ["oauth2_credentials"] = {
                  {
                    ["redirect_uris"] = {
                      [2] = "cannot parse 'foobar'",
                    }
                  },
                  {
                    ["redirect_uris"] = {
                      [1] = "cannot parse 'foobar'",
                    }
                  }
                }
              }
            }
          }, err)
        end)

        it("does not accept foreign fields", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
              oauth2_credentials:
              - name: hello
                redirect_uris:
                - https://example.com
                consumer: foo
          ]]))
          assert.falsy(ok)
          assert.same({
            ["consumers"] = {
              {
                ["oauth2_credentials"] = {
                  {
                    ["consumer"] = "value must be null",
                  }
                }
              }
            }
          }, err)
        end)

      end)

      describe("oauth2_tokens in oauth2_credentials", function()
        it("accepts an empty list", function()
          assert(DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            oauth2_credentials:
            - name: my-credential
              consumer: bob
              redirect_uris:
              - https://example.com
              oauth2_tokens:
          ]])))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            oauth2_credentials:
            - name: my-credential
              consumer: bob
              redirect_uris:
              - https://example.com
              oauth2_tokens:
              - expires_in: 1
              - expires_in: 10
                scope: "foo"
          ]]))

          assert(DeclarativeConfig:validate(config))
        end)

        it("verifies required fields", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            oauth2_credentials:
            - name: my-credential
              redirect_uris:
              - https://example.com
              oauth2_tokens:
              - scope: "foo"
          ]]))
          assert.falsy(ok)
          assert.same({
            ["oauth2_credentials"] = {
              {
                ["consumer"] = "required field missing",
                ["oauth2_tokens"] = {
                  {
                    ["expires_in"] = "required field missing",
                  }
                }
              }
            }
          }, err)
        end)

        it("does not accept foreign fields", function()
          local ok, err = DeclarativeConfig:validate(lyaml.load([[
            _format_version: "1.1"
            oauth2_credentials:
            - name: my-credential
              consumer: bob
              redirect_uris:
              - https://example.com
              oauth2_tokens:
              - expires_in: 1
                service: svc1
          ]]))
          assert.falsy(ok)
          assert.same({
            ["oauth2_credentials"] = {
              {
                ["oauth2_tokens"] = {
                  {
                    ["service"] = "value must be null",
                  }
                }
              }
            }
          }, err)
        end)

      end)

    end)
  end)
end)
