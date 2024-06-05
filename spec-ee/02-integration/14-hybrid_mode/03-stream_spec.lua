-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"


-- [[ XXX EE
for _, strategy in helpers.each_strategy() do
  describe("[stream] with data plane in konnect_mode - FT-3559", function()
    local MESSAGE  = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"
    local tcp_port = 19000

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })

      local service = assert(bp.services:insert {
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_stream_port,
        protocol = "tcp",
      })

      assert(bp.routes:insert {
        destinations = {
          { port = tcp_port },
        },
        protocols = {
          "tcp",
        },
        service = service,
      })

      -- This is for `declarative_config = helpers.make_yaml_file()`
      -- when starting Kong with Konnect mode enabled.
      -- An old prefix directory may exist from previous tests,
      -- which has configuration `database` might be set to `off`,
      -- and then the `helpers.make_yaml_file()` will error as
      -- generating a declarative config file by invoking
      -- `kong config db_export`, which requires a backend database.
      -- So, we need to clean the prefix directory before starting Kong.
      helpers.clean_prefix()

      assert(helpers.start_kong({
        role               = "data_plane",
        database           = "off",
        konnect_mode       = "on",
        stream_listen      = helpers.get_proxy_ip(false) .. ":" .. tcp_port,
        nginx_conf         = "spec/fixtures/custom_nginx.template",
        cluster_cert       = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key   = "spec/fixtures/kong_clustering.key",
        declarative_config = helpers.make_yaml_file(),
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("successfully establishes connection and transfers message", function()
      local tcp_client = ngx.socket.tcp()
      assert(tcp_client:connect(helpers.get_proxy_ip(false), tcp_port))
      assert(tcp_client:send(MESSAGE))
      local body = assert(tcp_client:receive("*a"))
      assert.equal(MESSAGE, body)
      assert(tcp_client:close())
    end)
  end)
end
-- ]]
