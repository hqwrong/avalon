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

log = {
    Info = function (...)
        print(("[%s]<INF %s>"):format(fmttime(), Tag),  ...)
    end,

    Infof = function (fmt, ...)
        print(("[%s]<INF %s>"):format(fmttime(), Tag),  string.format(fmt,...))
    end,

    Warn = function (...)
        print(("[%s]<Warn %s>"):format(fmttime(), Tag),  ...)
    end,

    Error = function (...)
        print(("[%s]<ERR %s>"):format(fmttime(), Tag),  ...)
    end,
}

function log.printf(...)
	skynet.error(string.format("[%s] %s",fmttime(),string.format(...)))
end

function log.tag(tag)
    Tag = tag
end

return log
