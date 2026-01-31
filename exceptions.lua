local exceptions = {}
exceptions.__index = exceptions

function exceptions.new(msg, pos)
	return setmetatable({ msg = msg, pos = pos }, exceptions)
end

function exceptions:__tostring()
	return string.format("%s at %d", self.msg, self.pos)
end

return exceptions
