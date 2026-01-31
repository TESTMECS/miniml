--[[
-- Run the example
--]]
local compiler = require("compile")
local c = compiler.new(false)
c:compile("x y z = if y < z then y * z else y / z")
c:compile("main = lambda -> print(x(1,2))")
print("About to execute...")
c:execute()
