require "kong.tools.ngx_stub"

local jwt_parser = require "kong.plugins.jwt.jwt_parser"

local rs256_private_key = [[
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAw5mp3MS3hVLkHwB9lMrEx34MjYCmKeH/XeMLexNpTd1FzuNv
6rArovTY763CDo1Tp0xHz0LPlDJJtpqAgsnfDwCcgn6ddZTo1u7XYzgEDfS8J4SY
dcKxZiSdVTpb9k7pByXfnwK/fwq5oeBAJXISv5ZLB1IEVZHhUvGCH0udlJ2vadqu
R03phBHcvlNmMbJGWAetkdcKyi+7TaW7OUSjlge4WYERgYzBB6eJH+UfPjmw3aSP
ZcNXt2RckPXEbNrL8TVXYdEvwLJoJv9/I8JPFLiGOm5uTMEk8S4txs2efueg1Xyy
milCKzzuXlJvrvPA4u6HI7qNvuvkvUjQmwBHgwIDAQABAoIBAQCP3ZblTT8abdRh
xQ+Y/+bqQBjlfwk4ZwRXvuYz2Rwr7CMrP3eSq4785ZAmAaxo3aP4ug9bL23UN4Sm
LU92YxqQQ0faZ1xTHnp/k96SGKJKzYYSnuEwREoMscOS60C2kmWtHzsyDmhg/bd5
i6JCqHuHtPhsYvPTKGANjJrDf+9gXazArmwYrdTnyBeFC88SeRG8uH2lP2VyqHiw
ZvEQ3PkRRY0yJRqEtrIRIlgVDuuu2PhPg+MR4iqR1RONjDUFaSJjR7UYWY/m/dmg
HlalqpKjOzW6RcMmymLKaW6wF3y8lbs0qCjCYzrD3bZnlXN1kIw6cxhplfrSNyGZ
BY/qWytJAoGBAO8UsagT8tehCu/5smHpG5jgMY96XKPxFw7VYcZwuC5aiMAbhKDO
OmHxYrXBT/8EQMIk9kd4r2JUrIx+VKO01wMAn6fF4VMrrXlEuOKDX6ZE1ay0OJ0v
gCmFtKB/EFXXDQLV24pgYgQLxnj+FKFV2dQLmv5ZsAVcmBHSkM9PBdUlAoGBANFx
QPuVaSgRLFlXw9QxLXEJbBFuljt6qgfL1YDj/ANgafO8HMepY6jUUPW5LkFye188
J9wS+EPmzSJGxdga80DUnf18yl7wme0odDI/7D8gcTfu3nYcCkQzeykZNGAwEe+0
SvhXB9fjWgs8kFIjJIxKGmlMJRMHWN1qaECEkg2HAoGBAIb93EHW4as21wIgrsPx
5w8up00n/d7jZe2ONiLhyl0B6WzvHLffOb/Ll7ygZhbLw/TbAePhFMYkoTjCq++z
UCP12i/U3yEi7FQopWvgWcV74FofeEfoZikLwa1NkV+miUYskkVTnoRCUdJHREbE
PrYnx2AOLAEbAxItHm6vY8+xAoGAL85JBePpt8KLu+zjfximhamf6C60zejGzLbD
CgN/74lfRcoHS6+nVs73l87n9vpZnLhPZNVTo7QX2J4M5LHqGj8tvMFyM895Yv+b
3ihnFVWjYh/82Tq3QS/7Cbt+EAKI5Yzim+LJoIZ9dBkj3Au3eOolMym1QK2ppAh4
uVlJORsCgYBv/zpNukkXrSxVHjeZj582nkdAGafYvT0tEQ1u3LERgifUNwhmHH+m
1OcqJKpbgQhGzidXK6lPiVFpsRXv9ICP7o96FjmQrMw2lAfC7stYnFLKzv+cj8L9
h4hhNWM6i/DHXjPsHgwdzlX4ulq8M7dR8Oqm9DrbdAyWz8h8/kzsnA==
-----END RSA PRIVATE KEY-----
]]

local rs256_public_key = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw5mp3MS3hVLkHwB9lMrE
x34MjYCmKeH/XeMLexNpTd1FzuNv6rArovTY763CDo1Tp0xHz0LPlDJJtpqAgsnf
DwCcgn6ddZTo1u7XYzgEDfS8J4SYdcKxZiSdVTpb9k7pByXfnwK/fwq5oeBAJXIS
v5ZLB1IEVZHhUvGCH0udlJ2vadquR03phBHcvlNmMbJGWAetkdcKyi+7TaW7OUSj
lge4WYERgYzBB6eJH+UfPjmw3aSPZcNXt2RckPXEbNrL8TVXYdEvwLJoJv9/I8JP
FLiGOm5uTMEk8S4txs2efueg1XyymilCKzzuXlJvrvPA4u6HI7qNvuvkvUjQmwBH
gwIDAQAB
-----END PUBLIC KEY-----
]]

describe("JWT parser", function()
  describe("Encoding", function()
    it("should properly encode using HS256", function()
      local token = jwt_parser.encode({
        sub = "1234567890",
        name = "John Doe",
        admin = true
      }, "secret")
      assert.equal("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhZG1pbiI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwic3ViIjoiMTIzNDU2Nzg5MCJ9.eNK_fimsCW3Q-meOXyc_dnZHubl2D4eZkIcn6llniCk", token)
    end)
    it("should properly encode using RS256", function()
      local token = jwt_parser.encode({
        sub = "1234567890",
        name = "John Doe",
        admin = true
      }, rs256_private_key, 'RS256')
      assert.equal("eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhZG1pbiI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwic3ViIjoiMTIzNDU2Nzg5MCJ9.EiOLxyMimY8vbLR8EcGOlXAiEe-eEVn7Aewgu0gYIBPyiEhVTq0CzB_XtHoQ_0y4gBBBZVRnz1pgruOtNmOzcaoXnyplFm1IbrCCBKYQeA4lanmu_-Wzk6Dw4p-TimRHpf8EEHBUJSEbVEyet3cpozUo2Ep0dEfA_Nf3T-g8RjfOYXkFTr3M6FuIDq95cFZloH-DRGodUVQX508wgggtcFKN-Pi7_rWzBtQwP2u4CrFD4ZJbn2sxobzSlFb9fn4nRh_-rPPjDSeHVKwrpsYpFSLBJxwX-KhbeGUfalg2eu9tHLDPHC4gTCpoQKxxRIwfMjW5zlHOZhohKZV2ZtpcgA", token)
    end)
  end)
  describe("Decoding", function()
    it("should throw an error if not given a string", function()
      assert.has_error(function()
        jwt_parser:new()
      end, "JWT must be a string")
    end)
    it("should refuse invalid typ", function()
      local token = jwt_parser.encode({sub = "1234"}, "secret", nil, {typ = "foo"})
      local _, err = jwt_parser:new(token)
      assert.equal("Invalid typ", err)
    end)
    it("should refuse invalid alg", function()
      local token = jwt_parser.encode({sub = "1234"}, "secret", nil, {typ = "JWT", alg = "foo"})
      local _, err = jwt_parser:new(token)
      assert.equal("Invalid alg", err)
    end)
  end)
  describe("Verify signature", function()
    it("should verify a signature using HS256", function()
      local token = jwt_parser.encode({sub = "foo"}, "secret")
      local jwt, err = jwt_parser:new(token)
      assert.falsy(err)
      assert.True(jwt:verify_signature("secret"))
      assert.False(jwt:verify_signature("invalid"))
    end)
    it("should verify a signature using RS256", function()
      local token = jwt_parser.encode({sub = "foo"}, rs256_private_key, 'RS256')
      local jwt, err = jwt_parser:new(token)
      assert.falsy(err)
      assert.True(jwt:verify_signature(rs256_public_key))
      assert.False(jwt:verify_signature(rs256_public_key:gsub('QAB', 'zzz')))
    end)
  end)
  describe("Verify registered claims", function()
    it("should require claims passed as arguments", function()
      local token = jwt_parser.encode({sub = "foo"}, "secret")
      local jwt, err = jwt_parser:new(token)
      assert.falsy(err)
      local valid, errors = jwt:verify_registered_claims({"exp", "nbf"})
      assert.False(valid)
      assert.same({exp = "must be a number", nbf = "must be a number"}, errors)

      valid, errors = jwt:verify_registered_claims({"nbf"})
      assert.False(valid)
      assert.same({nbf = "must be a number"}, errors)
    end)
    it("should check the type of given registered claims", function()
      local token = jwt_parser.encode({exp = "bar", nbf = "foo"}, "secret")
      local jwt, err = jwt_parser:new(token)
      assert.falsy(err)
      local valid, errors = jwt:verify_registered_claims({"exp", "nbf"})
      assert.False(valid)
      assert.same({exp = "must be a number", nbf = "must be a number"}, errors)
    end)
    it("should check the exp claim", function()
      local token = jwt_parser.encode({exp = os.time()}, "secret")
      local jwt, err = jwt_parser:new(token)
      assert.falsy(err)
      local valid, errors = jwt:verify_registered_claims({"exp"})
      assert.False(valid)
      assert.same({exp = "token expired"}, errors)
    end)
    it("should check the nbf claim", function()
      local token = jwt_parser.encode({nbf = os.time() + 10}, "secret")
      local jwt, err = jwt_parser:new(token)
      assert.falsy(err)
      local valid, errors = jwt:verify_registered_claims({"nbf"})
      assert.False(valid)
      assert.same({nbf = "token not valid yet"}, errors)
    end)
  end)
end)
