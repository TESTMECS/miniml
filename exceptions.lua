-- Base exception class
---@class Exception
---@field msg string
---@field pos number
---@field __tostring function
---@field new fun(msg: string, pos: number): Exception
local Exception = {}
Exception.__index = Exception

function Exception.new(msg, pos)
	return setmetatable({ msg = msg, pos = pos }, Exception)
end

function Exception:__tostring()
	if self.pos then
		return string.format("%s at %d", self.msg, self.pos)
	else
		return self.msg
	end
end

---@class MLParserException: Exception
local MLParserException = setmetatable({}, Exception)
MLParserException.__index = MLParserException

function MLParserException.new(msg, pos)
	return setmetatable({ msg = msg, pos = pos }, MLParserException)
end

---@class MLEvalException: Exception
local MLEvalException = setmetatable({}, Exception)
MLEvalException.__index = MLEvalException

function MLEvalException.new(msg)
	return setmetatable({ msg = msg }, MLEvalException)
end

---@class MLCompilerException: Exception
local MLCompilerException = setmetatable({}, Exception)
MLCompilerException.__index = MLCompilerException

---@class MLTypingException: Exception
function MLCompilerException.new(msg)
	return setmetatable({ msg = msg }, MLCompilerException)
end

---@class MLTypingException: Exception
local MLTypingException = setmetatable({}, Exception)
MLTypingException.__index = MLTypingException

function MLTypingException.new(msg)
	return setmetatable({ msg = msg }, MLTypingException)
end

return {
	Exception = Exception,
	MLParserException = MLParserException,
	MLEvalException = MLEvalException,
	MLCompilerException = MLCompilerException,
	MLTypingException = MLTypingException,
}
