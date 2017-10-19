local asn_sequence = require "kong.plugins.jwt.asn_sequence"

describe("Plugin: jwt (asn)", function()
  describe("constructing error checking", function()
    it("should require input to be a table", function()
      assert.has_error(function()
        asn_sequence.create_simple_sequence("bad thing")
      end, "Argument #1 must be a table")
    end)

    it("should require numeric keys", function()
      assert.has_error(function()
        local seq = {}
        seq["foo"] = "bar"
        asn_sequence.create_simple_sequence(seq)
      end, "Table must use numbers as keys")
    end)
  end)

  describe("constructing", function()
    it("should make simple asn", function()
      local seq = {}
      seq[1] = "\x01\x02\x03"
      seq[2] = "\x08\x09\x0A"
      local asn = asn_sequence.create_simple_sequence(seq)
      assert.equal("\x30\x0A\x02\x03\x01\x02\x03\x02\x03\x08\x09\x0A", asn)
    end)

    it("should construct in key order", function()
      local seq = {}
      seq[2] = "\x08\x09\x0A"
      seq[1] = "\x01\x02\x03"
      local asn = asn_sequence.create_simple_sequence(seq)
      assert.equal("\x30\x0A\x02\x03\x01\x02\x03\x02\x03\x08\x09\x0A", asn)
    end)

    it("should round-trip parsing and constructing", function()
      local seq = {}
      seq[2] = "\x08\x09\x0A"
      seq[1] = "\x01\x02\x03"
      local asn = asn_sequence.create_simple_sequence(seq)
      local parsed = asn_sequence.parse_simple_sequence(asn)
      assert.same(seq, parsed)
    end)
  end)

  describe("parsing", function()
    it("should parse simple integer sequence", function()
      local seq = asn_sequence.parse_simple_sequence("\x30\x03\x02\x01\x99")
      assert.equal("\x99", seq[1])
    end)

    it("should parse multiple integers", function()
      local seq = asn_sequence.parse_simple_sequence("\x30\x09\x02\x01\x99\x02\x01\xFF\x02\x01\xCC")
      assert.equal("\x99", seq[1])
      assert.equal("\xFF", seq[2])
      assert.equal("\xCC", seq[3])
    end)

    it("should parse 32-byte integer", function()
      local seq = asn_sequence.parse_simple_sequence(
        "\x30\x22\x02\x20\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x10" ..
        "\x11\x12\x13\x14\x15\x16\x17\x18\x19\x20\x21\x22\x23\x24\x25" ..
        "\x26\x27\x28\x29\x30\x31"
      )
      assert.equal(32, #seq[1])
    end)
  end)

  describe("unsign integer", function()
    it("should remove zero sign byte", function()
      assert.equal("\xFF", asn_sequence.unsign_integer("\x00\xFF", 1))
    end)

    it("should not remove all sign zeros", function()
      assert.equal("\x00\xFF", asn_sequence.unsign_integer("\x00\x00\xFF", 2))
    end)

    it("should not remove non-zero", function()
      assert.equal("\xFF\xFF", asn_sequence.unsign_integer("\xFF\xFF", 2))
    end)
  end)

  describe("resign integer", function()
    it ("should readd zero sign byte", function()
      assert.equal("\x00\xFF", asn_sequence.resign_integer("\xFF"))
    end)

    it ("should not readd zero sign byte when not needed", function()
      assert.equal("\x00\xFF", asn_sequence.resign_integer("\x00\xFF"))
    end)

    it("should not remove significant leading sign zero", function()
      assert.equal("\x00\xFF\x23", asn_sequence.resign_integer("\x00\xFF\x23"))
    end)

    it("should convert to compact form", function()
      assert.equal("\x00\xFF\x23", asn_sequence.resign_integer("\x00\x00\x00\xFF\x23"))
    end)
  end)

  describe("parsing error checking", function()
    it("should not allow empty input", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("")
      end, "Argument #1 must not be empty")
    end)

    it("should not allow input other than strings", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence({})
      end, "Argument #1 must be string")
    end)

    it("should not allow non-sequence data", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x06")
      end, "Argument #1 is not a sequence")
    end)

    it("should not allow incomplete sequences", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30")
      end, "Sequence is incomplete")
    end)

    it("should not allow multi-byte lengths for sequences", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30\xFF")
      end, "Multi-byte lengths are not supported")
    end)

    it("should produce error when asn's declared length is beyond string length", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30\x40\x00")
      end, "Sequence's asn length does not match expected length")
    end)

    it("should produce error when extra data beyond sequence", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30\x01\x00\x00")
      end, "Sequence's asn length does not match expected length")
    end)

    it("should produce error when sequence contains a non integer", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30\x03\x04\x01\x40")
      end, "Sequence did not contain integers")
    end)

    it("should not allow multi-byte lengths for integers in sequence", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30\x02\x02\xFF")
      end, "Multi-byte lengths are not supported.")
    end)

    it("should produce error when integer's length is beyond string length", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30\x03\x02\x40\x00")
      end, "Integer is longer than remaining length")
    end)

    it("should produce error when extra data", function()
      assert.has_error(function()
        asn_sequence.parse_simple_sequence("\x30\x04\x02\x01\x00\x00")
      end, "Sequence did not contain integers")
    end)
  end)
end)
