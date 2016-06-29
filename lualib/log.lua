local skynet = require "skynet"
local os = os
local string = string
local math = math

local log = {}
local Tag = ""
local cache_ti
local cache_str
local function fmttime()
	local ti = math.floor(skynet.time())
	if ti ~= cache_ti then
		cache_ti = ti
		cache_str = os.date("%F %T",ti)
	end
	return cache_str
end

function pp(logtype, ...)
    local info = debug.getinfo(2+1, "Sl")
    
    print(("[%s %s %s]@%s:%s:"):format(fmttime(), logtype, Tag, info.source, info.currentline),  ...)    
end

function ppf(logtype, fmt, ...)
    local info = debug.getinfo(2+1, "Sl")
    
    print(("[%s %s %s]%s:%s:"):format(fmttime(), logtype, Tag, info.source, info.currentline),  string.format(fmt, ...))
end

log = {
    Info = function (...)
        pp("INF", ...)
    end,

    Infof = function (fmt, ...)
        ppf("INF", fmt, ...)
    end,

    Warn = function (...)
        pp("WARN", ...)
    end,

    Warnf = function (fmt, ...)
        ppf("WARN", fmt, ...)
    end,

    Error = function (...)
        pp("ERR", ...)
    end,

    Errorf = function (fmt, ...)
        ppf("ERR",fmt, ...)
    end,

}

function log.printf(...)
	skynet.error(string.format("[%s] %s",fmttime(),string.format(...)))
end

function log.tag(tag)
    Tag = tag
end

return log
