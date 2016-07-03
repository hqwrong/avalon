local Log = require"log"
local Rule = require "rule"
local ObjProxy = require"objproxy"

local table = table
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local math = math

local mt = {}
mt.__index = mt

local function _total(votes)
    local total,yes = 0,0
    for _,flag in pairs(votes) do
        total = total + 1
        if flag then yes = yes+1 end
    end
    return total, yes
end

function mt:add_history(htype)
    local function addvotes(l)
        local no_votes = {}
        local yes_votes = {}
        for uid,flag in pairs(self.p.votes) do
            table.insert(flag and yes_votes or no_votes, self:get_name(uid))
        end
        l.votes_no = table.concat(no_votes, ", ")
        l.votes_yes = table.concat(yes_votes, ", ")
        return l
    end
    
    local function addstage(l)
        l.stage = {}
        for _, uid in ipairs(self.p.stage) do
            table.insert(l.stage, self:get_name(uid))
        end
    end

    local l = {}
    l.no = ("%d.%d"):format(self.p.round, self.p.pass)
    if htype == "qs" or htype == "qf" then
        l.htype = htype == "qs" and "任务成功" or "任务失败"
        local total, yes = _total(self.p.votes)
        l.n = total-yes
        addstage(l)
    elseif htype == "ps" or htype == "pf" then
        l.htype = htype == "ps" and "提议通过" or "提议流产"
        l.leader = self:get_name(self.p.leader)
        addvotes(l)
        addstage(l)
    end

    table.insert(self.history, l)
end

function mt:get_name(uid)
    return self.users[uid].name
end

function mt:enter_quest()
    self.p.mode = "quest"
    self.p.votes = {}
end

function mt:enter_audit()
    self.p.mode = "audit"
end

function mt:end_game(win)
    self.p.mode = "end"
    self.p.winner = win and "正" or "邪"
end

function mt:is_good_win()
    return self.p.nsuccess > Rule.nround/2
end

function mt:is_evil_win()
    return (self.p.round - self.p.nsuccess) > Rule.nround/2
end

function mt:resolve()
    local win = self:is_good_win()

    if win then
        for _,u in pairs(self.users) do
            if u.role == 5 then     -- 刺客
                self.p.mode = "assasin"
                return
            end
        end
    end

    self:end_game(win)
end

function mt:next_pass()
    self.p.mode = "plan"
    self.p.stage = {}
    self.p.votes = {}
    self.p.pass = self.p.pass + 1

    for i,uid in ipairs(self.uidlist) do
        if uid == self.p.leader then
            local j = i == #self.uidlist and 1 or i+1
            self.p.leader = self.uidlist[j]
            break
        end
    end
end

function mt:next_round(success)
    if success then
        self.p.nsuccess = self.p.nsuccess + 1
    end

    if self:is_good_win() or self:is_evil_win() then
        self:resolve()
        return
    end

    self.p.round = self.p.round + 1
    self.p.pass = 0

    self:next_pass()
end

function mt:vote_audit(userid, approve)
    if self.p.mode ~= "audit" then
        Log.Warn("vote_audit invalid mode", self.p.mode, userid)
        return
    end

    self.p.votes[userid] = approve
    local total, yes = _total(self.p.votes)
    if total < #self.uidlist then
        return
    end

    if yes > total/2 then
        self:add_history("ps")
        self:enter_quest()
    else
        self:add_history("pf")
        self:next_pass()
    end
end

function mt:vote_quest(userid, approve)
    if self.p.mode ~= "quest" then
        Log.Warn("vote_quest invalid mode", self.p.mode, userid)
        return
    end

    if not self:in_stage(userid) then
        return false
    end

    self.p.votes[userid] = approve
    local total, yes = _total(self.p.votes)
    if total ~= #self.p.stage then
        return
    end

    local needtwo = self.stage_per_round[self.p.round] < 0
    if yes == total or needtwo and yes == total - 1 then
        self:add_history("qs")
        self:next_round(true)
    else
        self:add_history("qf")
        self:next_round(false)
    end
end

function mt:in_stage(userid)
    for _, uid in ipairs(self.p.stage) do
        if uid == userid then
            return true
        end
    end

    return false
end

-- 提名
function mt:stage(userid, stagelist)
    if self.p.mode ~= "plan" or userid ~= self.p.leader then
        Log.Error("stage invalid", self.p.mode, userid)
        return
    end

    if #stagelist ~= math.abs(self.stage_per_round[self.p.round]) then
        Log.Error("wrong stagelist length", stagelist)
        return
    end
    
    for _,tuid in ipairs(stagelist) do
        if not self.users[tuid] then
            Log.Error("stage invalid stagelist", tuid)
            return
        end
    end

    self.p.stage = stagelist
    if self.p.pass < Rule.pass_limit then
        self:enter_audit()
    else
        self:add_history("ps")
        self:enter_quest()
    end
end

function mt:assasin(userid, tuid)
    if self.p.mode ~= "assasin" then
        Log.Warn("invalid mode to assasin", self.p.mode, userid)
        return
    end

    local u = self.users[userid]
    if not u or u.role ~= 5 then
        Log.Warn("invalid role to assasin", userid, u.role)
        return
    end

    local tu = self.users[tuid]
    if tu and tu.role == 1 then
        self:end_game(false)    -- 邪方胜利
    else
        self:end_game(true)     -- 正方胜利
    end
end

function mt:visible_info(userid)
    local ret = {}
    local u = self.users[userid]
    local role_visible = u and Rule.visible[u.role] or true -- u未nil时，为旁观者

    for _, u in pairs(self.users) do
        local visible = role_visible == true and true or role_visible[u.role]
        if visible and u.uid ~= userid then
            local r = Rule.role[u.role]
            if visible == true then
                role_name = r.name
            elseif visible == 4 then -- 只能看见阵营名
                role_name = r.camp
            elseif visible == 3 and self.rules[8] then -- 兰斯洛特规则
                role_name = r.name
            elseif visible == 1 then -- 派西维尔规则
                role_name = Rule.role[1].name -- 梅林
            end
            if role_name then
                table.insert(ret, {uid = u.uid, role_name = role_name, name = u.name}) -- to rm username
            end
        end
    end

    return ret
end

function mt:users_info()
    local ret = {}
    for _,uid in ipairs(self.uidlist) do
        local u = self.users[uid]
        table.insert(ret, {uid = u.uid, name = u.name})
        if self.p.mode == "end" then -- to rm
            ret[#ret].role_name = Rule.role[u.role].name
        end
    end

    return ret
end

function mt:votes_info()
    local ret = {}
    for uid in pairs(self.p.votes) do
        table.insert(ret, uid)
    end

    return ret
end

function mt:info(userid)
    if not self.viewers[userid] and not self.users[userid] then
        return {}
    end

    local u = self.users[userid]
    local ret = {}
    return {
        visible = self:visible_info(userid),
        users = self:users_info(),
        role = u and u.role or 0,
        evil_count = #self.uidlist - Rule.camp_good[#self.uidlist],
        history = self.history,

        votes = self:votes_info(),
        round = self.p.round,
        pass = self.p.pass,
        leader = self.p.leader,
        stage = self.p.stage,
        mode = self.p.mode,
        nstage = self.stage_per_round[self.p.round],
        nsuccess = self.p.nsuccess,
        winner = self.p.winner,

        role_name = u and Rule.role[u.role].name or "", -- to rm
        role_desc = u and Rule.role[u.role].desc or "", -- to rm
    }
end

local M = {}

function M.new(rules, users, viewers)
    local self = setmetatable({}, mt)

    self.rules = rules
    self.users = users
    self.viewers = viewers
    self.uidlist = {}

    for _,u in pairs(users) do
        table.insert(self.uidlist, u.uid)
    end

    self.history = {}
    -- 每轮的任务投票数
    self.stage_per_round = Rule.stage_per_round[#self.uidlist]

    self.p = ObjProxy.new{
        votes = {},          -- 投票统计，选举阶段和任务阶段共用
        round = 1,          -- 第n轮
        pass =1,            -- 第n次提案
        nsuccess = 0,  -- 成功任务数
        leader = self.uidlist[math.random(#self.uidlist)], -- 选举阶段的领袖
        stage = {},         -- 被提名的人
        winner = nil,          -- 胜利方
        mode = "plan"      -- plan/audit/quest/end/assasin
    }

    return self
end

return M
