# Changelog; Kong Serverless Functions Plugin

## 2.1.0 2010-01-08

- Use Kong sandboxing module

## 2.0.0 2020-12-22

- Change: Only allow kong PDK, nginx and plain Lua

## 1.0.0 released 7-Apr-2020

- Change: adds the ability to run functions in each phase
- Fix: bug when upvalues are used, combined with an early exit

## 0.3.1

- Do not execute functions when validating ([Kong/kong#5110](https://github.com/Kong/kong/issues/5110))

## 0.3.0

- Functions can now have upvalues
- Plugins are no longer required to inherit from the `BasePlugin` module

## 0.2.0

- Updated schemas to new format
- Updated specs to test Services & Routes instead of plugins, and adapted to new schemas

## 0.1.0 Initial release

- `pre-function` and `post-function` plugins added
