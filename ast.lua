local exceptions = require("exceptions")
local unpack = unpack or table.unpack ---@diagnostic disable-line
-- Base node ------------------------------------------------
---@class Node
---@field typ Type
---@field children Node[]
---@field compile fun(self:Node, unifier:any):string
---@field eval fun(self:Node, env:any):any
local Node = {}
Node.__index = Node
Node.visit_children = function(self, f)
	if not self.children then
		return
	end
	for _, c in ipairs(self.children) do
		f(c)
	end
end
-- Values --------------------------------------------------
---@class Val:Node
---@field value any
local Val = setmetatable({}, Node)
Val.__index = Val
Val.new = function(value)
	return setmetatable({ value = value }, Val)
end
Val.__tostring = function(self)
	return tostring(self.value)
end
Val.compile = function(self)
	return tostring(math.floor(self.value))
end
-- Int -----------------------------------------------------
---@class IntVal:Val
---@field value number
local Int = setmetatable({}, Val)
Int.__index = Int
Int.new = function(v)
	return setmetatable({ value = v }, Int)
end
Int.eval = function(self)
	return math.floor(self.value)
end
-- Bool ----------------------------------------------------
---@class BoolVal:Val
---@field value boolean
local Bool = setmetatable({}, Val)
Bool.__index = Bool
Bool.new = function(v)
	return setmetatable({ value = v }, Bool)
end
Bool.eval = function(self)
	return not not self.value
end
-- Id ------------------------------------------------------
---@class Id:Node
---@field name string
local Id = setmetatable({}, Node)
Id.__index = Id
Id.new = function(name)
	return setmetatable({ name = name }, Id)
end
Id.__tostring = function(self)
	return self.name
end
Id.compile = function(self)
	return self.name
end
Id.eval = function(self, env)
	return env[self.name]
end
-- Operators ----------------------------------------------
local OPERATORS = {
	["+"] = function(a, b)
		return a + b
	end,
	["-"] = function(a, b)
		return a - b
	end,
	["*"] = function(a, b)
		return a * b
	end,
	["/"] = function(a, b)
		return a / b
	end,
	["<"] = function(a, b)
		return a < b
	end,
	["<="] = function(a, b)
		return a <= b
	end,
	[">"] = function(a, b)
		return a > b
	end,
	[">="] = function(a, b)
		return a >= b
	end,
	["=="] = function(a, b)
		return a == b
	end,
}
-- Op ------------------------------------------------------
---@class Op:Node
---@field op string
---@field left Node
---@field right Node
local Op = setmetatable({}, Node)
Op.__index = Op
Op.new = function(op, left, right)
	return setmetatable({
		op = op,
		left = left,
		right = right,
		children = { left, right },
	}, Op)
end
Op.__tostring = function(self)
	return ("(%s %s %s)"):format(self.left, self.op, self.right)
end
Op.compile = function(self, unifier)
	return ("%s %s %s"):format(self.left:compile(unifier), self.op, self.right:compile(unifier))
end
Op.eval = function(self, env)
	return OPERATORS[self.op](self.left:eval(env), self.right:eval(env))
end
-- App -----------------------------------------------------
---@class App:Node
---@field f Node
---@field args Node[]
local App = setmetatable({}, Node)
App.__index = App
App.new = function(f, args)
	return setmetatable({
		f = f,
		args = args or {},
		children = { f, unpack(args or {}) },
	}, App)
end
App.__tostring = function(self)
	local parts = {}
	for i, a in ipairs(self.args) do
		parts[i] = tostring(a)
	end
	return ("%s(%s)"):format(self.f, table.concat(parts, ", "))
end
App.compile = function(self, unifier)
	local parts = {}
	for i, a in ipairs(self.args) do
		parts[i] = a:compile(unifier)
	end
	return ("%s(%s)"):format(self.f, table.concat(parts, ", "))
end
App.eval = function(self, env)
	local f = self.f:eval(env)
	local args = {}
	for i, a in ipairs(self.args) do
		args[i] = a:eval(env)
	end
	return f:eval(env, args)
end
-- If ------------------------------------------------------
---@class If:Node
---@field ifx Node
---@field thenx Node
---@field elsex Node
local If = setmetatable({}, Node)
If.__index = If
If.new = function(cond, thenx, elsex)
	return setmetatable({
		ifx = cond,
		thenx = thenx,
		elsex = elsex,
		children = { cond, thenx, elsex },
	}, If)
end
If.__tostring = function(self)
	return ("(if %s then %s else %s)"):format(self.ifx, self.thenx, self.elsex)
end
If.compile = function(self, unifier)
	return ("%s ? %s : %s"):format(self.ifx:compile(unifier), self.thenx:compile(unifier), self.elsex:compile(unifier))
end
If.eval = function(self, env)
	if self.ifx:eval(env) then
		return self.thenx:eval(env)
	end
	return self.elsex:eval(env)
end
-- Lambda --------------------------------------------------
---@class Lambda:Node
---@field argnames string[]
---@field expr Node
---@field argtypes any[]
local Lambda = setmetatable({}, Node)
Lambda.__index = Lambda
Lambda.new = function(argnames, expr)
	return setmetatable({
		argnames = argnames,
		expr = expr,
		children = { expr },
		argtypes = nil,
	}, Lambda)
end
Lambda.__tostring = function(self)
	local arg_str = ""
	for i, arg in ipairs(self.argnames) do
		if i > 1 then
			arg_str = arg_str .. ", "
		end
		arg_str = arg_str .. arg
	end
	return ("(lambda %s -> %s)"):format(arg_str, self.expr)
end
Lambda.eval = function(self, env, args)
	if #args ~= #self.argnames then
		error(exceptions.MLEvalException.new(("lambda expected %d args, got %d"):format(#self.argnames, #args)))
	end
	local new_env = {}
	for k, v in pairs(env) do
		new_env[k] = v
	end
	for i, name in ipairs(self.argnames) do
		new_env[name] = args[i]
	end
	return self.expr:eval(new_env)
end
Lambda.compile = function(self, unifier)
	local typ = unifier(self.expr.typ):to_c()
	local compiled = self.expr:compile(unifier)
	local body = string.format("return %s;", compiled)

	local args = {}
	for _, name in ipairs(self.argnames) do
		table.insert(args, string.format("%s %s", unifier(self.argtypes[name]):to_c(), name))
	end

	local body_lines = {}
	for line in body:gmatch("[^\n]+") do
		table.insert(body_lines, "  " .. line)
	end

	return string.format("(%s) {\n%s\n}", table.concat(args, ", "), table.concat(body_lines, "\n"))
end
-- Decl ----------------------------------------------------
---@class Decl:Node
---@field name string
---@field expr Node
local Decl = setmetatable({}, Node)
Decl.__index = Decl
Decl.new = function(name, expr)
	return setmetatable({
		name = name,
		expr = expr,
		children = { expr },
	}, Decl)
end
Decl.__tostring = function(self)
	return ("%s = %s"):format(self.name, self.expr)
end
Decl.eval = function(self, env)
	env[self.name] = self.expr
end
Decl.compile = function(self, unifier)
	if getmetatable(self.expr) == Lambda then
		-- Generate a proper C function with arguments
		local args = {}
		for i, name in ipairs(self.expr.argnames) do
			args[i] = "int " .. name
		end
		local argstr = ""
		for i, arg in ipairs(args) do
			if i > 1 then
				argstr = argstr .. ", "
			end
			argstr = argstr .. arg
		end
		return ("int %s(%s) {\n    return %s;\n}"):format(self.name, argstr, self.expr.expr:compile(unifier))
	else
		-- Simple function with no arguments
		return ("int %s() {\n    return %s;\n}"):format(self.name, self.expr:compile(unifier))
	end
end
return {
	Node = Node,
	Val = Val,
	Int = Int,
	Bool = Bool,
	Id = Id,
	Op = Op,
	App = App,
	If = If,
	Lambda = Lambda,
	Decl = Decl,
}
