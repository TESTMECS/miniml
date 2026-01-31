local lpeg = require("lpeg")
local P, R, S, C, Cp = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Cp

local alpha = R("az", "AZ")
local digit = R("09")
local alnum = alpha + digit
local ws = S(" \t\n\r") ^ 0

-- Token --------------------------------------------------

local Token = {}
Token.__index = Token

function Token.new(typ, val, pos)
	return setmetatable({ typ = typ, val = val, pos = pos }, Token)
end

function Token:__tostring()
	return string.format("%s(%s) at %d", self.typ, self.val, self.pos)
end

-- Token types -------------------------------------------

local T = {
	IF = "if",
	THEN = "then",
	ELSE = "else",
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

-- Helper: token constructor pattern ---------------------

local function tok(pat, typ)
	return Cp() * C(pat) / function(pos, val)
		return Token.new(typ, val, pos)
	end
end

-- Rules (ordered!) --------------------------------------

local rules = {
	-- keywords (word boundary)
	tok(P("if") * -alnum, T.IF),
	tok(P("then") * -alnum, T.THEN),
	tok(P("else") * -alnum, T.ELSE),
	tok(P("true") * -alnum, T.TRUE),
	tok(P("false") * -alnum, T.FALSE),
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

	-- identifiers (last)
	tok(alpha * alnum ^ 0, T.ID),
}

-- Lexer -------------------------------------------------

local Lexer = {}
Lexer.__index = Lexer

function Lexer.new()
	return setmetatable({}, Lexer)
end

function Lexer:start(buf)
	-- strip (* ... *) comments, preserve positions
	self.buf = buf:gsub("%(%*.-%*%)", function(s)
		return string.rep(" ", #s)
	end)
	self.pos = 1
end

function Lexer:token()
	-- skip whitespace
	self.pos = ws:match(self.buf, self.pos) or self.pos

	if self.pos > #self.buf then
		return nil
	end

	for _, rule in ipairs(rules) do
		local tok = rule:match(self.buf, self.pos)
		if tok then
			self.pos = self.pos + #tok.val
			return tok
		end
	end

	error(("lexer error at %d"):format(self.pos))
end

function Lexer:peek()
	local p = self.pos
	local t = self:token()
	self.pos = p
	return t
end

function Lexer:tokens()
	return function()
		return self:token()
	end
end

return Lexer
