package t::Util;

use strict;
use warnings;
use Cwd qw(cwd);

our $cwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_package_path \'$cwd/?.lua;$cwd/?/init.lua;;\';

    init_by_lua_block {
        local log = ngx.log
        local ERR = ngx.ERR

        local verbose = false
        -- local verbose = true
        local outfile = "$Test::Nginx::Util::ErrLogFile"
        if verbose then
            local dump = require "jit.dump"
            dump.on(nil, outfile)
        else
            local v = require "jit.v"
            v.on(outfile)
        end

        if os.getenv("PDK_PHASE_CHECKS_LUACOV") == "1" then
            require("luacov.runner")("t/phase_checks.luacov")
            jit.off()
        end

        local private_phases = require("kong.pdk.private.phases")
        local phases = private_phases.phases

        -- This function executes 1 or more pdk methods twice: the first time with phase
        -- checking deactivated, and the second time with phase checking activated.
        -- Params:
        -- * phase: the phase we want to test, i.e. "access"
        -- * skip_fnlist controls a check: by default, this method
        --         will check that the provided list of methods is "complete" - that
        --         all the methods inside the `mod` (see below) are covered. Setting
        --         `skip_fnlist` to `true` will skip that test (so the `mod` can have
        --         methods that go untested)
        --
        -- This method also reads from 2 globals:
        -- * phase_check_module is just a string used to determine the "module"
        --   For example, if `phase_check_module` is "kong.response", then `mod` is "response"
        -- * phase_check_data is an array of tables with this format:
        --    {
        --      method        = "exit",  -- the method inside mod, `kong.response.exit` for example
        --      args          = { 200 }, -- passed to the method
        --      init_worker   = false,     -- expected to always throw an error on init_worker phase
        --      certificate   = "pending", -- ignored phase
        --      rewrite       = true,      -- expected to work with and without the phase checker
        --      access        = true,
        --      header_filter = "forced false", -- exit will only error with the phase_checks active
        --      body_filter   = false,
        --      log           = false,
        --      admin_api     = true,
        --    }
        --
        function phase_check_functions(phase, skip_fnlist)

            -- mock balancer structure
            ngx.ctx.balancer_data = {}

            local mod
            do
                local PDK = require "kong.pdk"
                local pdk = PDK.new({ enabled_headers = { ["Server"] = true } })
                mod = pdk
                for part in phase_check_module:gmatch("[^.]+") do
                    mod = mod[part]
                end
            end

            local entries = {}
            for _, entry in ipairs(phase_check_data) do
                entries[entry.method] = true
            end

            if not skip_fnlist then
                for fname, fn in pairs(mod) do
                    if type(fn) == "function" and not entries[fname] then
                        log(ERR, "function " .. fname .. " has no phase checking data")
                    end
                end
            end

            for _, fdata in ipairs(phase_check_data) do
                local fname = fdata.method
                local fn = mod[fname]

                if type(fn) ~= "function" then
                    log(ERR, "function " .. fname .. " does not exist in module")
                    goto continue
                end

                local msg = "in " .. phases[phase] .. ", " ..
                            fname .. " expected "

                -- Run function with phase checked disabled
		if kong then
		  kong.ctx = nil
		end
		-- kong = nil

                local expected = fdata[phases[phase]]
                if expected == "pending" then
                    goto continue
                end

                local forced_false = expected == "forced false"
                if forced_false then
                    expected = true
                end

                local ok1, err1 = pcall(fn, unpack(fdata.args or {}))

                if ok1 ~= expected then
                    local errmsg = ""
                    if type(err1) == "string" then
                        errmsg = "; error: " .. err1:gsub(",", ";")
                    end
                    log(ERR, msg, tostring(expected),
                             " when phase check is disabled", errmsg)
                    ok1 = not ok1
                end

                if not forced_false
                   and ok1 == false
                   and not err1:match("attempt to index field ")
                   and not err1:match("API disabled in the ")
                   and not err1:match("headers have already been sent") then
                    log(ERR, msg, "an OpenResty error but got ", (err1:gsub(",", ";")))
                end

                -- Re-enable phase checking and compare results
		if not kong then
		  kong = {}
		end
                kong.ctx = { core = { phase = phase } }

                if forced_false then
                    ok1, err1 = false, ""
                    expected = false
                end

                ---[[
                local ok2, err2 = pcall(fn, unpack(fdata.args or {}))

                if ok1 then
                    -- succeeded without phase checking,
                    -- phase checking should not block it.
                    if not ok2 then
                        log(ERR, msg, "true when phase check is enabled; got: ", (err2:gsub(",", ";")))
                    end
                else
                    if ok2 then
                        log(ERR, msg, "false when phase check is enabled")
                    end

                    -- if failed with OpenResty phase error
                    if err1:match("API disabled in the ") then
                        -- should replace with a Kong error
                        if not err2:match("function cannot be called") then
                            log(ERR, msg, "a Kong-generated error; got: ", (err2:gsub(",", ";")))
                        end
                    end
                end
                --]]

                ::continue::
            end
        end
    }
_EOC_

1;
