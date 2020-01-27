local cjson         = require "cjson"
local utils         = require "kong.tools.utils"
local helpers       = require "spec.helpers"
local pl_path       = require "pl.path"
local pl_file       = require "pl.file"
local pl_stringx    = require "pl.stringx"


local FILE_LOG_PATH = os.tmpname()


for _, strategy in helpers.each_strategy() do
  describe("Plugin: file-log (log) [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_grpc, proxy_client_grpcs

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route = bp.routes:insert {
        hosts = { "file_logging.com" },
      }

      bp.plugins:insert {
        route = { id = route.id },
        name     = "file-log",
        config   = {
          path   = FILE_LOG_PATH,
          reopen = true,
        },
      }

      local grpc_service = assert(bp.services:insert {
        name = "grpc-service",
        url = "grpc://localhost:15002",
      })

      local route2 = assert(bp.routes:insert {
        service = grpc_service,
        protocols = { "grpc" },
        hosts = { "tcp_logging_grpc.test" },
      })

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "file-log",
        config   = {
          path   = FILE_LOG_PATH,
          reopen = true,
        },
      }

      local grpcs_service = assert(bp.services:insert {
        name = "grpcs-service",
        url = "grpcs://localhost:15003",
      })

      local route3 = assert(bp.routes:insert {
        service = grpcs_service,
        protocols = { "grpcs" },
        hosts = { "tcp_logging_grpcs.test" },
      })

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "file-log",
        config   = {
          path   = FILE_LOG_PATH,
          reopen = true,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client_grpc = helpers.proxy_client_grpc()
      proxy_client_grpcs = helpers.proxy_client_grpcs()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      os.remove(FILE_LOG_PATH)
    end)
    after_each(function()
      if proxy_client then
        proxy_client:close()
      end

      os.remove(FILE_LOG_PATH)
    end)

    it("logs to file", function()
      local uuid = utils.random_string()

      -- Making the request
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["file-log-uuid"] = uuid,
          ["Host"] = "file_logging.com"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
      end, 10)

      local file_log = pl_file.read(FILE_LOG_PATH)
      local log_message = cjson.decode(pl_stringx.strip(file_log))
      assert.same("127.0.0.1", log_message.client_ip)
      assert.same(uuid, log_message.request.headers["file-log-uuid"])
    end)

    it("logs to file #grpc", function()
      local uuid = utils.random_string()

      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-H"] = "'file-log-uuid: " .. uuid .. "'",
          ["-authority"] = "tcp_logging_grpc.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
      end, 10)

      local file_log = pl_file.read(FILE_LOG_PATH)
      local log_message = cjson.decode(pl_stringx.strip(file_log))
      assert.same("127.0.0.1", log_message.client_ip)
      assert.same(uuid, log_message.request.headers["file-log-uuid"])
    end)

    it("logs to file #grpcs", function()
      local uuid = utils.random_string()

      -- Making the request
      local ok, resp = proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-H"] = "'file-log-uuid: " .. uuid .. "'",
          ["-authority"] = "tcp_logging_grpcs.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
      end, 10)

      local file_log = pl_file.read(FILE_LOG_PATH)
      local log_message = cjson.decode(pl_stringx.strip(file_log))
      assert.same("127.0.0.1", log_message.client_ip)
      assert.same(uuid, log_message.request.headers["file-log-uuid"])
    end)

    it("reopens file on each request", function()
      local uuid1 = utils.uuid()

      -- Making the request
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["file-log-uuid"] = uuid1,
          ["Host"] = "file_logging.com"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
      end, 10)

      -- remove the file to see whether it gets recreated
      os.remove(FILE_LOG_PATH)

      -- Making the next request
      local uuid2 = utils.uuid()
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["file-log-uuid"] = uuid2,
          ["Host"] = "file_logging.com"
        }
      }))
      assert.res_status(200, res)

      local uuid3 = utils.uuid()
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["file-log-uuid"] = uuid3,
          ["Host"] = "file_logging.com"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
      end, 10)

      local file_log, err = pl_file.read(FILE_LOG_PATH)
      assert.is_nil(err)
      assert(not file_log:find(uuid1, nil, true), "did not expected 1st request in logfile")
      assert(file_log:find(uuid2, nil, true), "expected 2nd request in logfile")
      assert(file_log:find(uuid3, nil, true), "expected 3rd request in logfile")
    end)
  end)
end
