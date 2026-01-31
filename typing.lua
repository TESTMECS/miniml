local ast = require("ast")
local exceptions = require("exceptions")
-- Base Type ------------------------------------------------
---@class Type
---@field name string
---@field c string
---@field __tostring fun(self: Type): string
---@field equals fun(self: Type, other: Type): boolean
---@field to_c fun(self: Type): string
local Type = {}
Type.__index = Type
Type.__tostring = function(self)
	return self.name
end
Type.__repr = Type.__tostring
Type.equals = function(self, other)
	return getmetatable(self) == getmetatable(other)
end
Type.to_c = function(self)
	return self.c
end
-- Int -----------------------------------------------------
---@class Int:Type
---@field new fun(): Int
local Int = setmetatable({ name = "Int", c = "int" }, Type)
Int.__index = Int

Int.new = function()
	return setmetatable({}, Int)
end
-- Bool ----------------------------------------------------
---@class Bool: Type
---@field new fun(): Bool
local Bool = setmetatable({ name = "Bool", c = "int" }, Type)
Bool.__index = Bool

Bool.new = function()
	return setmetatable({}, Bool)
end
-- Func ----------------------------------------------------
---@class Func: Type
---@field argtypes Type[]
---@field rettype Type
---@field new fun(argtypes: Type[], rettype: Type): Func
local Func = setmetatable({}, Type)
Func.__index = Func
Func.new = function(argtypes, rettype)
	return setmetatable({
		argtypes = argtypes,
		rettype = rettype,
	}, Func)
end
Func.__tostring = function(self)
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
---@description Check function equality using argtypes
---@param other Func
Func.equals = function(self, other)
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
Func.to_c = function(self)
	return self.rettype:to_c()
end
-- TypeVar -------------------------------------------------
---@class TypeVar:Type
local TypeVar = setmetatable({}, Type)
TypeVar.__index = TypeVar
TypeVar.new = function(name)
	return setmetatable({ name = name }, TypeVar)
end
TypeVar.equals = function(self, other)
	return getmetatable(other) == TypeVar and self.name == other.name
end
TypeVar.to_c = function(self)
	return self.name
end
-- Fresh type variables -----------------------------------
local type_counter = 0
local reset_type_counter = function()
	type_counter = 0
end
---@return string
local fresh_typename = function()
	local n = type_counter
	type_counter = type_counter + 1
	return "t" .. n
end
---@return TypeVar
local make_type_var = function()
	return TypeVar.new(fresh_typename())
end
-- Errors --------------------------------------------------
local exceptor = function(msg)
	error(exceptions.MLTypingException.new(msg))
end
-- Assign type variables ----------------------------------
---@return table<string, Type>
local function assign_typenames(node, symtab)
	symtab = symtab or {}
	if getmetatable(node) == ast.Id then
		-- Lookup Id in symboltable
		if symtab[node.name] then
			node.typ = symtab[node.name]
		else
			error('unbound name "' .. node.name .. '"')
		end
	elseif getmetatable(node) == ast.Lambda then
		node.typ = make_type_var()
		-- Create new scope
		local local_symtab = {}
		node.argtypes = {}
		-- Generate type variables for each argument
		for i, name in ipairs(node.argnames) do
			local_symtab[name] = make_type_var()
			node.argtypes[i] = local_symtab[name]
		end
		-- Merge Symbol table with local scope
		local merged = {}
		for k, v in pairs(symtab) do
			merged[k] = v
		end
		for k, v in pairs(local_symtab) do
			merged[k] = v
		end
		-- Assign types to children
		assign_typenames(node.expr, merged)
	elseif getmetatable(node) == ast.Op or getmetatable(node) == ast.If or getmetatable(node) == ast.App then
		-- If, App, or Op
		-- Generate a new type variable
		-- Assign types to children
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
---@class Equation
---@field left Type
---@field right Type
---@field original Node
---@field new fun(left: Type, right: Type, original: Node): Equation
---@field __tostring fun(self: Equation): string
---@field equals fun(self: Equation, other: Equation): boolean
local Equation = {}
Equation.__index = Equation
Equation.new = function(left, right, original)
	return setmetatable({
		left = left,
		right = right,
		original = original,
	}, Equation)
end
Equation.__tostring = function(self)
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
local unify_variable = function(v, typ, subst)
	if subst[v.name] then
		return Unify(subst[v.name], typ, subst)
	end
	if getmetatable(typ) == TypeVar and subst[typ.name] then
		return Unify(v, subst[typ.name], subst)
	end
	if occurs_check(v, typ, subst) then
		return nil
	end
	subst[v.name] = typ
	return subst
end
function Unify(x, y, subst)
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
		subst = Unify(x.rettype, y.rettype, subst)
		for i = 1, #x.argtypes do
			subst = Unify(x.argtypes[i], y.argtypes[i], subst)
		end
		return subst
	end
	return nil
end
local unify_equations = function(eqs)
	local subst = {}
	for _, eq in ipairs(eqs) do
		subst = Unify(eq.left, eq.right, subst)
		if not subst then
			break
		end
	end
	return subst
end
-- Apply unifier ------------------------------------------
---@return Type|Func|nil
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
-- Get final expression type after unification -----------------
local get_expression_type = function(typ, unifier)
	if not unifier then
		return typ
	end
	return apply_unifier(typ, unifier)
end
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
	get_expression_type = get_expression_type,
	reset_type_counter = reset_type_counter,
}
