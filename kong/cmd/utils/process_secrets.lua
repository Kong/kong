local b64 = require "ngx.base64"
local cjson = require "cjson.safe"
local file = require "pl.file"
local path = require "pl.path"
local cipher = require "resty.openssl.cipher"
local digest = require "resty.openssl.digest"
local rand = require "resty.openssl.rand"


local fmt = string.format
local sub = string.sub
local type = type
local pairs = pairs


local CIPHER_ALG = "aes-256-gcm"
local DIGEST_ALG = "sha256"
local IV_SIZE = 12
local TAG_SIZE = 16
local AAD = fmt("%s|%s", CIPHER_ALG, DIGEST_ALG)


local function read_key_data(key_data_path)
  if not path.exists(key_data_path) then
    return nil, fmt("failed to read key data (%s): file not found", key_data_path)
  end

  local key_data, err = file.read(key_data_path, true)
  if not key_data then
    return nil, fmt("failed to read key data file: %s", err)
  end

  return key_data
end


local function hash_key_data(key_data)
  local hash, err = digest.new(DIGEST_ALG)
  if not hash then
    return nil, fmt("unable to initialize digest (%s)", err)
  end

  local ok
  ok, err = hash:update(key_data)
  if not ok then
    return nil, fmt("unable to update digest (%s)", err)
  end

  local key
  key, err = hash:final()
  if not key then
    return nil, fmt("unable to create digest (%s)", err)
  end

  return key
end


local function extract(conf)
  local refs = conf["$refs"]
  if not refs or type(refs) ~= "table" then
    return
  end

  local secrets = {}
  for k in pairs(refs) do
    secrets[k] = conf[k]
  end

  return secrets
end


local function encrypt(plaintext, key_data)
  local key, err = hash_key_data(key_data)
  if not key then
    return nil, err
  end

  local iv
  iv, err = rand.bytes(IV_SIZE)
  if not iv then
    return nil, fmt("unable to generate initialization vector (%s)", err)
  end

  local cip, err = cipher.new(CIPHER_ALG)
  if not cip then
    return nil, fmt("unable to initialize cipher (%s)", err)
  end

  local ciphertext
  ciphertext, err = cip:encrypt(key, iv, plaintext, false, AAD)
  if not ciphertext then
    return nil, fmt("unable to encrypt (%s)", err)
  end

  local tag
  tag, err = cip:get_aead_tag(TAG_SIZE)
  if not tag then
    return nil, fmt("unable to get authentication tag (%s)", err)
  end

  return iv .. tag .. ciphertext
end


local function decrypt(ciphertext, key_data)
  local key, err = hash_key_data(key_data)
  if not key then
    return nil, err
  end

  local iv = sub(ciphertext, 1, IV_SIZE)
  local tag = sub(ciphertext, IV_SIZE + 1, IV_SIZE + TAG_SIZE)

  ciphertext = sub(ciphertext, IV_SIZE + TAG_SIZE + 1)

  local cip, err = cipher.new(CIPHER_ALG)
  if not cip then
    return nil, fmt("unable to initialize cipher (%s)", err)
  end

  local plaintext
  plaintext, err = cip:decrypt(key, iv, ciphertext, false, AAD, tag)
  if not plaintext then
    return nil, fmt("unable to decrypt (%s)", err)
  end

  return plaintext
end


local function serialize(input, key_data_path)
  local output, err = cjson.encode(input)
  if not output then
    return nil, fmt("failed to json encode process secrets: %s", err)
  end

  if key_data_path then
    local key_data
    key_data, err = read_key_data(key_data_path)
    if not key_data then
      return nil, err
    end

    output, err = encrypt(output, key_data)
    if not output then
      return nil, fmt("failed to encrypt process secrets: %s", err)
    end
  end

  output, err = b64.encode_base64url(output)
  if not output then
    return nil, fmt("failed to base64 encode process secrets: %s", err)
  end

  return output
end


local function deserialize(input, key_data_path)
  local output, err = b64.decode_base64url(input)
  if not output then
    return nil, fmt("failed to base64 decode process secrets: %s", err)
  end

  if key_data_path then
    local key_data
    key_data, err = read_key_data(key_data_path)
    if not key_data then
      return nil, err
    end

    output, err = decrypt(output, key_data)
    if not output then
      return nil, fmt("failed to decrypt process secrets: %s", err)
    end
  end

  output, err = cjson.decode(output)
  if not output then
    return nil, fmt("failed to json decode process secrets: %s", err)
  end

  return output
end


return {
  extract = extract,
  encrypt = encrypt,
  decrypt = decrypt,
  serialize = serialize,
  deserialize = deserialize,
}
