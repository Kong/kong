local DB = require "kong.db"
local helpers = require "spec.helpers"
local Blueprints = require "spec.fixtures.blueprints"


local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


for _, strategy in helpers.each_strategy() do
  describe(string.format("blueprints db [#%s]", strategy), function()

    local bp
    lazy_setup(function()
      local db = assert(DB.new(helpers.test_conf, strategy))
      assert(db:init_connector())
      assert(db.plugins:load_plugin_schemas(helpers.test_conf.loaded_plugins))
      assert(db:truncate())
      bp = assert(Blueprints.new(db))
    end)

    local service

    it("inserts services", function()
      local s = bp.services:insert()
      assert.matches(UUID_PATTERN, s.id)
      assert.equal("http", s.protocol)
      assert.equal("number", type(s.created_at))
      assert.equal("number", type(s.updated_at))

      local s2 = bp.services:insert({ protocol = "https" })
      assert.matches(UUID_PATTERN, s2.id)
      assert.equal("https", s2.protocol)
      assert.equal("number", type(s2.created_at))
      assert.equal("number", type(s2.updated_at))

      service = s
    end)

    it("inserts routes", function()
      if not service then
        assert.fail("could not run: missing Service from previous test")
      end

      local r = bp.routes:insert({
        methods = { "GET" },
        hosts   = { "example.com" },
      })
      assert.matches(UUID_PATTERN, r.id)
      assert.same({ "http", "https" }, r.protocols)
      assert.same({ "GET" }, r.methods)
      assert.equal("number", type(r.created_at))
      assert.equal("number", type(r.updated_at))
      assert.equal(0, r.regex_priority)
      assert.not_nil(r.service) -- automatically inserted by blueprint as well

      local r2 = bp.routes:insert({
        protocols = { "http" },
        methods   = { "GET" },
        regex_priority  = 200,
        service   = service,
      })
      assert.matches(UUID_PATTERN, r2.id)
      assert.same({ "http" }, r2.protocols)
      assert.same({ "GET" }, r2.methods)
      assert.equal("number", type(r.created_at))
      assert.equal("number", type(r.updated_at))
      assert.equal(200, r2.regex_priority)
    end)
  end)
end

for _, strategy in helpers.each_strategy() do
  local bp, db

  lazy_setup(function()
    db = assert(DB.new(helpers.test_conf, strategy))
    assert(db:init_connector())
    assert(db.plugins:load_plugin_schemas(helpers.test_conf.loaded_plugins))
    bp  = assert(Blueprints.new(db))
  end)

  lazy_teardown(function()
    ngx.shared.kong_cassandra:flush_expired()
  end)

  describe(string.format("blueprints for #%s", strategy), function()
    it("inserts oauth2 plugins", function()
      local s = bp.services:insert()
      local p = bp.oauth2_plugins:insert({ service = { id = s.id } })
      assert.equal("oauth2", p.name)
      assert.equal(s.id, p.service.id)
      assert.same({ "email", "profile" }, p.config.scopes)
    end)

    it("inserts certificates", function()
      local c = bp.certificates:insert()
      assert.equal("string", type(c.cert))
      assert.equal("string", type(c.key))
    end)

    it("inserts snis", function()
      local c = bp.certificates:insert()
      local s = bp.snis:insert({ certificate = c })
      assert.equal("string", type(s.name))

      local s2 = bp.snis:insert()
      assert.equal("string", type(s2.name))
      assert.equal("string", type(s2.certificate.id))
    end)

    it("inserts consumers", function()
      local c = bp.consumers:insert()
      assert.equal("string", type(c.custom_id))
      assert.equal("string", type(c.username))
    end)

    it("inserts plugins", function()
      local p = bp.plugins:insert({ name = "dummy" })
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts targets", function()
      local t = bp.targets:insert({target = "localhost:3000"})
      assert.matches(UUID_PATTERN, t.id)
      assert.equals("localhost:3000", t.target)
      assert.equals(10, t.weight)
    end)

    it("inserts acl plugins", function()
      local p = bp.acl_plugins:insert({ config = { whitelist = {"admin"} } })
      assert.equals("acl", p.name)
      assert.same({"admin"}, p.config.whitelist)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts cors plugins", function()
      local p = bp.cors_plugins:insert()
      assert.equals("cors", p.name)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts loggly plugins", function()
      local p = bp.loggly_plugins:insert({ config = { key = "foobar" } })
      assert.equals("loggly", p.name)
      assert.equals("foobar", p.config.key)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts tcp_log_plugins", function()
      local p = bp.tcp_log_plugins:insert()
      assert.equals("tcp-log", p.name)
      assert.equals("127.0.0.1", p.config.host)
      assert.equals(35001, p.config.port)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts udp_log_plugins", function()
      local p = bp.udp_log_plugins:insert()
      assert.equals("udp-log", p.name)
      assert.equals("127.0.0.1", p.config.host)
      assert.equals(35001, p.config.port)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts jwt plugins", function()
      local p = bp.jwt_plugins:insert()
      assert.equals("jwt", p.name)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts jwt secrets", function()
      local c = bp.consumers:insert()
      local s = bp.jwt_secrets:insert({ consumer = { id = c.id } })
      assert.equals("secret", s.secret)
      assert.equals("HS256", s.algorithm)
      assert.is_string(s.key)
      assert.matches(UUID_PATTERN, s.id)
    end)

    it("inserts oauth2 credendials", function()
      local co = bp.consumers:insert()
      local c = bp.oauth2_credentials:insert({
        consumer  = { id = co.id },
        redirect_uris = { "http://foo.com" },
      })
      assert.equals("oauth2 credential", c.name)
      assert.equals("secret", c.client_secret)
      assert.matches(UUID_PATTERN, c.id)
    end)

    it("inserts oauth2 authorization codes", function()
      local co = bp.consumers:insert()
      local cr = bp.oauth2_credentials:insert({
        consumer  = { id = co.id },
        redirect_uris = { "http://foo.com" },
      })
      local c = bp.oauth2_authorization_codes:insert({ credential = { id = cr.id } })
      assert.is_string(c.code)
      assert.equals("default", c.scope)
      assert.matches(UUID_PATTERN, c.id)
    end)

    it("inserts oauth2 tokens", function()
      local co = bp.consumers:insert()
      local cr = bp.oauth2_credentials:insert({
        consumer = { id = co.id },
        redirect_uris = { "http://foo.com" },
      })
      local t = bp.oauth2_tokens:insert({ credential = { id = cr.id } })
      assert.equals("bearer", t.token_type)
      assert.equals("default", t.scope)
      assert.matches(UUID_PATTERN, t.id)
    end)

    it("inserts key auth plugins", function()
      local p = bp.key_auth_plugins:insert()
      assert.equals("key-auth", p.name)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts hmac auth plugins", function()
      local p = bp.hmac_auth_plugins:insert()
      assert.equals("hmac-auth", p.name)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts hmac usernames", function()
      local c = bp.consumers:insert()
      local u = bp.hmacauth_credentials:insert({ consumer = { id = c.id } })
      assert.is_string(u.username)
      assert.equals("secret", u.secret)
      assert.matches(UUID_PATTERN, u.id)
    end)

    it("inserts rate limiting plugins", function()
      local p = bp.rate_limiting_plugins:insert({ config = { hour = 42 } })
      assert.equals("rate-limiting", p.name)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts response rate limiting plugins", function()
      local p = bp.response_ratelimiting_plugins:insert({ config = { limits = { video = { minute = 3 } } } })
      assert.equals("response-ratelimiting", p.name)
      assert.matches(UUID_PATTERN, p.id)
    end)

    it("inserts datadog plugins", function()
      local p = bp.datadog_plugins:insert()
      assert.equals("datadog", p.name)
      assert.matches(UUID_PATTERN, p.id)
    end)

  end)
end

