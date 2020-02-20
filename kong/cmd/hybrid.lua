local log = require("kong.cmd.utils.log")
local pkey = require("resty.openssl.pkey")
local x509 = require("resty.openssl.x509")
local name = require("resty.openssl.x509.name")
local pl_file = require("pl.file")
local pl_path = require("pl.path")


local assert = assert
local tonumber = tonumber


local CERT_FILENAME = "./cluster.crt"
local KEY_FILENAME = "./cluster.key"
local DEFAULT_DURATION = 3 * 365 * 86400


local function generate_cert(duration, cert_file, key_file)
  if pl_file.access_time(cert_file) then
    error(cert_file .. " already exists.\nWill not overwrite it.")
  end

  if pl_file.access_time(key_file) then
    error(key_file .. " already exists.\nWill not overwrite it.")
  end

  local key = assert(pkey.new({
    type  = "EC",
    curve = "secp384r1",
  }))

  local crt = assert(x509.new())

  assert(crt:set_pubkey(key))

  local time = ngx.time()
  assert(crt:set_not_before(time))
  assert(crt:set_not_after(time + duration))

  local cn = assert(name.new())
  assert(cn:add("CN", "kong_clustering"))

  assert(crt:set_subject_name(cn))
  assert(crt:set_issuer_name(cn))

  assert(crt:sign(key))

  pl_file.write(cert_file, crt:to_PEM())
  pl_file.write(key_file, key:to_PEM("private"))

  os.execute("chmod 644 " .. cert_file)
  os.execute("chmod 600 " .. key_file)

  log("Successfully generated certificate/key pairs, " ..
      "they have been written to: '" .. cert_file .. "' and '" ..
      key_file .. "'.")
end


local function execute(args)
  if args.command == "gen_cert" then
    local day = args.d or args.days

    if #args ~= 0 and #args ~= 2 then
      error("both cert and key path needs to be provided")
    end

    local cert_file = args[1] or CERT_FILENAME
    local key_file = args[2] or KEY_FILENAME

    generate_cert(day and tonumber(day) * 86400 or DEFAULT_DURATION,
                  pl_path.abspath(cert_file),
                  pl_path.abspath(key_file))
    os.exit(0)
  end

  error("unknown command '" .. args.command .. "'")
end

local lapp = [[
Usage: kong hybrid COMMAND [OPTIONS]

Hybrid mode utilities for Kong.

The available commands are:
  gen_cert [<cert> <key>]           Generate a certificate/key pair that is suitable
                                    for use in hybrid mode deployment.
                                    Cert and key will be written to
                                    ']] .. CERT_FILENAME .. [[' and ']] ..
                                    KEY_FILENAME .. [[' inside
                                    the current directory unless filenames are given.

Options:
 -d,--days        (optional number) Override certificate validity duration.
                                    Default: 1095 days (3 years)
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    gen_cert = true,
  },
}
