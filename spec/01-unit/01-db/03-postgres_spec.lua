local postgres_db = require "kong.dao.db.postgres"


describe("postgres_db", function()
  describe("extract_major_minor()", function()
    it("extract major and minor version digits", function()
      assert.equal("9.4", postgres_db.extract_major_minor("9.4.11"))
      assert.equal("9.4", postgres_db.extract_major_minor("9.4"))
      assert.equal("9.5", postgres_db.extract_major_minor("9.5.6"))
      assert.equal("9.6", postgres_db.extract_major_minor("9.6.10"))
      assert.equal("9.10", postgres_db.extract_major_minor("9.10"))
      assert.equal("10.0", postgres_db.extract_major_minor("10.0.1"))
      assert.equal("10.0", postgres_db.extract_major_minor("10.0"))
    end)
  end)
end)
