# Contributing to Kong :monkey_face:

Hello, and welcome! Whether you are looking for help, trying to report a bug,
thinking about getting involved in the project or about to submit a patch, this
document is for you! Its intent is to be both an entry point for newcomers to
the community (with various technical backgrounds), and a guide/reference for
contributors and maintainers.

Consult the Table of Contents below, and jump to the desired section.

## Table of Contents

- [Where to seek for help?](#where-to-seek-for-help)
  - [Enterprise Edition](#enterprise-edition)
  - [Community Edition](#community-edition)
- [Where to report bugs?](#where-to-report-bugs)
- [Where to submit feature requests?](#where-to-submit-feature-requests)
- [Contributing](#contributing)
  - [Improving the documentation](#improving-the-documentation)
  - [Proposing a new plugin](#proposing-a-new-plugin)
  - [Submitting a patch](#submitting-a-patch)
    - [Git branches](#git-branches)
    - [Commit atomicity](#commit-atomicity)
    - [Commit message format](#commit-message-format)
    - [Static linting](#static-linting)
    - [Writing tests](#writing-tests)
    - [Writing performant code](#writing-performant-code)
  - [Contributor T-shirt](#contributor-t-shirt)
- [Code style](#code-style)

## Where to seek for help?

### Enterprise Edition

If you are a Kong Enterprise customer, contact the Enterprise Support channels
by opening an Enterprise support ticket on
[https://support.konghq.com](https://support.konghq.com/).

If you are experiencing a P1 issue, please call the [24/7 Enterprise Support
phone line](https://support.konghq.com/hc/en-us/articles/115004921808-Telephone-Support)
for immediate assistance, as published in the Customer Success Reference Guide.

If you are interested in becoming a Kong Enterprise customer, please visit
https://konghq.com/kong-enterprise-edition/ or contact us at
[sales@konghq.com](mailto:sales@konghq.com).

[Back to TOC](#table-of-contents)

### Community Edition

There are several channels where you can get answers from the community
or the maintainers of this project:

- Our public forum, [Kong Nation](https://discuss.konghq.com), is great for
  asking questions, giving advice, and staying up-to-date with the latest
  announcements. Kong Nation is frequented by Kong maintainers.
- Two chat channels are used by the community, but are rarely visited by Kong
  maintainers:
  - [Gitter](https://gitter.im/Kong/kong)
  - IRC, registered on freenode as
    [#kong](https://webchat.freenode.net/?channels=kong)

**Please avoid opening GitHub issues for general questions or help**, as those
should be reserved for actual bug reports. The Kong community is welcoming and
more than willing to assist you on those channels!

[Back to TOC](#table-of-contents)

## Where to report bugs?

Feel free to [submit an issue](https://github.com/Kong/kong/issues/new/choose) on
the GitHub repository, we would be grateful to hear about it! Please make sure
to respect the GitHub issue template, and include:

1. A summary of the issue
2. A list of steps to reproduce the issue
3. The version of Kong you encountered the issue with
4. Your Kong configuration, or the parts that are relevant to your issue

If you wish, you are more than welcome to propose a patch to fix the issue!
See the [Submit a patch](#submitting-a-patch) section for more information
on how to best do so.

[Back to TOC](#table-of-contents)

## Where to submit feature requests?

You can [submit an issue](https://github.com/Kong/kong/issues/new/choose) for feature
requests. Please add as much detail as you can when doing so.

You are also welcome to propose patches adding new features. See the section
on [Submitting a patch](#submitting-a-patch) for details.

[Back to TOC](#table-of-contents)

## Contributing

We welcome contributions of all kinds, you do not need to code to be helpful!
All of the following tasks are noble and worthy contributions that you can
make without coding:

- Reporting a bug (see the [report bugs](#where-to-report-bugs) section)
- Helping other members of the community on the support channels
- Fixing a typo in the code
- Fixing a typo in the documentation at https://docs.konghq.com (see
  the [documentation contribution](#improving-the-documentation) section)
- Providing your feedback on the proposed features and designs
- Reviewing Pull Requests

If you wish to contribute code (features or bug fixes), see the [Submitting a
patch](#submitting-a-patch) section.

[Back to TOC](#table-of-contents)

### Improving the documentation

The documentation hosted at https://docs.konghq.com is open source and built
with [Jekyll](https://jekyllrb.com/). You are welcome to propose changes to it
(correct typos, add examples or clarifications...) and contribute to the
[Kong Hub](https://docs.konghq.com/hub/)!

The repository is also hosted on GitHub at:
https://github.com/Kong/docs.konghq.com/

[Back to TOC](#table-of-contents)

### Proposing a new plugin

We **do not** accept new plugins into the core repository. The plugins that are
currently part of this repository are there because of historical reasons, but
will be pushed into separate repositories in the foreseeable future.

If you wish to write a new plugin for your own needs, you should start by
reading the [Plugin Development
Guide](https://docs.konghq.com/latest/plugin-development).

If you already wrote a plugin, and are thinking about making it available to
the community, we strongly encourage you to host it on a publicly available
repository (like GitHub), and to distribute it via
[LuaRocks](https://luarocks.org/search?q=kong). A good resource on how to do
so is the [Distribution
Section](https://docs.konghq.com/latest/plugin-development/distribution/#distributing-your-plugin)
of the Plugin Development Guide.

To give visibility to your plugin, we advise that you:

1. [Add your
   plugin](https://github.com/Kong/docs.konghq.com/blob/master/CONTRIBUTING.md#contributing-to-kong-documentation-and-the-kong-hub)
   to the [Kong Hub](https://docs.konghq.com/hub/)
2. Create a post in the [Announcements category of Kong
   Nation](https://discuss.konghq.com/c/announcements)

[Back to TOC](#table-of-contents)

### Submitting a patch

Feel free to contribute fixes or minor features, we love to receive Pull
Requests! If you are planning to develop a larger feature, come talk to us
first!

When contributing, please follow the guidelines provided in this document. They
will cover topics such as the different Git branches we use, the commit message
format to use or the appropriate code style.

Once you have read them, and you are ready to submit your Pull Request, be sure
to verify a few things:

- Your work was based on the appropriate branch (`master` vs. `next`), and you
  are opening your Pull Request against the appropriate one
- Your commit history is clean: changes are atomic and the git message format
  was respected
- Rebase your work on top of the base branch (seek help online on how to use
  `git rebase`; this is important to ensure your commit history is clean and
   linear)
- The static linting is succeeding: run `make lint`, or `luacheck .` (see the
  development documentation for additional details)
- The tests are passing: run `make test`, `make test-all`, or whichever is
  appropriate for your change
- Do not update CHANGELOG.md yourself. Your change will be included there in
  due time if it is accepted, no worries!

If the above guidelines are respected, your Pull Request has all its chances
to be considered and will be reviewed by a maintainer.

If you are asked to update your patch by a reviewer, please do so! Remember:
**you are responsible for pushing your patch forward**. If you contributed it,
you are probably the one in need of it. You must be prepared to apply changes
to it if necessary.

If your Pull Request was accepted and fixes a bug, adds functionality, or
makes it significantly easier to use or understand Kong, congratulations!
You are now an official contributor to Kong. Get in touch with us to receive
your very own [Contributor T-shirt](#contributor-t-shirt)!

Your change will be included in the subsequent release Changelog, and we will
not forget to include your name if you are an external contributor. :wink:

[Back to TOC](#table-of-contents)

#### Git branches

We work on two branches: `master`, where non-breaking changes land, and `next`,
where important features or breaking changes land in-between major releases.

When contributing to Kong, this distinction is important. Please ensure that
you are basing your work on top of the appropriate branch, it might save you
some time down the road!

If you have write access to the GitHub repository, please follow the following
naming scheme when pushing your branch(es):

- `feat/foo-bar` for new features
- `fix/foo-bar` for bug fixes
- `tests/foo-bar` when the change concerns only the test suite
- `refactor/foo-bar` when refactoring code without any behavior change
- `style/foo-bar` when addressing some style issue
- `docs/foo-bar` for updates to the README.md, this file, or similar documents

[Back to TOC](#table-of-contents)

#### Commit atomicity

When submitting patches, it is important that you organize your commits in
logical units of work. You are free to propose a patch with one or many
commits, as long as their atomicity is respected. This means that no unrelated
changes should be included in a commit.

For example: you are writing a patch to fix a bug, but in your endeavour, you
spot another bug. **Do not fix both bugs in the same commit!** Finish your
work on the initial bug, propose your patch, and come back to the second bug
later on. This is also valid for unrelated style fixes, refactors, etc...

You should use your best judgment when facing such decisions. A good approach
for this is to put yourself in the shoes of the person who will review your
patch: will they understand your changes and reasoning just by reading your
commit history? Will they find unrelated changes in a particular commit? They
shouldn't!

Writing meaningful commit messages that follow our commit message format will
also help you respect this mantra (see the below section).

[Back to TOC](#table-of-contents)

#### Commit message format

To maintain a healthy Git history, we ask of you that you write your commit
messages as follows:

- The tense of your message must be **present**
- Your message must be prefixed by a type, and a scope
- The header of your message should not be longer than 50 characters
- A blank line should be included between the header and the body
- The body of your message should not contain lines longer than 72 characters

Here is a template of what your commit message should look like:

```
<type>(<scope>) <subject>
<BLANK LINE>
<body>
<BLANK LINE>
<footer>
```

##### Type

The type of your commit indicates what type of change this commit is about. The
accepted types are:

- **feat**: A new feature
- **fix**: A bug fix
- **hotfix**: An urgent bug fix during a release process
- **tests**: A change that is purely related to the test suite only (fixing
  a test, adding a test, improving its reliability, etc...)
- **docs**: Changes to the README.md, this file, or other such documents
- **style**: Changes that do not affect the meaning of the code (white-space
  trimming, formatting, etc...)
- **perf**: A code change that significantly improves performance
- **refactor**: A code change that neither fixes a bug nor adds a feature, and
  is too big to be considered just `perf`
- **chore**: Maintenance changes related to code cleaning that isn't
  considered part of a refactor, build process updates, dependency bumps, or
  auxiliary tools and libraries updates (LuaRocks, Travis-ci, etc...).

##### Scope

The scope is the part of the codebase that is affected by your change. Choosing
it is at your discretion, but here are some of the most frequent ones:

- **proxy**: A change that affects the proxying of requests
- **router**: A change that affects the router, which matches a request to the
  desired configured API
- **admin**: A change to the Admin API
- **balancer**: Changes related to the internal Load Balancer
- **core**: Changes affecting a large part of the core, and touching many parts
  such as `proxy`, `balancer`, `dns`
- **dns**: Changes related to internal DNS resolution
- **dao**: A change related to the DAO, the interface to the datastores
- **cli**: Changes to the CLI
- **cache**: Changes to the configuration entities caching (datastore entities)
- **deps**: When updating dependencies (to be used with the `chore` prefix)
- **conf**: Configuration-related changes (new values, improvements...)
- **`<plugin-name>`**: This could be `basic-auth`, or `ldap` for example
- `*`: When the change affects too many parts of the codebase at once (this
  should be rare and avoided)

##### Subject

Your subject should contain a succinct description of the change. It should be
written so that:

- It uses the present, imperative tense: "fix typo", and not "fixed" or "fixes"
- It is **not** capitalized: "fix typo", and not "Fix typo"
- It does **not** include a period. :smile:

##### Body

The body of your commit message should contain a detailed description of your
changes. Ideally, if the change is significant, you should explain its
motivation, the chosen implementation, and justify it.

As previously mentioned, lines in the commit messages should not exceed 72
characters.

##### Footer

The footer is the ideal place to link to related material about the change:
related GitHub issues, Pull Requests, fixed bug reports, etc...

##### Examples

Here are a few examples of good commit messages to take inspiration from:

```
fix(admin) send HTTP 405 on unsupported method

The appropriate status code when the request method is not supported
on an endpoint it 405. We previously used to send HTTP 404, which
is not appropriate. This updates the Admin API helpers to properly
return 405 on such user errors.

* return 405 when the method is not supported in the Admin API helpers
* add a new test case in the Admin API test suite

Fix #678
```

Or:

```
tests(proxy) add a new test case for URI encoding

When proxying upstream, the URI sent by Kong should be the one
received from the client, even if it was percent-encoded.

This adds a new test case which was missing, to ensure it is
the case.
```

[Back to TOC](#table-of-contents)

#### Static linting

As mentioned in the guidelines to submit a patch, the linter must succeed. We
use [Luacheck](https://github.com/mpeterv/luacheck) to statically lint our Lua
code. You can lint the code like so:

```
$ make lint
```

Or:

```
$ luacheck .
```

[Back to TOC](#table-of-contents)

#### Writing tests

We use [busted](https://olivinelabs.com/busted/) to write our tests. Your patch
should include the related test updates or additions, in the appropriate test
suite.

- `spec/01-unit` gathers our unit tests (to test a given Lua module or
  function)
- `spec/02-integration` contains tests that start Kong (connected to a running
  database), execute Admin API and proxy requests against it, and verify the
  output
- `spec/03-plugins` contains tests (both unit and integration) for the bundled
  plugins (those plugins still live in the core repository as of now, but will
  eventually be externalized)

A few guidelines when writing tests:

- Use appropriate `describe` and `it` blocks, so it's obvious what is being
  tested exactly
- Ensure the atomicity of your tests: no test should be asserting two
  unrelated behaviors at the same time
- Run tests related to the datastore against all supported databases

And a few recommendations, when asserting types:

```lua
-- bad
assert.Nil(foo)
assert.True(bar)

-- good
assert.is_nil(foo)
assert.is_true(bar)
```

Comparing tables:

```lua
-- bad (most of the time)
assert.equal(t1, t2)

-- good
assert.same(t1, t2)
```

[Back to TOC](#table-of-contents)

#### Writing performant code

We write code for the [LuaJIT](https://github.com/Kong/kong/issues/new)
interpreter, **not** Lua-PUC. As such, you should follow the LuaJIT best
practices:

- Do **not** instantiate global variables
- Consult the [LuaJIT wiki](http://wiki.luajit.org/Home)
- Follow the [Performance
  Guide](http://wiki.luajit.org/Numerical-Computing-Performance-Guide)
  recommendations
- Do **not** use [NYI functions](http://wiki.luajit.org/NYI) on hot code paths
- Prefer using the FFI over traditional bindings via the Lua C API
- Avoid table rehash by pre-allocating the slots of your tables when possible

  ```lua
  -- bad
  local t = {}
  for i = 1, 100 do
    t[i] = i
  end

  -- good
  local new_tab = require "table.new"
  local t = new_tab(100, 0)
  for i = 1, 100 do
    t[i] = i
  end
  ```

- Cache the globals used by your hot code paths

  ```lua
  -- bad
  for i = 1, 100 do
    t[i] = math.random()
  end

  -- good
  local random = math.random
  for i = 1, 100 do
    t[i] = random()
  end
  ```

- Cache the length and indices of your tables to avoid unnecessary CPU cycles

  ```lua
  -- bad
  for i = 1, 100 do
    t[#t + 1] = other_tab[#other_tab]
  end

  -- good
  local n = 0
  local n_other_tab = #other_tab
  for i = 1, 100 do
    n = n + 1
    t[n] = other_tab[n_other_tab]
  end
  ```

And finally, most importantly: use your best judgment to design an
efficient algorithm. Doing so will always be more performant than a
poorly-designed algorithm, even following all the performance tricks of the
language you are using. :smile:

[Back to TOC](#table-of-contents)

### Contributor T-shirt

If your Pull Request to [Kong/kong](https://github.com/Kong/kong) was
accepted, and it fixes a bug, adds functionality, or makes it significantly
easier to use or understand Kong, congratulations! You are eligible to
receive the very special Contributor T-shirt! Go ahead and fill out the
[Contributors Submissions form](https://goo.gl/forms/5w6mxLaE4tz2YM0L2).

Proudly wear your T-shirt and show it to us by tagging
[@thekonginc](https://twitter.com/thekonginc) on Twitter!

![Kong Contributor T-shirt](https://konghq.com/wp-content/uploads/2018/04/100-contributor-t-shirt-1024x768.jpg)

[Back to TOC](#table-of-contents)

## Code style

In order to ensure a healthy and consistent codebase, we ask of you that you
respect the adopted code style. This section contains a non-exhaustive list
of preferred styles for writing Lua. It is opinionated, but follows the
code styles of OpenResty and, by association, Nginx. OpenResty or Nginx
contributors should find themselves at ease when contributing to Kong.

- No line should be longer than 80 characters
- Indentation should consist of 2 spaces

When you are unsure about the style to adopt, please browse other parts of the
codebase to find a similar case, and stay consistent with it.

You might also notice places in the code base where the described style is not
respected. This is due to legacy code. **Contributions to update the code to
the recommended style are welcome!**

[Back to TOC](#table-of-contents)

### Table of Contents - Code style

- [Modules](#modules)
- [Variables](#variables)
- [Tables](#tables)
- [Strings](#strings)
- [Functions](#functions)
- [Conditional expressions](#conditional-expressions)

### Modules

When writing a module (a Lua file), separate logical blocks of code with
**two** blank lines:

```lua
local foo = require "kong.foo"


local _M = {}


function _M.bar()
  -- do thing...
end


function _M.baz()
  -- do thing...
end


return _M
```

[Back to code style TOC](#table-of-contents---code-style)

### Variables

When naming a variable or function, **do** use snake_case:

```lua
-- bad
local myString = "hello world"

-- good
local my_string = "hello world"
```

When assigning a constant variable, **do** give it an uppercase name:

```lua
-- bad
local max_len = 100

-- good
local MAX_LEN = 100
```

[Back to code style TOC](#table-of-contents---code-style)

### Tables

Use the constructor syntax, and **do** include a trailing comma:

```lua
-- bad
local t = {}
t.foo = "hello"
t.bar = "world"

-- good
local t = {
  foo = "hello",
  bar = "world", -- note the trailing comma
}
```

On single-line constructors, **do** include spaces around curly-braces and
assignments:

```lua
-- bad
local t = {foo="hello",bar="world"}

-- good
local t = { foo = "hello", bar = "world" }
```

[Back to code style TOC](#table-of-contents---code-style)

### Strings

**Do** favor the use of double quotes in all Lua code (plain files and
`*_by_lua_block` directives):

```lua
-- bad
local str = 'hello'

-- good
local str = "hello"
```

If a string contains double quotes, **do** favor long bracket strings:

```lua
-- bad
local str = "message: \"hello\""

-- good
local str = [[message: "hello"]]
```

When using the concatenation operator, **do** insert spaces around it:

```lua
-- bad
local str = "hello ".."world"

-- good
local str = "hello " .. "world"
```

[Back to code style TOC](#table-of-contents---code-style)

### Functions

Prefer the function syntax over variable syntax:

```lua
-- bad
local foo = function()

end

-- good
local function foo()

end
```

Perform validation early and return as early as possible:

```lua
-- bad
local function check_name(name)
  local valid = #name > 3
  valid = valid and #name < 30

  -- other validations

  return valid
end

-- good
local function check_name(name)
  if #name <= 3 or #name >= 30 then
    return false
  end

  -- other validations

  return true
end
```

Follow the return values conventions: Lua supports multiple return values, and
by convention, handles recoverable errors by returning `nil` plus a `string`
describing the error:

```lua
-- bad
local function check()
  local ok, err = do_thing()
  if not ok then
    return false, { message = err }
  end

  return true
end

-- good
local function check()
  local ok, err = do_thing()
  if not ok then
    return nil, "could not do thing: " .. err
  end

  return true
end
```

When a function call makes a line go over 80 characters, **do** align the
overflowing arguments to the first one:

```lua
-- bad
local str = string.format("SELECT * FROM users WHERE first_name = '%s'", first_name)

-- good
local str = string.format("SELECT * FROM users WHERE first_name = '%s'",
                          first_name)
```

[Back to code style TOC](#table-of-contents---code-style)

### Conditional expressions

Avoid writing 1-liner conditions, **do** indent the child branch:

```lua
-- bad
if err then return nil, err end

-- good
if err then
  return nil, err
end
```

When testing the assignment of a value, **do** use shortcuts, unless you
care about the difference between `nil` and `false`:

```lua
-- bad
if str ~= nil then

end

-- good
if str then

end
```

When creating multiple branches that span multiple lines, **do** include a
blank line above the `elseif` and `else` statements:

```lua
-- bad
if foo then
  do_stuff()
  keep_doing_stuff()
elseif bar then
  do_other_stuff()
  keep_doing_other_stuff()
else
  error()
end

-- good
if thing then
  do_stuff()
  keep_doing_stuff()

elseif bar then
  do_other_stuff()
  keep_doing_other_stuff()

else
  error()
end
```

For one-line blocks, blank lines are not necessary:

```lua
--- good
if foo then
  do_stuff()
else
  error("failed!")
end
```

Note in the correct "long" example that if some branches are long, then all
branches are created with the preceding blank line (including the one-liner
`else` case).

When a branch returns, **do not** create subsequent branches, but write the
rest of your logic on the parent branch:

```lua
-- bad
if not str then
  return nil, "bad value"
else
  do_thing(str)
end

-- good
if not str then
  return nil, "bad value"
end

do_thing(str)
```

When assigning a value or returning from a function, **do** use ternaries if
it makes the code more readable:

```lua
-- bad
local foo
if bar then
  foo = "hello"

else
  foo = "world"
end

-- good
local foo = bar and "hello" or "world"
```

When an expression makes a line longer than 80 characters, **do** align the
expression on the following lines:

```lua
-- bad
if thing_one < 1 and long_and_complicated_function(arg1, arg2) < 10 or thing_two > 10 then

end

-- good
if thing_one < 1 and long_and_complicated_function(arg1, arg2) < 10
   or thing_two > 10
then

end
```

[Back to code style TOC](#table-of-contents---code-style)
