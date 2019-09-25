local cost = require "kong.plugins.gql-rate-limiting.cost"
local build_ast = require "kong.gql.query.build_ast"
local cjson = require "cjson.safe"
local Schema = require "kong.gql.schema"

describe("Function cost(query_ast, default): ", function ()
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

describe("Function cost(query_ast, node_quantifier): ", function ()
    local schema
    setup(function ()
        -- See file for full type definitions
        local raw_body = require "spec.fixtures.schema-json-02"
        local json_data = cjson.decode(raw_body)
        schema = Schema.deserialize_json_data(json_data)
    end)

    describe("queries with no arguments", function()
        local QUERY = [[
            query {
              allPeople {
                people {
                  name
                  vehicleConnection {
                    vehicles {
                      name
                    }
                  }
                }
              }
            }
        ]]

        it("cost is 0 on undecorated schemas", function()
            local query_ast = build_ast(QUERY)
            assert.are.equal(0, cost(query_ast, "node_quantifier"))
        end)

        it("cost is 0 on decorated schemas", function()
            local query_ast = build_ast(QUERY)
            query_ast:decorate_data({
                "Query.allPeople", "Person.vehicleConnection"
            }, schema, { mul_arguments={ "first" }})
            assert.are.equal(0, cost(query_ast, "node_quantifier"))
        end)
    end)

    describe("queries with arguments", function()
        it("counts number of potentially visited nested nodes", function()
            local QUERY = [[
                query {
                  allPeople(first:100) { # 1
                    people {
                      name
                      vehicleConnection(first:10) { # 100
                        vehicles {
                          name
                          filmConnection(first:5) { # 10 * 100
                            films{
                              title
                              characterConnection(first:50) { # 5 * 10 * 100
                                characters {
                                  name
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
                # Cost: 1 + 100 + 10 * 100 + 5 * 10 * 100 = 6101
            ]]
            local query_ast = build_ast(QUERY)
            query_ast:decorate_data({
                "Query.allPeople", "Person.vehicleConnection",
                "Vehicle.filmConnection", "Film.characterConnection"
            }, schema, { mul_arguments = {"first"}})
            assert.are.equal(6101, cost(query_ast, "node_quantifier"))
        end)

        it("counts number of potentially visited sibling nodes", function()
            local QUERY = [[
                query {
                  allPeople(first: 100) { # 1 node
                    people {
                      name
                      vehicleConnection(first: 200) { # 100 nodes
                        vehicles {
                          name
                        }
                      }
                      filmConnection(first: 5) { # 100 nodes
                        films {
                          title
                        }
                      }
                    }
                  }
                }
                # Cost: (1 + 100 + 100) = 201
            ]]
            local query_ast = build_ast(QUERY)
            query_ast:decorate_data({
                "Query.allPeople", "Person.vehicleConnection",
                "Person.filmConnection"
            }, schema, { mul_arguments = {"first"}})
            assert.are.equal(201, cost(query_ast, "node_quantifier"))
        end)

        it("can add a specific cost per node", function()
            local QUERY = [[
                query {
                  allPeople(first:100) { # 1
                    people {
                      name
                      vehicleConnection(first:10) { # 100 ( * 42)
                        vehicles {
                          name
                          filmConnection(first:5) { # 10 * 100
                            films{
                              title
                              characterConnection(first:50) { # 5 * 10 * 100
                                characters {
                                  name
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
                # Cost: 1 + 100 * 42 + 10 * 100 + 5 * 10 * 100 = 6101
                # 1 + 4200 + 1000 + 5000 = 10201
            ]]
            local query_ast = build_ast(QUERY)
            query_ast:decorate_data({
                "Query.allPeople", "Person.vehicleConnection",
                "Vehicle.filmConnection", "Film.characterConnection"
            }, schema, { mul_arguments = {"first"}})
            -- Calling /person/10/vehicles has an extra 42 cost
            query_ast:decorate_data({
                "Person.vehicleConnection"
            }, schema, { add_constant = 42 })
            assert.are.equal(10201, cost(query_ast, "node_quantifier"))
        end)
    end)
end)
