-- these tests only apply to the ring-balancer
-- for dns-record balancing see the `dns_spec` files

describe("Balancer", function()
  describe("Balancing", function()
    pending("over multiple targets in a ring-balancer", function()
    end)
    pending("failure due to unresolved targets", function()
    end)
    pending("failure due to no targets", function()
    end)
  end)
end)
