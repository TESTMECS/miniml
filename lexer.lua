local lpeg = require("lpeg")
local P, R, S, C, Cp = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Cp

local alpha = R("az", "AZ")
local digit = R("09")
local alnum = alpha + digit
local ws = S(" \t\n\r") ^ 0

-- Token --------------------------------------------------
---@class Token
---@field typ string
---@field val string
---@field pos number
---@field new fun(typ: string|nil, val: string|nil, pos: number|nil): Token
---@field __tostring fun(self: Token): string
local Token = {}
Token.__index = Token

Token.new = function(typ, val, pos)
	return setmetatable({ typ = typ, val = val, pos = pos }, Token)
end

Token.__tostring = function(self)
	return string.format("%s(%s) at %d", self.typ, self.val, self.pos)
end

-- Token types -------------------------------------------

local T = {
	IF = "if",
	THEN = "then",
	ELSE = "else",
	LET = "let",
	REC = "rec",
	IN = "in",
	TRUE = "true",
	FALSE = "false",
	LAMBDA = "lambda",
	INT = "int",
	ARROW = "->",
	NEQ = "!=",
	EQEQ = "==",
	GEQ = ">=",
	LEQ = "<=",
	GT = ">",
	LT = "<",
	PLUS = "+",
	MINUS = "-",
	TIMES = "*",
	DIV = "/",
	LPAREN = "(",
	RPAREN = ")",
	EQ = "=",
	COMMA = ",",
	ID = "id",
}

---@description Match the Pattern and return a new token
---@param pat string
---@param typ string
---@return Token
local tok = function(pat, typ)
	return Cp() * C(pat) / function(pos, val)
		return Token.new(typ, val, pos)
	end
end

-- Rules (ordered!) --------------------------------------
--- 'P(string)': Literal match of 'string'
--- '*': Followed by
--- '-alnum': Match alphanumeric and fallback to ""
local rules = {
	-- keywords (word boundary)
	tok(P("if") * -alnum, T.IF),
	tok(P("then") * -alnum, T.THEN),
	tok(P("else") * -alnum, T.ELSE),
	tok(P("true") * -alnum, T.TRUE),
	tok(P("false") * -alnum, T.FALSE),
	tok(P("let") * -alnum, T.LET),
	tok(P("rec") * -alnum, T.REC),
	tok(P("in") * -alnum, T.IN),
	tok(P("lambda") * -alnum, T.LAMBDA),
	tok(P("int") * -alnum, T.INT),

	-- operators (longest first)
	tok(P("!="), T.NEQ),
	tok(P("=="), T.EQEQ),
	tok(P(">="), T.GEQ),
	tok(P("<="), T.LEQ),
	tok(P("->"), T.ARROW),

	tok(P(">"), T.GT),
	tok(P("<"), T.LT),
	tok(P("+"), T.PLUS),
	tok(P("-"), T.MINUS),
	tok(P("*"), T.TIMES),
	tok(P("/"), T.DIV),
	tok(P("="), T.EQ),
	tok(P(","), T.COMMA),

	tok(P("("), T.LPAREN),
	tok(P(")"), T.RPAREN),

	-- integers('^1' match at least one digit)
	tok(digit ^ 1, T.INT),

	-- identifiers (last)
	tok(alpha * alnum ^ 0, T.ID),
}

-- Lexer -------------------------------------------------
---@class Lexer
---@field buf string
---@field pos number
---@field new fun(): Lexer
---@field start fun(self: Lexer, buf: string)
---@field token fun(self: Lexer): Token|nil
---@field peek fun(self: Lexer): Token|nil
---@field tokens fun(self: Lexer): fun(): Token|nil
local Lexer = {}
Lexer.__index = Lexer

Lexer.new = function()
	return setmetatable({}, Lexer)
end

---@TODO drew : fix comment stripping
---@param buf string
Lexer.start = function(self, buf)
	-- strip (* ... *) comments, preserve positions
	self.buf = buf:gsub("%(%*.-%*%)", function(s)
		return string.rep(" ", #s)
	end)
	self.pos = 1
end

---@description Get the next token
---@return Token|nil
Lexer.token = function(self)
	-- skip whitespace
	self.pos = ws:match(self.buf, self.pos) or self.pos

	if self.pos > #self.buf then
		return nil
	end

	for _, rule in ipairs(rules) do
		---@diagnostic disable
		local tok = rule:match(self.buf, self.pos)
		if tok then
			self.pos = self.pos + #tok.val
			return tok
		end
	end
	error(("lexer error at %d"):format(self.pos))
end

Lexer.peek = function(self)
	local p = self.pos
	local t = self:token()
	self.pos = p
	return t
end

---@description return a generator for tokens.
Lexer.tokens = function(self)
	return function()
		return self:token()
	end
end

return {
	Lexer = Lexer,
	Token = Token,
	-- Token constants
	IF = T.IF,
	THEN = T.THEN,
	ELSE = T.ELSE,
	LET = T.LET,
	REC = T.REC,
	IN = T.IN,
	TRUE = T.TRUE,
	FALSE = T.FALSE,
	LAMBDA = T.LAMBDA,
	INT = T.INT,
	ARROW = T.ARROW,
	NEQ = T.NEQ,
	EQEQ = T.EQEQ,
	GEQ = T.GEQ,
	LEQ = T.LEQ,
	GT = T.GT,
	LT = T.LT,
	PLUS = T.PLUS,
	MINUS = T.MINUS,
	TIMES = T.TIMES,
	DIV = T.DIV,
	LPAREN = T.LPAREN,
	RPAREN = T.RPAREN,
	EQ = T.EQ,
	COMMA = T.COMMA,
	ID = T.ID,
}
