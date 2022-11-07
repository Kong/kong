-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local swagger_parser = require("kong.plugins.mocking.swagger-parser.swagger_parser")
local lyaml = require "lyaml"

describe("swagger parser", function()
  it("dereference", function()
    local expected_schema_yaml = [[
      openapi: 3.0.1
      paths:
        "/api":
          get:
            responses:
              '200':
                description: success
                content:
                  application/json:
                    schema:
                      allOf:
                      - type: object
                        properties:
                          code:
                            type: string
                          msg:
                            type: string
                      - type: object
                        properties:
                          data:
                            type: object
                            properties:
                              id:
                                type: string
                              name:
                                type: string
                              releaseDate:
                                type: string
      components:
        schemas:
          APIResponse:
            type: object
            properties:
              code:
                type: string
              msg:
                type: string
          GetInventoryItemResponse:
            allOf:
            - type: object
              properties:
                code:
                  type: string
                msg:
                  type: string
            - type: object
              properties:
                data:
                  type: object
                  properties:
                    id:
                      type: string
                    name:
                      type: string
                    releaseDate:
                      type: string
          InventoryItem:
            type: object
            properties:
              id:
                type: string
              name:
                type: string
              releaseDate:
                type: string
    ]]
    local schema_yaml = [[
      openapi: 3.0.1
      paths:
        "/api":
          get:
            responses:
              '200':
                description: success
                content:
                  application/json:
                    schema:
                      "$ref": "#/components/schemas/GetInventoryItemResponse"
      components:
        schemas:
          APIResponse:
            type: object
            properties:
              code:
                type: string
              msg:
                type: string
          GetInventoryItemResponse:
            allOf:
            - "$ref": "#/components/schemas/APIResponse"
            - type: object
              properties:
                data:
                  "$ref": "#/components/schemas/InventoryItem"
          InventoryItem:
            type: object
            properties:
              id:
                type: string
              name:
                type: string
              releaseDate:
                type: string
    ]]
    local deref_schema, err = swagger_parser.dereference(lyaml.load(schema_yaml))
    assert.is_nil(err)
    assert.same(lyaml.load(expected_schema_yaml), deref_schema)
  end)

  it("recursive reference", function()
    local schema_yaml = [[
      openapi: 3.0.1
      paths:
        "/api":
          get:
            responses:
              '200':
                description: success
                content:
                  application/json:
                    schema:
                      "$ref": "#/components/schemas/GetInventoryItemResponse"
      components:
        schemas:
          APIResponse:
            type: object
            properties:
              code:
                type: string
              msg:
                type: string
          GetInventoryItemResponse:
            allOf:
            - "$ref": "#/components/schemas/APIResponse"
            - type: object
              properties:
                data:
                  "$ref": "#/components/schemas/GetInventoryItemResponse"
    ]]
    local _, err = swagger_parser.dereference(lyaml.load(schema_yaml))
    assert.not_nil(err)
    assert.equal("max recursion of 1000 exceeded in schema dereferencing", err)
  end)

  it("recursive reference", function()
    local schema_yaml = [[
      openapi: 3.0.1
      paths:
        "/api":
          get:
            responses:
              '200':
                description: success
                content:
                  application/json:
                    schema:
                      "$ref": "#/components/schemas/InventoryItem1"
      components:
        schemas:
          InventoryItem1:
            $ref: "#/components/schemas/InventoryItem2"
          InventoryItem2:
            $ref: "#/components/schemas/InventoryItem1"
    ]]
    local _, err = swagger_parser.dereference(lyaml.load(schema_yaml))
    assert.not_nil(err)
    assert.equal("max recursion of 1000 exceeded in schema dereferencing", err)
  end)

end)
