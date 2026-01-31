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

local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(interactive)
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
function Compiler:compile(source)
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
		print(string.format("%s :: %s", parsed, t))
	end

	self.symtab[parsed.name] = t

	if parsed.name == "main" then
		self.main = #self.code + 1
	end

	table.insert(self.code, parsed)
	return pos
end

-- Get type function for codegen
function Compiler:get_type()
	local self_ref = self
	return function(x)
		return typing.get_expression_type(x, self_ref.unifier)
	end
end

-- Interpreter mode
function Compiler:interpret()
	local Printr = {}
	function Printr:eval(env, arg)
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
function Compiler:execute()
	if #self.code == 0 then
		error(exceptions.MLCompilerException.new("Nothing to execute!"))
	end
	if self.main == -1 then
		error(exceptions.MLCompilerException.new("No `main` function specified!"))
	end

	local main_node = self.code[self.main]
	local lines = { PRELUDE }

	-- compile non-main nodes
	for i, node in ipairs(self.code) do
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
