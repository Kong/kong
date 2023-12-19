-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local swagger_parser = require "kong.enterprise_edition.openapi.plugins.swagger-parser.parser"
local lyaml = require "lyaml"

local opts = {
  dereference = {

  }
}

describe("swagger-parser", function()

  describe("parse()", function()
    it("sanity json", function ()
      local spec_str = [[
        {
          "openapi": "3.0.0",
          "info": {
            "title": "Sample API",
            "description": "A Sample OpenAPI Spec",
            "version": "1.0.0"
          },
          "servers": [
            {
              "url": "http://example.com/v1"
            }
          ],
          "paths": {
            "/pets": {
              "get": {
                "summary": "List all pets",
                "operationId": "listPets",
                "tags": [
                  "pets"
                ],
                "responses": {
                  "200": {
                    "description": "A paged array of pets",
                    "headers": {
                      "x-next": {
                        "description": "A link to the next page of responses",
                        "schema": {
                          "type": "string"
                        }
                      }
                    },
                    "content": {
                      "application/json": {
                        "schema": {
                          "type": "string"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      ]]
      local spec, err = swagger_parser.parse(spec_str)
      assert.truthy(spec)
      assert.is_nil(err)
    end)

    it("sanity yaml", function()
      local spec_str = [[
        openapi: 3.0.0
        info:
          title: Sample API
          description: A Sample OpenAPI Spec
          version: 1.0.0
        servers:
          - url: http://example.com/v1
        paths:
          /pets:
            get:
              summary: List all pets
              operationId: listPets
              tags:
                - pets
              responses:
                '200':
                  description: A paged array of pets
                  headers:
                    x-next:
                      description: A link to the next page of responses
                      schema:
                        type: string
                  content:
                    application/json:
                      schema:
                        type: string
      ]]
      local spec, err = swagger_parser.parse(spec_str)
      assert.truthy(spec)
      assert.is_nil(err)
    end)
  end)

  describe("parse() with opts", function()
    describe("resolve_base_path", function()
      it("swagger: sanity", function()
        local spec_str = [[
          swagger: "2.0"
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          basePath: /v1
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /c:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/v1/a"] = true,
          ["/v1/b"] = true,
          ["/v1/c"] = true,
        }, paths)
      end)

      it("swagger: omitted basePath", function()
        local spec_str = [[
          swagger: "2.0"
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /c:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/a"] = true,
          ["/b"] = true,
          ["/c"] = true,
        }, paths)
      end)

      it("openapi: sanity", function()
        local spec_str = [[
          openapi: 3.0.1
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          servers:
            - url: "/v1"
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /c:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/v1/a"] = true,
          ["/v1/b"] = true,
          ["/v1/c"] = true,
        }, paths)

        local spec_str = [[
          openapi: 3.0.1
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          servers:
            - url: "https://example.com/v1"
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /c:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/v1/a"] = true,
          ["/v1/b"] = true,
          ["/v1/c"] = true,
        }, paths)

        -- trailing slash
        local spec_str = [[
          openapi: 3.0.1
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          servers:
            - url: "/v1/"
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/v1/a"] = true,
          ["/v1/b"] = true,
        }, paths)

        -- trailing slashes
        local spec_str = [[
          openapi: 3.0.1
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          servers:
            - url: "/v1//"
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/v1/a"] = true,
          ["/v1/b"] = true,
        }, paths)


      end)

      it("openapi: should not resolve paths when spec has multiple servers", function()
        local spec_str = [[
          openapi: 3.0.1
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          servers:
            - url: "/v1"
            - url: "/v1"
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /c:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/a"] = true,
          ["/b"] = true,
          ["/c"] = true,
        }, paths)
      end)

      it("openapi: should not resolve paths when servers[].url is fully-qualified URL but without containing path", function()
        local spec_str = [[
          openapi: 3.0.1
          info:
            title: Sample API
            description: A Sample OpenAPI Spec
            version: 1.0.0
          servers:
            - url: https://example.com
          paths:
            /a:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /b:
              get:
                summary: get
                responses:
                  '200':
                    description: success
            /c:
              get:
                summary: get
                responses:
                  '200':
                    description: success
        ]]
        local spec, err = swagger_parser.parse(spec_str, { resolve_base_path = true })
        assert.truthy(spec)
        assert.is_nil(err)
        local paths = {}
        for path in pairs(spec.spec.paths) do
          paths[path] = true
        end
        assert.same({
          ["/a"] = true,
          ["/b"] = true,
          ["/c"] = true,
        }, paths)
      end)

    end)
  end)

  describe("dereference()", function()
    it("dereference", function()
      -- only resolve spec $ref, does not touch the $ref in schema(jsonschema)
      local expected_schema_yaml = [[
        openapi: 3.0.1
        paths:
          /api:
            get:
              responses:
                '404':
                  content:
                    application/json:
                      schema:
                        $ref: '#/components/schemas/APIResponse'
                  description: NotFound response
                '500':
                  description: success
                  content:
                    application/json:
                      schema:
                        type: array
                        items:
                          "$ref": "#/components/schemas/GetApiDto"
                '200':
                  content:
                    application/json:
                      schema:
                        $ref: '#/components/schemas/GetApiDto'
                  description: success
        components:
          responses:
            NotFound:
              content:
                application/json:
                  schema:
                    $ref: '#/components/schemas/APIResponse'
              description: NotFound response
          schemas:
            APIResponse:
              properties:
                code:
                  type: string
                msg:
                  type: string
              type: object
            GetApiDto:
              allOf:
              - $ref: '#/components/schemas/APIResponse'
              - properties:
                  data:
                    $ref: '#/components/schemas/InventoryItem'
                type: object
            InventoryItem:
              properties:
                name:
                  type: string
                id:
                  type: string
                releaseDate:
                  type: string
              type: object
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
                      schema: # should not be resolved
                        "$ref": "#/components/schemas/GetApiDto"
                '500':
                  description: success
                  content:
                    application/json:
                      schema: # should not be resolved
                        type: array
                        items:
                          "$ref": "#/components/schemas/GetApiDto"
                '404':
                  "$ref": "#/components/responses/NotFound" # should be resolved
        components:
          responses:
            NotFound:
              description: NotFound response
              content:
                application/json:
                  schema:
                    $ref: '#/components/schemas/APIResponse'
          schemas:
            APIResponse:
              type: object
              properties:
                code:
                  type: string
                msg:
                  type: string
            GetApiDto:
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
      local deref_schema, err = swagger_parser.dereference(lyaml.load(schema_yaml), opts)
      assert.is_nil(err)
      assert.same(lyaml.load(expected_schema_yaml), deref_schema)
    end)

    it("should succeed when contians recursive reference", function()
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
                        "$ref": "#/components/schemas/Person"
        components:
          schemas:
            Person:
              type: object
              properties:
                name:
                  type: string
                children:
                  type: array
                  items:
                    $ref: "#/components/schemas/Person"
      ]]
      local _, err = swagger_parser.dereference(lyaml.load(schema_yaml), opts)
      assert.is_nil(err)
    end)

    it("should fail when contains circle reference", function()
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
                        "$ref": "#/components/schemas/ItemCycle1"
        components:
          schemas:
            ItemCycle1:
              $ref: "#/components/schemas/ItemCycle2"
            ItemCycle2:
              $ref: "#/components/schemas/ItemCycle1"
      ]]
      local _, err = swagger_parser.dereference(lyaml.load(schema_yaml), opts)
      assert.not_nil(err)
      assert.equal("recursion detected in schema dereferencing: #/components/schemas/ItemCycle1", err)
    end)

    it("should fail when contains recursive reference", function()
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

      local _, err = swagger_parser.dereference(lyaml.load(schema_yaml), opts)
      assert.not_nil(err)
      assert.equal("recursion detected in schema dereferencing: #/components/schemas/InventoryItem1", err)
    end)
  end)
end)
