local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
	describe("Plugin: upstream-timeout", function ()
		local admin_client
		local proxy_client

		setup(function ()
			local bp = helpers.get_db_utils(strategy)

			-- Note there is already service to echo the request
			bp.routes:insert({
				hosts = { "test_upstream_timeout.adult" }
			})

			assert(helpers.start_kong({
				database = strategy,
				nginx_conf = "spec/fixtures/custom_nginx.template"
			}))

			proxy_client = helpers.proxy_client()
			admin_client = helpers.admin_client()
		end)

		lazy_teardown(function ()
			if proxy_client and admin_client then
				proxy_client.close()
				admin_client.close()
			end
			helpers.stop_kong()
		end)

		describe("POST", function ()
			describe("config.send_timeout", function ()
				local res = assert(admin_client:send {
					method = "POST",
					path   = "/plugins",
					headers = {
						["Content-Type"] = "application/json"
					},
					body   = {
						name   = "upstream-timeout",
						config = {
							send_timeout = 0,
							read_timeout = 0
						}
					}
				})

				res = assert(proxy_client:send {
					method = "GET",
					path   = "/request",
					headers = {
						["Host"]  = "test_upstream_timeout.adult",
						["Content-Type"] = "application/json"
					},
					body = {
						data = { "ping", "pong" }
					}
				})

				-- What is timeout status
			end)


		end)
	end)

end