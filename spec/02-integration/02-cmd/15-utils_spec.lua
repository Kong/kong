local signals = require "kong.cmd.utils.nginx_signals"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local shell = require "resty.shell"

describe("kong cli utils", function()

  describe("nginx_signals", function()

    describe("find_nginx_bin()", function()
      local tmpdir
      before_each(function()
        tmpdir = pl_path.tmpname()
        assert(os.remove(tmpdir))
      end)

      after_each(function()
        pcall(pl_dir.rmtree, tmpdir)
      end)

      local function fake_nginx_binary(version)
        local bin_dir = pl_path.join(tmpdir, "nginx/sbin")
        pl_dir.makepath(bin_dir)

        local nginx = pl_path.join(bin_dir, "nginx")
        pl_file.write(nginx, string.format(
          [[#!/bin/sh
echo 'nginx version: openresty/%s' >&2]], version
        ))

        assert(shell.run("chmod +x " .. nginx, nil, 0))

        return nginx
      end


      it("works with empty/unset input", function()
        local bin, err = signals.find_nginx_bin()
        assert.is_nil(err)
        assert.matches("sbin/nginx", bin)
        assert.truthy(pl_path.exists(bin))
      end)

      it("works when openresty_path is unset", function()
        local bin, err = signals.find_nginx_bin({})
        assert.is_nil(err)
        assert.matches("sbin/nginx", bin)
        assert.truthy(pl_path.exists(bin))
      end)

      it("prefers `openresty_path` when supplied", function()
        local meta = require "kong.meta"
        local version = meta._DEPENDENCIES.nginx[1]

        local nginx = fake_nginx_binary(version)

        local bin, err = signals.find_nginx_bin({ openresty_path = tmpdir })

        assert.is_nil(err)
        assert.equals(nginx, bin)
      end)

      it("returns nil+error if a compatible nginx bin is not found in `openresty_path`", function()
        fake_nginx_binary("1.0.1")
        local bin, err = signals.find_nginx_bin({ openresty_path = tmpdir })
        assert.is_nil(bin)
        assert.not_nil(err)
        assert.matches("could not find OpenResty", err)
      end)

    end)

  end)

end)
