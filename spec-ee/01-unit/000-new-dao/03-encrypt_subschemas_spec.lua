-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

describe("encrypt subschemas", function()
  describe("should encrypt/decrypt accordingly for", function()
    describe("encrypt = true", function()
      local ref, Test_Sub, TestArrays_Sub
      local MOCK_ENC = "mock encrypted"
      local MOCK_DEC = "mock decrypted"
      local mockdb = {}
      local mock_test_strategy
      local mock_test_arrays_strategy

      setup(function()
        ref = package.loaded["kong.keyring"]
        package.loaded["kong.keyring"] = {
          encrypt = function()
            return MOCK_ENC
          end,

          decrypt = function()
            return MOCK_DEC
          end,
        }

        local Entity = require "kong.db.schema.entity"
        local dao = require "kong.db.dao"

        package.loaded["kong.db.schema"] = nil


        Test_Sub = assert(Entity.new({
          name = "test",
          primary_key = { "id" },
          subschema_key = "name",
          subschema_error = "schema '%s' not enabled",
          fields = {
            { name = { type = "string", required = true, }, },
            { id = { type = "string" } },
            { str_not_enc = { type = "string" } },
            { str_enc = { type = "string" } },
          }
        }))

        assert(Test_Sub:new_subschema("Test_Subschema", {
          name = "Test_Subschema",
          primary_key = { "id" },
          fields = {
            { id = { type = "string" } },
            { str_not_enc = { type = "string" } },
            { str_enc = { type = "string", encrypted = true } },
          }
        }))

        assert(Test_Sub:new_subschema("Test_Subschema_Plain", {
          name = "Test_Subschema_Plain",
          primary_key = { "id" },
          fields = {
            { id = { type = "string" } },
            { str_not_enc = { type = "string" } },
            { str_enc = { type = "string", encrypted = false } },
          }
        }))

        TestArrays_Sub = assert(Entity.new({
          name = "test_arrays",
          subschema_key = "name",
          subschema_error = "schema '%s' not enabled",
          primary_key = { "id" },
          fields = {
            { name = { type = "string", required = true, }, },
            { id = { type = "string" } },
            {
              str_enc = {
                type = "string",
              }
            },
            {
              arr_not_enc = {
                type = "array",
                elements = {
                  type = "string",
                }
              }
            },
            {
              arr_enc_1 = {
                type = "array",
                elements = {
                  type = "string",
                }
              }
            },
            {
              arr_enc_2 = {
                type = "array",
                elements = {
                  type = "string",
                  encrypted = true,
                }
              }
            },
          }
        }))

        assert(TestArrays_Sub:new_subschema("TestArrays_Subschema", {
          name = "TestArrays_Subschema",
          primary_key = { "id" },
          fields = {
            { id = { type = "string" } },
            {
              str_enc = {
                type = "string",
                encrypted = true,
              }
            },
            {
              -- encrypted only works as a top-level key: this won't encrypt
              arr_not_enc = {
                type = "array",
                elements = {
                  type = "string",
                  encrypted = true,
                }
              }
            },
            {
              arr_enc_1 = {
                type = "array",
                encrypted = true,
                elements = {
                  type = "string",
                }
              }
            },
            {
              arr_enc_2 = {
                type = "array",
                encrypted = true,
                elements = {
                  type = "string",
                  encrypted = true,
                  random_field = true,
                }
              }
            },
          }
        }))

        assert(TestArrays_Sub:new_subschema("TestArrays_Subschema_Plain", {
          name = "TestArrays_Subschema_Plain",
          primary_key = { "id" },
          fields = {
            { id = { type = "string" } },
            {
              str_enc = {
                type = "string",
                encrypted = false,
              }
            },
            {
              -- encrypted only works as a top-level key: this won't encrypt
              arr_not_enc = {
                type = "array",
                elements = {
                  type = "string",
                  encrypted = false,
                }
              }
            },
            {
              arr_enc_1 = {
                type = "array",
                encrypted = false,
                elements = {
                  type = "string",
                }
              }
            },
            {
              arr_enc_2 = {
                type = "array",
                encrypted = false,
                elements = {
                  type = "string",
                  encrypted = false,
                  random_field = true,
                }
              }
            },
          }
        }))

        local errors = require("kong.db.errors").new("mockstrategy")

        mock_test_strategy = {
          insert = function(self, data)
            self.value = data
            return data
          end,

          update = function(self, _, data)
            self.value = data
            return data
          end,

          upsert = function(self, _, data)
            self.value = data
            return data
          end,

          select = function(self)
            return self.value
          end,
        }

        mock_test_arrays_strategy = {
          insert = function(self, data)
            self.value = data
            return data
          end,

          update = function(self, _, data)
            self.value = data
            return data
          end,

          upsert = function(self, _, data)
            self.value = data
            return data
          end,

          select = function(self)
            return self.value
          end,
        }

        mockdb.test = dao.new(mockdb, Test_Sub, mock_test_strategy, errors)
        mockdb.test_arrays = dao.new(mockdb, TestArrays_Sub, mock_test_arrays_strategy, errors)
      end)

      teardown(function()
        package.loaded["kong.keyring"] = ref
      end)

      it("on insert", function()

        spy.on(mock_test_strategy, "insert")

        local obj = assert(mockdb.test:insert({
          name = "Test_Subschema",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        assert.spy(mock_test_strategy.insert).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
      end)

      it("on insert (plain)", function()

        spy.on(mock_test_strategy, "insert")

        local obj = assert(mockdb.test:insert({
          name = "Test_Subschema_Plain",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        assert.spy(mock_test_strategy.insert).was_called(1)

        assert.same("foo", obj.str_not_enc)
        assert.same("bar", obj.str_enc)
      end)


      it("on insert (arrays)", function()
        spy.on(mock_test_arrays_strategy, "insert")

        local obj = assert(mockdb.test_arrays:insert({
          name = "TestArrays_Subschema",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        assert.spy(mock_test_arrays_strategy.insert).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)

      it("on insert (arrays, plain)", function()
        spy.on(mock_test_arrays_strategy, "insert")

        local obj = assert(mockdb.test_arrays:insert({
          name = "TestArrays_Subschema_Plain",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        assert.spy(mock_test_arrays_strategy.insert).was_called(1)

        assert.same("foo", obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same("one", obj.arr_enc_1[1])
        assert.same("two", obj.arr_enc_1[2])
        assert.same("one", obj.arr_enc_2[1])
        assert.same("two", obj.arr_enc_2[2])
      end)

      it("on update", function()
        spy.on(mock_test_strategy, "update")

        local obj = assert(mockdb.test:update({ id = "wat" }, {
          name = "Test_Subschema",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        assert.spy(mock_test_strategy.update).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
      end)

      it("on update (plain)", function()
        spy.on(mock_test_strategy, "update")

        local obj = assert(mockdb.test:update({ id = "wat" }, {
          name = "Test_Subschema_Plain",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        assert.spy(mock_test_strategy.update).was_called(1)

        assert.same("bar", obj.str_enc)
      end)

      it("on update (arrays)", function()
        spy.on(mock_test_arrays_strategy, "update")

        local obj = assert(mockdb.test_arrays:update({ id = "wat" }, {
          name = "TestArrays_Subschema",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        assert.spy(mock_test_arrays_strategy.update).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)

      it("on update (arrays, plain)", function()
        spy.on(mock_test_arrays_strategy, "update")

        local obj = assert(mockdb.test_arrays:update({ id = "wat" }, {
          name = "TestArrays_Subschema_Plain",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        assert.spy(mock_test_arrays_strategy.update).was_called(1)

        assert.same("foo", obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same("one", obj.arr_enc_1[1])
        assert.same("two", obj.arr_enc_1[2])
        assert.same("one", obj.arr_enc_2[1])
        assert.same("two", obj.arr_enc_2[2])
      end)

      it("on upsert", function()
        spy.on(mock_test_strategy, "upsert")

        local obj = assert(mockdb.test:upsert({ id = "wat" }, {
          name = "Test_Subschema",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        assert.spy(mock_test_strategy.upsert).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
      end)

      it("on upsert (plain)", function()
        spy.on(mock_test_strategy, "upsert")

        local obj = assert(mockdb.test:upsert({ id = "wat" }, {
          name = "Test_Subschema_Plain",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        assert.spy(mock_test_strategy.upsert).was_called(1)

        assert.same("bar", obj.str_enc)
      end)

      it("on upsert (arrays)", function()
        spy.on(mock_test_arrays_strategy, "upsert")

        local obj = assert(mockdb.test_arrays:upsert({ id = "wat" }, {
          name = "TestArrays_Subschema",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        assert.spy(mock_test_arrays_strategy.upsert).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)

      it("on upsert (arrays, plain)", function()
        spy.on(mock_test_arrays_strategy, "upsert")

        local obj = assert(mockdb.test_arrays:upsert({ id = "wat" }, {
          name = "TestArrays_Subschema_Plain",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        assert.spy(mock_test_arrays_strategy.upsert).was_called(1)

        assert.same("foo", obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same("one", obj.arr_enc_1[1])
        assert.same("two", obj.arr_enc_1[2])
        assert.same("one", obj.arr_enc_2[1])
        assert.same("two", obj.arr_enc_2[2])
      end)

      it("on select", function()
        spy.on(mock_test_strategy, "select")

        assert(mockdb.test:insert({
          name = "Test_Subschema",
          id = "wat",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        local obj = assert(mockdb.test:select({ id = "wat" }))

        assert.spy(mock_test_strategy.select).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
      end)

     it("on select (plain)", function()
        spy.on(mock_test_strategy, "select")

        assert(mockdb.test:insert({
          name = "Test_Subschema_Plain",
          id = "wat",
          str_not_enc = "foo",
          str_enc = "bar",
        }))

        local obj = assert(mockdb.test:select({ id = "wat" }))

        assert.spy(mock_test_strategy.select).was_called(1)

        assert.same("bar", obj.str_enc)
      end)

      it("on select (arrays)", function()
        spy.on(mock_test_arrays_strategy, "select")

        assert(mockdb.test_arrays:insert({
          name = "TestArrays_Subschema",
          id = "wat",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        local obj = assert(mockdb.test_arrays:select({ id = "wat" }))

        assert.spy(mock_test_arrays_strategy.select).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)

      it("on select (arrays, plain)", function()
        spy.on(mock_test_arrays_strategy, "select")

        assert(mockdb.test_arrays:insert({
          name = "TestArrays_Subschema_Plain",
          id = "wat",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        }))

        local obj = assert(mockdb.test_arrays:select({ id = "wat" }))

        assert.spy(mock_test_arrays_strategy.select).was_called(1)

        assert.same("foo", obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same("one", obj.arr_enc_1[1])
        assert.same("two", obj.arr_enc_1[2])
        assert.same("one", obj.arr_enc_2[1])
        assert.same("two", obj.arr_enc_2[2])
      end)
    end)
  end)
end)
