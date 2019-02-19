local declarative = require "kong.db.declarative"
local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"

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
      write_timeout = 60000
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
      run_on = "first",
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

    describe("load_into_db", function()
      it("imports base and custom entities with associations", function()
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
  end)
end


