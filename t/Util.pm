package t::Util;

use strict;
use warnings;
use Cwd qw(cwd);

our $cwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_package_path \'$cwd/?/init.lua;;\';

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

        require "resty.core"

        if os.getenv("PDK_PHASE_CHECKS_LUACOV") == "1" then
            require("luacov.runner")("t/phase_checks.luacov")
            jit.off()
        end

        local private_phases = require("kong.pdk.private.phases")
        local phases = private_phases.phases

        function phase_check_functions(phase, skip_fnlist)

            -- mock balancer structure
            ngx.ctx.balancer_address = {}
            ngx.ctx.upstream_url_data = {}

            local mod
            do
                local PDK = require "kong.pdk"
                local pdk = PDK.new()
                mod = pdk
                for part in phase_check_module:gmatch("[^.]+") do
                    mod = mod[part]
                end
            end

            kong = nil

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
                kong = nil

                local expected = fdata[phases[phase]]

                local forced_false = expected == "forced false"
                if forced_false then
                    expected = true
                end

                local ok1, err1 = pcall(fn, unpack(fdata.args))

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
                kong = { ctx = { core = { phase = phase } } }

                if forced_false then
                    ok1, err1 = false, ""
                    expected = false
                end

                ---[[
                local ok2, err2 = pcall(fn, unpack(fdata.args))

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
