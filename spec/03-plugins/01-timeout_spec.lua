local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
	describe("Plugin: upstream-timeout", function ()
		local admin_client
		local proxy_client
		local timeout_route

		setup(function ()
			local bp = helpers.get_db_utils(strategy)

			-- Note there is already service to echo the request
			timeout_route = bp.routes:insert({
				hosts = { "test_upstream_timeout.adult" }
			})

			assert(helpers.start_kong({
				database = strategy,
				nginx_conf = "spec/fixtures/custom_nginx.template"
			}))

			proxy_client = helpers.proxy_client()
			admin_client = helpers.admin_client()
		end)

		teardown(function ()
			if proxy_client and admin_client then
				proxy_client:close()
				admin_client:close()
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
						name   = "key-auth",
						config = {
							route = { id = timeout_route.id }
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
				assert.response(res).has.status(500)
			end)


		end)
	end)

end
