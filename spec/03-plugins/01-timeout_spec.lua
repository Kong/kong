local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
	describe("Plugin enabled on Service:", function ()
		local admin_client
		local proxy_client
		local no_delay_service, delay_service

		lazy_setup(function ()
			local bp = helpers.get_db_utils(strategy, {
				"services",
				"routes",
				"plugins"
			})

			no_delay_service = assert(bp.services:insert({
				name = "no-delay-service",
				url = "http://httpbin.org/delay/0",
			}))
			delay_service = assert(bp.services:insert({
				name = "delay-service",
				url = "http://httpbin.org/delay/2" -- 2 second delay
			}))

			assert(bp.routes:insert({
				hosts = { "no.delay.com" },
				service = { id = no_delay_service.id }
			}))
			assert(bp.routes:insert({
				hosts = { "twoseconds.delay.com" },
				service = { id = delay_service.id }
			}))


			assert(bp.plugins:insert {
				service = { id = no_delay_service.id },
				name    = "upstream-timeout",
				config  = {
					read_timeout = 1000
				}
			})
			assert(bp.plugins:insert {
				service = { id = delay_service.id },
				name    = "upstream-timeout",
				config  =  {
					read_timeout = 1000
				}
			})

			assert(helpers.start_kong({
				database = strategy,
				nginx_conf = "spec/fixtures/custom_nginx.template",
				plugins = "bundled, upstream-timeout"
			}))

			proxy_client = helpers.proxy_client()
			admin_client = helpers.admin_client()
		end)

		lazy_teardown(function ()
			if proxy_client and admin_client then
				proxy_client:close()
				admin_client:close()
			end
			helpers.stop_kong()
		end)

		describe("request upstream", function ()
			local function upstream_request(host)
				return proxy_client:send({
					method = "GET",
					path = "/",
					headers = {
						host = host
					}
				})
			end

			it("will succeed if response below timeout", function ()
				local res = assert(upstream_request("no.delay.com"))
				assert.response(res).has.status(200)
			end)

			it("will fail if response exceeds timeout", function ()
				local res = assert(upstream_request("twoseconds.delay.com"))
				assert.response(res).has.status(504)
			end)

		end)
	end)
end
