local helpers = require "spec.helpers"


for _, inc_sync in ipairs { "on", "off" } do
describe("invalid config are rejected" .. " inc_sync=" .. inc_sync, function()
  describe("role is control_plane", function()
    it("can not disable admin_listen", function()
      local ok, err = helpers.start_kong({
        role = "control_plane",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        admin_listen = "off",
        cluster_incremental_sync = inc_sync,
      })

      assert.False(ok)
      assert.matches("Error: admin_listen must be specified when role = \"control_plane\"", err, nil, true)
    end)

    it("can not disable cluster_listen", function()
      local ok, err = helpers.start_kong({
        role = "control_plane",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_listen = "off",
        cluster_incremental_sync = inc_sync,
      })

      assert.False(ok)
      assert.matches("Error: cluster_listen must be specified when role = \"control_plane\"", err, nil, true)
    end)

    it("can not use DB-less mode", function()
      local ok, err = helpers.start_kong({
        role = "control_plane",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = "off",
        cluster_incremental_sync = inc_sync,
      })

      assert.False(ok)
      assert.matches("Error: in-memory storage can not be used when role = \"control_plane\"", err, nil, true)
    end)

    it("must define cluster_ca_cert", function()
      local ok, err = helpers.start_kong({
        role = "control_plane",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_mtls = "pki",
        cluster_incremental_sync = inc_sync,
      })

      assert.False(ok)
      assert.matches("Error: cluster_ca_cert must be specified when cluster_mtls = \"pki\"", err, nil, true)
    end)
  end)

  describe("role is proxy", function()
    it("can not disable proxy_listen", function()
      local ok, err = helpers.start_kong({
        role = "data_plane",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        proxy_listen = "off",
        cluster_incremental_sync = inc_sync,
      })

      assert.False(ok)
      assert.matches("Error: proxy_listen must be specified when role = \"data_plane\"", err, nil, true)
    end)

    it("can not use DB mode", function()
      local ok, err = helpers.start_kong({
        role = "data_plane",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_incremental_sync = inc_sync,
      })

      assert.False(ok)
      assert.matches("Error: only in-memory storage can be used when role = \"data_plane\"\n" ..
        "Hint: set database = off in your kong.conf", err, nil, true)
    end)

    it("fails to start if invalid labels are loaded", function()
      local ok, err = helpers.start_kong({
        role = "data_plane",
        database = "off",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_dp_labels = "w@:_a",
        cluster_incremental_sync = inc_sync,
      })

      assert.False(ok)
      assert.matches("Error: label key validation failed: w@", err, nil, true)
    end)

    it("starts correctly if valid labels are loaded", function()
      local ok = helpers.start_kong({
        role = "data_plane",
        database = "off",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        proxy_listen = "0.0.0.0:" .. helpers.get_available_port(),
        cluster_dp_labels = "Aa-._zZ_key:Aa-._zZ_val",
        cluster_incremental_sync = inc_sync,
      })
      assert.True(ok)
      helpers.stop_kong("servroot2")
    end)
  end)

  for _, param in ipairs({ { "control_plane", "postgres" }, { "data_plane", "off" }, }) do
    describe("role is " .. param[1], function()
      it("errors if cluster certificate is not found", function()
        local ok, err = helpers.start_kong({
          role = param[1],
          nginx_conf = "spec/fixtures/custom_nginx.template",
          database = param[2],
          prefix = "servroot2",
          cluster_incremental_sync = inc_sync,
        })

        assert.False(ok)
        assert.matches("Error: cluster certificate and key must be provided to use Hybrid mode", err, nil, true)
      end)

      it("errors if cluster certificate key is not found", function()
        local ok, err = helpers.start_kong({
          role = param[1],
          nginx_conf = "spec/fixtures/custom_nginx.template",
          database = param[2],
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_incremental_sync = inc_sync,
        })

        assert.False(ok)
        assert.matches("Error: cluster certificate and key must be provided to use Hybrid mode", err, nil, true)
      end)
    end)
  end
end)

-- note that lagacy modes still error when CP exits
describe("when CP exits before DP" .. " inc_sync=" .. inc_sync, function()
  local need_exit = true

  lazy_setup(function()
    -- reset and bootstrap DB before starting CP
    helpers.get_db_utils(nil)

    assert(helpers.start_kong({
      role = "control_plane",
      prefix = "servroot1",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_listen = "127.0.0.1:9005",
      cluster_incremental_sync = inc_sync,
    }))
    assert(helpers.start_kong({
      role = "data_plane",
      prefix = "servroot2",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      database = "off",
      cluster_incremental_sync = inc_sync,
      -- EE [[
      -- vitals uses the clustering strategy by default, and it logs the exact
      -- same "error while receiving frame from peer" error strings that this
      -- test checks for, so it needs to be disabled
      vitals = "off",
      -- ]]
    }))
  end)

  lazy_teardown(function()
    if need_exit then
      helpers.stop_kong("servroot1")
    end
    helpers.stop_kong("servroot2")
  end)

  it("DP should not emit error message", function ()
    helpers.clean_logfile("servroot2/logs/error.log")
    assert(helpers.stop_kong("servroot1"))
    need_exit = false
    assert.logfile("servroot2/logs/error.log").has.no.line("error while receiving frame from peer", true)
  end)
end)
end -- for inc_sync
