package t::Util;

use strict;
use warnings;
use Cwd qw(cwd);

our $cwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_package_path \'$cwd/?/init.lua;;\';

    init_by_lua_block {
        local log = ngx.log
        local ERR = ngx.ERR

        local verbose = false
        -- local verbose = true
        local outfile = "$Test::Nginx::Util::ErrLogFile"
        if verbose then
            local dump = require "jit.dump"
            dump.on(nil, outfile)
        else
            local v = require "jit.v"
            v.on(outfile)
        end

        require "resty.core"
    }
_EOC_

1;
