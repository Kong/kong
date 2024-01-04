
local cjson = require "cjson"
local tablex = require "pl.tablex"
local uh = require "spec.upgrade_helpers"

local function matches(t1, t2)
    local inters = tablex.merge(t1, t2)
    return assert.same(inters, t1)
end

local function deep_matches(t1, t2, parent_keys)
    for key, v in pairs(t1) do
        local composed_key = (parent_keys and parent_keys .. "." .. key) or key
        if type(v) == "table" then
            deep_matches(t1[key], t2[key], composed_key)
        else
            assert.message("expected values at key " .. composed_key .. " to be the same").equal(t1[key], t2[key])
        end
    end
end

if uh.database_type() == 'postgres' then
    describe("acme plugin migration", function()
        lazy_setup(function()
            -- uh.get_database()
            assert(uh.start_kong())
        end)

        lazy_teardown(function ()
            assert(uh.stop_kong(nil, true))
        end)

        uh.setup(function ()
            local admin_client = assert(uh.admin_client())

            local res = assert(admin_client:send {
                method = "POST",
                path = "/plugins/",
                body = {
                    name = "acme",
                    config = {
                        account_email = "test@example.com",
                        storage = "redis",
                        storage_config = {
                            redis = {
                                host = "localhost",
                                port = 57198,
                                auth = "secret",
                                database = 2
                            }
                        }
                    }
                },
                headers = {
                ["Content-Type"] = "application/json"
                }
            })
            assert.res_status(201, res)
            admin_client:close()
        end)

        uh.new_after_up("has updated acme redis configuration", function ()
            local admin_client = assert(uh.admin_client())
            local res = assert(admin_client:send {
                method = "GET",
                path = "/plugins/"
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.equal(1, #body.data)
            local expected_config = {
                account_email = "test@example.com",
                storage = "redis",
                storage_config = {
                    redis = {
                        base = {
                            host = "localhost",
                            port = 57198,
                            password = "secret",
                            database = 2
                        }
                    }
                }

            }
            deep_matches(expected_config, body.data[1].config)
            admin_client:close()
        end)
    end)
end
