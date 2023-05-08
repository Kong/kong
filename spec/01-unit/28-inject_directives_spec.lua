local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local inject_directives = require "kong.cmd.utils.inject_directives"
local construct_cmd = inject_directives.construct_cmd
local fmt = string.format

describe("construct_cmd", function()
  for _, strategy in helpers.all_strategies() do
    it("default prefix, database = " .. strategy, function()
      local main_conf = [[
]]
      local main_conf_off = [[
lmdb_environment_path /usr/local/kong/dbless.lmdb;
lmdb_map_size         128m;
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
      local kong_path = "/kong/bin/kong"
      local cmd_name = "vault"
      local args = {
        "test-env/test",
        command = "get",
        v = true,
      }

      local conf = assert(conf_loader(nil, {
        database = strategy,
      }))
      local cmd, err = construct_cmd(conf, cmd_name, args)
      assert.is_nil(err)
      local expected_args = "get test-env/test --v --no-inject"
      local expected_main_conf = main_conf
      if strategy == "off" then
        expected_main_conf = main_conf_off
      end
      local expected_cmd = fmt("resty --main-conf \"%s\" --http-conf \"%s\" --stream-conf \"%s\" %s %s %s",
        expected_main_conf, http_conf, stream_conf, kong_path, cmd_name, expected_args)
      assert.matches(expected_cmd, cmd, nil, true)
    end)

    it("specified prefix, database = " .. strategy, function()
      local main_conf = [[
]]
      local main_conf_off = [[
lmdb_environment_path /kong/servroot/dbless.lmdb;
lmdb_map_size         128m;
]]
      local http_conf = [[
lua_ssl_verify_depth   1;
lua_ssl_trusted_certificate '/kong/servroot/.ca_combined';
lua_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
]]
      local stream_conf = [[
lua_ssl_verify_depth   1;
lua_ssl_trusted_certificate '/kong/servroot/.ca_combined';
lua_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
]]
      local kong_path = "/kong/bin/kong"
      local cmd_name = "vault"
      local args = {
        "test-env/test",
        command = "get",
        v = true,
      }

      local conf = assert(conf_loader(nil, {
        database = strategy,
        prefix = "/kong/servroot",
      }))
      local cmd, err = construct_cmd(conf, cmd_name, args)
      assert.is_nil(err)
      local expected_args = "get test-env/test --v --no-inject"
      local expected_main_conf = main_conf
      if strategy == "off" then
        expected_main_conf = main_conf_off
      end
      local expected_cmd = fmt("resty --main-conf \"%s\" --http-conf \"%s\" --stream-conf \"%s\" %s %s %s",
        expected_main_conf, http_conf, stream_conf, kong_path, cmd_name, expected_args)
      assert.matches(expected_cmd, cmd, nil, true)
    end)
  end
end)
