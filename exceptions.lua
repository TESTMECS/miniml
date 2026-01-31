-- Base exception class
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

-- MLParserException
local MLParserException = setmetatable({}, Exception)
MLParserException.__index = MLParserException

function MLParserException.new(msg, pos)
	return setmetatable({ msg = msg, pos = pos }, MLParserException)
end

-- MLEvalException
local MLEvalException = setmetatable({}, Exception)
MLEvalException.__index = MLEvalException

function MLEvalException.new(msg)
	return setmetatable({ msg = msg }, MLEvalException)
end

-- MLCompilerException
local MLCompilerException = setmetatable({}, Exception)
MLCompilerException.__index = MLCompilerException

function MLCompilerException.new(msg)
	return setmetatable({ msg = msg }, MLCompilerException)
end

-- MLTypingException
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
