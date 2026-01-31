local exceptions = require("exceptions")

-- Base node ------------------------------------------------

local Node = {}
Node.__index = Node

function Node:visit_children(f)
	if not self.children then
		return
	end
	for _, c in ipairs(self.children) do
		f(c)
	end
end

-- Values --------------------------------------------------

local Val = setmetatable({}, Node)
Val.__index = Val

function Val.new(value)
	return setmetatable({ value = value }, Val)
end

function Val:__tostring()
	return tostring(self.value)
end

function Val:compile(unifier)
	return tostring(math.floor(self.value))
end

-- Int -----------------------------------------------------

local Int = setmetatable({}, Val)
Int.__index = Int

function Int.new(v)
	return setmetatable({ value = v }, Int)
end

function Int:eval(env)
	return math.floor(self.value)
end

-- Bool ----------------------------------------------------

local Bool = setmetatable({}, Val)
Bool.__index = Bool

function Bool.new(v)
	return setmetatable({ value = v }, Bool)
end

function Bool:eval(env)
	return not not self.value
end

-- Id ------------------------------------------------------

local Id = setmetatable({}, Node)
Id.__index = Id

function Id.new(name)
	return setmetatable({ name = name }, Id)
end

function Id:__tostring()
	return self.name
end

function Id:compile(unifier)
	return self.name
end

function Id:eval(env)
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

local Op = setmetatable({}, Node)
Op.__index = Op

function Op.new(op, left, right)
	return setmetatable({
		op = op,
		left = left,
		right = right,
		children = { left, right },
	}, Op)
end

function Op:__tostring()
	return ("(%s %s %s)"):format(self.left, self.op, self.right)
end

function Op:compile(unifier)
	return ("%s %s %s"):format(self.left:compile(unifier), self.op, self.right:compile(unifier))
end

function Op:eval(env)
	return OPERATORS[self.op](self.left:eval(env), self.right:eval(env))
end

-- App -----------------------------------------------------

local App = setmetatable({}, Node)
App.__index = App

function App.new(f, args)
	return setmetatable({
		f = f,
		args = args or {},
		children = { f, table.unpack(args or {}) },
	}, App)
end

function App:__tostring()
	local parts = {}
	for i, a in ipairs(self.args) do
		parts[i] = tostring(a)
	end
	return ("%s(%s)"):format(self.f, table.concat(parts, ", "))
end

function App:compile(unifier)
	local parts = {}
	for i, a in ipairs(self.args) do
		parts[i] = a:compile(unifier)
	end
	return ("%s(%s)"):format(self.f, table.concat(parts, ", "))
end

function App:eval(env)
	local f = self.f:eval(env)
	local args = {}
	for i, a in ipairs(self.args) do
		args[i] = a:eval(env)
	end
	return f:eval(env, args)
end

-- If ------------------------------------------------------

local If = setmetatable({}, Node)
If.__index = If

function If.new(cond, thenx, elsex)
	return setmetatable({
		ifx = cond,
		thenx = thenx,
		elsex = elsex,
		children = { cond, thenx, elsex },
	}, If)
end

function If:__tostring()
	return ("(if %s then %s else %s)"):format(self.ifx, self.thenx, self.elsex)
end

function If:compile(unifier)
	return ("%s ? %s : %s"):format(self.ifx:compile(unifier), self.thenx:compile(unifier), self.elsex:compile(unifier))
end

function If:eval(env)
	if self.ifx:eval(env) then
		return self.thenx:eval(env)
	end
	return self.elsex:eval(env)
end

-- Lambda --------------------------------------------------

local Lambda = setmetatable({}, Node)
Lambda.__index = Lambda

function Lambda.new(argnames, expr)
	return setmetatable({
		argnames = argnames,
		expr = expr,
		children = { expr },
		argtypes = nil,
	}, Lambda)
end

function Lambda:__tostring()
	return ("(lambda %s -> %s)"):format(table.concat(self.argnames, ", "), self.expr)
end

function Lambda:eval(env, args)
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

-- Decl ----------------------------------------------------

local Decl = setmetatable({}, Node)
Decl.__index = Decl

function Decl.new(name, expr)
	return setmetatable({
		name = name,
		expr = expr,
		children = { expr },
	}, Decl)
end

function Decl:__tostring()
	return ("%s = %s"):format(self.name, self.expr)
end

function Decl:eval(env)
	env[self.name] = self.expr
end

-- exports -------------------------------------------------

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
