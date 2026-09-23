local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do


describe("Admin API - GUI logs - kong_admin #" .. strategy, function ()
  lazy_setup(function ()
    helpers.get_db_utils(strategy)                          -- clear db
    assert(helpers.start_kong({
      strategy = strategy,
      prefix = "servroot",
      admin_gui_listen = "0.0.0.0:8002",
    }))
  end)

  lazy_teardown(function ()
    assert(helpers.stop_kong())
  end)

  it("every path should to be logged", function ()
    local prefix = "/really.really.really.really.really.not.exists"
    local suffixes = {
      jpg = {
        status = 404,
      },
      jpeg = {
        status = 404,
      },
      png = {
        status = 404,
      },
      gif = {
        status = 404,
      },
      ico = {
        status = 404,
      },
      css = {
        status = 404,
      },
      ttf = {
        status = 404,
      },
      js = {
        status = 404,
      },

      --[[
        For `try_files $uri /index.html;` in nginx-kong.lua,
        so every non-exists path should be redirected to /index.html,
        so the status is 200.
      --]]
      html = {
        status = 200,
      },
      txt = {
        status = 200,
      },
    }

    local client = assert(helpers.http_client("localhost", 8002))

    for suffix, info in ipairs(suffixes) do
      local path = string.format("%s.%s", prefix, suffix)

      local res = assert(client:request({
        method = "GET",
        path = path,
      }))

      assert.res_status(info.status, res)
      assert.logfile("servroot/logs/admin_gui_access.log").has.line("GET " .. path, true, 20)

      if info.status == 404 then
        assert.logfile("servroot/logs/admin_gui_error.log").has.line(path .. "\" failed (2: No such file or directory)", true, 20)
      end
    end

    assert(client:close())
  end)

end)


end -- of the for _, strategy in helpers.each_strategy() do
