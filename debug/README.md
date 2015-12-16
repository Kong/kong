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

NOTE: The code files must be open in the IDE to enable the debugger to find the related source code.

ZeroBrane has some great debug features, like a remote console that allows for live manipulation of the target. A watch and stack window and variable-value-tooltips in the code editor. For more information on the debug features in ZeroBrane Studio check [the documentation](http://studio.zerobrane.com/doc-lua-debugging).

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

Tutorial
========

As an example, let's debug the `basic-auth` plugin tests. Make sure you've installed Zerobrane Studio and updated the `debug/config.lua` accordingly.

 - Open Zerobrane Studio and in the menu "Project" select "Start debugger server"
 - prepare your Kong development and test environment for debugging, on the commandline execute;
   - `debug/setup`
 - In the IDE open the `kong/spec/plugins/basic-auth/api_spec.lua` file
 - At the top insert the `debug.start()` and `debug.stop()` commands, then the code should look something like this;
```lua
  setup(function()
debug.start()                      --> inserted for debugging
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
debug.stop()                       --> inserted for debugging
  end)
````
 - now insert a breakpoint; select a line somewhere in one of the `it()` blocks below and click the breakpoint button (red dot) on the toolbar (alternatively click the whitespace just right of the line number, or hit F9). If succesful a red dot icon will mark the selected line to indicate the breakpoint was set.
 - switch to the commandline and execute the tests for this plugin only;
   - `debug/test spec/plugins/basic-auth`
 - switch back to the IDE and the code will be interrupted at the `debug.start()` line. Due to a bug it will not automatically switch there or display the line marker. Click the 'step-into' button (or hit F10), and it will show the marker right after the `debug.start()` line.
 - now click 'continue' (or hit F5) and it will resume the execution and break again at the breakpoint earlier inserted.
 - right-click a variable at the breakpoint and select 'Add Watch Expression' from the menu. The watch panel will open and it will display the value of the variable.

From here on you can;
 - continue or step through the code
 - display the 'stack' window to see the execution stack
 - execute code in the remote application by typing commands in the 'Remote console' panel

Note: if you don't want the debugger to stop at the `debug.start()` command, but only at the breakpoints, you can set the `debugger.runonstart` parameter to `true` (see [debugger configuration](https://studio.zerobrane.com/doc-general-preferences#debugger))

FAQ
===
 - _The application stops, but I don't see anything in the ide?_ There is a bug that prevents the display of the debug line marker. Click the 'step-into' button or hit F10 to show it.
 - _I've set a breakpoint, but it is never hit_ If the `debug.start()` function was not called, it will not break anywhere. Make sure you call it before the code hits your breakpoint.
 - _breakpoints in my tests are hit, but not in the application_ When running tests, you're executing 2 Lua environments in parallel; OpenResty and Busted. You must make sure that in __both__ environments the `debug.start()` method is called before hitting the breakpoint.

More...
=======

- `debug.start()` is a shortcut for `require("mobdebug").start()` and by passing an ip address and port you can also debug from a remote machine, see the `mobdebug` documentation
- [ZeroBrane Studio](http://studio.zerobrane.com/)
- [mobdebug module](https://github.com/pkulchenko/MobDebug)
- [Debugger configuration](https://studio.zerobrane.com/doc-general-preferences#debugger))
- [Debugging OpenResty with ZeroBrane Studio](http://notebook.kulchenko.com/zerobrane/debugging-openresty-nginx-lua-scripts-with-zerobrane-studio)


