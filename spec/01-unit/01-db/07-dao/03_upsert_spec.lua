local helpers = require ("spec.helpers")

describe("dao upsert: ", function()
  local db
  lazy_setup(function()
    _, db = helpers.get_db_utils("postgres", {
      "services"
    })
  end)

  it("behavior of generation of `created_at` and `updated_at`", function()

    local entity1 = db.daos["services"]:insert({
      name = "foo",
      host = "foo1.com"
    })
    assert(entity1)

    -- `created_at` is generated when entities are created
    assert(entity1.created_at)
    -- `updated_at` is generated with the creation of entities
    assert(entity1.updated_at == entity1.created_at)
    ngx.sleep(1)
    local entity2 = db.daos["services"]:upsert(
      { id = entity1.id },
      { host = "foo2.com"}
    )
    assert(entity2)
    -- `created_at` never changes with the update of entities
    assert(entity2.created_at == entity1.created_at)
    -- `updated_at` will be updated when entities are updated
    assert(entity2.updated_at ~= nil and entity2.updated_at > entity1.updated_at)
  end)
end)