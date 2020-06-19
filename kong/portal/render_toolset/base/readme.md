
# Base()
* `base` methods are always included as chainable methods, and are dynamically included based off of the current type of return value at a given time (if the last method returns a string, the table, the `table` methods will be available).
---
## :table(_arg_)
- **description**
  - sets the chain context as table passed as an argument.
- **arguments**
  - _arg_ - list or table
- **return type**
  - _list_ or _table_
- **examples**
```
<!-- table example -->
base():table({ a = "dog", b = "cat", c = "bat" }):print()

<!-- result -->
{ a = "dog", b = "cat", c = "bat" }
```

```
<!-- list example -->
base():table({ "dog", "cat", "bat" }):print()

<!-- result -->
{ "dog", "cat", "bat" }
```


#### :filter(_callback_)
- **description**
  - iterates over a table of key value pairs, and filters based upon a the boolean result of a passed in callback
- **arguments**
  - _callback_ - function in which to filter table or list by.
- **return type**
  - _list_ or _table_
- **examples**
```
<!-- table example -->
base()
  :table({ a = "dog", b = "cat", c = "bat" })
  :filter(function(k, v)
    return v == "dog"
  end)
  :print()

<!-- result -->
{ a = "dog" }
```

```
<!-- list example -->
base()
  :table({ "dog", "cat", "bat" })
  :filter(function(i, v)
    return v == "dog"
  end)
  :print()

<!-- result -->
{ "dog" }
```


#### :sub(_first_idx_, _last_idx_)
- **description**
  - Extract a range from a table, like ‘string.sub’. If first or last are negative then they are relative to the end of the list eg. sub(t,-2) gives last 2 entries in a list, and sub(t,-4,-2) gives from -4th to -2nd
- **arguments**
  - _first_idx_ - index to begin slice
  - _last_idx_ - index to end slice
- **return type**
  - _any_
- **examples**
```
<!-- positive index example -->
base()
  :table({ "a", "b", "c", "d", "e" })
  :sub(2, 4)
  :print()

<!-- result -->
{ "b", "c", "d" }
```

```
<!-- negative index example -->
base()
  :table({ "a", "b", "c", "d", "e" })
  :sub(-2, -1)
  :print()

<!-- result -->
{ "d", "e" }
```

#### :keys()
- **description**
  - return all the keys of a table in arbitrary order
- **return type**
  - _list_
- **examples**
```
<!-- table example -->

base()
  :table({ x = "value_x", y = "value_y", z = "value_z" })
  :keys()
  :print()

<!-- result -->
{ "x", "y", "z" }
```


#### :values()
- **description**
  - return all the values of the table in arbitrary order
- **return type**
  - _list_
- **examples**
```
<!-- table example -->

base()
  :table({ x = "value_x", y = "value_y", z = "value_z" })
  :values()
  :print()

<!-- result -->
{ "value_x", "value_y", "value_z" }
```


#### :val(_key_)
- **description**
  - returns value based off of a passed key, or chain of keys
- **arguments**
  - _key_ - string representing a key, or string of keys (for nested values)
- **return type**
  - _any_
- **examples**
```
<!-- non-nested example -->
base()
  :table({ x = "value_x", y = "value_y" })
  :val("x")
  :print()

<!-- result -->
"value_x"
```
```
<!-- nested example -->
base()
  :table({
    x = {
      y = {
        z = {
          key = "value"
        }
      }
    }
  })
  :val("x.y.z.key")
  :print()

<!-- result -->
"value"
```


#### :idx(_i_)
- **description**
  - returns value based off of a passed idx
- **arguments**
  - _i_ - number representing an index
- **return type**
  - _any_
- **examples**
```
<!-- non-nested example -->
base()
  :table({ "a", "b", "c" })
  :val("a")
  :print()

<!-- result -->
"a"
```


#### :size()
- **description**
  - total number of elements in this table
- **return type**
  - _number_
- **examples**
```
<!-- table example -->

base()
  :table({ x = "value_x", y = "value_y", z = "value_z" })
  :size()
  :print()

<!-- result -->
3
```

```
<!-- list example -->

base()
  :table({ "x", "y", "z" })
  :size()
  :print()

<!-- result -->
3
```

#### :pairs()
- **description**
  - iterates over table or list within the context of a template
- **return type**
  - _any_
- **examples**
```
<!-- table example -->

{% for k, v in base():table({ x = "a", y = "b", z = "c" }):pairs() do %}
  <p>{{k}}-{{v}}</p>\n
{% end %}

<!-- result -->
<p>x-a</p>
<p>y-b</p>
<p>z-c</p>
```
```
<!-- list example -->

{% for i, v in  base():table({ "a", "b", "c" }):pairs() do %}
  <p>{{i}}-{{v}}</p>\n
{% end %}

<!-- result -->
<p>1-a</p>
<p>2-b</p>
<p>3-c</p>
```


#### :sortv(_callback_)
- **description**
  - iterates over table or list after sorting by value
- **arguments**
  - _callback_ - Optional sort function that takes two arguments. Overrides default sorting implementation
- **return type**
  - _list_
- **examples**
```
<!-- default example -->

{% for k, v in base():table({ z = "c",  y = "b", x = "a"}):sortv() do %}
  <p>{{k}}-{{v}}</p>\n
{% end %}

<!-- result -->
<p>x-a</p>
<p>y-b</p>
<p>z-c</p>
```
```
<!-- example with arg -->

{%
  for i, v in  base():table({ z = "c",  y = "b", x = "a"}):sortv(function(a, b)
    return a > b
  end) do
%}

  <p>{{i}}-{{v}}</p>\n
{% end %}

<!-- result -->
<p>z-c</p>
<p>y-b</p>
<p>x-a</p>
```


#### :sortk(_callback_)
- **description**
  - iterates over table or list after sorting by key
- **arguments**
  - _callback_ - Optional sort function that takes two arguments. Overrides default sorting implementation
- **return type**
  - _list_
- **examples**
```
<!-- default example -->

{% for k, v in base():table({ z = "c",  y = "b", x = "a"}):sortk() do %}
  <p>{{k}}-{{v}}</p>\n
{% end %}

<!-- result -->
<p>x-a</p>
<p>y-b</p>
<p>z-c</p>
```
```
<!-- example with arg -->

{%
  for i, v in  base():table({ z = "c",  y = "b", x = "a"}):sortk(function(a, b)
    return a > b
  end) do
%}

  <p>{{i}}-{{v}}</p>\n
{% end %}

<!-- result -->
<p>z-c</p>
<p>y-b</p>
<p>x-a</p>
```


## :string()
- **description**
  - sets the chain context string passed as an argument
- **return type**
  - _string_
- **examples**
```
<!-- table example -->
base():string("dog"):print()

<!-- result -->
"dog"
```

#### :upper()
- **description**
  - changes lowercase characters in a string to uppercase
- **return type**
  - _string_
- **examples**
```
base()
  :string("dog")
  :upper()
  :print()

<!-- result -->
"DOG"
```

#### :lower()
- **description**
  - changes uppercase characters in a string to lowercase
- **return type**
  - _string_
- **examples**
```
base()
  :string("DOG")
  :lower()
  :print()

<!-- result -->
"dog"
```

#### :gsub(_s_, _r_, _[n]_)
- **description**
  - replaces all occurrences of a pattern in a string
- **arguments**
  - _s_ - string delimiter to be replaces
  - _r_ - replacement string or function returning a string
  - _n (optional) -_ number of occurances to replace
- **return type**
  - _string_
- **examples**
```
<!-- replace all occurances -->
base()
  :string("moose")
  :gsub("o", "V")
  :print()

<!-- result -->
"mVVse"
```
```
<!-- replace all set ammount of occurances -->
base()
  :string("moose")
  :gsub("o", "V", 1)
  :print()

<!-- result -->
"mVose"
```
```
<!-- uses function to evaluate replacements -->
base()
  :string("moose")
  :gsub("o", function(v)
    return v .. "U"
  end)
  :print()

<!-- result -->
"moUoUse"
```

#### :len()
- **description**
  - returns the length of a string (number of characters)
- **return type**
  - _number_
- **examples**
```
base()
  :string("dog")
  :len()
  :print()

<!-- result -->
3
```

#### :reverse()
- **description**
  - reverses a string
- **return type**
  - _string_
- **examples**
```
base()
  :string("dog")
  :reverse()
  :print()

<!-- result -->
"god"
```

#### :split(_s_, _[n]_)
- **description**
  - split a string into a list of strings using a delimiter
- **arguments**
  - _s_ - string delimiter to be replaces
  - _n (optional) -_ number of occurances to replace
- **return type**
  - _list_
- **examples**
```
<!-- split by delimiter -->
base()
  :string("d.o.g")
  :split(".")
  :print()

<!-- result -->
'{ "d", "o", "g" }'
```
```
<!-- split by delimiter with limit -->
base()
  :string("d.o.g")
  :split(".", 2)
  :print()

<!-- result -->
{ "d", "og" }
```
