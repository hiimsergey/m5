# m5
A conditional text transformer, written in Zig.

Intended as a dead-simple alternative to m4.

## Goals
- m5 is a line-based preprocessor, kind of like the C preprocessor, meaning it only supports adding/removing entire lines, unlike m4, which can also preprocess inline. That makes the syntax much easier.
- m5 files should be valid files in their respective language. m5 syntax can be hidden in any comment syntax with the `--prefix` flag, for example in programming language comments.
- The syntax should be brief and intuitive.
- Parsing multiple files should be possible with the use of stdin.

## Usage
```
Usage: m5 [<options>] <input>

Options:
  --help               print this message
  --safe               exit with error on encountering undefined macro

  -o:<file>            write result into file
                         if not given, write to stdout
  -p:<text>            set string marking beginning of m5 directive lines
                         if value not given, default is "m5"
  -d:<key>[=<number>]  define macro with value
                         if value not given, default is 1
```

m5 takes an input file (or a text stream through stdin, more below) and generates a single output file (or stdout) with the m5-specific syntax processed.

The program differentiates between normal lines and directive lines. The latter start with a special sequence called "prefix" and use an m5 keyword.

### Basic example
```
m5 if alice
hi alice
m5 end
```

Given this as the input file, m5 will only include `hi alice` in the output if the macro `alice` is defined with a truthy value, i.e. anything except 0. To do so, run:

```sh
$ m5 input.txt -d:alice
```

The string `m5` in the file is the prefix. Only lines starting with the prefix, preceeded by any amount whitespace, are read as m5 directives.

By default, the output will go to stdout. Alternatively, you can set an output file:

```sh
$ m5 input.txt -d:alice -o:output.txt
```

The order of CLI arguments doesn't matter.

### Taking stdin
Instead of an input, m5 also supports receiving input through piping:

```sh
$ cat input.txt | grep -v pattern | m5 -o:output.txt
```

### Setting a custom prefix
```
.if bob
if you see this, 'bob' is set to true
.end
```

The default prefix `m5` can be overridden with with -p flag:

```
$ m5 input.txt -o:output.txt -p:.
```

### Keywords
Only `if`, `else` and `end` are m5 keywords.

```
m5 if PlanA
primary case
m5 else
you only see this text if PlanA is set to false
m5 end
```

Like programming languages, m5 supports the concept of "else if":

```
m5 if PlanA
primary case, again
m5 else if PlanB
PlanA is false but thankfully PlanB is true
m5 end
```

To allow clarity, the end keyword doesn't care what follows it:

```
m5 if showLongText
...
...
...
m5 end if-clause for showLongText
```

### Scoping
if-blocks may be nested. m5 doesn't care about indentation, as long as there's the prefix:

```
m5 if a
m5 if b

both a and b hold

m5 else

only a holds

    m5 end (belongs to b)
m5 end (belongs to a)
```

### Comparisons
If you define a macro by name only, it gets the value 1. But you also give it any numeric integer value representable with an `intptr_t` (also known as `isize` in Rust and Zig) and use comparison operators:

```
m5 if year < 2026
using in-dev version
m5 else
using post-1.0 version
m5 end

m5 if one = 1
m5 if two >= 2
lgtm
m5 end
m5 end
```

As you see, m5 uses a single `=` for equality comparisons.

You can also chain comparions, as usually seen in mathematical notation:

```
m5 if 1 < 2 < 3
absolute order \o/
m5 end

m5 if 4 < 6 < 5
you won't see this line
m5 else
lgtm
m5 end
```

### Logic gates
Additionally, you can treat macros as booleans. If one has the value 0, it's treated as falsy, otherwise truthy.

```
m5 if one = 1 & two = 2 & three = 3
lgtm
m5 end

m5 if linux | macos | bsd
not using windows
m5 end

m5 if false & true | true
AND and OR have the same precedence and are thus evaluated left-to-right
m5 end
```

### Complex expressions
Logical comparsions themselves evaluate to either 1 or 0, so they can be mixed with numeric comparisons:

```
m5 if (linux | macos) = 1
not using windows
m5 end
```

As you, you are free to use parentheses to enforce precedence

### Safe mode
By default, undefined macros are treated as if they have the value 0. If you want m5 to abort with an error message, use the `--safe` flag:

```
m5 if undefined
oh oh
m5 end
```

```sh
$ m5 input.txt -o:output.txt --safe
error: line 1: Undefined macro found! (You see this error because of --safe)
```

## Real world example
Take a look at my own Neovim configuration that I share with my friends [over here](https://github.com/mminl-de/aldivim). Different preferences are guard with m5 if-blocks.

## Installation
Your available options to obtain m5 are
- install a binary from the [Releases page](https://github.com/hiimsergey/m5/releases/latest) or
- compile from source (see below)

```sh
git clone https://github.com/hiimsergey/m5
cd m5
zig build -Doptimize=ReleaseSmall
```

The resulting binary appears at `./zig-out/bin/m5`.
