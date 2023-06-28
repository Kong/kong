local pl_path = require "pl.path"
local helpers = require "spec.helpers"
local inject_confs = require "kong.cmd.utils.inject_confs"
local compile_confs = inject_confs.compile_confs
local currentdir = pl_path.currentdir
local fmt = string.format

describe("compile_confs", function()
  for _, strategy in helpers.all_strategies() do
    it("database = " .. strategy, function()
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

      local args = {
        prefix = helpers.test_conf.prefix,
        database = strategy,
      }
      local confs = compile_confs(args)
      assert(confs)
      local expected_main_conf = main_conf
      if strategy == "off" then
        expected_main_conf = main_conf_off
      end
      assert.matches(expected_main_conf, confs.main_conf, nil, true)
      assert.matches(http_conf, confs.http_conf, nil, true)
      assert.matches(stream_conf, confs.stream_conf, nil, true)
    end)
  end
end)
