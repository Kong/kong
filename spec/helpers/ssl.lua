local ffi = require "ffi"
local C = ffi.C
local bit = require "bit"
local format_error = require("resty.openssl.err").format_error
local BORINGSSL = require("resty.openssl.version").BORINGSSL
require "resty.openssl.include.ssl"

ffi.cdef [[
  typedef struct ssl_method_st SSL_METHOD;
  const SSL_METHOD *TLS_method(void);
  const SSL_METHOD *TLS_server_method(void);

  SSL_CTX *SSL_CTX_new(const SSL_METHOD *method);
  void SSL_CTX_free(SSL_CTX *ctx);

  int SSL_CTX_use_certificate_chain_file(SSL_CTX *ctx, const char *file);
  int SSL_CTX_use_PrivateKey_file(SSL_CTX *ctx, const char *file, int type);

  SSL *SSL_new(SSL_CTX *ctx);
  void SSL_free(SSL *s);

  long SSL_ctrl(SSL *ssl, int cmd, long larg, void *parg);
  long SSL_set_mode(SSL *ssl, long mode);

  int SSL_set_fd(SSL *ssl, int fd);

  void SSL_set_accept_state(SSL *ssl);

  int SSL_do_handshake(SSL *ssl);
  int SSL_get_error(const SSL *ssl, int ret);

  int SSL_read(SSL *ssl, void *buf, int num);
  int SSL_write(SSL *ssl, const void *buf, int num);
  int SSL_shutdown(SSL *ssl);


  typedef struct pollfd {
      int   fd;         /* file descriptor */
      short events;     /* requested events */
      short revents;    /* returned events */
  } pollfd;

  int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]


local SSL = {}
local ssl_mt = { __index = SSL }

local modes = {
  SSL_MODE_ENABLE_PARTIAL_WRITE = 0x001,
  SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER = 0x002,
  SSL_MODE_AUTO_RETRY = 0x004,
  SSL_MODE_NO_AUTO_CHAIN = 0x008,
  SSL_MODE_RELEASE_BUFFERS = 0x010,
  SSL_MODE_SEND_CLIENTHELLO_TIME = 0x020,
  SSL_MODE_SEND_SERVERHELLO_TIME = 0x040,
  SSL_MODE_SEND_FALLBACK_SCSV = 0x080,
  SSL_MODE_ASYNC = 0x100,
  SSL_MODE_DTLS_SCTP_LABEL_LENGTH_BUG = 0x400,
}

local errors = {
  SSL_ERROR_NONE = 0,
  SSL_ERROR_SSL = 1,
  SSL_ERROR_WANT_READ = 2,
  SSL_ERROR_WANT_WRITE = 3,
  SSL_ERROR_WANT_X509_LOOKUP = 4,
  SSL_ERROR_SYSCALL = 5,
  SSL_ERROR_ZERO_RETURN = 6,
  SSL_ERROR_WANT_CONNECT = 7,
  SSL_ERROR_WANT_ACCEPT = 8,
  SSL_ERROR_WANT_ASYNC = 9,
  SSL_ERROR_WANT_ASYNC_JOB = 10,
  SSL_ERROR_WANT_CLIENT_HELLO_CB = 11,
  SSL_ERROR_WANT_RETRY_VERIFY = 12,
}

local errors_literal = {}
for k, v in pairs(errors) do
  errors_literal[v] = k
end

local SOCKET_INVALID = -1


local ssl_set_mode
if BORINGSSL then
  ssl_set_mode = function(...) return C.SSL_set_mode(...) end
else
  local SSL_CTRL_MODE = 33
  ssl_set_mode = function(ctx, mode) return C.SSL_ctrl(ctx, SSL_CTRL_MODE, mode, nil) end
end

local SSL_FILETYPE_PEM = 1

local function ssl_ctx_new(cfg)
  if cfg.protocol and cfg.protocol ~= "any" then
    return nil, "protocol other than 'any' is currently not supported"
  elseif cfg.mode and cfg.mode ~= "server" then
    return nil, "mode other than 'server' is currently not supported"
  end
  cfg.protocol = nil
  cfg.mode = nil

  local ctx = C.SSL_CTX_new(C.TLS_server_method())
  if ctx == nil then
    return nil, format_error("SSL_CTX_new")
  end
  ffi.gc(ctx, C.SSL_CTX_free)

  for k, v in pairs(cfg) do
    if k == "certificate" then
      if C.SSL_CTX_use_certificate_chain_file(ctx, v) ~= 1 then
        return nil, format_error("SSL_CTX_use_certificate_chain_file")
      end
    elseif k == "key" then -- password protected key is NYI
      if C.SSL_CTX_use_PrivateKey_file(ctx, v, SSL_FILETYPE_PEM) ~= 1 then
        return nil, format_error("SSL_CTX_use_PrivateKey_file")
      end
    else
      return nil, "unknown option \"" .. k .. "\""
    end
  end

  return ctx
end

local function ssl_new(ssl_ctx)
  if not ssl_ctx or not ffi.istype("SSL_CTX*", ssl_ctx) then
    return nil, "ssl_new: expect SSL_CTX* as first argument"
  end

  local ctx = C.SSL_new(ssl_ctx)
  if ctx == nil then
    return nil, format_error("SSL_new")
  end
  ffi.gc(ctx, C.SSL_free)

  C.SSL_set_fd(ctx, SOCKET_INVALID)
  ssl_set_mode(ctx, bit.bor(modes.SSL_MODE_ENABLE_PARTIAL_WRITE,
                    modes.SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER))
  ssl_set_mode(ctx, modes.SSL_MODE_RELEASE_BUFFERS)

  C.SSL_set_accept_state(ctx) -- me is server

  return ctx
end

function SSL.wrap(sock, cfg)
  local ctx, err
   if type(cfg) == "table" then
      ctx, err = ssl_ctx_new(cfg)
      if not ctx then return nil, err end
   else
      ctx = cfg
   end
   local s, err = ssl_new(ctx)
   if s then
    local fd = sock:getfd()
    C.SSL_set_fd(s, fd)
    sock:setfd(SOCKET_INVALID)

    local self = setmetatable({
      ssl_ctx = ctx,
      ctx = s,
      fd = fd,
    }, ssl_mt)
  
    return self, nil
   end
   return nil, err 
end

local function socket_waitfd(fd, events, timeout)
  local pfd = ffi.new("pollfd")
  pfd.fd = fd
  pfd.events = events
  pfd.revents = 0
  local ppfd = ffi.new("pollfd[1]", pfd)

  local wait = timeout and 1 or -1

  while true do
    local ret = C.poll(ppfd, 1, wait)
    timeout = timeout and timeout - 1
    if ret ~= -1 then
      break
    end
  end
end

local POLLIN = 1
local POLLOUT = 2

local function handle_ssl_io(self, cb, ...)
  local err, code
  while true do
    err = cb(self.ctx, ...)
    code = C.SSL_get_error(self.ctx, err)
    if code == errors.SSL_ERROR_NONE then
      break
    elseif code == errors.SSL_ERROR_WANT_READ then
      err = socket_waitfd(self.fd, POLLIN, 10)
      if err then return nil, "want read: " .. err end
    elseif code == errors.SSL_ERROR_WANT_WRITE then
      err = socket_waitfd(self.fd, POLLOUT, 10)
      if err then return nil, "want write: " .. err end
    elseif code == errors.SSL_ERROR_SYSCALL then
      if err == 0 then
        return nil, "closed"
      end
      if C.ERR_peek_error() then
        return nil, format_error("SSL_ERROR_SYSCALL")
      end
    else
      return nil, errors_literal[code] or "unknown error"
    end
  end
end

function SSL:dohandshake()
  return handle_ssl_io(self, C.SSL_do_handshake)
end


function SSL:receive(pattern)
  if pattern and pattern ~= "*l" then
    return nil, "receive pattern other than '*l' is currently not supported"
  end

  local buf = ffi.new("char[1024]")
  local ret = ""

  while true do
    local ok, err = handle_ssl_io(self, C.SSL_read, ffi.cast("void *", buf), 1024)
    if err then
      if err == "SSL_ERROR_ZERO_RETURN" then
        err = "closed"
      end
      return ok, err
    end

    local current = ffi.string(buf)
    -- do we need to find \r?
    local pos = current:find("\n")
    if pos then -- found a newline
      ret = ret .. current:sub(1, pos-1)
      break
    else
      ret = ret .. current
    end
  end

  return ret
end

function SSL:send(s)
  local buf = ffi.new("char[?]", #s+1, s)
  local ok, err = handle_ssl_io(self, C.SSL_write, ffi.cast("void *", buf), #s)
  if err then
    return ok, err
  end

  return true
end

function SSL:close()
  if C.SSL_shutdown(self.ctx) ~= 1 then
    return nil, format_error("SSL_shutdown")
  end
  return true
end

return SSL
