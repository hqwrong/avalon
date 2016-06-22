local Rule = require "rule"
local skynet = require "skynet"
local Log = require "log"

local mt = {}
mt._index = mt

local READY = 0
local NOTREADY = 1
local BLOCK = 2

function mt:_get(userid)
    return self.users[userid]
end

function mt:_add(userid, username)
    self.users[userid] = {
        userid = userid,
        username = username,
        timestamp = skynet.now(),
        status = NOTREADY,	-- not ready
    }
end

function mt:enter(userid, username)
    local u = self:_get(userid)
	if u then
		u.timestamp = skynet.now()
		u.username = username
	else
        self:_add(userid, username)
	end
end

function mt:leave(userid)
    self.users[userid] = nil
    if not self.users[self.owner] then
        self.owner == next(self.users)
    end
end

function mt:begin_game(userid)
end

function mt:hash()
    
end

local M = {}

function M.new(roomid)
    local self = setmetatable({}, mt)
    self.roomid = roomid
    self.status = "prepare"
	self.needs = ""
	Log.printf("[Room:%d] open", roomid)

    return self
end

return M

