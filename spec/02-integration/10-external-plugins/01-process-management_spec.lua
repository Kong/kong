local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("manages a pluginserver #" .. strategy, function()
    lazy_setup(function()
      assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }))
    end)

    describe("process management", function()
      it("starts/stops an external plugin server [golang]", function()
        local kong_prefix = helpers.test_conf.prefix

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
          log_level = "notice",
          database = strategy,
          plugins = "bundled,go-hello",
          pluginserver_names = "test",
          pluginserver_test_socket = kong_prefix .. "/go-hello.socket",
          pluginserver_test_query_cmd = helpers.external_plugins_path .. "/go/go-hello -dump",
          pluginserver_test_start_cmd = helpers.external_plugins_path .. "/go/go-hello -kong-prefix " .. kong_prefix,
        }))
        assert.logfile().has.line([[started, pid [0-9]+]])
        assert(helpers.stop_kong(nil, true))
        assert.logfile().has.line([[successfully stopped pluginserver 'test', pid [0-9]+]])
      end)
  
      it("starts/stops an external plugin server [python]", function()
        local kong_prefix = helpers.test_conf.prefix

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
          log_level = "notice",
          database = strategy,
          plugins = "bundled,py-hello",
          pluginserver_names = "test",
          pluginserver_test_socket = kong_prefix .. "/py-hello.socket",
          pluginserver_test_query_cmd = helpers.external_plugins_path .. "/py/py-hello.py --dump",
          pluginserver_test_start_cmd = helpers.external_plugins_path .. "/py/py-hello.py --socket-name py-hello.socket --kong-prefix " .. kong_prefix,
        }))
        assert.logfile().has.line([[started, pid [0-9]+]])
        assert(helpers.stop_kong(nil, true))
        assert.logfile().has.line([[successfully stopped pluginserver 'test', pid [0-9]+]])
      end)

      it("starts/stops an external plugin server [golang, python]", function()
        local kong_prefix = helpers.test_conf.prefix

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
          log_level = "notice",
          database = strategy,
          plugins = "bundled,go-hello,py-hello",
          pluginserver_names = "test-go,test-py",
          pluginserver_test_go_socket = kong_prefix .. "/go-hello.socket",
          pluginserver_test_go_query_cmd = helpers.external_plugins_path .. "/go/go-hello -dump",
          pluginserver_test_go_start_cmd = helpers.external_plugins_path .. "/go/go-hello -kong-prefix " .. kong_prefix,
          pluginserver_test_py_socket = kong_prefix .. "/py-hello.socket",
          pluginserver_test_py_query_cmd = helpers.external_plugins_path .. "/py/py-hello.py --dump",
          pluginserver_test_py_start_cmd = helpers.external_plugins_path .. "/py/py-hello.py --socket-name py-hello.socket --kong-prefix " .. kong_prefix,
        }))
        assert.logfile().has.line([[started, pid [0-9]+]])
        assert(helpers.stop_kong(nil, true))
        assert.logfile().has.line([[successfully stopped pluginserver 'test-go', pid [0-9]+]])
        assert.logfile().has.line([[successfully stopped pluginserver 'test-py', pid [0-9]+]])
      end)
    end)

    it("queries plugin info [golang]", function()
        local proc_management = require "kong.runloop.plugin_servers.process"
        local kong_prefix = helpers.test_conf.prefix
        local conf_loader = require "kong.conf_loader"

        local conf, err = conf_loader(nil, {
          plugins = "bundled,go-hello",
          pluginserver_names = "test",
          pluginserver_test_socket = kong_prefix .. "/go-hello.socket",
          pluginserver_test_query_cmd = helpers.external_plugins_path .. "/go/go-hello -dump",
          pluginserver_test_start_cmd = helpers.external_plugins_path .. "/go/go-hello -kong-prefix " .. kong_prefix,
        })
        assert.is_nil(err)

        helpers.build_go_plugins(helpers.external_plugins_path .. "/go")
        local plugin_infos = proc_management.load_external_plugins_info(conf)
        assert.not_nil(plugin_infos["go-hello"])

        local info = plugin_infos["go-hello"]
        assert.equal(1, info.PRIORITY)
        assert.equal("0.1", info.VERSION)
        assert.equal("go-hello", info.name)
        assert.same({ "access", "response", "log" }, info.phases)
        assert.same("ProtoBuf:1", info.server_def.protocol)
    end)

    it("queries plugin info [python]", function()
        local proc_management = require "kong.runloop.plugin_servers.process"
        local kong_prefix = helpers.test_conf.prefix
        local conf_loader = require "kong.conf_loader"

        local conf, err = conf_loader(nil, {
          plugins = "bundled,py-hello",
          pluginserver_names = "test",
          pluginserver_test_socket = kong_prefix .. "/py-hello.socket",
          pluginserver_test_query_cmd = helpers.external_plugins_path .. "/py/py-hello.py --dump",
          pluginserver_test_start_cmd = helpers.external_plugins_path .. "/py/py-hello.py --socket-name py-hello.socket --kong-prefix " .. kong_prefix,
        })
        assert.is_nil(err)

        local plugin_infos = proc_management.load_external_plugins_info(conf)
        assert.not_nil(plugin_infos["py-hello"])

        local info = plugin_infos["py-hello"]
        assert.equal(100, info.PRIORITY)
        assert.equal("0.1.0", info.VERSION)
        assert.equal("py-hello", info.name)
        assert.same({ "access" }, info.phases)
        assert.same("MsgPack:1", info.server_def.protocol)
      end)

      it("queries plugin info [golang, python]", function()
        local proc_management = require "kong.runloop.plugin_servers.process"
        local kong_prefix = helpers.test_conf.prefix
        local conf_loader = require "kong.conf_loader"

        local conf, err = conf_loader(nil, {
          plugins = "bundled,py-hello",
          pluginserver_names = "test-go,test-py",
          pluginserver_test_go_socket = kong_prefix .. "/go-hello.socket",
          pluginserver_test_go_query_cmd = helpers.external_plugins_path .. "/go/go-hello -dump",
          pluginserver_test_go_start_cmd = helpers.external_plugins_path .. "/go/go-hello -kong-prefix " .. kong_prefix,
          pluginserver_test_py_socket = kong_prefix .. "/py-hello.socket",
          pluginserver_test_py_query_cmd = helpers.external_plugins_path .. "/py/py-hello.py --dump",
          pluginserver_test_py_start_cmd = helpers.external_plugins_path .. "/py/py-hello.py --socket-name py-hello.socket --kong-prefix " .. kong_prefix,
        })
        assert.is_nil(err)

        local plugin_infos = proc_management.load_external_plugins_info(conf)
        assert.not_nil(plugin_infos["go-hello"])
        assert.not_nil(plugin_infos["py-hello"])

        local go_info = plugin_infos["go-hello"]
        assert.equal(1, go_info.PRIORITY)
        assert.equal("0.1", go_info.VERSION)
        assert.equal("go-hello", go_info.name)
        assert.same({ "access", "response", "log" }, go_info.phases)
        assert.same("ProtoBuf:1", go_info.server_def.protocol)

        local py_info = plugin_infos["py-hello"]
        assert.equal(100, py_info.PRIORITY)
        assert.equal("0.1.0", py_info.VERSION)
        assert.equal("py-hello", py_info.name)
        assert.same({ "access" }, py_info.phases)
        assert.same("MsgPack:1", py_info.server_def.protocol)
      end)
    end)
end
