-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local digest = require "resty.openssl.digest"


local rand = math.random


local algs = {
  "S256",
  "S384",
  "S512",
}

local sha256, sha384, sha512
do
  local digests = {}

  local function h(alg, s)
    local _, bin, err
    if not digests[alg] then
      digests[alg], err = digest.new(alg)
      if err then
        return nil, err
      end
    end

    bin, err = digests[alg]:final(s)
    if err then
      digests[alg] = nil
      return nil, err
    end

    _, err = digests[alg]:reset()
    if err then
      digests[alg] = nil
    end

    return bin
  end

  function sha256(s)
    return h("sha256", s)
  end

  function sha384(s)
    return h("sha384", s)
  end

  function sha512(s)
    return h("sha512", s)
  end
end


local hash = {
  S256 = sha256,
  S384 = sha384,
  S512 = sha512,
}


local n = #algs


function hash.none(s)
  return s
end


function hash.random(s)
  return hash[algs[rand(n)]](s)
end


return hash
