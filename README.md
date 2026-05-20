# m5
A conditional text transformer, written in Zig.

Intended as a dead-simple alternative to m4.

## Goals
- m5 is a line-based preprocessor, like [cpp](https:/example.com/TODO), meaning it only supports adding/removing entire lines, unlike m4, which can also preprocess inline. That makes the syntax much easier.
- m5 files should be valid files in their respective language. m5 syntax can be hidden in any comment syntax with the `--prefix` flag, for example in programming language comments.
- The syntax should be brief and intuitive.
- Parsing multiple files should be possible with the use of stdin.

## Usage
m5 takes an input file (or a text stream through stdin, more below) and generates a single output file with the m5-specific syntax processed.

The program differentiates between normal lines and directive lines. The latter start with a special sequence called "prefix" and use an m5 keyword.

### Basic example
```
m5 if alice
hi alice
m5 end
```

Given this as the input file, m5 will only include `hi alice` in the output if the variable "alice" is set to true. To do so, run:

```sh
m5 input.txt -o:output.txt -d:alice
```

The string `m5` in the file is the prefix. Only lines starting with the prefix, optionally preceeded by whitespace are read as m5 directives.

### Setting a custom prefix
```sh
.if bob
if you see this, 'bob' is set to true
.end
```

The default prefix `m5` can be overridden with with -p flag:

```sh
m5 input.txt -o:output.txt -p:"."
```

### Keywords
Only `if`, `else` and `end` are m5 keywords.

```sh
m5 if PlanA
primary case
m5 else
you only see this text if PlanA is set to false
m5 end
```

Like programming languages, m5 supports the concept of "else if":

```sh
m5 if PlanA
primary case, again
m5 else if PlanB
PlanA is false but thankfully PlanB is true
m5 end
```

For the sake of clarity, the end keyword doesn't care what follows it:

```sh
m5 if showLongText
...
...
...
m5 end if-clause for showLongText
```

### Scoping
TODO MENTION nested
TODO MENTION idc about indentation, as long as prefix is there

TODO PLAN if-else
TODO PLAN usage of end keyword
TODO PLAN nested ifs

TODO MENTION safe mode
TODO MENTION stdin
TODO MENTION & and |
TODO MENTION cmp

TODO PLAN real code usage (lua)

TODO add cli samples for necessary syntax examples
TODO CONSIDER REMOVE [[#CLI usage]]

## CLI usage
```
Usage: m5 [<options>] <input>

Options:
  --help               print this message
  --safe               exit with error on encountering undefined variable

  -o:<file>            write result into file
                         if not given, write to stdout
  -p:<text>            set string marking beginning of m5 directive lines
                         if value not given, default is "m5"
  -d:<key>[=<number>]  define variable with value
                         if value not given, default is 1
```

### CLI examples
```sh
# Parse one file to stdout with "m5" as prefix
m5 input.txt
```

```sh
# Parse one file to ./output.txt with "m5" as prefix
m5 input.txt -o:output.txt
```

```sh
# Parse one file to ./output.c with custom prefix
m5 input.c -o:output.c -p:"// m5"
```

```sh
# Parse one file to stdout with only "alice" set to true
m5 input.txt -d:alice
```

```sh
# Parse one file to stdout with multiple variables set to numeric values
m5 input.txt -d:alice=1 -d:bob=42 -d:charlie=-300
```

```sh
# Parse multiple files to ./output.txt with "m5" as prefix
cat a.txt b.txt c.txt | m5 -o:output.txt
```

## Installation
Your available options to obtain m5 are
- install a binary from the [Releases page](TODO) or
- compile from source (see below)

```sh
git clone https://github.com/hiimsergey/m5
cd m5
zig build -Doptimize=ReleaseFast
```

The resulting binary appears at `./zig-out/bin/m5`.
