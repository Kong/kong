local helpers = require "spec.helpers"
local fmt = string.format

for _, role in ipairs({"traditional", "control_plane", "data_plane"}) do

describe("#wasm wasmtime (role: " .. role .. ")", function()
  describe("kong prepare", function()
    local conf
    local prefix = "./wasm"

    lazy_setup(function()
      helpers.clean_prefix(prefix)
      assert(helpers.kong_exec("prepare", {
        database = role == "data_plane" and "off" or "postgres",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        wasm = true,
        prefix = prefix,
        role = role,
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
      }))

      conf = assert(helpers.get_running_conf(prefix))
    end)

    lazy_teardown(function()
      helpers.clean_prefix(prefix)
    end)

    if role == "control_plane" then
      it("does not populate wasmtime config values", function()
        assert.is_nil(conf.wasmtime_cache_directory,
                         "wasmtime_cache_directory should not be set")
        assert.is_nil(conf.wasmtime_cache_config_file,
                         "wasmtime_cache_config_file should not be set")
      end)

    else
      it("populates wasmtime config values", function()
        assert.is_string(conf.wasmtime_cache_directory,
                         "wasmtime_cache_directory was not set")
        assert.is_string(conf.wasmtime_cache_config_file,
                         "wasmtime_cache_config_file was not set")
      end)

      it("creates the cache directory", function()
        assert(helpers.path.isdir(conf.wasmtime_cache_directory),
               fmt("expected cache directory (%s) to exist",
                   conf.wasmtime_cache_directory))
      end)

      it("creates the cache config file", function()
        assert(helpers.path.isfile(conf.wasmtime_cache_config_file),
               fmt("expected cache config file (%s) to exist",
                   conf.wasmtime_cache_config_file))

        local cache_config = assert(helpers.file.read(conf.wasmtime_cache_config_file))
        assert.matches(conf.wasmtime_cache_directory, cache_config, nil, true,
                       "expected cache config file to reference the cache directory")
      end)
    end
  end) -- cache_config
end) -- wasmtime
end -- each role
