local type = type
local fmt = string.format
local find = string.find
local pcall = pcall
local remove = table.remove
local concat = table.concat
local assert = assert
local tonumber = tonumber
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local strip = require("kong.tools.string").strip
local split = require("kong.tools.string").split
local get_rand_bytes = require("kong.tools.rand").get_rand_bytes


local ENABLED_ALGORITHMS = {
  ARGON2 = false,
  BCRYPT = false,
  PBKDF2 = true,
  SCRYPT = false,
}

--local CORES
--do
--  local infos = utils.get_system_infos()
--  if type(infos) == "table" then
--    CORES = infos.cores
--  end
--  if not CORES then
--    CORES = ngx.worker.count() or 1
--  end
--end


local function infer(value)
  value = strip(value)
  return tonumber(value, 10) or value
end


local function parse_phc(phc)
  local parts = split(phc, "$")
  local count = #parts
  if count < 2 or count > 5 then
    return nil, "invalid phc string format"
  end

  local id = parts[2]
  local id_parts = split(id, "-")
  local id_count = #id_parts

  local prefix
  local digest
  if id_count == 1 then
    prefix = id_parts[1]
  else
    prefix = id_parts[1]
    remove(id_parts, 1)
    digest = concat(id_parts, "-")
  end

  local params = {}
  local prms = parts[3]
  if prms then
    local prm_parts = split(prms, ",")
    for i = 1, #prm_parts do
      local param = prm_parts[i]
      local kv = split(param, "=")
      local kv_count = #kv
      if kv_count == 1 then
        params[#params + 1] = infer(kv[1])
      elseif kv_count == 2 then
        local k = strip(kv[1])
        params[k] = infer(kv[2])
      else
        return nil, "invalid phc string format for parameter"
      end
    end
  end

  local salt = parts[4]
  if salt then
    local decoded_salt = decode_base64(salt)
    if decoded_salt then
      salt = decoded_salt
    end
  end

  local hash = parts[5]
  if hash then
    local decoded_hash = decode_base64(hash)
    if decoded_hash then
      hash = decoded_hash
    end
  end

  return {
    id     = strip(id),
    prefix = strip(prefix),
    digest = strip(digest),
    params = params,
    salt   = salt,
    hash   = hash,
  }
end


local PREFIX = nil -- currently chosen algorithm (nil means that we try to find one)


local ARGON2
local ARGON2_ID = "$argon2"
if ENABLED_ALGORITHMS.ARGON2 then
  local ARGON2_PREFIX
  local ok, crypt = pcall(function()
    local argon2 = require "argon2"

    -- argon2 settings
    local ARGON2_VARIANT     = argon2.variants.argon2_id
    local ARGON2_PARALLELISM = 1 --CORES
    local ARGON2_T_COST      = 1
    local ARGON2_M_COST      = 4096
    local ARGON2_HASH_LEN    = 32
    local ARGON2_SALT_LEN    = 16

    local ARGON2_OPTIONS = {
      variant     = ARGON2_VARIANT,
      parallelism = ARGON2_PARALLELISM,
      hash_len    = ARGON2_HASH_LEN,
      t_cost      = ARGON2_T_COST,
      m_cost      = ARGON2_M_COST,
    }
    do
      local hash = argon2.hash_encoded("", get_rand_bytes(ARGON2_SALT_LEN), ARGON2_OPTIONS)
      local parts = split(hash, "$")
      remove(parts)
      remove(parts)
      ARGON2_PREFIX = concat(parts, "$")
    end

    local crypt = {}

    function crypt.hash(secret)
      return argon2.hash_encoded(secret, get_rand_bytes(ARGON2_SALT_LEN), ARGON2_OPTIONS)
    end

    function crypt.verify(secret, hash)
      return argon2.verify(hash, secret)
    end

    return crypt
  end)

  if ok then
    ARGON2 = crypt
    PREFIX = PREFIX or ARGON2_PREFIX
  end
end


local BCRYPT
local BCRYPT_ID = "$2"
if ENABLED_ALGORITHMS.BCRYPT then
  local BCRYPT_PREFIX
  local ok, crypt = pcall(function()
    local bcrypt = require "bcrypt"

    -- bcrypt settings
    local BCRYPT_ROUNDS = 12

    do
      local hash = bcrypt.digest("", BCRYPT_ROUNDS)
      local parts = split(hash, "$")
      remove(parts)
      BCRYPT_PREFIX = concat(parts, "$")
    end

    local crypt = {}

    function crypt.hash(secret)
      return bcrypt.digest(secret, BCRYPT_ROUNDS)
    end

    function crypt.verify(secret, hash)
      return bcrypt.verify(secret, hash)
    end

    return crypt
  end)

  if ok then
    BCRYPT = crypt
    PREFIX = PREFIX or BCRYPT_PREFIX
  end
end


local PBKDF2
local PBKDF2_ID = "$pbkdf2"
if ENABLED_ALGORITHMS.PBKDF2 then
  local PBKDF2_PREFIX

  local ok, crypt = pcall(function()
    local openssl_kdf = require "resty.openssl.kdf"

    -- pbkdf2 default settings
    local PBKDF2_DIGEST     = "sha512"
    local PBKDF2_ITERATIONS = 10000
    local PBKDF2_HASH_LEN   = 32
    local PBKDF2_SALT_LEN   = 16

    local EMPTY  = {}

    local kdf

    local function derive(secret, opts)
      opts = opts or EMPTY
      local err
      if kdf then
        local _, err = kdf:reset()
        if err then
          kdf = nil
        end
      end

      if not kdf then
        kdf, err = openssl_kdf.new("PBKDF2")
        if err then
          return nil, err
        end
      end

      local salt = opts.salt or get_rand_bytes(PBKDF2_SALT_LEN)
      local hash, err = kdf:derive(opts.outlen or PBKDF2_HASH_LEN, {
        pass        = secret,
        salt        = salt,
        digest      = opts.digest or PBKDF2_DIGEST,
        iter        = opts.iter   or PBKDF2_ITERATIONS,
      }, 4)
      if not hash then
        return nil, err
      end

      local HASH = encode_base64(hash, true)
      local SALT = encode_base64(salt, true)

      return fmt("%s-%s$i=%u,l=%u$%s$%s",
                 PBKDF2_ID, PBKDF2_DIGEST,
                 PBKDF2_ITERATIONS, PBKDF2_HASH_LEN,
                 SALT, HASH)
    end

    do
      local hash = derive("")
      local parts = split(hash, "$")
      remove(parts)
      remove(parts)
      PBKDF2_PREFIX = concat(parts, "$")
    end

    local crypt = {}

    function crypt.hash(secret, options)
      return derive(secret, options)
    end

    function crypt.verify(secret, hash)
      local phc, err = parse_phc(hash)
      if not phc then
        return nil, err
      end

      local outlen = phc.params.l
      if not outlen and phc.hash then
        outlen = #phc.hash
      end

      local calculated_hash, err = derive(secret, {
        outlen      = outlen,
        salt        = phc.salt,
        digest      = phc.digest,
        iter        = phc.params.i
      })
      if not calculated_hash then
        return nil, err
      end

      return calculated_hash == hash
    end

    return crypt
  end)


  if ok then
    PBKDF2 = crypt
    PREFIX = PREFIX or PBKDF2_PREFIX
  end
end


local crypt = {}


function crypt.hash(secret, options)
  assert(type(secret) == "string", "secret needs to be a string")

  if ARGON2 then
    return ARGON2.hash(secret)
  end

  if BCRYPT then
    return BCRYPT.hash(secret)
  end

  if PBKDF2 then
    return PBKDF2.hash(secret, options)
  end

  return nil, "no suitable password hashing algorithm found"
end


function crypt.verify(secret, hash)
  if type(secret) ~= "string" then
    return false, "secret needs to be a string"
  end

  if type(hash) ~= "string" then
    return false, "hash needs to be a string"
  end

  if ARGON2 and find(hash, ARGON2_ID, 1, true) == 1 then
    return ARGON2.verify(secret, hash)
  end

  if BCRYPT and find(hash, BCRYPT_ID, 1, true) == 1 then
    return BCRYPT.verify(secret, hash)
  end

  if PBKDF2 and find(hash, PBKDF2_ID, 1, true) == 1 then
    return PBKDF2.verify(secret, hash)
  end

  return false, "no suitable password hashing algorithm found"
end


function crypt.needs_rehash(hash)
  if type(hash) ~= "string" then
    return true
  end

  if PREFIX then
    return find(hash, PREFIX, 1, true) ~= 1
  end

  return true
end


return crypt
