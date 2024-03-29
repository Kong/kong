-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local codec       = require "kong.openid-connect.codec"


local sub         = string.sub
local find        = string.find
local type        = type
local byte        = string.byte
local concat      = table.concat
local tonumber    = tonumber
local tostring    = tostring
local rematch     = ngx.re.match
local decode_args = codec.args.decode
local encode_args = codec.args.encode
local encode_uri  = codec.uri.encode
local new_tab
local clr_tab


local SLASH = byte("/")
local COLON = byte(":")


-- see: https://tools.ietf.org/html/rfc3986#appendix-B
local REGEX_URI   = [[(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?]]
local REGEX_PORT  = [[[1-9]{1}\d{0,4}$]]
local AUTHORITIES = {
  ["gmail.com"]   = "accounts.google.com",
  ["google.com"]  = "accounts.google.com",
  ["yahoo.com"]   = "api.login.yahoo.com",
  ["outlook.com"] = "login.live.com",
  ["hotmail.com"] = "login.live.com",
  ["live.com"]    = "login.live.com",
  ["msn.com"]     = "login.live.com",
}


do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function()
      return {}
    end
  end

  ok, clr_tab = pcall(require, "table.clear")
  if not ok then
    local pairs = pairs
    clr_tab = function(tab)
      for k, _ in pairs(tab)
        do tab[k] = nil
      end
    end
  end
end


local function prefix(resource, c)
  local s = find(resource, c, nil, true)
  if s then
    return sub(resource, 1, s - 1)
  end

  return resource
end


local res = new_tab(9, 0)
local uri = {}


function uri.parse(s, max_args)
  clr_tab(res)

  local ok, err = rematch(tostring(s), REGEX_URI, "ajos", nil, res)
  if not ok then
    return nil, err
  end

  local scheme    = res[2] and res[2] ~= "" and res[2] or nil
  local authority = res[4] and res[4] ~= "" and res[4] or nil
  local path      = res[5] and res[5] ~= "" and res[5] or nil
  local query     = res[7] and res[7] ~= "" and res[7] or nil
  local fragment  = res[9] and res[9] ~= "" and res[9] or nil

  local userinfo, user, pass, host, port, args
  if authority then
    if byte(authority, -1) == COLON then
      authority = sub(authority, 1, -2)
    end

    if authority == "" then
      authority = nil
    end
  end

  if authority then
    local p = find(authority, "@", 2, true)
    if p then
      host = sub(authority, p + 1)
      if host == "" then
        host = nil
      end

      userinfo = sub(authority, 1, p - 1)
      p = find(userinfo, ":", 2, true)
      if p then
        user = sub(userinfo, 1, p - 1)
        pass = sub(userinfo, p + 1)

      else
        user = userinfo
      end

    else
      host = authority
    end

    if host then
      p = find(host, ":", 2, true)
      if p then
        port = sub(host, p + 1)
        host = sub(host, 1, p - 1)
        if rematch(port, REGEX_PORT, "adjo") then
          port = tonumber(port)
          if port < 1 or port > 65535 then
            port = nil
          end

        else
          port = nil
        end
      end
    end
  end

  if not port then
    if userinfo then
      authority = userinfo .. "@" .. host
    else
      authority = host
    end
  end

  if query then
    if max_args then
      args = decode_args(query, max_args)

    else
      args = decode_args(query)
    end
  end

  return {
    scheme    = scheme    ~= "" and scheme    or nil,
    authority = authority ~= "" and authority or nil,
    userinfo  = userinfo  ~= "" and userinfo  or nil,
    user      = user      ~= "" and user      or nil,
    pass      = pass      ~= "" and pass      or nil,
    host      = host      ~= "" and host      or nil,
    port      = port      ~= "" and port      or nil,
    path      = path      ~= "" and path      or nil,
    query     = query     ~= "" and query     or nil,
    args      = args      ~= "" and args      or nil,
    fragment  = fragment  ~= "" and fragment  or nil,
  }
end


function uri.create(options)
  local u, i = {}, 1

  local scheme    = options.scheme
  local authority = options.authority
  local user      = options.user
  local pass      = options.pass
  local host      = options.host
  local port      = options.port
  local path      = options.path
  local args      = options.args or options.query
  local fragment  = options.fragment

  local has_authority

  if scheme then
    scheme = tostring(scheme)
    if scheme ~= "" then
      u[i]   = scheme
      u[i+1] = ":"
      i=i+2
    end
  end

  if authority then
    authority = tostring(authority)
    if authority ~= "" then
      has_authority = true
      u[i]   = "//"
      u[i+1] = authority
      i=i+2
    end
  else
    if user then
      user = tostring(user)
      if user ~= "" then
        has_authority = true
        u[i] = "//"
        u[i+1] = user
        i=i+2
        if pass then
          pass = tostring(pass)
          if pass ~= "" then
            u[i] = ":"
            u[i+1] = pass
            i=i+2
          end
        end
        if host then
          host = tostring(host)
          if host ~= "" then
            u[i]   = "@"
            u[i+1] = host
            i=i+2
            if port then
              port = tostring(port)
              if port ~= "" then
                u[i]   = ":"
                u[i+1] = port
                i=i+2
              end
            end
          end
        end

      else
        if host then
          host = tostring(host)
          if host ~= "" then
            has_authority = true
            u[i] = host
            i=i+1
            if port then
              port = tostring(port)
              if port ~= "" then
                u[i]   = ":"
                u[i+1] = port
                i=i+2
              end
            end
          end
        end
      end

    elseif host then
      host = tostring(host)
      if host ~= "" then
        has_authority = true
        u[i] = "//"
        u[i+1] = host
        i=i+2
        if port then
          port = tostring(port)
          if port ~= "" then
            u[i]   = ":"
            u[i+1] = port
            i=i+2
          end
        end
      end
    end
  end

  if path then
    path = tostring(path)
    if path ~= "" then
      if has_authority then
        if sub(path, 1, 1) == "/" then
          u[i] = path
          i=i+1

        else
          u[i] = "/"
          u[i+1] = path
          i=i+2
        end

      else
        u[i] = path
        i=i+1
      end
    end
  end

  if args then
    if type(args) == "table" then
      args = encode_args(args)
      if args ~= "" then
        u[i]   = "?"
        u[i+1] = args
        i=i+2
      end

    else
      args = tostring(args)
      if args ~= "" then
        if sub(args, 1, 1) == "?" then
          u[i] = args
          i=i+1

        else
          u[i]   = "?"
          u[i+1] = args
          i=i+2
        end
      end
    end
  end

  if fragment then
    fragment = tostring(fragment)
    if fragment ~= "" then
      if sub(fragment, 1, 1) == "#" then
        u[i] = fragment

      else
        u[i]   = "#"
        u[i+1] = fragment
      end
    end
  end

  return concat(u)
end


function uri.normalize(url)
  if sub(url, 1, 5) == "acct:" and sub(url, 6, 7) ~= "//" then
    url = "acct://" .. sub(url, 6)
  end

  local p, err = uri.parse(url)
  if not p then
    return nil, err
  end

  local n
  if p.authority then
    n = p

  else
    n, err = uri.parse("//" .. url)
    if not n then
      return nil, err
    end
  end

  if p.scheme and p.scheme ~= "acct" and not n.port then
    return prefix(url, "#")
  end

  local normalized = {}

  if n.userinfo and n.host and not n.port and not n.path and not n.query and not n.fragment then
    normalized.scheme = "acct"
    normalized.path = encode_uri(n.userinfo) .. "@" .. n.host

  else
    if p.scheme == "http" then
      normalized.scheme    = "http"

    else
      normalized.scheme    = "https"
    end

    normalized.authority = n.authority
    normalized.path      = n.path
    normalized.query     = n.query
  end

  return uri.create(normalized)
end


function uri.webfinger(subject)
  local u = uri.normalize(subject)

  local p, err = uri.parse(u)
  if not p then
    return nil, err
  end

  if not p.authority then
    local host = p.path
    if host then
      local s = find(host, "@", 2, true)
      if s then
        host = sub(host, s + 1)
        if host == "" then
          host = nil
        end
      end
    end
    p.host = host or "localhost"
    p.path = nil
  end

  if p.userinfo and p.host and not p.port and not p.path and not p.query and not p.fragment then
    u = "acct:" .. encode_uri(p.userinfo) .. "@" .. p.host
  end

  p.authority = nil

  if p.scheme == "acct" then
    p.userinfo = nil
    p.user     = nil
    p.pass     = nil
  end

  if p.path then
    if byte(p.path, -1) == SLASH then
      p.path = p.path .. ".well-known/webfinger"

    else
      p.path = p.path .. "/.well-known/webfinger"
    end

  else
    p.path = "/.well-known/webfinger"
  end

  if p.scheme ~= "http" then
    p.scheme = "https"
  end

  p.args   = {
    rel      = "http://openid.net/specs/connect/1.0/issuer",
    resource = u,
  }

  return uri.create(p)
end

function uri.discover(issuer)
  local u = uri.normalize(issuer)

  local p, err = uri.parse(u)
  if not p then
    return nil, err
  end

  if not p.authority then
    local host = p.path
    if host then
      local s = find(host, "@", 2, true)
      if s then
        host = sub(host, s + 1)
        if host == "" then
          host = nil
        end
      end
    end
    p.host = host or "localhost"
    p.path = nil
  end

  p.authority = nil

  if p.scheme == "acct" then
    p.userinfo = nil
    p.user     = nil
    p.pass     = nil
  end

  if p.path then
    if  sub(p.path, -33) ~= "/.well-known/openid-configuration"
    and sub(p.path, -39) ~= "/.well-known/oauth-authorization-server"
    then
      if byte(p.path, -1) == SLASH then
        p.path = p.path .. ".well-known/openid-configuration"

      else
        p.path = p.path .. "/.well-known/openid-configuration"
      end
    end

  else
    p.path = "/.well-known/openid-configuration"
  end

  if p.scheme ~= "http" then
    p.scheme = "https"
  end

  if AUTHORITIES[p.host] then
    p.host = AUTHORITIES[p.host]
  end

  return uri.create(p)
end


return uri
