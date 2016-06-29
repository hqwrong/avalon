local skynet = require "skynet"
local log = require "log"
local table = table
local staticfile = require "staticfile"
local rule = require "rule"
local json = require"json"
local objproxy = require"objproxy"
local Room = require"room"

Log = require"log"


local content = staticfile["room.html"]

local ALIVETIME = 100 * 60 * 10 -- 10 minutes
local PUSH_TIME = 100 * 30      -- 30s

local roomid = ...

Log.tag(string.format("room:%d", roomid))

local R = {
    version = 1,
    room = nil,
    game = nil,
    push_tbl={},
}

local roomkeeper
local alive
local userservice
local cmds = {}

local function exit()
	if roomid then
		local id = roomid
		roomid = nil
		skynet.call(roomkeeper, "lua", "close", id)
	end
	skynet.exit()
end

local function heartbeat()
	alive = skynet.now()
	while true do
		skynet.sleep(ALIVETIME//2)
		if skynet.now() - alive > ALIVETIME then
			exit()
		end
	end
end

local function roominfo(userid)
    local ret
    if R.game then
        ret = R.game:info(userid)
        ret.status = "game"
    else
        ret = R.room:info(userid)
        ret.status = "prepare"
    end
    ret.version = R.version
    return json.encode(ret)
end

function cmds.web(userid, username)
	R.room:enter(userid, username)
	return content
end

local api = {}

function api.setname(args)
	local userid = args.userid
	local username = args.username
    R.room:enter(userid, username)
    skynet.call(userservice, "lua", userid, username)
end

function api.begin_game(args)
    local userid = args.userid

    if not R.game then
        R.game = R.room:begin_game(userid)
    end

    if not R.game then
        return {error = "不能开始游戏"}
    end

    return roominfo(userid)
end

function api.vote_audit(args)
    local userid = args.userid
    local approve = args.approve

    if not R.game then
        return
    end

    R.game:vote_audit(userid, approve)
end

function api.vote_quest(args)
    local userid = args.userid
    local approve = args.approve

    if not R.game then
        return
    end

    R.game:vote_quest(userid, approve)
end

function api.stage(args)
    if not R.game then
        return
    end
    R.game:stage(args.userid, args.stagelist)
end

function api.assasin(args)
    local userid = args.userid
    local tuid = args.tuid

    R.game:assasin(userid, tuid)
end

function api.ready(args)
	local userid = args.userid
	local enable = args.enable

    R.room:set_ready(userid, enable)
end

function api.set_rule(args)
	local rule = tonumber(args.rule)
	local enable = args.enable
    local userid = args.userid

    R.room:set_rule(userid, rule, enable)
end

-- long poll
function api.request(args)
	local userid = args.userid
	local version = tonumber(args.version)
	local co = R.push_tbl[userid]
	if co then
		skynet.wakeup(co)
        R.push_tbl[userid] = nil
	end

	if version ~= 0 and version == R.version then
		local co = coroutine.running()
		R.push_tbl[userid] = co
        skynet.sleep(PUSH_TIME)
		R.push_tbl[userid] = nil
		if version == R.version then
			return {version = version}
        end
	end
	return roominfo(userid)
end

function cmds.api(args)
    Log.Info("api request:", args.action)
	local f = args.action and api[args.action]
	if not f then
		return {error = "Invalid Action"}
	end

	return f(args)
end

local function update_status()
	local idx, co = next(R.push_tbl)
	while(co) do
		skynet.wakeup(co)
		idx, co = next(R.push_tbl, idx)
	end
end

local function update_loop()
    while true do
        if objproxy.is_dirty(R.room.p) or R.game and objproxy.is_dirty(R.game.p) then
            R.version = R.version + 1
            Log.Info("incr version:", R.version)
            R.cache = nil
            objproxy.clean(R.room.p)
            if R.game then
                objproxy.clean(R.game.p)
            end
            update_status()
        end

        skynet.sleep(100)
    end
end

skynet.start(function()
	roomkeeper = assert(skynet.uniqueservice "roomkeeper")
	userservice = assert(skynet.uniqueservice "userid")
	skynet.fork(heartbeat)
    skynet.fork(update_loop)

    R.room = Room.new(roomid)

	skynet.dispatch("lua", function (_,_,cmd,...)
		alive = skynet.now()
		local f = cmds[cmd]
		if not f then
            Log.Error("invalid cmd", cmd)
            return
        end

        Log.Info("room request:", cmd, ...)
        local ok, ret = xpcall(f, debug.traceback, ...)
        if not ok then
            Log.Error(ret)
            ret = nil
        end
        skynet.retpack(ret)
	end)
end)
