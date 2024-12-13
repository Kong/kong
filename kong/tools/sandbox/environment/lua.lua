-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


return [[
_VERSION assert   error ipairs next   pairs pcall print select
tonumber tostring type  unpack xpcall

bit.arshift bit.band bit.bnot bit.bor    bit.bswap bit.bxor
bit.lshift  bit.rol  bit.ror  bit.rshift bit.tobit bit.tohex

coroutine.create coroutine.resume coroutine.running
coroutine.status coroutine.wrap   coroutine.yield

io.type

jit.os jit.arch jit.version jit.version_num

math.abs   math.acos math.asin  math.atan math.atan2 math.ceil
math.cos   math.cosh math.deg   math.exp  math.floor math.fmod
math.frexp math.huge math.ldexp math.log  math.log10 math.max
math.min   math.modf math.pi    math.pow  math.rad   math.random
math.sin   math.sinh math.sqrt  math.tan  math.tanh

os.clock os.date os.difftime os.time

string.byte    string.char string.find  string.format string.gmatch
string.gsub    string.len  string.lower string.match  string.rep
string.reverse string.sub  string.upper

table.clear table.clone  table.concat  table.foreach table.foreachi
table.getn  table.insert table.isarray table.isempty table.maxn
table.move  table.new    table.nkeys   table.pack    table.remove
table.sort  table.unpack
]]
