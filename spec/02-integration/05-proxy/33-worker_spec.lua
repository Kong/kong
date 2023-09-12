local helpers = require "spec.helpers"

for _, flavor in ipairs({ "traditional", "traditional_compatible" }) do
for _, strategy in helpers.each_strategy({"postgres"}) do
  describe("#worker Proxying [#" .. strategy .. "] [#" .. flavor .. "]", function()
    local bp
    local admin_client
    local proxy_client

    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "upstreams",
        "plugins",
      })

      local service = bp.services:insert()

      bp.routes:insert {
        hosts   = { "worker.com" },
        service = service,
      }

  
      bp.plugins:insert {
        name    = "pre-function",
        service = { id = service.id },
        config = {
            access = {[[
                local pl_read = require "pl.file".read
                local pids = ngx.worker.pids()
                local oom_scores = {}
                local cjson = require "cjson"
                ngx.log(ngx.ERR, "pids: ", cjson.encode(pids))
                for i = 1, #pids do
                    local pid = pids[i]
                    local file = "/proc/" .. pid .. "/oom_score"
                    local adj_file = "/proc/" .. pid .. "/oom_score_adj"
                    local oom_score_adj = tonumber(pl_read(adj_file))
                    local oom_score = tonumber(pl_read(file))
                    ngx.log(ngx.ERR, "pid: ", pid, " oom_score: ", oom_score, " oom_score_adj: ", oom_score_adj)
                    oom_scores[i] = oom_score
                end

                local worker_0 = oom_scores[1]
                for i = 2, #oom_scores do
                    if worker_0 >= oom_scores[i] then
                        ngx.log(ngx.ERR, "worker_0: ", worker_0, " worker_", i, ": ", oom_scores[i])
                        ngx.exit(500)
                        return
                    end
                end
                ngx.exit(200)
            ]]}
          }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "pre-function",
        untrusted_lua = "on",
        nginx_main_worker_processes = 8,
        proxy_error_log = "/tmp/error.log",
      }))
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      admin_client:close()
      helpers.stop_kong()
    end)

    it("worker oom score", function()
        -- populate cache
        local res = assert(proxy_client:send {
            path = "/",
            headers = {
              ["Host"] = "worker.com",
            },
          })
        assert.res_status(200, res)
    end)
  end)
end
end
