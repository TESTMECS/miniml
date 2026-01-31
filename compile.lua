local os = require("os")
local io = require("io")
local parser = require("parser")
local typing = require("typing")
local exceptions = require("exceptions")

local PRELUDE = [[
#include <stdio.h>

int print(int in) {
    printf("%d\n", in);
    return 0;
}
]]
---@class Compiler
---@field interactive boolean: for printing type info
---@field p Parser
---@field equations table
---@field symtab table<string, Type>
---@field code table
---@field main number
---@field unifier table
local Compiler = {}
Compiler.__index = Compiler
Compiler.new = function(interactive)
	return setmetatable({
		interactive = interactive ~= false,
		p = parser.new(),
		equations = {},
		symtab = { print = typing.Func.new({ typing.Int.new() }, typing.Int.new()) },
		code = {},
		main = -1,
		unifier = nil,
	}, Compiler)
end
-- Compile source, assign types, generate equations, unify
Compiler.compile = function(self, source)
	local parsed, pos = self.p:parse(source, self.interactive)

	if self.symtab[parsed.name] then
		print(string.format("Warning! Redefining %s!", parsed.name))
	end

	-- assign types
	local st = typing.assign_typenames(parsed.expr, self.symtab)
	for k, v in pairs(st) do
		self.symtab[k] = v
	end

	-- generate equations and unify
	local eqs = typing.generate_equations(parsed.expr)
	for _, e in ipairs(eqs) do
		table.insert(self.equations, e)
	end
	self.unifier = typing.unify_equations(self.equations)

	local t = typing.get_expression_type(parsed.expr.typ, self.unifier)

	if self.interactive then
		local name
		if t.argtypes then
			name = string.format("(lambda %s -> %s)", table.concat(t.argtypes, ", "), t.rettype.name or "")
		elseif t.rettype then
			name = string.format("%s", t.rettype.name)
		elseif t.name then
			name = string.format("%s", t.name)
		end
		print(string.format("%s :: %s\n", parsed, name))
		-- print(vim.inspect(t))
	end

	self.symtab[parsed.name] = t

	if parsed.name == "main" then
		self.main = #self.code + 1
	end

	table.insert(self.code, parsed)
	return pos
end

-- Get type function for codegen
Compiler.get_type = function(self)
	local self_ref = self
	return function(x)
		return typing.get_expression_type(x, self_ref.unifier)
	end
end

-- Interpreter mode
Compiler.interpret = function(self)
	local Printr = {}
	function Printr:eval(_env, arg)
		print(arg[1])
	end

	local env = { print = Printr }
	for _, node in ipairs(self.code) do
		node:eval(env)
	end

	if env.main then
		local ok, err = pcall(function()
			env.main:eval(env, {})
		end)
		if not ok then
			error(exceptions.MLEvalException.new(err))
		end
	end
end

-- Execute by generating C, compiling, and running
Compiler.execute = function(self)
	if #self.code == 0 then
		error(exceptions.MLCompilerException.new("Nothing to execute!"))
	end
	if self.main == -1 then
		error(exceptions.MLCompilerException.new("No `main` function specified!"))
	end

	local main_node = self.code[self.main]
	local lines = { PRELUDE }

	-- compile non-main nodes
	for _, node in ipairs(self.code) do
		if node ~= main_node then
			table.insert(lines, node:compile(self:get_type()))
		end
	end
	table.insert(lines, main_node:compile(self:get_type()))

	local compiled = table.concat(lines, "\n")

	-- write temporary C file
	local cfile = os.tmpname() .. ".c"
	local exe = os.tmpname()

	local f = io.open(cfile, "w")
	if f == nil then
		error(exceptions.MLCompilerException.new("Could not open temporary C file!"))
	end
	f:write(compiled)
	f:close()

	local cc = os.getenv("CC") or "gcc"
	local compile_cmd = string.format("%s %s -o %s", cc, cfile, exe)
	local ok = os.execute(compile_cmd)
	if ok ~= 0 then
		error(exceptions.MLCompilerException.new("Compilation failed!"))
	end

	local run_cmd = exe
	ok = os.execute(run_cmd)
	if ok ~= 0 then
		error(exceptions.MLCompilerException.new("Execution failed!"))
	end
end
return Compiler
