describe("encrypt", function()
  describe("should encrypt/decrypt accordingly for", function()
    describe("encrypt = true", function()
      local ref, Test, TestArrays
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


        Test = Entity.new({
          name = "test",
          primary_key = { "id" },
          fields = {
            { id = { type = "string" } },
            { str_not_enc = { type = "string" } },
            { str_enc = { type = "string", encrypted = true } },
          }
        })

        TestArrays = Entity.new({
          name = "test_arrays",
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
        })

        local errors = require("kong.db.errors").new("mockstrategy")

        mock_test_strategy = {
          insert = function(self, data)
            self.value = data
            assert.same(MOCK_ENC, data.str_enc)
            return data
          end,

          update = function(self, pk, data)
            self.value = data
            assert.same(MOCK_ENC, data.str_enc)
            return data
          end,

          upsert = function(self, pk, data)
            self.value = data
            assert.same(MOCK_ENC, data.str_enc)
            return data
          end,

          select = function(self)
            return self.value
          end,
        }

        mock_test_arrays_strategy = {
          insert = function(self, data)
            self.value = data
            assert.same(MOCK_ENC, data.str_enc)
            assert.same(MOCK_ENC, data.arr_enc_1[1])
            assert.same(MOCK_ENC, data.arr_enc_1[2])
            assert.same(MOCK_ENC, data.arr_enc_2[1])
            assert.same(MOCK_ENC, data.arr_enc_2[2])
            return data
          end,

          update = function(self, pk, data)
            self.value = data
            assert.same(MOCK_ENC, data.str_enc)
            assert.same(MOCK_ENC, data.arr_enc_1[1])
            assert.same(MOCK_ENC, data.arr_enc_1[2])
            assert.same(MOCK_ENC, data.arr_enc_2[1])
            assert.same(MOCK_ENC, data.arr_enc_2[2])
            return data
          end,

          upsert = function(self, pk, data)
            self.value = data
            assert.same(MOCK_ENC, data.str_enc)
            assert.same(MOCK_ENC, data.arr_enc_1[1])
            assert.same(MOCK_ENC, data.arr_enc_1[2])
            assert.same(MOCK_ENC, data.arr_enc_2[1])
            assert.same(MOCK_ENC, data.arr_enc_2[2])
            return data
          end,

          select = function(self)
            return self.value
          end,
        }

        mockdb.test = dao.new(mockdb, Test, mock_test_strategy, errors)
        mockdb.test_arrays = dao.new(mockdb, TestArrays, mock_test_arrays_strategy, errors)
      end)

      teardown(function()
        package.loaded["kong.keyring"] = ref
      end)

      it("on insert", function()

        spy.on(mock_test_strategy, "insert")

        local obj = mockdb.test:insert({
          str_not_enc = "foo",
          str_enc = "bar",
        })

        assert.spy(mock_test_strategy.insert).was_called(1)

        assert.same(obj.str_enc, MOCK_DEC)
      end)

      it("on insert (arrays)", function()
        spy.on(mock_test_arrays_strategy, "insert")

        local obj, err = mockdb.test_arrays:insert({
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        })
        assert.same(nil, err)

        assert.spy(mock_test_arrays_strategy.insert).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)

      it("on update", function()
        spy.on(mock_test_strategy, "update")

        local obj = mockdb.test:update({ id = "wat" }, {
          str_not_enc = "foo",
          str_enc = "bar",
        })

        assert.spy(mock_test_strategy.update).was_called(1)

        assert.same(obj.str_enc, MOCK_DEC)
      end)

      it("on update (arrays)", function()
        spy.on(mock_test_arrays_strategy, "update")

        local obj = mockdb.test_arrays:update({ id = "wat" }, {
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        })

        assert.spy(mock_test_arrays_strategy.update).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)

      it("on upsert", function()
        spy.on(mock_test_strategy, "upsert")

        local obj = mockdb.test:upsert({ id = "wat" }, {
          str_not_enc = "foo",
          str_enc = "bar",
        })

        assert.spy(mock_test_strategy.upsert).was_called(1)

        assert.same(obj.str_enc, MOCK_DEC)
      end)

      it("on upsert (arrays)", function()
        spy.on(mock_test_arrays_strategy, "upsert")

        local obj = mockdb.test_arrays:upsert({ id = "wat" }, {
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        })

        assert.spy(mock_test_arrays_strategy.upsert).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)

      it("on select", function()
        spy.on(mock_test_strategy, "select")

        mockdb.test:insert({
          id = "wat",
          str_not_enc = "foo",
          str_enc = "bar",
        })

        local obj = mockdb.test:select({ id = "wat" })

        assert.spy(mock_test_strategy.select).was_called(1)

        assert.same(obj.str_enc, MOCK_DEC)

      end)

      it("on select (arrays)", function()
        spy.on(mock_test_arrays_strategy, "select")

        mockdb.test_arrays:insert({
          id = "wat",
          str_enc = "foo",
          arr_not_enc = { "bar", "bar2" },
          arr_enc_1 = { "one", "two" },
          arr_enc_2 = { "one", "two" }
        })

        local obj = mockdb.test_arrays:select({ id = "wat" })

        assert.spy(mock_test_arrays_strategy.select).was_called(1)

        assert.same(MOCK_DEC, obj.str_enc)
        assert.same("bar", obj.arr_not_enc[1])
        assert.same("bar2", obj.arr_not_enc[2])
        assert.same(MOCK_DEC, obj.arr_enc_1[1])
        assert.same(MOCK_DEC, obj.arr_enc_1[2])
        assert.same(MOCK_DEC, obj.arr_enc_2[1])
        assert.same(MOCK_DEC, obj.arr_enc_2[2])
      end)
    end)
  end)
end)
