#m5
An audacious m4 alternative, written in Zig.

## TODO goal
- be a line-based preprocessor, as opposed to in-line-based pre-processors as [GNU m4](https://www.gnu.org/software/m4/m4.html)
- let m5 files also be valid files in their respective language
- be brief and readable
- preprocess multiple files with one command

## TODO Syntax
```m4
EXPRESSIONS:
	if [CONDITION] then
	end

	if [CONDITION] then
	else if [CONDITION] then
	end

CONDITIONS:
	+MACRO – MACRO is defined
	-MACRO – MACRO is not defined
	+[M1, M2] – either of M1 or M2 is defined
	+M1 +M2 – both M1 and M2 defined
```

## TODO Usage
```
m5 [OPTIONS]

OPTIONS
	--define,   -D [MACRO]
	--prefix,   -p [PREFIX]
	--output,   -o [OUTPUT]
	--undefine, -U [MACRO]
	--verbose,  -v
```

## TODO Examples
```sh
m5 -D something.m5
```

```sh
m5 \
	--prefix "-- m5" -DSERGEY \
	m5/init.m5.lua -o lua/init.lua \
	m5/keys.m5.lua -o lua/keys.lua \
	m5/lazy.m5.lua -o lua/lazy.lua \
	m5/opts.m5.lua -o lua/opts.lua
```
