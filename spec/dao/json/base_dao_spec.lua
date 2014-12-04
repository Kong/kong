require "spec.dao.json.configuration"

describe("JSON DAO #dao", function()

	setup(function()
		_G.dao = require("apenode.dao.json.base_dao")("entities")
	end)

	teardown(function()
		os.remove(configuration.dao.properties.file_path)
	end)

	describe("BaseDao", function()

	  describe("#save()", function()

	  		it("should return the saved entity", function()
	  			local entity = { key = "value1" }
	  			local savedEntity = dao:save(entity)
	  			assert.are.same(entity, savedEntity)
	  		end)

	  		it("should set an id property", function()
	  			local savedEntity = dao:save({ key = "value2" })
	  			assert.truthy(savedEntity.id)
	  		end)

	  end)

	  describe("#get_by_id()", function()

			it("should retrieve an entity", function()
				local savedEntity = dao:save({ key = "value3" })
				local retrievedEntity = dao:get_by_id(savedEntity.id)
				assert.are.same(retrievedEntity, {
					key = "value3",
					id = savedEntity.id
				})
			end)

			it("should return nil if entity is not found", function()
				local retrievedEntity = dao:get_by_id("0")
				assert.falsy(retrievedEntity)
			end)

			it("should return nil if id is nil", function()
				local retrievedEntity = dao:get_by_id(nil)
				assert.falsy(retrievedEntity)
			end)

	  end)

	  describe("#get_all()", function()

	  		it("should retrieve all saved entities", function()
	  			local retrieved = dao:get_all()
	  			assert.are.unique(retrieved)
	  			assert.are.equal(3, table.getn(retrieved))
	  		end)

	  end)

	  describe("#update()", function()

	  		it("should return the updated entity", function()
	  			local savedEntity = dao:save({ key = "oldvalue" })
	  			local updatedEntity = dao:update(savedEntity)
	  			assert.truthy(updatedEntity)
	  		end)

	  		it("should update the entity", function()
				local savedEntity = dao:save({ key = "oldvalue" })
				savedEntity.key = "newvalue"
				dao:update(savedEntity)

				local updatedEntity = dao:get_by_id(savedEntity.id)

				assert.are.equal("newvalue", updatedEntity.key)
	  		end)

	  end)

	  describe("#delete()", function()

	  		it("should delete an entity", function()
				local savedEntity = dao:save({ key = "value4" })
				local retrievedEntity = dao:get_by_id(savedEntity.id)
				assert.truthy(retrievedEntity)

				local deletedEntity = dao:delete(savedEntity.id)
				assert.truthy(deletedEntity)

	 			retrievedEntity = dao:get_by_id(savedEntity.id)
				assert.falsy(retrievedEntity)
	  		end)

	  end)

	end)

end)