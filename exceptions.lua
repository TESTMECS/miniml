-- Base exception class
---@class Exception
---@field msg string
---@field pos number
---@field __tostring function
---@field new fun(msg: string, pos: number): Exception
local Exception = {}
Exception.__index = Exception
Exception.new = function(msg, pos)
	return setmetatable({ msg = msg, pos = pos }, Exception)
end
Exception.__tostring = function(self)
	if self.pos then
		return string.format("%s at %d", self.msg, self.pos)
	else
		return self.msg
	end
end
------ MLParserException ------
---@class MLParserException: Exception
local MLParserException = setmetatable({}, Exception)
MLParserException.__index = MLParserException
MLParserException.new = function(msg, pos)
	return setmetatable({ msg = msg, pos = pos }, MLParserException)
end
------ MLEvalException ------
---@class MLEvalException: Exception
local MLEvalException = setmetatable({}, Exception)
MLEvalException.__index = MLEvalException
MLEvalException.new = function(msg)
	return setmetatable({ msg = msg }, MLEvalException)
end
------ MLCompilerException ------
---@class MLCompilerException: Exception
local MLCompilerException = setmetatable({}, Exception)
MLCompilerException.__index = MLCompilerException
MLCompilerException.new = function(msg)
	return setmetatable({ msg = msg }, MLCompilerException)
end
------ MLTypingException ------
---@class MLTypingException: Exception
local MLTypingException = setmetatable({}, Exception)
MLTypingException.__index = MLTypingException
MLTypingException.new = function(msg)
	return setmetatable({ msg = msg }, MLTypingException)
end
return {
	Exception = Exception,
	MLParserException = MLParserException,
	MLEvalException = MLEvalException,
	MLCompilerException = MLCompilerException,
	MLTypingException = MLTypingException,
}
