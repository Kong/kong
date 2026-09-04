local splitn = require("kong.tools.string").splitn
local isplitn = require("kong.tools.string").isplitn
local split_once = require("kong.tools.string").split_once
local inspect = require "inspect"


local it = it
local same = assert.same
local equal = assert.equal
local select = select
local ipairs = ipairs
local describe = describe


local TEST_MATRIX = {
  --inp-------pat---max--out------------------------
  { nil,      nil,  nil, {                      } },
  { nil,      nil,   -1, {                      } },
  { nil,      nil,    0, {                      } },
  { nil,      nil,    1, {                      } },
  { nil,      nil,    2, {                      } },
  { nil,      nil,    3, {                      } },
  --
  { "",       nil,  nil, { ""                   } },
  { "",       nil,   -1, {                      } },
  { "",       nil,    0, {                      } },
  { "",       nil,    1, { ""                   } },
  { "",       nil,    2, { ""                   } },
  { "",       nil,    3, { ""                   } },
  --
  { nil,       "",  nil, {                      } },
  { nil,       "",   -1, {                      } },
  { nil,       "",    0, {                      } },
  { nil,       "",    1, {                      } },
  { nil,       "",    2, {                      } },
  { nil,       "",    3, {                      } },
  --
  { "",        "",  nil, { "", ""               } },
  { "",        "",   -1, {                      } },
  { "",        "",    0, {                      } },
  { "",        "",    1, { ""                   } },
  { "",        "",    2, { "", ""               } },
  { "",        "",    3, { "", ""               } },
  --
  { "a",      nil,  nil, { "a"                  } },
  { "a",      nil,   -1, {                      } },
  { "a",      nil,    0, {                      } },
  { "a",      nil,    1, { "a"                  } },
  { "a",      nil,    2, { "a"                  } },
  { "a",      nil,    3, { "a"                  } },
  --
  { "a",       "",  nil, { "", "a", ""          } },
  { "a",       "",   -1, {                      } },
  { "a",       "",    0, {                      } },
  { "a",       "",    1, { "a"                  } },
  { "a",       "",    2, { "", "a"              } },
  { "a",       "",    3, { "", "a", ""          } },
  { "a",       "",    4, { "", "a", ""          } },
  --
  { nil,      "a",  nil, {                      } },
  { nil,      "a",   -1, {                      } },
  { nil,      "a",    0, {                      } },
  { nil,      "a",    1, {                      } },
  { nil,      "a",    2, {                      } },
  { nil,      "a",    3, {                      } },
  --
  { "",       "a",  nil, { ""                   } },
  { "",       "a",   -1, {                      } },
  { "",       "a",    0, {                      } },
  { "",       "a",    1, { ""                   } },
  { "",       "a",    2, { ""                   } },
  { "",       "a",    3, { ""                   } },
  { "",       "a",    4, { ""                   } },
  --
  { "ab",     nil,  nil, { "ab"                 } },
  { "ab",     nil,   -1, {                      } },
  { "ab",     nil,    0, {                      } },
  { "ab",     nil,    1, { "ab"                 } },
  { "ab",     nil,    2, { "ab"                 } },
  { "ab",     nil,    3, { "ab"                 } },
  --
  { "ab",      "", nil, { "", "a", "b", ""      } },
  { "ab",      "",  -1, {                       } },
  { "ab",      "",   0, {                       } },
  { "ab",      "",   1, { "ab"                  } },
  { "ab",      "",   2, { "", "ab"              } },
  { "ab",      "",   3, { "", "a", "b"          } },
  { "ab",      "",   4, { "", "a", "b", ""      } },
  { "ab",      "",   5, { "", "a", "b", ""      } },
  --
  { "abc",    nil, nil, { "abc"                 } },
  { "abc",    nil,  -1, {                       } },
  { "abc",    nil,   0, {                       } },
  { "abc",    nil,   1, { "abc"                 } },
  { "abc",    nil,   2, { "abc"                 } },
  { "abc",    nil,   3, { "abc"                 } },
  --
  { "abc",     "", nil, { "", "a", "b", "c", "" } },
  { "abc",     "",  -1, {                       } },
  { "abc",     "",   0, {                       } },
  { "abc",     "",   1, { "abc"                 } },
  { "abc",     "",   2, { "", "abc"             } },
  { "abc",     "",   3, { "", "a", "bc"         } },
  { "abc",     "",   4, { "", "a", "b", "c"     } },
  { "abc",     "",   5, { "", "a", "b", "c", "" } },
  { "abc",     "",   6, { "", "a", "b", "c", "" } },
  --
  { "a,b",    ",", nil, { "a", "b"              } },
  { "a,b",    ",",  -1, {                       } },
  { "a,b",    ",",   0, {                       } },
  { "a,b",    ",",   1, { "a,b"                 } },
  { "a,b",    ",",   2, { "a", "b"              } },
  { "a,b",    ",",   3, { "a", "b"              } },
  --
  { "a,b,c",  ",", nil, { "a", "b", "c"         } },
  { "a,b,c",  ",",  -1, {                       } },
  { "a,b,c",  ",",   0, {                       } },
  { "a,b,c",  ",",   1, { "a,b,c"               } },
  { "a,b,c",  ",",   2, { "a", "b,c"            } },
  { "a,b,c",  ",",   3, { "a", "b", "c"         } },
  { "a,b,c",  ",",   4, { "a", "b", "c"         } },
  --
  { ",b,c",   ",", nil, { "", "b", "c"          } },
  { ",b,c",   ",",  -1, {                       } },
  { ",b,c",   ",",   0, {                       } },
  { ",b,c",   ",",   1, { ",b,c"                } },
  { ",b,c",   ",",   2, { "", "b,c"             } },
  { ",b,c",   ",",   3, { "", "b", "c"          } },
  { ",b,c",   ",",   4, { "", "b", "c"          } },
  --
  { "a,b,",   ",", nil, { "a", "b", ""          } },
  { "a,b,",   ",",  -1, {                       } },
  { "a,b,",   ",",   0, {                       } },
  { "a,b,",   ",",   1, { "a,b,"                } },
  { "a,b,",   ",",   2, { "a", "b,"             } },
  { "a,b,",   ",",   3, { "a", "b", ""          } },
  { "a,b,",   ",",   4, { "a", "b", ""          } },
  --
  { ",b,",    ",", nil, { "", "b", ""           } },
  { ",b,",    ",",  -1, {                       } },
  { ",b,",    ",",   0, {                       } },
  { ",b,",    ",",   1, { ",b,"                 } },
  { ",b,",    ",",   2, { "", "b,"              } },
  { ",b,",    ",",   3, { "", "b", ""           } },
  { ",b,",    ",",   4, { "", "b", ""           } },
  --
  { "////",  "//", nil, { "", "", ""            } },
  { "////",  "//",  -1, {                       } },
  { "////",  "//",   0, {                       } },
  { "////",  "//",   1, { "////"                } },
  { "////",  "//",   2, { "", "//"              } },
  { "////",  "//",   3, { "", "", ""            } },
  { "////",  "//",   4, { "", "", ""            } },
}


local function fn(f, ...)
  local c = select("#", ...)
  local m = f .. "("
  for i = 1, c do
    local v = inspect((select(i, ...)))
    m = m .. (i > 1 and ", " .. v or v)
  end
  return m  .. ")"
end


describe("kong.tools.string:", function()
  for _, t in ipairs(TEST_MATRIX) do
    local test = fn("splitn", t[1], t[2], t[3])
    it(test, function()
      local r, c = splitn(t[1], t[2], t[3])
      same(t[4], r, test)
      equal(#t[4], c, test)
    end)
  end
  it("splitn (long string special cases)", function()
    local v = ("abcdefghij"):rep(10) .. "a" -- 101 chars in total
    local r, c = splitn(v, nil, nil)
    same({ v }, r)
    equal(1, #r)
    equal(1, c)
    local r, c = splitn(v, "", nil)
    equal(nil,   r[0])
    equal("",    r[1])
    equal("a",   r[2])
    equal("j",   r[101])
    equal("a",   r[102])
    equal("",    r[103])
    equal(nil,   r[104])
    equal(103,   c)
    local r, c = splitn(v, "", 100)
    equal(nil,   r[0])
    equal("",    r[1])
    equal("a",   r[2])
    equal("h",   r[99])
    equal("ija", r[100])
    equal(nil,   r[101])
    equal(100,   c)
    local r, c = splitn(v, "", 101)
    equal(nil,   r[0])
    equal("",    r[1])
    equal("a",   r[2])
    equal("ja",  r[101])
    equal(nil,   r[102])
    equal(101,   c)
    local r, c = splitn(v, "", 102)
    equal(nil,   r[0])
    equal("",    r[1])
    equal("a",   r[2])
    equal("j",   r[101])
    equal("a",   r[102])
    equal(nil,   r[103])
    equal(102,   c)
    local r, c = splitn(v, "", 103)
    equal(nil,   r[0])
    equal("",    r[1])
    equal("a",   r[2])
    equal("j",   r[101])
    equal("a",   r[102])
    equal("",    r[103])
    equal(nil,   r[104])
    equal(103,   c)
    local r, c = splitn(v, "", 104)
    equal(nil,   r[0])
    equal("",    r[1])
    equal("a",   r[2])
    equal("j",   r[101])
    equal("a",   r[102])
    equal("",    r[103])
    equal(nil,   r[104])
    equal(103,   c)
  end)
  for _, t in ipairs(TEST_MATRIX) do
    local r, c = splitn(t[1], t[2], t[3])
    local test = fn("isplitn", t[1], t[2], t[3])
    it(test, function()
      local i = 0
      for v in isplitn(t[1], t[2], t[3]) do
        i =  i + 1
        equal(r[i], v, test)
      end
      equal(c, i, test)
    end)
  end
  for _, t in ipairs(TEST_MATRIX) do
    if t[3] ~= 2 then
      goto continue
    end
    local r = splitn(t[1], t[2], t[3])
    local test = fn("split_once", t[1], t[2])
    it(test, function()
      local k, v = split_once(t[1], t[2])
      equal(r[1], k, test)
      equal(r[2], v, test)
    end)
::continue::
  end
end)
