Debug support
=============

This setup consists of 2 scripts and 1 configuration file;

 - `config.lua` : contains configuration information
 - `setup` : will update the `kong_DEVELOPMENT.yml` and `kong_TEST.yml` files to configure them for debugging
 - `test` : will run tests with Busted within a debug setting
 
Prerequisites
=============

- Kong development environment must have been setup
- ZeroBrane Studio must be installed

Instructions
============

- edit `debug/config.lua` and update the location of Zerobrane Studio in the `zerobrane_path` variable
- run `debug/setup` to modify the Kong configuration files
- open Zerobrane studio and the file to debug, insert an extra line `debug.start()` which will act as the first breakpoint
- in the menu "Project" select "Start debugger server"
- restart Kong and wait for the breakpoint to be hit.

For debugging tests;
- run `debug/test` with the spec files to run; eg. `debug.test spec/unit` to run the unit tests

The function `debug.start()` will start the connection to the IDE and will break at that point in the code. Once this has been hit, the IDE can be used to set additional breakpoints. To speed up application execution the `debug.stop()` function can be used to close the connection and disable the debugger again, when (temporarily) no longer needed.

NOTE: The code files must be open in the IDE to enable the debugger to find the related source code .

How it works
============
The debugger used is the `mobdebug` module, which uses a TCP connection to connect to the Zerobrane IDE. Due to some incompatibilities
in the socket functions of OpenResty, they won't work properly with the debugger, and hence the LuaSocket implementation included with
Zerobrane Studio will be used.

When developing for Kong there are 2 Lua environments that are being used;

1. The Lua implementation in OpenResty
2. The Lua engine used by Busted to execute the test sets

To make the debugger work 2 things need to be taken care of;

- Make sure the debugger and required socket module are in the Lua paths so they can be found and take precedence over the internal socket functions
- Expose some globals for easy access to the debugger functions (that would be; `debug.start()` and `debug.stop()`)

OpenResty
---------
The `setup` script will update the test and development OpenResty config. After the update the paths will include the Zerobrane paths, and the `init_by_lua` directive will be modified to expose the 2 globals right when OpenResty starts.

Busted
------
When running tests through `debug/test` a temporary file `busted-helper.lua` will be created and executed on the busted command line with the `--helper` commandline option. This helper file will expose the global debug functions. Through the options `--lpath` and `--cpath` the search paths are updated to include the Zerobrane modules.

More...
=======

- [ZeroBrane Studio](http://studio.zerobrane.com/)
- [mobdebug module](https://github.com/pkulchenko/MobDebug)
- [Debugging OpenResty with ZeroBrane Studio](http://notebook.kulchenko.com/zerobrane/debugging-openresty-nginx-lua-scripts-with-zerobrane-studio)


