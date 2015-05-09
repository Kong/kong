local reg = require "rex_pcre"

_G.ngx = {
  re = {
    match = reg.match
  }
}
