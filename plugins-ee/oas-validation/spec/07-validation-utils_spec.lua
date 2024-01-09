-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local swagger_parser = require "kong.enterprise_edition.openapi.plugins.swagger-parser.parser"
local validation_utils = require "kong.plugins.oas-validation.utils.validation"
local utils = require "kong.plugins.oas-validation.utils"


describe("validation utils spec", function ()

  it("can fetch correct path & method spec", function ()
    local spec_str = [[
      openapi: 3.0.3
      info:
        title: Swagger Petstore - OpenAPI 3.0
        description: |-
          This is a sample Pet Store Server based on the OpenAPI 3.0 specification.  You can find out more about
          Swagger at [https://swagger.io](https://swagger.io). In the third iteration of the pet store, we've switched to the design first approach!
          You can now help us improve the API whether it's by making changes to the definition itself or to the code.
          That way, with time, we can improve the API in general, and expose some of the new features in OAS3.

          Some useful links:
          - [The Pet Store repository](https://github.com/swagger-api/swagger-petstore)
          - [The source API definition for the Pet Store](https://github.com/swagger-api/swagger-petstore/blob/master/src/main/resources/openapi.yaml)

        termsOfService: http://swagger.io/terms/
        contact:
          email: apiteam@swagger.io
        license:
          name: Apache 2.0
          url: http://www.apache.org/licenses/LICENSE-2.0.html
        version: 1.0.11
      externalDocs:
        description: Find out more about Swagger
        url: http://swagger.io
      servers:
        - url: https://petstore3.swagger.io/api/v3
      tags:
        - name: pet
          description: Everything about your Pets
          externalDocs:
            description: Find out more
            url: http://swagger.io
        - name: store
          description: Access to Petstore orders
          externalDocs:
            description: Find out more about our store
            url: http://swagger.io
        - name: user
          description: Operations about user
      paths:
        /pet/{petId}:
          get:
            tags:
              - pet
            summary: Find pet by ID
            description: Returns a single pet
            operationId: getPetById
            parameters:
              - name: petId
                in: path
                description: ID of pet to return
                required: true
                schema:
                  type: integer
                  format: int64
            responses:
              '200':
                description: successful operation
                content:
                  application/json:
                    schema:
                      $ref: '#/components/schemas/Pet'
                  application/xml:
                    schema:
                      $ref: '#/components/schemas/Pet'
              '400':
                description: Invalid ID supplied
              '404':
                description: Pet not found
            security:
              - api_key: []
              - petstore_auth:
                  - write:pets
                  - read:pets
          post:
            tags:
              - pet
            summary: Updates a pet in the store with form data
            description: ''
            operationId: updatePetWithForm
            parameters:
              - name: petId
                in: path
                description: ID of pet that needs to be updated
                required: true
                schema:
                  type: integer
                  format: int64
              - name: name
                in: query
                description: Name of pet that needs to be updated
                schema:
                  type: string
              - name: status
                in: query
                description: Status of pet that needs to be updated
                schema:
                  type: string
            responses:
              '405':
                description: Invalid input
            security:
              - petstore_auth:
                  - write:pets
                  - read:pets
          delete:
            tags:
              - pet
            summary: Deletes a pet
            description: delete a pet
            operationId: deletePet
            parameters:
              - name: api_key
                in: header
                description: ''
                required: false
                schema:
                  type: string
              - name: petId
                in: path
                description: Pet id to delete
                required: true
                schema:
                  type: integer
                  format: int64
            responses:
              '400':
                description: Invalid pet value
            security:
              - petstore_auth:
                  - write:pets
                  - read:pets
      components:
        schemas:
          Category:
            type: object
            properties:
              id:
                type: integer
                format: int64
                example: 1
              name:
                type: string
                example: Dogs
            xml:
              name: category
          Tag:
            type: object
            properties:
              id:
                type: integer
                format: int64
              name:
                type: string
            xml:
              name: tag
          Pet:
            required:
              - name
              - photoUrls
            type: object
            properties:
              id:
                type: integer
                format: int64
                example: 10
              name:
                type: string
                example: doggie
              category:
                $ref: '#/components/schemas/Category'
              photoUrls:
                type: array
                xml:
                  wrapped: true
                items:
                  type: string
                  xml:
                    name: photoUrl
              tags:
                type: array
                xml:
                  wrapped: true
                items:
                  $ref: '#/components/schemas/Tag'
              status:
                type: string
                description: pet status in the store
                enum:
                  - available
                  - pending
                  - sold
            xml:
              name: pet
    ]]
    local spec, err = swagger_parser.parse(spec_str)
    assert.is_nil(err)
    local path_spec = utils.retrieve_operation(spec.spec, "/pet/123", "GET")
    local path_spec2 = utils.retrieve_operation(spec.spec, "/pet/538434e2-600d-11ed-841e-860b1c27d8fd", "GET")
    local path_spec3 = utils.retrieve_operation(spec.spec, "/pet/woof.woof", "GET")
    assert.not_nil(path_spec)
    assert.same(path_spec, path_spec2)
    assert.same(path_spec2, path_spec3)
  end)

  it("can merge parameters correctly when only have path-level parameters", function ()
    local spec_str = [[
      {
        "openapi": "3.0.0",
        "info": {
          "title": "Sample API",
          "description": "A Sample OpenAPI Spec",
          "termsOfService": "http://swagger.io/terms/",
          "contact": {
            "email": ""
          },
          "license": {
            "name": "Apache 2.0",
            "url": "http://www.apache.org/licenses/LICENSE-2.0.html"
          },
          "version": "1.0.0"
        },
        "servers": [
          {
            "url": "http://example.com/v1"
          }
        ],
        "paths": {
          "/pet/{id}": {
            "parameters": [
              {
                "in": "path",
                "name": "id",
                "schema": {
                  "type": "integer"
                },
                "required": "true",
                "description": "The pet ID"
              }
            ],
            "get": {
              "summary": "Get a pet by its id",
              "operationId": "getPet",
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
    assert.is_nil(err)
    local path_spec, _, method_spec = utils.retrieve_operation(spec.spec, "/pet/123", "GET")
    local parameters = method_spec.parameters or {}
    if path_spec.parameters then
      parameters = validation_utils.merge_params(path_spec.parameters, parameters)
    end
    assert.same(parameters, path_spec.parameters)
  end)

  it("can merge parameters correctly when have both method-level and path-level parameters", function ()
    local spec_str = [[
      {
        "openapi": "3.0.0",
        "info": {
          "title": "Sample API",
          "description": "A Sample OpenAPI Spec",
          "termsOfService": "http://swagger.io/terms/",
          "contact": {
            "email": ""
          },
          "license": {
            "name": "Apache 2.0",
            "url": "http://www.apache.org/licenses/LICENSE-2.0.html"
          },
          "version": "1.0.0"
        },
        "servers": [
          {
            "url": "http://example.com/v1"
          }
        ],
        "paths": {
          "/pet/{id}": {
            "parameters": [
              {
                "in": "path",
                "name": "id",
                "schema": {
                  "type": "integer"
                },
                "required": "true",
                "description": "The pet ID"
              },
              {
                "in": "query",
                "name": "pathparam",
                "schema": {
                  "type": "integer"
                },
                "required": "true",
                "description": "An unique path parameter"
              }
            ],
            "get": {
              "parameters": [
                {
                  "in": "path",
                  "name": "id",
                  "schema": {
                    "type": "integer"
                  },
                  "required": "true",
                  "description": "The pet ID with more comment! Should override the path-level parameter"
                },
                {
                  "in": "query",
                  "name": "id",
                  "schema": {
                    "type": "integer"
                  },
                  "required": "true",
                  "description": "The pet ID in query! Should not override"
                }
              ],
              "summary": "Get a pet by its id",
              "operationId": "getPet",
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
    local path_spec, _, method_spec = utils.retrieve_operation(spec.spec, "/pet/123", "GET")
    local parameters = method_spec.parameters or {}
    if path_spec.parameters then
      parameters = validation_utils.merge_params(path_spec.parameters, parameters)
    end
    local expected_result = cjson.decode([[[
      {
        "in": "path",
        "name": "id",
        "schema": {
          "type": "integer"
        },
        "required": "true",
        "description": "The pet ID with more comment! Should override the path-level parameter"
      },
      {
        "in": "query",
        "name": "pathparam",
        "schema": {
          "type": "integer"
        },
        "required": "true",
        "description": "An unique path parameter"
      },
      {
        "in": "query",
        "name": "id",
        "schema": {
          "type": "integer"
        },
        "required": "true",
        "description": "The pet ID in query! Should not override"
      }
    ]
]])
    assert.same(parameters, expected_result)
  end)

  it("can fetch request body content schema", function ()
    local spec_str = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-simple.json"):read("*a"))
    local spec, err = swagger_parser.parse(spec_str)
    assert.truthy(spec)
    assert.is_nil(err)
    local _, _, method_spec = utils.retrieve_operation(spec.spec, "/pet", "PUT")
    assert.truthy(method_spec)
    local schema, _ = validation_utils.locate_request_body_schema(method_spec.requestBody, "application/json")
    assert.truthy(schema)

    local schema2, err = validation_utils.locate_request_body_schema(method_spec.requestBody, "text/plain")
    assert.is_nil(schema2)
    assert.same(err, "no request body schema found for content type 'text/plain'")
  end)

  it("can fetch response body content schema", function ()
    local spec_str = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-simple.json"):read("*a"))
    local spec, err = swagger_parser.parse(spec_str)
    assert.truthy(spec)
    assert.is_nil(err)
    local _, _, method_spec = utils.retrieve_operation(spec.spec, "/pet", "PUT")
    assert.truthy(method_spec)

    local schema, err = validation_utils.locate_response_body_schema("openapi", method_spec, 200, "application/json")
    assert.truthy(schema)
    assert.is_nil(err)

    local schema, err = validation_utils.locate_response_body_schema("openapi", method_spec, 400, "application/json")
    assert.is_nil(schema)
    assert.same(err, "no response body schema found for status code '400' and content type 'application/json'")
  end)
end)
