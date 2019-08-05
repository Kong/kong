local cost = require "kong.plugins.gql-rate-limiting.cost"
local build_ast = require "kong.gql.query.build_ast"
local cjson = require "cjson.safe"
local Schema = require "kong.gql.schema"

describe("Function cost(query_ast:)", function ()


    local schema
    setup(function ()
        -- See file for full type definitions
        local raw_body = require "spec.fixtures.schema-json-01"
        local json_data = cjson.decode(raw_body)

        schema = Schema.deserialize_json_data(json_data)
    end)

    describe("for multi-level nested query, it", function ()

        local FRIENDS_NESTED_QUERY = [[
            query { # + 1
                allUsers(pageSize: 10) { # * 10 + 1
                    id # + 1
                    friends(pageSize: 10) { # * 10 + 1
                        birthday,  # + 1
                        hobbies {  # + 1
                            name   # + 1
                        }
                    }
                }
            }
            # total cost: (((3 * 10 + 1) + 1) * 10 + 1) + 1 = 322
        ]]

        it("should multiply subtree by values of mul_arguments", function ()
            local query_ast = build_ast(FRIENDS_NESTED_QUERY)
            query_ast:decorate_data({
                "User.friends", "Query.allUsers"
            }, schema, { mul_arguments={ "pageSize" }})

            local query_cost = cost(query_ast)
            assert.are.equal(322, query_cost)
        end)
    end)

    describe("for non-sense query decoration", function ()
        local HOBBY_QUERY = [[
            query { # + 1
                allHobbies(pageSize:4) { # * 4 + 4 + 1
                    name,   # + 5
                    id      # + 1
                }
            }
            # total cost: ((5 + 1) * 4 + 4 + 1) + 1) = 30
        ]]

        it([[should multiply subtree by mul_constant, add subtree by values of add_arguments,
            and add subtree cost by add_constant]], function ()
            local query_ast = build_ast (HOBBY_QUERY)
            query_ast:decorate_data({
                "Query.allHobbies"
            }, schema, { mul_constant = 4 })
            query_ast:decorate_data({
                "Query.allHobbies"
            }, schema, { add_arguments = {"pageSize"}})
            query_ast:decorate_data({
                "Hobby.name"
            }, schema, { add_constant = 5 })

            local query_cost = cost(query_ast)
            assert.are.equal(30, query_cost)
        end)
    end)
end)