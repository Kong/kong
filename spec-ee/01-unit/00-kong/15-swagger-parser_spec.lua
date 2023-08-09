-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local swagger_parser = require "kong.enterprise_edition.openapi.plugins.swagger-parser.parser"
local lyaml = require "lyaml"

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

    it("should dereference reference", function ()
      local spec_str = [[
        {
          "openapi": "3.0.3",
          "info": {
            "title": "Swagger Petstore - OpenAPI 3.0",
            "description": "",
            "termsOfService": "http://swagger.io/terms/",
            "contact": {
              "email": "apiteam@swagger.io"
            },
            "license": {
              "name": "Apache 2.0",
              "url": "http://www.apache.org/licenses/LICENSE-2.0.html"
            },
            "version": "1.0.11"
          },
          "externalDocs": {
            "description": "Find out more about Swagger",
            "url": "http://swagger.io"
          },
          "servers": [
            {
              "url": "https://petstore3.swagger.io/api/v3"
            }
          ],
          "paths": {
            "/pet": {
              "put": {
                "summary": "Update an existing pet",
                "description": "Update an existing pet by Id",
                "operationId": "updatePet",
                "requestBody": {
                  "description": "Update an existent pet in the store",
                  "content": {
                    "application/json": {
                      "schema": {
                        "$ref": "#/components/schemas/Pet"
                      }
                    },
                    "application/xml": {
                      "schema": {
                        "$ref": "#/components/schemas/Pet"
                      }
                    },
                    "application/x-www-form-urlencoded": {
                      "schema": {
                        "$ref": "#/components/schemas/Pet"
                      }
                    }
                  },
                  "required": true
                },
                "responses": {
                  "200": {
                    "description": "Successful operation",
                    "content": {
                      "application/json": {
                        "schema": {
                          "$ref": "#/components/schemas/Pet"
                        }
                      },
                      "application/xml": {
                        "schema": {
                          "$ref": "#/components/schemas/Pet"
                        }
                      }
                    }
                  },
                  "400": {
                    "description": "Invalid ID supplied"
                  },
                  "404": {
                    "description": "Pet not found"
                  },
                  "405": {
                    "description": "Validation exception"
                  }
                }
              }
            }
          },
          "components": {
            "schemas": {
              "Tag": {
                "type": "object",
                "properties": {
                  "id": {
                    "type": "integer",
                    "format": "int64"
                  },
                  "name": {
                    "type": "string"
                  }
                },
                "xml": {
                  "name": "tag"
                }
              },
              "Pet": {
                "required": [
                  "name",
                  "photoUrls"
                ],
                "type": "object",
                "properties": {
                  "id": {
                    "type": "integer",
                    "format": "int64",
                    "example": 10
                  },
                  "name": {
                    "type": "string",
                    "example": "doggie"
                  },
                  "photoUrls": {
                    "type": "array",
                    "xml": {
                      "wrapped": true
                    },
                    "items": {
                      "type": "string",
                      "xml": {
                        "name": "photoUrl"
                      }
                    }
                  },
                  "tags": {
                    "type": "array",
                    "xml": {
                      "wrapped": true
                    },
                    "items": {
                      "$ref": "#/components/schemas/Tag"
                    }
                  },
                  "status": {
                    "type": "string",
                    "description": "pet status in the store",
                    "enum": [
                      "available",
                      "pending",
                      "sold"
                    ]
                  }
                },
                "xml": {
                  "name": "pet"
                }
              }
            }
          }
        }
          ]]

      local spec, err = swagger_parser.parse(spec_str)
      assert.truthy(spec)
      assert.is_nil(err)
      assert.is_not_nil(spec.spec["components"]["schemas"]["Pet"]["properties"]["tags"]["items"])
      assert.is_not_nil(spec.spec["paths"]["/pet"]["put"]["requestBody"]["content"]["application/json"]["schema"]["properties"])
    end)

    it("should fail when contains recursive reference", function ()
      local spec_str = [[
        {
          "openapi": "3.0.3",
          "info": {
            "title": "Swagger Petstore - OpenAPI 3.0",
            "description": "",
            "termsOfService": "http://swagger.io/terms/",
            "contact": {
              "email": "apiteam@swagger.io"
            },
            "license": {
              "name": "Apache 2.0",
              "url": "http://www.apache.org/licenses/LICENSE-2.0.html"
            },
            "version": "1.0.11"
          },
          "externalDocs": {
            "description": "Find out more about Swagger",
            "url": "http://swagger.io"
          },
          "servers": [
            {
              "url": "https://petstore3.swagger.io/api/v3"
            }
          ],
          "paths": {
            "/pet": {
              "put": {
                "summary": "Update an existing pet",
                "description": "Update an existing pet by Id",
                "operationId": "updatePet",
                "requestBody": {
                  "description": "Update an existent pet in the store",
                  "content": {
                    "application/json": {
                      "schema": {
                        "$ref": "#/components/schemas/Pet"
                      }
                    },
                    "application/xml": {
                      "schema": {
                        "$ref": "#/components/schemas/Pet"
                      }
                    },
                    "application/x-www-form-urlencoded": {
                      "schema": {
                        "$ref": "#/components/schemas/Pet"
                      }
                    }
                  },
                  "required": true
                },
                "responses": {
                  "200": {
                    "description": "Successful operation",
                    "content": {
                      "application/json": {
                        "schema": {
                          "$ref": "#/components/schemas/Pet"
                        }
                      },
                      "application/xml": {
                        "schema": {
                          "$ref": "#/components/schemas/Pet"
                        }
                      }
                    }
                  },
                  "400": {
                    "description": "Invalid ID supplied"
                  },
                  "404": {
                    "description": "Pet not found"
                  },
                  "405": {
                    "description": "Validation exception"
                  }
                }
              }
            }
          },
          "components": {
            "schemas": {
              "Tag": {
                "type": "object",
                "properties": {
                  "id": {
                    "type": "integer",
                    "format": "int64"
                  },
                  "name": {
                    "type": "string"
                  },
                  "recursivepet": {
                    "$ref": "#/components/schemas/Tag"
                  }
                },
                "xml": {
                  "name": "tag"
                }
              },
              "Pet": {
                "required": [
                  "name",
                  "photoUrls"
                ],
                "type": "object",
                "properties": {
                  "id": {
                    "type": "integer",
                    "format": "int64",
                    "example": 10
                  },
                  "name": {
                    "type": "string",
                    "example": "doggie"
                  },
                  "photoUrls": {
                    "type": "array",
                    "xml": {
                      "wrapped": true
                    },
                    "items": {
                      "type": "string",
                      "xml": {
                        "name": "photoUrl"
                      }
                    }
                  },
                  "tags": {
                    "type": "array",
                    "xml": {
                      "wrapped": true
                    },
                    "items": {
                      "$ref": "#/components/schemas/Tag"
                    }
                  },
                  "status": {
                    "type": "string",
                    "description": "pet status in the store",
                    "enum": [
                      "available",
                      "pending",
                      "sold"
                    ]
                  }
                },
                "xml": {
                  "name": "pet"
                }
              }
            }
          }
        }
      ]]
      local res, err = swagger_parser.parse(spec_str)
      assert.is_nil(res)
      assert.same(err, "recursion detected in schema dereferencing")
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
      assert.equal("recursion detected in schema dereferencing", err)
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

      local _, err = swagger_parser.dereference(lyaml.load(schema_yaml))
      assert.not_nil(err)
      assert.equal("recursion detected in schema dereferencing", err)
    end)
  end)
end)
