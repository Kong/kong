local signals = require "kong.cmd.utils.nginx_signals"
local process = require "kong.cmd.utils.process"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local pipe = require "ngx.pipe"

math.randomseed(ngx.worker.pid() + ngx.now())

describe("kong.cmd.utils.nginx_signals", function()
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

      assert(os.execute("chmod +x " .. nginx))

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

describe("kong.cmd.utils.process", function()
  local pid_file

  before_each(function()
    pid_file = assert.truthy(pl_path.tmpname())
  end)

  after_each(function()
    if pid_file and pl_path.exists(pid_file) then
      assert(os.remove(pid_file))
    end
  end)

  describe("guess_pid()", function()
    it("accepts a number", function()
      local pid, err = process.guess_pid(123)
      assert.is_nil(err)
      assert.equals(123, pid)
    end)

    it("accepts a pid filename", function()
      assert.truthy(pl_file.write(pid_file, "1234"))
      local pid, err = process.guess_pid(pid_file)
      assert.is_nil(err)
      assert.equals(1234, pid)
    end)

    it("accepts a pid as a numeric string", function()
      local pid, err = process.guess_pid("123")
      assert.is_nil(err)
      assert.equals(123, pid)
    end)

    it("prefers a pid file to a numeric string pid", function()
      local pid = 123
      local fname = "456"

      assert.truthy(pl_file.write(fname, tostring(pid)))
      finally(function()
        os.remove(fname)
      end)

      local got, err = process.guess_pid(fname)
      assert.is_nil(err)
      assert.equals(123, got)
    end)

    it("throws an error for non-number/non-string inputs", function()
      assert.has_errors(function()
        process.guess_pid(nil)
      end)

      assert.has_errors(function()
        process.guess_pid({})
      end)

      assert.has_errors(function()
        process.guess_pid(ngx.null)
      end)

      assert.has_errors(function()
        process.guess_pid(false)
      end)
    end)

    it("throws an error for values less than 1", function()
      assert.has_errors(function()
        process.guess_pid(-1)
      end)

      assert.has_errors(function()
        process.guess_pid(0)
      end)

      assert.truthy(pl_file.write(pid_file, "-1"))
      assert.has_errors(function()
        process.guess_pid(pid_file)
      end)

      assert.truthy(pl_file.write(pid_file, "0"))
      assert.has_errors(function()
        process.guess_pid(pid_file)
      end)
    end)
  end)

  describe("pid_from_file()", function()
    it("reads pid from a file", function()
      assert.truthy(pl_file.write(pid_file, "1234"))
      local pid, err = process.pid_from_file(pid_file)
      assert.is_nil(err)
      assert.equals(1234, pid)
    end)

    it("trims whitespace from the file contents", function()
      assert.truthy(pl_file.write(pid_file, "1234\n"))
      local pid, err = process.pid_from_file(pid_file)
      assert.is_nil(err)
      assert.equals(1234, pid)
    end)

    it("returns nil+error on filesystem errors", function()
      if pl_path.exists(pid_file) then
        assert.truthy(os.remove(pid_file))
      end

      local pid, err = process.pid_from_file(pid_file)
      assert.is_nil(pid)
      assert.is_string(err)
      assert.matches("No such file", err)
    end)

    it("returns nil+error if the pid file is empty", function()
      local pid, err = process.pid_from_file(pid_file)
      assert.is_nil(pid)
      assert.is_string(err)
      assert.matches("empty", err)

      -- whitespace trimming applies before empty check
      assert.truthy(pl_file.write(pid_file, "  \n"))
      pid, err = process.pid_from_file(pid_file)
      assert.is_nil(pid)
      assert.is_string(err)
      assert.matches("empty", err)
    end)

    it("returns nil+error if the pid file contents are invalid", function()
      assert.truthy(pl_file.write(pid_file, "not a pid\n"))
      local pid, err = process.pid_from_file(pid_file)
      assert.is_nil(pid)
      assert.is_string(err)
      assert.matches("does not contain a pid", err)
    end)
  end)

  describe("exists()", function()
    it("returns true for a pid of a running process", function()
      local exists, err = process.exists(ngx.worker.pid())
      assert.is_nil(err)
      assert.is_true(exists)
    end)

    it("returns true for a pid file of a running process", function()
      assert.truthy(pl_file.write(pid_file, tostring(ngx.worker.pid())))
      local exists, err = process.exists(pid_file)
      assert.is_nil(err)
      assert.is_true(exists)
    end)

    it("returns false for the pid of a non-existent process", function()
      local exists, err

      for _ = 1, 1000 do
        local pid = math.random(1000, 2^16)
        exists, err = process.exists(pid)
        if exists == false then
          break
        end
      end

      assert.is_nil(err)
      assert.is_false(exists)
    end)

    it("returns false for the pid file of a non-existent process", function()
      local exists, err

      for _ = 1, 1000 do
        local pid = math.random(1000, 2^16)
        assert.truthy(pl_file.write(pid_file, tostring(pid)))
        exists, err = process.exists(pid_file)
        if exists == false then
          break
        end
      end

      assert.is_nil(err)
      assert.is_false(exists)
    end)

    it("returns nil+error when a pid file does not exist", function()
      if pl_path.exists(pid_file) then
        assert.truthy(os.remove(pid_file))
      end

      local pid, err = process.exists(pid_file)
      assert.is_nil(pid)
      assert.is_string(err)
      assert.matches("No such file", err)
    end)

    it("returns nil+error when a pid file does not contain a valid pid", function()
      assert.truthy(pl_file.write(pid_file, "nope\n"))
      local pid, err = process.exists(pid_file)
      assert.is_nil(pid)
      assert.is_string(err)
      assert.matches("file does not contain a pid", err)
    end)
  end)

  describe("signal()", function()
    local proc

    local function spawn()
      local err
      proc, err = pipe.spawn({ "sleep", "60" }, {
        write_timeout = 100,
        stdout_read_timeout = 100,
        stderr_read_timeout = 100,
        wait_timeout = 1000,
      })
      assert.is_nil(err)
      assert.not_nil(proc)

      assert.truthy(proc:shutdown("stdin"))

      local pid = proc:pid()
      local deadline = ngx.now() + 2

      while ngx.now() < deadline do
        -- There is a non-zero amount of time involved in starting up our
        -- child process (before the sleep executable is invoked and nanosleep()
        -- is called).
        --
        -- During this time, signals may be ignored, so we should always delay
        -- at least _some_ amount here.
        ngx.sleep(0.5)

        if process.exists(pid) then
          break
        end

        ngx.update_time()
      end

      assert.is_true(process.exists(pid), "failed to spawn process")

      return proc
    end

    after_each(function()
      if proc then
        pcall(proc.kill, proc, 9)
        pcall(proc.wait, proc)
      end
    end)

    it("sends a signal to a running process, using a pid", function()
      spawn()
      local pid = proc:pid()

      local ok, err = process.signal(pid, 15)
      assert.is_nil(err)
      assert.truthy(ok)

      local reason, status
      ok, reason, status = proc:wait()
      assert.falsy(ok)
      assert.equals("signal", reason)
      assert.equals(15, status)

      assert.is_false(process.exists(pid))
    end)

    it("sends a signal to a running process, using a pid file", function()
      spawn()
      local pid = proc:pid()

      assert.truthy(pl_file.write(pid_file, tostring(pid)))

      local ok, err = process.signal(pid_file, 15)
      assert.is_nil(err)
      assert.truthy(ok)

      local reason, status
      ok, reason, status = proc:wait()
      assert.falsy(ok)
      assert.equals("signal", reason)
      assert.equals(15, status)

      assert.is_false(process.exists(pid_file))
    end)

    it("returns nil+error for a non-existent process", function()
      local ok, err

      for _ = 1, 1000 do
        local pid = math.random(1000, 2^16)
        ok, err = process.signal(pid, 0)
        if ok == nil then
          break
        end
      end

      assert.is_nil(ok)
      assert.is_string(err)
      assert.equals("No such process", err)
    end)

    it("accepts a signal name in place of signum", function()
      spawn()
      local pid = proc:pid()

      local ok, err = process.signal(pid, "INT")
      assert.is_nil(err)
      assert.truthy(ok)

      local reason, status
      ok, reason, status = proc:wait()
      assert.falsy(ok)
      assert.equals("signal", reason)
      assert.equals(2, status)

      assert.is_false(process.exists(pid))
    end)

  end)
end)
