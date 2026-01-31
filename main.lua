--[[
-- To run the example use 
-- `lua main.lua examples/<filename>`
--]]
local interactive = false
local compiler = require("compile")
local c = compiler.new(interactive)
local filename = arg[1]
assert(filename, "usage: lua main.lua <filename>")

for line in io.lines(filename) do
	if line:match("%S") then
		c:compile(line)
	end
end

print("Executing...")
c:execute()
