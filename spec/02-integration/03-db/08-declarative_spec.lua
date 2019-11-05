local declarative = require "kong.db.declarative"
local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local lyaml = require "lyaml"

for _, strategy in helpers.each_strategy() do
  describe("declarative config #" .. strategy, function()
    local db
    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy)
      _G.kong.db = db
      assert(helpers.start_kong({
        database   = strategy,
      }))
    end)

    lazy_teardown(function()
      assert(helpers.stop_kong())
    end)

    local service_def = {
      _tags = ngx.null,
      connect_timeout = 60000,
      created_at = 1549025889,
      host = "example.com",
      id = "3b9c2302-a610-4925-a7b9-25942309335d",
      name = "foo",
      path = ngx.null,
      port = 80,
      protocol = "https",
      read_timeout = 60000,
      retries = 5,
      updated_at = 1549025889,
      write_timeout = 60000,
      tags = { "potato", "carrot" },
    }

    local route_def = {
      _tags = ngx.null,
      created_at = 1549025889,
      id = "eb88ccb8-274d-4e7e-b4cb-0d673a4fa93b",
      name = "bar",
      protocols = { "http", "https" },
      methods = ngx.null,
      hosts = { "example.com" },
      paths = ngx.null,
      regex_priority = 0,
      strip_path = true,
      preserve_host = false,
      snis = ngx.null,
      sources = ngx.null,
      destinations = ngx.null,
      service = { id = service_def.id },
    }

    local certificate_def = {
      _tags = ngx.null,
      created_at = 1541088353,
      id = "f6c12564-47c8-48b4-b171-0a0d9dbf7cb0",
      cert  = ssl_fixtures.cert,
      key   = ssl_fixtures.key,
    }

    local sni_def = {
      _tags = ngx.null,
      created_at = 1549689381,
      id = "ae54d23c-9977-4022-8536-8ceac8c0d0f0",
      name = "baz",
      certificate = { id = certificate_def.id },
    }

    local consumer_def = {
      _tags = ngx.null,
      created_at = 1549476023,
      id = "ad06b77c-0d2f-407a-8d6d-07f272a92d6a",
      username = "andru",
      custom_id = "donalds",
    }

    local plugin_def = {
      _tags = ngx.null,
      created_at = 1547047308,
      id = "389ad9bd-b158-4e19-aed7-c9b040f7f312",
      service = { id = service_def.id },
      enabled = true,
      name = "acl",
      config = {
        whitelist = { "*" },
        hide_groups_header = false,
      }
    }

    local acl_def = {
      _tags = ngx.null,
      created_at = 154796740,
      id = "21698f76-e00b-4017-96e5-cc5ece1508a5",
      consumer = { id = consumer_def.id },
      group = "The A Team"
    }
    before_each(function()
      db.acls:truncate()
      db.plugins:truncate()
      db.routes:truncate()
      db.services:truncate()
      db.snis:truncate()
      db.certificates:truncate()
      db.consumers:truncate()

      assert(declarative.load_into_db({
        snis = { [sni_def.id] = sni_def },
        certificates = { [certificate_def.id] = certificate_def },
        routes = { [route_def.id] = route_def },
        services = { [service_def.id] = service_def },
        consumers = { [consumer_def.id] = consumer_def },
        plugins = { [plugin_def.id] = plugin_def },
        acls = { [acl_def.id] = acl_def  },
      }))
    end)

    describe("load_into_db", function()
      it("imports base and custom entities with associations", function()
        local sni = assert(db.snis:select_by_name("baz"))
        assert.equals(sni_def.id, sni.id)
        assert.equals(certificate_def.id, sni.certificate.id)

        local cert = assert(db.certificates:select({ id = certificate_def.id }))
        assert.equals(certificate_def.id, cert.id)
        assert.same(ssl_fixtures.key, cert.key)
        assert.same(ssl_fixtures.cert, cert.cert)

        local service = assert(db.services:select_by_name("foo"))
        assert.equals(service_def.id, service.id)
        assert.equals("example.com", service.host)
        assert.equals("https", service.protocol)

        local route = assert(db.routes:select_by_name("bar"))
        assert.equals(route_def.id, route.id)
        assert.equals("example.com", route.hosts[1])
        assert.same({ "http", "https" }, route.protocols)
        assert.equals(service_def.id, route.service.id)

        local consumer = assert(db.consumers:select_by_username("andru"))
        assert.equals(consumer_def.id, consumer.id)
        assert.equals("andru", consumer_def.username)
        assert.equals("donalds", consumer_def.custom_id)

        local plugin = assert(db.plugins:select({ id = plugin_def.id }))
        assert.equals(plugin_def.id, plugin.id)
        assert.equals(service.id, plugin.service.id)
        assert.equals("acl", plugin.name)
        assert.same(plugin_def.config, plugin.config)

        local acl = assert(db.acls:select({ id = acl_def.id }))
        assert.equals(consumer_def.id, acl.consumer.id)
        assert.equals("The A Team", acl.group)
      end)
    end)

    describe("export_from_db", function()
      it("exports base and custom entities with associations", function()

        -- Add a basicauth_credential to make sure it is not exported
        db.basicauth_credentials:insert({
          username = "some_username",
          password = "secret",
          consumer = { id = consumer_def.id },
        })

        local fake_file = {
          buffer = {},
          write = function(self, str)
            self.buffer[#self.buffer + 1] = str
          end,
        }

        assert(declarative.export_from_db(fake_file))

        local exported_str = table.concat(fake_file.buffer)
        local yaml = lyaml.load(exported_str)

        -- ensure tags & basicauth_credentials are not being exported
        local toplevel_keys = {}
        for k in pairs(yaml) do
          toplevel_keys[#toplevel_keys + 1] = k
        end
        table.sort(toplevel_keys)
        assert.same({
          "_format_version",
          "acls",
          "certificates",
          "consumers",
          "plugins",
          "routes",
          "services",
          "snis"
        }, toplevel_keys)

        assert.equals("1.1", yaml._format_version)

        assert.equals(1, #yaml.snis)
        local sni = assert(yaml.snis[1])
        assert.equals(sni_def.id, sni.id)
        assert.equals(sni_def.name, sni.name)
        assert.equals(certificate_def.id, sni.certificate)

        assert.equals(1, #yaml.certificates)
        local cert = assert(yaml.certificates[1])
        assert.equals(certificate_def.id, cert.id)
        assert.equals(ssl_fixtures.key, cert.key)
        assert.equals(ssl_fixtures.cert, cert.cert)

        assert.equals(1, #yaml.services)
        local service = assert(yaml.services[1])
        assert.equals(service_def.id, service.id)
        assert.equals("example.com", service.host)
        assert.equals("https", service.protocol)
        table.sort(service.tags)
        assert.same({"carrot", "potato"}, service.tags)

        assert.equals(1, #yaml.routes)
        local route = assert(yaml.routes[1])
        assert.equals(route_def.id, route.id)
        assert.equals("example.com", route.hosts[1])
        assert.same({ "http", "https" }, route.protocols)
        assert.equals(service_def.id, route.service)

        assert.equals(1, #yaml.consumers)
        local consumer = assert(yaml.consumers[1])
        assert.equals(consumer_def.id, consumer.id)
        assert.equals("andru", consumer_def.username)
        assert.equals("donalds", consumer_def.custom_id)

        assert.equals(1, #yaml.plugins)
        local plugin = assert(yaml.plugins[1])
        assert.equals(plugin_def.id, plugin.id)
        assert.equals(service.id, plugin.service)
        assert.equals("acl", plugin.name)
        assert.same(plugin_def.config, plugin.config)

        assert.equals(1, #yaml.acls)
        local acl = assert(yaml.acls[1])
        assert.equals(consumer_def.id, acl.consumer)
        assert.equals("The A Team", acl.group)
      end)
    end)
  end)
end


