##To be added;

returning errors
documenting functions
empty-tables


# Mashape Kong contributing guidelines

This guide contains a list of guidelines that we try to follow for the
Kong codebase. 



## <a name='TOC'>Table of Contents</a>

  1. [Version control](#version-control)
      - [Branches](#branches)
      - [Commit message format](#commits)
      - [Pull requests](#pullrequests)
  1. [Testing](#testing)
  1. [Performance](#performance)
  1. [Lua Style Guide](#style-guide)
      - [Tables](#tables)
      - [Strings](#strings)
      - [Functions](#functions)
      - [Properties](#properties)
      - [Variables](#variables)
      - [constants](#constants)
      - [Conditional Expressions & Equality](#conditionals)
      - [Blocks](#blocks)
      - [Whitespace](#whitespace)
      - [Commas](#commas)
      - [Semicolons](#semicolons)
      - [Type Casting & Coercion](#type-coercion)
      - [Naming Conventions](#naming-conventions)
      - [Modules](#modules)

## <a name='version-control'>Version control</a>

### <a name='branches'>Branches</a>

  There are two important branches in the repository:
  
  - `master` is the branch for stable, released code
  - `next` a development branch where new features land
  
  When contributing the distinction is important. When contributing a bugfix found
  in a release, base your fix of the `master` branch. New features and fixes on
  `next` should be based of the `next` branch.

  **[[back to top]](#TOC)**

### <a name='commits'>Commit message format</a>

  - This part of the guide was copied from the 
    [Angular commit message format](https://github.com/angular/angular.js/blob/master/CONTRIBUTING.md#commit-message-format)
    and has been adopted to our needs.

  - Please write insightful and descriptive commit messages. It lets us and future contributors
    quickly understand your changes without having to read your changes. Please provide a
    summary in the first line and eventually, go to greater lengths in
    your message's body. We also like commit message with a **type** and **scope**.

  - Please create commits containing **related changes**. For example, two different bugfixes
    should produce two separate commits. A feature should be made of commits splitted by
    **logical chunks** (no half-done changes). Use your best judgement as to how many commits
    your changes require, and try to keep them atomic.

  Each commit message consists of a **header**, a **body** and a **footer**.  The header has a special
  format that includes a **type**, a **scope** and a **subject**:

  ```
  <type>(<scope>) <subject>
  <BLANK LINE>
  <body>
  <BLANK LINE>
  <footer>
  ```

  The **header** is mandatory, with a maximum of 50 characters. Any other line of the commit 
  message cannot be longer than 72 characters! This allows the message to be easier to read 
  on GitHub as well as in various git tools.

  #### Type
  
  Must be one of the following:

  * **feat**: A new feature
  * **fix**: A bug fix (based of the `next` branch)
  * **hotfix**: A bug fix (based of the `master` branch)
  * **docs**: Documentation only changes
  * **style**: Changes that do not affect the meaning of the code (white-space, formatting, missing
    semi-colons, etc)
  * **refactor**: A code change that neither fixes a bug nor adds a feature
  * **perf**: A code change that improves performance
  * **test**: Adding missing or correcting existing tests
  * **chore**: Changes to the build process or auxiliary tools and libraries such as documentation
    generation

  #### Scope
  
  The scope could be anything specifying the place of the commit change. Common examples:
  
  * **`<plugin-name>`**: This could be `basic-auth`, or `ldap` for example
  * **admin**: the admin api
  * **proxy**: the core proxy functionality
  * **balancer**: the loadbalancer
  * **dns**: dns resolution
  * **dao**: datastore persistence functionality
  * **cache**: for Lua or shm based caching
  * **cli**: command line interface
  * **deps**: for updating dependencies
  * **conf**: for configuration related changes
  
  You can use `*` when the change affects more than a single scope.

  ### Subject

  The subject contains succinct description of the change:

  * use the imperative, present tense: "change" not "changed" nor "changes"
  * don't capitalize first letter
  * no dot (.) at the end

  ### Body

  Just as in the **subject**, use the imperative, present tense: "change" not "changed" nor "changes".
  The body should include the motivation for the change and contrast this with previous behavior.

  ### Footer

  The footer should contain any information about **Breaking Changes** and is also the place to
  [reference GitHub issues that this commit closes](https://help.github.com/articles/closing-issues-via-commit-messages/).

  **Breaking Changes** should start with the word `BREAKING CHANGE:` with a space or two newlines.
  The rest of the commit message is then used for this.

  A detailed explanation can be found in this [document](https://docs.google.com/document/d/1QrDFcIiPjSLDn3EL15IJygNPiHORgU1_OOAqWjiDU5Y/edit#).

  **[[back to top]](#TOC)**

### <a name='pullrequests'>Pull requests</a>


  - First of all, make sure to base your work on the [appropriate branch][#branches]:

    ```
    # a bugfix branch for `next` would be prefixed by fix/
    # a bugfix branch for `master` would be prefixed by hotfix/
    $ git checkout -b feature/my-feature next
    ```

  - Write insightful and descriptive commit messages, formatted as [specified][#commits].

  - Please **include the appropriate test cases** for your patch.

  - Make sure all tests pass before submitting your changes. See the
    [Makefile operations](/README.md#makefile-operations).

  - Make sure the linter does not throw any errors: `make lint`.

  - Rebase your commits. It may be that new commits have been introduced on `next`. Rebasing
    will update your branch with the most recent code and make your changes easier to review:

    ```
    $ git fetch
    $ git rebase origin/next
    ```

  - Push your changes:

    ```
    $ git push origin -u feature/my-feature
    ```

  - Open a pull request against the [appropriate branch][#branches].

  - If we suggest changes:
  
    - Please make the required updates (after discussion if any)
    - Re-run the test suite
    - Only create new commits if it makes sense. Generally, you will want to 
      [amend your latest commit or rebase your branch](http://gitready.com/advanced/2009/02/10/squashing-commits-with-rebase.html)
      after the new changes:

      ```
      $ git rebase -i next
      # choose which commits to edit and perform the updates
      ```

    - Force push to your branch:

      ```
      $ git push origin feature/my-feature -f
      ```
  
    **[[back to top]](#TOC)**

## <a name='testing'>Testing</a>

  - Use [busted](http://olivinelabs.com/busted) and write lots of tests in a /spec 
    folder. Separate tests by module.
  - Use descriptive `describe` and `it` blocks so it's obvious to see what
    precisely is failing.
  - Test one functionality per test, repeat for multiple functionalities.
  - Tests should be atomic, meaning they can only rely on `setup` and `before_each`
    functionalities, but never on the results or changes by a previous test (even
    if run on its own it should pass).

  - For the keyword assertions (`nil`, `true`, and `false`) use the `is_xxx` format

    ```lua
    --bad
    assert.Nil(something)

    --good
    assert.is_nil(something)
    ```

  - Use specific assertions where available. The specific assertion will provide better
    error messages when they fail, as they better understand the context.

    ```lua
    --bad
    local value = r.body.headers["x-something"]
    assert(value == "something","expected 'something'")

    --good
    local value = assert.request(r).has.header("x-something")
    assert.equal("something", value)
    ```

    **[[back to top]](#TOC)**

## <a name='performance'>Performance</a>

  - cache globals when used repeatedly. Locals are faster than looking up globals.

    ```lua
    --bad
    for i = 1, 20 do
      t[i] = math.floor(t[i])
    end

    --good
    local math_floor = math.floor
    for i = 1, 20 do
      t[i] = math_floor(t[i])
    end
    ```

  - Make sure to write JIT-able code

    TODO

  - Where possible use pre-allocated tables

    TODO

  - Insertion into lists by using the length operator `#`. Never use the 'length' 
    functions (neither `table.getn` nor `string.len`).

    ```lua
    --bad
    local t = {}
    for i, value in ipairs({ "hello", "world" }) do
      table_insert(t,value)
    end
    print(table.getn(t))

    --good
    local t = {}
    for i, value in ipairs({ "hello", "world" }) do
      t[#t + 1] = value
    end
    print(#t)
    ```

    **[[back to top]](#TOC)**

## <a name='style-guide'>Lua Style Guide</a>

This style guide started as a copy of the [Olivine Labs style guide](https://github.com/Olivine-Labs/lua-style-guide/blob/master/README.md#TOC)
and has been adapted for our needs.

This is quite a lengthy style guide, we know, we wrote it... The purpose of 
this guide is to help achieve some goals that we value:

- readable code that is easy to maintain with little cognitive load. We'd like
  the code to look beautiful.
- performant code, especially on hot code paths performance is more important
  than style.

Thanks for helping us.


### <a name='tables'>Tables</a>

  - Use the constructor syntax for table property creation where possible. Use
    trailing commas (last element) to minimize diffs in future updates.

    ```lua
    -- bad
    local player = {}
    player.name = "Jack"
    player.class = "Rogue"

    -- good
    local player = {
      name  = "Jack",   -- extra space to align the assignment statements
      class = "Rogue",  -- note the trailing comma here
    }
    ```

  - Define functions externally to table definition.

    ```lua
    -- bad
    local player = {
      attack = function() 
      -- ...stuff...
      end
    }

    -- good
    local function attack()
    end

    local player = {
      attack = attack
    }
    ```

  - Consider `nil` properties when selecting lengths.
    If a table (used as a list or array) can contain 'holes' or `nil` entries,
    the best approach is to use an `n` property to track the actual length.

    ```lua
    -- bad
    local list = { "hello", nil, "there" }

    -- good
    local list = { "hello", nil, "there", n = 3 }
    ```

  - When tables have functions, use `self` when referring to itself.

    ```lua
    -- bad
    local me = {
      fullname = function(this)
        return this.first_name .. " " .. this.last_name
      end
    }

    -- good
    local me = {
      fullname = function(self)
        return self.first_name .. " " .. self.last_name
      end
    }
    ```

    **[[back to top]](#TOC)**

### <a name='strings'>Strings</a>

  - Use double quotes `""` for strings.

    ```lua
    -- bad
    local name = 'Bob Parr'

    -- good
    local name = "Bob Parr"

    -- bad
    local fullName = 'Bob ' .. self.lastName

    -- good
    local fullName = "Bob " .. self.lastName
    ```

  - Strings longer than 80 characters should be written across multiple lines 
    using concatenation. This allows you to indent nicely.

    ```lua
    -- bad
    local errorMessage = "This is a super long error that was thrown because of Batman. When you stop to think about how Batman had anything to do with this, you would get nowhere fast."

    -- good
    local errorMessage = "This is a super long error that " ..
      "was thrown because of Batman. " ..
      "When you stop to think about " ..
      "how Batman had anything to do " ..
      "with this, you would get nowhere " ..
      "fast."
    ```

    **[[back to top]](#TOC)**


### <a name='functions'>Functions</a>
  - Prefer lots of small functions to large, complex functions. [Smalls Functions Are Good For The Universe](http://kikito.github.io/blog/2012/03/16/small-functions-are-good-for-the-universe/).

  - Prefer function syntax over variable syntax. This helps differentiate
    between named and anonymous functions. It also allows for recursion
    without forward declaring the local variable.

    ```lua
    -- bad
    local nope = function(name, options)
      -- ...stuff...
      return nope(name, options)  -- this fails because `nope` is unknown
    end

    -- good
    local function yup(name, options)
      -- ...stuff...
      return yup(name, options)  -- this works because `yup` is known
    end
    ```

  - Perform validation early and return as early as possible.

    ```lua
    -- bad
    local is_good_name = function(name, options, arg)
      local is_good = #name > 3
      is_good = is_good and #name < 30

      -- ...stuff...

      return is_bad
    end

    -- good
    local is_good_name = function(name, options, args)
      if #name < 3 or #name > 30 then
        return false
      end

      -- ...stuff...

      return true
    end
    ```

  **[[back to top]](#TOC)**


### <a name='properties'>Properties</a>

  - Use dot notation when accessing known properties.

    ```lua
    local luke = {
      jedi = true,
      age  = 28,          -- extra space and trailing comma
    }

    -- bad
    local is_jedi = luke["jedi"]

    -- good
    local is_jedi = luke.jedi
    ```

    **[[back to top]](#TOC)**


### <a name='variables'>Variables</a>

  - Always use `local` to declare variables. Not doing so will result in
    global variables and pollutes the global namespace. Also use the
    `make lint` operation before committing/pushing to catch accidental
    globals

    ```lua
    -- bad
    super_power = SuperPower()

    -- good
    local super_power = SuperPower()
    ```

    **[[back to top]](#TOC)**


### <a name='constants'>Constants</a>

  - Name constants in ALL_CAPS and declare them at the top of the module.

    ```lua
    -- bad
    -- do some stuff here
    local max_super_power = 100 

    -- good
    local MAX_SUPER_POWER = 100

    -- do some stuff here
    ```

    **[[back to top]](#TOC)**


### <a name='conditionals'>Conditional Expressions & Equality</a>

  - Use shortcuts when you can, unless you need to know the difference between
    `false` and `nil`.

    ```lua
    -- bad
    if name ~= nil then
      -- ...stuff...
    end

    -- good
    if name then
      -- ...stuff...
    end
    ```

  - Minimize branching where it makes sense.
    This will benefit the performance of the code. 

    ```lua
    --bad
    if thing then
      return false
    else
      -- ...do stuff...
    end

    --good
    if thing then
      return false
    end
    -- ...do stuff...
    ```

  - Prefer short code-paths where it makes sense. 

    ```lua
    --bad
    if not thing then
      -- ...stuff with lots of lines...
    else
      x = nil
    end

    --good
    if thing then
      x = nil
    else
      -- ...stuff with lots of lines...
    end
    ```

  - Prefer defaults to `else` statements where it makes sense. This results in
    less complex and safer code at the expense of variable reassignment, so
    situations may differ.

    ```lua
    --bad
    local function full_name(first, last)
      local name

      if first and last then
        name = first .. " " .. last
      else
        name = "John Smith"
      end

      return name
    end

    --good
    local function full_name(first, last)
      local name = "John Smith"

      if first and last then
        name = first .. " " .. last
      end

      return name
    end
    ```

  - Short ternaries are okay.

    ```lua
    local function default_name(name)
      -- return the default "Waldo" if name is nil
      return name or "Waldo"
    end

    local function brew_coffee(machine)
      return machine and machine.is_loaded and "coffee brewing" or "fill your water"
    end
    ```


    **[[back to top]](#TOC)**


### <a name='blocks'>Blocks</a>

  - Single line blocks are okay for *small* statements. Try to keep lines to 80 characters.
    Indent lines if they overflow past the limit.

    ```lua
    -- good
    if test then return false end

    -- good
    if test then
      return false
    end

    -- bad
    if test < 1 and do_complicated_function(test) == false or seven == 8 and nine == 10 then do_other_complicated_function() end

    -- good
    if test < 1 and do_complicated_function(test) == false or
       seven == 8 and nine == 10 then

      do_other_complicated_function() 
      return false 
    end
    ```

    **[[back to top]](#TOC)**


### <a name='whitespace'>Whitespace</a>

  - Use soft tabs set to 2 spaces. Tab characters and 4-space tabs result in public flogging.

    ```lua
    -- bad
    function() 
    ∙∙∙∙local name
    end

    -- bad
    function() 
    ∙local name
    end

    -- good
    function() 
    ∙∙local name
    end
    ```

  - Place 1 space before opening and closing braces. Place no spaces around parens.

    ```lua
    -- bad
    local test = {one=1}

    -- good
    local test = { one = 1 }

    -- bad
    dog.set("attr",{
      age = "1 year",
      breed = "Bernese Mountain Dog",
    })

    -- good
    dog.set("attr", {
      age   = "1 year",
      breed = "Bernese Mountain Dog",
    })
    ```

  - Place an empty newline at the end of the file.

    ```lua
    -- bad
    (function(global) 
      -- ...stuff...
    end)(self)
    ```

    ```lua
    -- good
    (function(global) 
      -- ...stuff...
    end)(self)
         --> invisible newline here
    ```

  - Surround operators with spaces.

    ```lua
    -- bad
    local thing=1
    thing = thing-1
    thing = thing*1
    thing = "string".."s"

    -- good
    local thing = 1
    thing = thing - 1
    thing = thing * 1
    thing = "string" .. "s"
    ```

  - Use one space after commas.

    ```lua
    --bad
    local thing = {1,2,3}
    thing = { 1 , 2 , 3 }
    thing = { 1 ,2 ,3 }

    --good
    local thing = { 1, 2, 3 }
    ```

  - Add double line breaks after top level functional blocks. Top level blocks
    are 'requires', 'shadow-globals', 'constants', and 'functions'.

    ```lua
    -- bad
    local x = require("x")
    local y = require("y")
    local insert = table.insert
    local remove = table.remove
    local NEVER_CHANGES = "different again"
    local function does_cool_stuff()
      -- totally cool stuff here
    end
    local function does_hot_stuff()
      -- totally hot stuff here
    end
    return {
      NEVER_CHANGES = NEVER_CHANGES,
      cool = does_cool_stuff,
      hot = does_hot_stuff,
    }
    
    -- good
    local x = require("x")
    local y = require("y")


    local insert = table.insert
    local remove = table.remove


    local NEVER_CHANGES = "different again"


    local function does_cool_stuff()
      -- totally cool stuff here
    end


    local function does_hot_stuff()
      -- totally hot stuff here
    end


    return {
      NEVER_CHANGES = NEVER_CHANGES,
      cool = does_cool_stuff,
      hot = does_hot_stuff,
    }
    ```

  - Add a line break after multiline blocks and before `else` and `elseif` blocks.

    ```lua
    --bad
    if thing then
      -- ...stuff...
    end
    function derp()
      -- ...stuff...
    end
    local wat = 7
    if x == y then
      -- ...stuff...
    elseif
      -- ...stuff...
    else
      -- ...stuff...
    end

    --good
    if thing then
      -- ...stuff...
    end


    function derp()
      -- ...stuff...
    end


    local wat = 7


    if x == y then
      -- ...stuff...

    elseif
      -- ...stuff...

    else
      -- ...stuff...
    end
    ```

  - Delete trailing whitespace at the end of lines.

    **[[back to top]](#TOC)**

### <a name='commas'>Commas</a>

  - Trailing commas are encouraged as they reduce the diff size when reviewing.

    ```lua
    -- bad
    local thing = {
      once = 1,
      upon = 2,
      aTime = 3
    }

    -- good
    local thing = {
      once  = 1,
      upon  = 2,
      aTime = 3,
    }
    ```

    **[[back to top]](#TOC)**


### <a name='type-coercion'>Type Casting & Coercion</a>

  - Perform type coercion at the beginning of the statement. Use the built-in functions. (`tostring`, `tonumber`, etc.)

  - Use `tostring` for strings if you need to cast without string concatenation.

    ```lua
    -- bad
    local total_score = review_score .. ""

    -- good
    local total_score = tostring(review_score)
    ```

  - Use `tonumber` for Numbers.

    ```lua
    local inputValue = "4"

    -- bad
    local val = inputValue * 1

    -- good
    local val = tonumber(inputValue)
    ```

    **[[back to top]](#TOC)**


### <a name='naming-conventions'>Naming Conventions</a>

  - Use descriptive names. Use more descriptive names for variables with larger scopes,
    single letter names are ok for small scopes.

    ```lua
    -- bad
    local x = "a variable that will used through out an entire module"
    local sum
    for some_very_long_name = 1, 5
      sum = sum + some_very_long_name
    end
    
    -- good
    local descriptive_name = "a variable that will used through out an entire module"
    local sum
    for i = 1, 5
      sum = sum + i
    end
    ```

  - Use underscores for ignored variables in loops or when ignoring (intermediate) return values.
    Ignoring trailing return values with underscores is ok if it enhances clarity.

    ```lua
    --good
    for _, name in pairs(names) do
      -- ...stuff...
    end
    local result1, _, result3 = returns_three_values()
    ```

    ```lua
    --ok
    local some_value, _, _ = returns_three_values()
    ```

  - Use snake_case when naming objects, functions, and instances. Tend towards
    verbosity if unsure about naming.

    ```lua
    -- bad
    local OBJEcttsssss = {}
    local thisIsMyObject = {}
    local this-is-my-object = {}

    local c = function()
      -- ...stuff...
    end

    -- good
    local this_is_my_object = {}

    local function do_that_thing()
      -- ...stuff...
    end
    ```

  - Use PascalCase for factories.

    ```lua
    -- bad
    local player = require("player")

    -- good
    local Player = require("player")
    local me = Player({ name = "Jack" })
    ```

  - Use `is` or `has` for boolean-returning functions.

    ```lua
    --bad
    local function evil(alignment)
      return alignment < 100
    end

    --good
    local function is_evil(alignment)
      return alignment < 100
    end
    ```

    **[[back to top]](#TOC)**

### <a name='modules'>Modules</a>

  - The module should return a table or function.
  - The module should not use the global namespace for anything ever.
  - The file should be named like the module.
  - The layout of a module is based on top level blocks with proper white
    space, separated by 2 blank lines (see [Whitespace](#whitespace)).

    **[[back to top]](#TOC)**

Thanks for making it to the bottom! Yes, there are a lot of guidelines 
herein - and yes, following them is important. Everyone that uses and 
contributes to Kong benefits from your efforts to adhere to these guidelines, 
to the best of your abilities. Thanks!
