local ast = require("ast")
local exceptions = require("exceptions")

-- Base Type ------------------------------------------------

local Type = {}
Type.__index = Type

function Type:__tostring()
	return self.name
end

Type.__repr = Type.__tostring

function Type:equals(other)
	return getmetatable(self) == getmetatable(other)
end

function Type:to_c()
	return self.c
end

-- Int -----------------------------------------------------

local Int = setmetatable({ name = "Int", c = "int" }, Type)
Int.__index = Int

function Int.new()
	return setmetatable({}, Int)
end

-- Bool ----------------------------------------------------

local Bool = setmetatable({ name = "Bool", c = "int" }, Type)
Bool.__index = Bool

function Bool.new()
	return setmetatable({}, Bool)
end

-- Func ----------------------------------------------------

local Func = setmetatable({}, Type)
Func.__index = Func

function Func.new(argtypes, rettype)
	return setmetatable({
		argtypes = argtypes,
		rettype = rettype,
	}, Func)
end

function Func:__tostring()
	if #self.argtypes == 0 then
		return "(-> " .. self.rettype .. ")"
	end
	if #self.argtypes == 1 then
		return "(" .. self.argtypes[1] .. " -> " .. self.rettype .. ")"
	end
	local parts = {}
	for i, a in ipairs(self.argtypes) do
		parts[i] = tostring(a)
	end
	return "(" .. table.concat(parts, " -> ") .. " -> " .. self.rettype .. ")"
end

function Func:equals(other)
	if getmetatable(other) ~= Func then
		return false
	end
	if not self.rettype:equals(other.rettype) then
		return false
	end
	if #self.argtypes ~= #other.argtypes then
		return false
	end
	for i = 1, #self.argtypes do
		if not self.argtypes[i]:equals(other.argtypes[i]) then
			return false
		end
	end
	return true
end

function Func:to_c()
	return self.rettype:to_c()
end

-- TypeVar -------------------------------------------------

local TypeVar = setmetatable({}, Type)
TypeVar.__index = TypeVar

function TypeVar.new(name)
	return setmetatable({ name = name }, TypeVar)
end

function TypeVar:equals(other)
	return getmetatable(other) == TypeVar and self.name == other.name
end

function TypeVar:to_c()
	return self.name
end

-- Fresh type variables -----------------------------------

local type_counter = 0

local function reset_type_counter()
	type_counter = 0
end

local function fresh_typename()
	local n = type_counter
	type_counter = type_counter + 1
	return "t" .. n
end

local function make_type_var()
	return TypeVar.new(fresh_typename())
end

-- Errors --------------------------------------------------

local function exceptor(msg)
	error(exceptions.MLTypingException.new(msg))
end

-- Assign type variables ----------------------------------

local function assign_typenames(node, symtab)
	symtab = symtab or {}

	if getmetatable(node) == ast.Id then
		if symtab[node.name] then
			node.typ = symtab[node.name]
		else
			exceptor('unbound name "' .. node.name .. '"')
		end
	elseif getmetatable(node) == ast.Lambda then
		node.typ = make_type_var()
		local local_symtab = {}
		node.argtypes = {}
		for _, name in ipairs(node.argnames) do
			local_symtab[name] = make_type_var()
			node.argtypes[name] = local_symtab[name]
		end
		local merged = {}
		for k, v in pairs(symtab) do
			merged[k] = v
		end
		for k, v in pairs(local_symtab) do
			merged[k] = v
		end
		assign_typenames(node.expr, merged)
	elseif getmetatable(node) == ast.Op or getmetatable(node) == ast.If or getmetatable(node) == ast.App then
		node.typ = make_type_var()
		node:visit_children(function(c)
			assign_typenames(c, symtab)
		end)
	elseif getmetatable(node) == ast.Int then
		node.typ = Int.new()
	elseif getmetatable(node) == ast.Bool then
		node.typ = Bool.new()
	else
		exceptor("unknown node")
	end

	return symtab
end

-- Equation ------------------------------------------------

local Equation = {}
Equation.__index = Equation

function Equation.new(left, right, original)
	return setmetatable({
		left = left,
		right = right,
		original = original,
	}, Equation)
end

function Equation:__tostring()
	return tostring(self.left) .. " :: " .. tostring(self.right) .. " [from " .. tostring(self.original) .. "]"
end

-- Equation generation ------------------------------------

local BOOL_OPS = {
	["!="] = true,
	["=="] = true,
	[">="] = true,
	["<="] = true,
	[">"] = true,
	["<"] = true,
}

local function generate_equations(node, eqs)
	eqs = eqs or {}

	if getmetatable(node) == ast.Int then
		table.insert(eqs, Equation.new(node.typ, Int.new(), node))
	elseif getmetatable(node) == ast.Bool then
		table.insert(eqs, Equation.new(node.typ, Bool.new(), node))
	elseif getmetatable(node) == ast.Op then
		node:visit_children(function(c)
			generate_equations(c, eqs)
		end)
		table.insert(eqs, Equation.new(node.left.typ, Int.new(), node))
		table.insert(eqs, Equation.new(node.right.typ, Int.new(), node))
		local t = BOOL_OPS[node.op] and Bool.new() or Int.new()
		table.insert(eqs, Equation.new(node.typ, t, node))
	elseif getmetatable(node) == ast.App then
		node:visit_children(function(c)
			generate_equations(c, eqs)
		end)
		local args = {}
		for i, a in ipairs(node.args) do
			args[i] = a.typ
		end
		table.insert(eqs, Equation.new(node.f.typ, Func.new(args, node.typ), node))
	elseif getmetatable(node) == ast.If then
		node:visit_children(function(c)
			generate_equations(c, eqs)
		end)
		table.insert(eqs, Equation.new(node.ifx.typ, Bool.new(), node))
		table.insert(eqs, Equation.new(node.typ, node.thenx.typ, node))
		table.insert(eqs, Equation.new(node.typ, node.elsex.typ, node))
	elseif getmetatable(node) == ast.Lambda then
		node:visit_children(function(c)
			generate_equations(c, eqs)
		end)
		local args = {}
		for _, n in ipairs(node.argnames) do
			table.insert(args, node.argtypes[n])
		end
		table.insert(eqs, Equation.new(node.typ, Func.new(args, node.expr.typ), node))
	end

	return eqs
end

-- Unification --------------------------------------------

local function occurs_check(v, typ, subst)
	if v:equals(typ) then
		return true
	end
	if getmetatable(typ) == TypeVar and subst[typ.name] then
		return occurs_check(v, subst[typ.name], subst)
	end
	if getmetatable(typ) == Func then
		if occurs_check(v, typ.rettype, subst) then
			return true
		end
		for _, a in ipairs(typ.argtypes) do
			if occurs_check(v, a, subst) then
				return true
			end
		end
	end
	return false
end

local function unify_variable(v, typ, subst)
	if subst[v.name] then
		return unify(subst[v.name], typ, subst)
	end
	if getmetatable(typ) == TypeVar and subst[typ.name] then
		return unify(v, subst[typ.name], subst)
	end
	if occurs_check(v, typ, subst) then
		return nil
	end
	subst[v.name] = typ
	return subst
end

function unify(x, y, subst)
	if not subst then
		return nil
	end
	if x:equals(y) then
		return subst
	end

	if getmetatable(x) == TypeVar then
		return unify_variable(x, y, subst)
	end
	if getmetatable(y) == TypeVar then
		return unify_variable(y, x, subst)
	end
	if getmetatable(x) == Func and getmetatable(y) == Func then
		if #x.argtypes ~= #y.argtypes then
			return nil
		end
		subst = unify(x.rettype, y.rettype, subst)
		for i = 1, #x.argtypes do
			subst = unify(x.argtypes[i], y.argtypes[i], subst)
		end
		return subst
	end
	return nil
end

local function unify_equations(eqs)
	local subst = {}
	for _, eq in ipairs(eqs) do
		subst = unify(eq.left, eq.right, subst)
		if not subst then
			break
		end
	end
	return subst
end

-- Apply unifier ------------------------------------------

local function apply_unifier(typ, subst)
	if not subst then
		return nil
	end
	if getmetatable(typ) == Int or getmetatable(typ) == Bool then
		return typ
	end
	if getmetatable(typ) == TypeVar then
		if subst[typ.name] then
			return apply_unifier(subst[typ.name], subst)
		end
		return typ
	end
	if getmetatable(typ) == Func then
		local args = {}
		for i, a in ipairs(typ.argtypes) do
			args[i] = apply_unifier(a, subst)
		end
		return Func.new(args, apply_unifier(typ.rettype, subst))
	end
end

-- Export --------------------------------------------------

return {
	Type = Type,
	Int = Int,
	Bool = Bool,
	Func = Func,
	TypeVar = TypeVar,
	assign_typenames = assign_typenames,
	generate_equations = generate_equations,
	unify_equations = unify_equations,
	apply_unifier = apply_unifier,
	reset_type_counter = reset_type_counter,
}
