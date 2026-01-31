# MiniML
- MiniML interpreter generating C code
# Credits
[@hellerve - Python Implementation](https://github.com/hellerve-pl-experiments/microml)
- Essentially a copy of the idea but in Lua.
## Deps 
- Lpeg - lexer.lua
- GCC - compile.lua
- Ran with `LuaJIT 2.1.1741730670` .
## Example
```lua
local compiler = require("compile")
local c = compiler.new(false) -- true = prints types after parsing.
c:compile("x y z = if y < z then y * z else y / z")
c:compile("main = lambda -> print(x(1,2))")
print("Executing...")
c:execute()
```
## Pipeline
- `compiler:new()` 
    1. lex and parse src
    2. assign types
    3. generate equations & unify
    4. Looks for `main` function to insert into code.
- `compiler:execute()` 
    - generates a temporary C file, compiles it, and runs it.









