local Rule = require "rule"
local Skynet = require "skynet"
local Log = require "log"
local ObjProxy = require"objproxy"
local Game = require"game"

local mt = {}
mt._index = mt

local READY = 0
local NOTREADY = 1
local BLOCK = 2

function mt:_get(userid)
    return self.p.users[userid]
end

function mt:_add(userid, username)
    if not self.owner then
        self.owner = userid
    end
    self.p.users[userid] = {
        userid = userid,
        username = username,
        timestamp = Skynet.now(),
        status = NOTREADY,	-- not ready
    }
end

function mt:enter(userid, username)
    local u = self:_get(userid)
	if u then
		u.timestamp = Skynet.now()
		u.username = username
	else
        self:_add(userid, username)
	end
end

function mt:set_rule(userid, rule, enable)
    if userid ~= self.owner or self.game then
        Log.Error("cannot set rule", userid, self.game == nil)
        return
    end
    self.p.rules[rule] = enable and true or nil
end

function mt:set_ready(userid, enable)
    local u = self:_get(userid)
    if not u then
        Log.Error("wrong userid", userid)
        return
    end

    u.status = enable and READY or NOTREADY
end

function mt:can_game()
    local ready_num = 0
    for _, u in pairs(self.p.users) do
        if u.status == READY then
            ready_num = ready_num + 1
        end
    end

    return rule.checkrules(self.rules, ready_num)
end

function mt:info()
    local info = {
        users = {},
        rules = {},
    }

    local can_game, reason = self:can_game()
    info.can_game = can_game
    info.reason = can_game and "" or reason

    for _, v in pairs(self.p.users) do
        table.insert(info.users, {
                         uid = v.uid,
                         name = v.name,
                         status = v.status})
    end

    for rule in pairs(self.p.rules) do
        table.insert(info.rules, rule)
    end

    return info
end

function mt:begin_game(userid)
    if userid ~= self.owner or not self:can_game() then
        return
    end

    local users = {}
    for uid,u in pairs(self.p.users) do
        if u.status = READY then
            users[uid] = {name = u.name,  uid = u.uid}
        end
    end

    self.game = Game.new(self.p.rules, users)
    return self.game
end

local M = {}

function M.new(roomid)
    local self = setmetatable({}, mt)
    self.roomid = roomid
    self.owner = nil
    self.game = nil

    self.p = ObjProxy.new{
        users  = {},
        rules = {},
    }

	Log.printf("[Room:%d] open", roomid)

    return self
end

return M
