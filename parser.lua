local ast = require("ast")
local exceptions = require("exceptions")
local lexer = require("lexer")

local OPERATORS = {
	[lexer.NEQ] = true,
	[lexer.EQEQ] = true,
	[lexer.GEQ] = true,
	[lexer.LEQ] = true,
	[lexer.LT] = true,
	[lexer.GT] = true,
	[lexer.PLUS] = true,
	[lexer.MINUS] = true,
	[lexer.TIMES] = true,
	[lexer.DIV] = true,
}
---@class Parser
---@field lexer Lexer
---@field token Token
local Parser = {}
Parser.__index = Parser

function Parser.new()
	return setmetatable({
		lexer = lexer.Lexer.new(),
		token = nil,
	}, Parser)
end

function Parser:parse(source, should_terminate)
	if should_terminate == nil then
		should_terminate = true
	end

	self.lexer:start(source)
	self:next()

	local decl = self:decl()
	if self.token.typ ~= nil and should_terminate then
		self:error(string.format('Unexpected token "%s" at %d', self.token.val, self.token.pos))
	end
	return decl, self.token.pos
end

function Parser:error(msg)
	error(exceptions.MLParserException.new(msg, self.token.pos))
end

function Parser:next()
	local token = self.lexer:token()
	if token ~= nil then
		self.token = token
	else
		error("Unexpected end of file")
	end
	if not self.token then
		self.token = lexer.Token.new(nil, nil, nil)
	end
end

function Parser:match(typ)
	if self.token.typ == typ then
		local val = self.token.val
		self:next()
		return val
	end
	local pos = self.token.pos or "unknown"
	self:error(string.format("Expected %s, but found %s at %s", typ, self.token.typ, pos))
end

function Parser:decl()
	local name = self:match(lexer.ID)
	local argnames = {}

	while self.token.typ == lexer.ID do
		table.insert(argnames, self.token.val)
		self:next()
	end

	self:match(lexer.EQ)
	local expr = self:expr()

	if #argnames > 0 then
		return ast.Decl.new(name, ast.Lambda.new(argnames, expr))
	end
	return ast.Decl.new(name, expr)
end

function Parser:expr()
	local node = self:expr_component()
	if OPERATORS[self.token.typ] then
		local op = self.token.typ
		self:next()
		local rhs = self:expr_component()
		return ast.Op.new(op, node, rhs)
	end
	return node
end

function Parser:expr_component()
	local tok = self.token

	if tok.typ == lexer.INT then
		self:next()
		return ast.Int.new(tok.val)
	end

	if tok.typ == lexer.TRUE or tok.typ == lexer.FALSE then
		self:next()
		return ast.Bool.new(tok.typ == lexer.TRUE)
	end

	if tok.typ == lexer.ID then
		self:next()
		if self.token.typ == lexer.LPAREN then
			return self:app(tok.val)
		end
		return ast.Id.new(tok.val)
	end

	if tok.typ == lexer.LPAREN then
		self:next()
		local e = self:expr()
		self:match(lexer.RPAREN)
		return e
	end

	if tok.typ == lexer.IF then
		return self:ifexpr()
	end

	if tok.typ == lexer.LAMBDA then
		return self:lambdaexpr()
	end

	self:error("We don’t support " .. tostring(tok.typ) .. " yet!")
end

function Parser:ifexpr()
	self:match(lexer.IF)
	local cond = self:expr()
	self:match(lexer.THEN)
	local thenexpr = self:expr()
	self:match(lexer.ELSE)
	local elseexpr = self:expr()
	return ast.If.new(cond, thenexpr, elseexpr)
end

function Parser:lambdaexpr()
	self:match(lexer.LAMBDA)
	local argnames = {}

	while self.token.typ == lexer.ID do
		table.insert(argnames, self.token.val)
		self:next()
	end

	self:match(lexer.ARROW)
	local expr = self:expr()
	return ast.Lambda.new(argnames, expr)
end

function Parser:app(name)
	self:match(lexer.LPAREN)
	local args = {}

	while self.token.typ ~= lexer.RPAREN do
		table.insert(args, self:expr())
		if self.token.typ == lexer.COMMA then
			self:next()
		elseif self.token.typ ~= lexer.RPAREN then
			self:error(string.format("Unexpected %s in application at %d", self.token.val, self.token.pos))
		end
	end

	self:match(lexer.RPAREN)
	return ast.App.new(ast.Id.new(name), args)
end

return Parser
