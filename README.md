# m5
A dead-simple m4 alternative, written in Zig.

## Goals
- m5 is a line-based preprocessor, like [cpp](https:/example.com/TODO), meaning it only supports adding/removing entire lines, unlike m4, which can also preprocess in-line. That makes the syntax much easier.
- m5 files should be valid files in their respective language. m5 syntax can be hidden in any comment syntax with the `--prefix` flag.
- m5 syntax should be brief and intuitive
- m5 allows preprocessing multiple files with one command, avoiding awkward shell scripts.

## TODO Syntax
m5 only supports if-else blocks with numeric or boolean variables as expressions.

Let's take C as an example and "// m5" as a prefix.

### If clauses
```c
int main(void) {
    // m5 if ALICE
    printf("Hello, Alice!\n");
    // m5 end

	return 0;
}
```

### If-else

### Negating variables

### AND/OR operations

### Numeric arguments

## TODO CLI Usage
```
m5 [OPTIONS]

OPTIONS
	-D[MACRO]=[VALUE]
	-U[MACRO]
	--prefix,  -p [PREFIX]
	--output,  -o [OUTPUT]
	--verbose, -v
```

### Examples
```sh
m5 \
	--prefix "-- m5" -DSERGEY \
	m5/init.m5.lua -o lua/init.lua \
	m5/keys.m5.lua -o lua/keys.lua \
	m5/lazy.m5.lua -o lua/lazy.lua \
	m5/opts.m5.lua -o lua/opts.lua
```

## Preprocessing example
Again, let's take C as an example and "// m5" as a prefix.

```c
// foo.m5.c
int main(void) {
	// m5 if ALICE
	printf("Hello, Alice!\n");
	// m5 end
	
	return 0;
}
```

The command `m5 --prefix "// m5" foo.m5.c -o foo.c` results in this file content at `foo.c`:

```c
// foo.c
int main(void) {
	
	return 0;
}
```

But `m5 --prefix "// m5" -DALICE foo.m5.c -o foo.c` results in:

```c
// foo.c
int main(void) {
	printf("Hello, Alice!\n");
	
	return 0;
}
```
