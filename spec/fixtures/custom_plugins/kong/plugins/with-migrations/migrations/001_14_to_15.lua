-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "foos" ADD "shape" TEXT UNIQUE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],

    teardown = function(connector, _)
      -- update shape in all foos
      for row, err in connector:iterate('SELECT * FROM "foos";') do
        if err then
          return nil, err
        end

        local shape = "triangle"
        local sql = string.format([[
          UPDATE "foos" SET "shape" = '%s' WHERE "color" = '%s';
        ]], shape, row.color)
        assert(connector:query(sql))
      end


      -- check insertion and update
      local count = 0
      for row, err in connector:iterate('SELECT * FROM "foos";') do
        if err then
          return nil, err
        end

        count = count + 1
        assert(row.color == "red", "Wrong color: " .. tostring(row.color))
        assert(row.shape == "triangle", "Wrong shape: " .. tostring(row.shape))
      end

      assert(count == 1, "Expected 1 foo, found " .. tostring(count))

      return true
    end,
  },
}
