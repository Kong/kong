local declarative_config = require "kong.db.schema.others.declarative_config"
local helpers = require "spec.helpers"
local lyaml = require "lyaml"


assert:set_parameter("TableFormatLevel", 10)


describe("declarative config: process_auto_fields", function()
  local DeclarativeConfig

  lazy_setup(function()
    DeclarativeConfig = assert(declarative_config.load(helpers.test_conf.loaded_plugins))
  end)

  describe("core entities", function()
    describe("services:", function()
      it("accepts an empty list", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          services:
        ]])
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          services = {}
        }, config)
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
            host: example.com
            protocol: https
            enabled: true
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
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          services = {
            {
              name = "foo",
              protocol = "https",
              host = "example.com",
              port = 80,
              connect_timeout = 60000,
              read_timeout = 60000,
              write_timeout = 60000,
              retries = 5,
              enabled = true,
              _comment = "my comment",
              _ignore = { { foo = "bar" } },
            },
            {
              name = "bar",
              protocol = "http",
              host = "example.test",
              port = 3000,
              connect_timeout = 60000,
              read_timeout = 60000,
              write_timeout = 60000,
              retries = 5,
              enabled = true,
              _comment = "my comment",
              _ignore = { { foo = "bar" } },
            }
          }
        }, config)
      end)

      it("allows url shorthand", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
            # url shorthand also works, and expands into multiple fields
            url: https://example.com:8000/hello/world
        ]])
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          services = {
            {
              name = "foo",
              protocol = "https",
              host = "example.com",
              port = 8000,
              path = "/hello/world",
              connect_timeout = 60000,
              read_timeout = 60000,
              write_timeout = 60000,
              retries = 5,
              enabled = true,
            }
          }
        }, config)
      end)
    end)

    describe("plugins:", function()
      it("accepts an empty list", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          plugins:
        ]])
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          plugins = {}
        }, config)
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
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          plugins = {
            {
              _comment = "my comment",
              _ignore = { { foo = "bar" } },
              name = "key-auth",
              enabled = true,
              protocols = { "grpc", "grpcs", "http", "https" },
              config = {
                hide_credentials = false,
                key_in_header = true,
                key_in_query = true,
                key_in_body = false,
                key_names = { "apikey" },
                run_on_preflight = true,
              }
            },
            {
              _comment = "my comment",
              _ignore = { { foo = "bar" } },
              name = "http-log",
              enabled = true,
              protocols = { "grpc", "grpcs", "http", "https" },
              config = {
                http_endpoint = "https://example.com",
                content_type = "application/json",
                flush_timeout = 2,
                keepalive = 60000,
                method = "POST",
                queue_size = 1,
                retry_count = 10,
                timeout = 10000,
                queue = {
                  batch_max_size = 1,
                  capacity = 10000,
                  max_delay = 1,
                  max_idle_time = 60,
                  max_retry_delay = 60,
                  max_retry_time = 60,
                  poll_time = 1,
                },
              }
            },
          }
        }, config)
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
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          plugins = {
            {
              route = "foo",
              name = "key-auth",
              enabled = true,
              protocols = { "grpc", "grpcs", "http", "https" },
              config = {
                hide_credentials = false,
                key_in_header = true,
                key_in_query = true,
                key_in_body = false,
                key_names = { "apikey" },
                run_on_preflight = true,
              }
            },
            {
              service = "svc1",
              consumer = "my-consumer",
              name = "http-log",
              enabled = true,
              protocols = { "grpc", "grpcs", "http", "https" },
              config = {
                http_endpoint = "https://example.com",
                content_type = "application/json",
                flush_timeout = 2,
                keepalive = 60000,
                method = "POST",
                queue_size = 1,
                retry_count = 10,
                timeout = 10000,
                queue = {
                  batch_max_size = 1,
                  capacity = 10000,
                  max_delay = 1,
                  max_idle_time = 60,
                  max_retry_delay = 60,
                  max_retry_time = 60,
                  poll_time = 1,
                },
              }
            },
          }
        }, config)
      end)
    end)

    describe("nested relationships:", function()
      describe("plugins in services", function()
        it("accepts an empty list", function()
          local config = lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              plugins: []
              host: example.com
          ]])
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            services = {
              {
                name = "foo",
                protocol = "http",
                host = "example.com",
                port = 80,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                plugins = {},
                enabled = true,
              }
            }
          }, config)
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
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            services = {
              {
                name = "foo",
                protocol = "https",
                host = "example.com",
                port = 80,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                _comment = "my comment",
                _ignore = { { foo = "bar" } },
                plugins = {
                  {
                    _comment = "my comment",
                    _ignore = { { foo = "bar" } },
                    name = "key-auth",
                    enabled = true,
                    protocols = { "grpc", "grpcs", "http", "https" },
                    config = {
                      hide_credentials = false,
                      key_in_header = true,
                      key_in_query = true,
                      key_in_body = false,
                      key_names = { "apikey" },
                      run_on_preflight = true,
                    }
                  },
                  {
                    name = "http-log",
                    enabled = true,
                    protocols = { "grpc", "grpcs", "http", "https" },
                    config = {
                      http_endpoint = "https://example.com",
                      content_type = "application/json",
                      flush_timeout = 2,
                      keepalive = 60000,
                      method = "POST",
                      queue_size = 1,
                      retry_count = 10,
                      timeout = 10000,
                      queue = {
                        batch_max_size = 1,
                        capacity = 10000,
                        max_delay = 1,
                        max_idle_time = 60,
                        max_retry_delay = 60,
                        max_retry_time = 60,
                        poll_time = 1,
                      },
                    }
                  },
                }
              },
              {
                name = "bar",
                protocol = "http",
                host = "example.test",
                port = 3000,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                plugins = {
                  {
                    name = "basic-auth",
                    enabled = true,
                    protocols = { "grpc", "grpcs", "http", "https" },
                    config = {
                      hide_credentials = false,
                    }
                  },
                  {
                    name = "tcp-log",
                    enabled = true,
                    protocols = { "grpc", "grpcs", "http", "https" },
                    config = {
                      host = "127.0.0.1",
                      port = 10000,
                      keepalive = 60000,
                      timeout = 10000,
                      tls = false,
                    }
                  },
                }
              }
            }
          }, config)
        end)
      end)

      describe("routes in services", function()
        it("accepts an empty list", function()
          local config = lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              routes: []
              host: example.com
          ]])
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            services = {
              {
                name = "foo",
                protocol = "http",
                host = "example.com",
                port = 80,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                routes = {}
              }
            }
          }, config)
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
                - path_handling: v1
                  paths:
                  - /path
                - path_handling: v1
                  hosts:
                  - example.com
                - path_handling: v1
                  methods: ["GET", "POST"]
            - name: bar
              host: example.test
              port: 3000
              routes:
                - path_handling: v1
                  paths:
                  - /path
                  hosts:
                  - example.com
                  methods: ["GET", "POST"]
          ]]))
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            services = {
              {
                name = "foo",
                protocol = "https",
                host = "example.com",
                port = 80,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                routes = {
                  {
                    paths = { "/path" },
                    preserve_host = false,
                    regex_priority = 0,
                    strip_path = true,
                    path_handling = "v1",
                    protocols = { "http", "https" },
                    https_redirect_status_code = 426,
                    request_buffering = true,
                    response_buffering = true,
                  },
                  {
                    hosts = { "example.com" },
                    preserve_host = false,
                    regex_priority = 0,
                    strip_path = true,
                    path_handling = "v1",
                    protocols = { "http", "https" },
                    https_redirect_status_code = 426,
                    request_buffering = true,
                    response_buffering = true,
                  },
                  {
                    methods = { "GET", "POST" },
                    preserve_host = false,
                    regex_priority = 0,
                    strip_path = true,
                    path_handling = "v1",
                    protocols = { "http", "https" },
                    https_redirect_status_code = 426,
                    request_buffering = true,
                    response_buffering = true,
                  },
                }
              },
              {
                name = "bar",
                protocol = "http",
                host = "example.test",
                port = 3000,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                routes = {
                  {
                    paths = { "/path" },
                    hosts = { "example.com" },
                    methods = { "GET", "POST" },
                    preserve_host = false,
                    regex_priority = 0,
                    strip_path = true,
                    path_handling = "v1",
                    protocols = { "http", "https" },
                    https_redirect_status_code = 426,
                    request_buffering = true,
                    response_buffering = true,
                  },
                }
              }
            }
          }, config)
        end)
      end)

      describe("plugins in routes in services", function()
        it("accepts an empty list", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
              - name: foo
                path_handling: v1
                methods: ["GET"]
                plugins:
          ]]))
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            services = {
              {
                name = "foo",
                protocol = "https",
                host = "example.com",
                port = 80,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                routes = {
                  {
                    name = "foo",
                    methods = { "GET" },
                    preserve_host = false,
                    strip_path = true,
                    path_handling = "v1",
                    protocols = { "http", "https" },
                    regex_priority = 0,
                    https_redirect_status_code = 426,
                    request_buffering = true,
                    response_buffering = true,
                    plugins = {},
                  }
                }
              }
            }
          }, config)
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
                path_handling: v1
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
                path_handling: v1
                paths:
                - /
                plugins:
                - name: basic-auth
                - name: tcp-log
                  config:
                    host: 127.0.0.1
                    port: 10000
          ]]))
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            services = {
              {
                name = "foo",
                protocol = "https",
                host = "example.com",
                port = 80,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                routes = {
                  {
                    name = "foo",
                    methods = { "GET" },
                    preserve_host = false,
                    strip_path = true,
                    path_handling = "v1",
                    protocols = { "http", "https" },
                    regex_priority = 0,
                    https_redirect_status_code = 426,
                    request_buffering = true,
                    response_buffering = true,
                    plugins = {
                      {
                        name = "key-auth",
                        enabled = true,
                        protocols = { "grpc", "grpcs", "http", "https" },
                        config = {
                          hide_credentials = false,
                          key_in_header = true,
                          key_in_query = true,
                          key_in_body = false,
                          key_names = { "apikey" },
                          run_on_preflight = true,
                        }
                      },
                      {
                        name = "http-log",
                        enabled = true,
                        protocols = { "grpc", "grpcs", "http", "https" },
                        config = {
                          http_endpoint = "https://example.com",
                          content_type = "application/json",
                          flush_timeout = 2,
                          keepalive = 60000,
                          method = "POST",
                          queue_size = 1,
                          retry_count = 10,
                          timeout = 10000,
                          queue = {
                            batch_max_size = 1,
                            capacity = 10000,
                            max_delay = 1,
                            max_idle_time = 60,
                            max_retry_delay = 60,
                            max_retry_time = 60,
                            poll_time = 1,
                          },
                        }
                      }
                    }
                  }
                }
              },
              {
                name = "bar",
                protocol = "http",
                host = "example.test",
                port = 3000,
                connect_timeout = 60000,
                read_timeout = 60000,
                write_timeout = 60000,
                retries = 5,
                enabled = true,
                routes = {
                  {
                    name = "bar",
                    paths = { "/" },
                    preserve_host = false,
                    strip_path = true,
                    path_handling = "v1",
                    protocols = { "http", "https" },
                    regex_priority = 0,
                    https_redirect_status_code = 426,
                    request_buffering = true,
                    response_buffering = true,
                    plugins = {
                      {
                        name = "basic-auth",
                        enabled = true,
                        protocols = { "grpc", "grpcs", "http", "https" },
                        config = {
                          hide_credentials = false,
                        }
                      },
                      {
                        name = "tcp-log",
                        enabled = true,
                        protocols = { "grpc", "grpcs", "http", "https" },
                        config = {
                          host = "127.0.0.1",
                          port = 10000,
                          keepalive = 60000,
                          timeout = 10000,
                          tls = false,
                        }
                      }
                    }
                  }
                }
              }
            }
          }, config)
        end)
      end)
    end)
  end)

  describe("custom entities", function()
    describe("oauth2_credentials:", function()
      it("accepts an empty list", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
        ]]))
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          oauth2_credentials = {}
        }, config)
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
          - name: my-credential
            redirect_uris:
            - https://example.com
          - name: another-credential
            consumer: foo
            redirect_uris:
            - https://example.test
        ]]))
        config = DeclarativeConfig:process_auto_fields(config, "select", false)
        assert.same({
          _format_version = "1.1",
          _transform = true,
          oauth2_credentials = {
            {
              client_type = "confidential",
              name = "my-credential",
              redirect_uris = { "https://example.com" },
              hash_secret = false,
            },
            {
              client_type = "confidential",
              name = "another-credential",
              consumer = "foo",
              redirect_uris = { "https://example.test" },
              hash_secret = false,
            },
          }
        }, config)
      end)
    end)

    describe("nested relationships:", function()
      describe("oauth2_credentials in consumers", function()
        it("accepts an empty list", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
              oauth2_credentials:
          ]]))
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            consumers = {
              {
                username = "bob",
                oauth2_credentials = {},
              }
            }
          }, config)
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
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            consumers = {
              {
                username = "bob",
                oauth2_credentials = {
                  {
                    client_type = "confidential",
                    name = "my-credential",
                    redirect_uris = { "https://example.com" },
                    hash_secret = false,
                  },
                  {
                    client_type = "confidential",
                    name = "another-credential",
                    redirect_uris = { "https://example.test" },
                    hash_secret = false,
                  },
                }
              }
            }
          }, config)
        end)
      end)

      describe("oauth2_tokens in oauth2_credentials", function()
        it("accepts an empty list", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            oauth2_credentials:
            - name: my-credential
              redirect_uris:
              - https://example.com
              oauth2_tokens:
          ]]))
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            oauth2_credentials = {
              {
                client_type = "confidential",
                name = "my-credential",
                redirect_uris = { "https://example.com" },
                oauth2_tokens = {},
                hash_secret = false,
              },
            }
          }, config)
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            oauth2_credentials:
            - name: my-credential
              redirect_uris:
              - https://example.com
              oauth2_tokens:
              - expires_in: 1
              - expires_in: 10
                scope: "foo"
          ]]))
          config = DeclarativeConfig:process_auto_fields(config, "select", false)
          assert.same({
            _format_version = "1.1",
            _transform = true,
            oauth2_credentials = {
              {
                client_type = "confidential",
                name = "my-credential",
                redirect_uris = { "https://example.com" },
                hash_secret = false,
                oauth2_tokens = {
                  {
                    expires_in = 1,
                    token_type = "bearer",
                  },
                  {
                    expires_in = 10,
                    token_type = "bearer",
                    scope = "foo",
                  }
                }
              },
            }
          }, config)
        end)

      end)
    end)
  end)

end)
