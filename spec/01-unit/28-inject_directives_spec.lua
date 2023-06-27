local pl_path = require "pl.path"
local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local inject_directives = require "kong.cmd.utils.inject_directives"
local construct_cmd = inject_directives._construct_cmd
local currentdir = pl_path.currentdir
local fmt = string.format

describe("construct_cmd", function()
  for _, strategy in helpers.all_strategies() do
    it("default prefix, database = " .. strategy, function()
      local cwd = currentdir()
      local main_conf = [[
]]
      local main_conf_off = [[
lmdb_environment_path /usr/local/kong/dbless.lmdb;
lmdb_map_size         2048m;
]]
      local http_conf = [[
lua_ssl_verify_depth   1;
lua_ssl_trusted_certificate '/usr/local/kong/.ca_combined';
lua_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
]]
      local stream_conf = [[
lua_ssl_verify_depth   1;
lua_ssl_trusted_certificate '/usr/local/kong/.ca_combined';
lua_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
]]
      local kong_path = cwd .. "/bin/kong"
      _G.cli_args = {
        [-1] = "resty",
        [0]  = kong_path,
        [1]  = "vault",
        [2]  = "get",
        [3]  = "test-env/test",
        [4] = "--v"
      }
      local conf = assert(conf_loader(nil, {
        database = strategy,
      }))
      local cmd, err = construct_cmd(conf)
      assert.is_nil(err)
      local expected_main_conf = main_conf
      if strategy == "off" then
        expected_main_conf = main_conf_off
      end
      local expected_cmd = fmt("KONG_CLI_RESPAWNED=1 resty --main-conf \"%s\" --http-conf \"%s\" --stream-conf \"%s\" %s vault get test-env/test --v",
        expected_main_conf, http_conf, stream_conf, kong_path)
      assert.matches(expected_cmd, cmd, nil, true)
    end)

    it("specified prefix, database = " .. strategy, function()
      local cwd = currentdir()
      local main_conf = [[
]]
      local main_conf_off = fmt([[
lmdb_environment_path %s/servroot/dbless.lmdb;
lmdb_map_size         2048m;
]], cwd)
      local http_conf = fmt([[
lua_ssl_verify_depth   1;
lua_ssl_trusted_certificate '%s/servroot/.ca_combined';
lua_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
]], cwd)
      local stream_conf = fmt([[
lua_ssl_verify_depth   1;
lua_ssl_trusted_certificate '%s/servroot/.ca_combined';
lua_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
]], cwd)
      local kong_path = cwd .. "/bin/kong"
      _G.cli_args = {
        [-1] = "resty",
        [0]  = kong_path,
        [1]  = "vault",
        [2]  = "get",
        [3]  = "test-env/test",
        [4]  = "--v"
      }
      local conf = assert(conf_loader(nil, {
        database = strategy,
        prefix = helpers.test_conf.prefix,
      }))
      local cmd, err = construct_cmd(conf)
      assert.is_nil(err)
      local expected_main_conf = main_conf
      if strategy == "off" then
        expected_main_conf = main_conf_off
      end
      local expected_cmd = fmt("KONG_CLI_RESPAWNED=1 resty --main-conf \"%s\" --http-conf \"%s\" --stream-conf \"%s\" %s vault get test-env/test --v",
        expected_main_conf, http_conf, stream_conf, kong_path)
      assert.matches(expected_cmd, cmd, nil, true)
    end)
  end
end)
