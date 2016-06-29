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

local function _seri(...)
    local cache = {}
    local function _seri(el, path)
        if type(el) ~= "table" then
            if type(el) == "string" then
                return el
            else
                return tostring(el)
            end
        end

        if cache[el] then return cache[el] end
        cache[el] = path == "" and "." or path

        local tmp = {}
        for i,v in ipairs(el) do
            table.insert(tmp, _seri(v, path.."."..i))
        end
        return string.format("[%s]", table.concat(tmp, ", "))
    end

    local output = {}
    for i=1,select("#", ...) do
        table.insert(output, _seri(select(i, ...), ""))
    end
    return table.concat(output, " ")
end

local hist_handles = {
    pass_limit = function (self) return Rule.pass_limit end,
    leader = function (self) return self:get_name(self.p.leader) end,
    stage = function (self)
        local l = {}
        for _,uid in ipairs(self.p.stage) do
            table.insert(l, self:get_name(uid))
        end
        return _seri(l)
    end,

    vote_yes = function (self)
        local l = {}
        for uid,flag in pairs(self.p.votes) do
            if flag then table.insert(l, self:get_name(uid)) end
        end
        return _seri(l)
    end,

    vote_no = function (self)
        local l = {}
        for uid,flag in pairs(self.p.votes) do
            if not flag then table.insert(l, self:get_name(uid)) end
        end
        return _seri(l)
    end
}

function mt:add_history(...)
    local l = {...}
    for i,s in ipairs(l) do
        l[i] = string.gsub(s, "{([%w_]+)}", function (w) return hist_handles[w](self) end)
    end

    local hist = ("%d.%d  "):format(self.p.round, self.p.pass) .. table.concat(l, "\n\t")
    table.insert(self.history, hist)
end

function mt:get_name(uid)
    return self.users[uid].name
end

function mt:enter_quest()
    self.p.mode = "quest"
    self.p.votes = {}
end

function mt:end_game(win)
    self.p.mode = "end"
    self.p.winner = win and "good" or "evil"
end

function mt:resolve()
    for _,u in pairs(self.users) do
        if u.role == 5 then     -- 刺客
            self.p.mode = "assasin"
            return
        end
    end

    self:end_game(self.p.nsuccess > Rule.nround/2)
end

function mt:next_pass()
    if self.p.pass >= Rule.pass_limit then
        self:add_history("任务失败! 提案连续{pass_limit}次没有通过")
        return self:next_round(false)
    end

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
    if self.p.round == #self.stage_per_round then
        self:resolve()
        return
    end

    self.p.round = self.p.round + 1
    self.p.pass = 0
    if success then
        self.p.nsuccess = self.p.nsuccess + 1
    end

    if self.p.round > #self.stage_per_round then
        self:resolve()
    else
        self:next_pass()
    end
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
        self:add_history("提议通过. {leader} 提议 {stage}", "赞同者: {vote_yes}", "反对者: {vote_no}")
        self:enter_quest()
    else
        self:add_history("提议否决! {leader} 提议 {stage}", "赞同者: {vote_yes}", "反对者: {vote_no}")
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
        self:add_history("任务成功.  参与者: {stage}", ("出现%d张失败票"):format(total-yes))
        self:next_round(true)
    else
        self:add_history("任务失败! 参与者: {stage}", ("出现%d张失败票"):format(total-yes))
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
    self.p.mode = "audit"
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

    local tu = self.users[userid]
    if tu and tu.role == 1 then
        self:end_game(true)
    else
        self:end_game(false)
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
                table.insert(ret, {uid = u.uid, role_name = role_name, name = u.name}) -- rm username
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
    end

    return ret
end

function mt:info(userid)
    local u = self.users[userid]
    local ret = {}
    return {
        visible = self:visible_info(userid),
        users = self:users_info(),
        role = u and u.role or 0,
        evil_count = #self.uidlist - Rule.camp_good[#self.uidlist],
        history = self.history,

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

local function shuffle(l)
    local tmp
    local sz = #l
    for i = 1,sz do
        local j = math.random(0, sz - i) + i
        tmp = l[i]
        l[i] = l[j]
        l[j] = tmp
    end
end

function M.new(rules, users)
    local self = setmetatable({}, mt)

    self.rules = rules
    self.users = users
    self.uidlist = {}

    for _,u in pairs(users) do
        table.insert(self.uidlist, u.uid)
    end
    shuffle(self.uidlist)

    self.history = {}
    -- 每轮的任务投票数
    self.stage_per_round = Rule.stage_per_round[#self.uidlist]

    self.p = ObjProxy.new{
        votes = {},          -- 投票统计，选举阶段和任务阶段共用
        round = 1,          -- 第n轮
        pass =1,            -- 第n次提案
        nsuccess = 0,  -- 成功任务数
        leader = self.uidlist[1], -- 选举阶段的领袖
        stage = {},         -- 被提名的人
        winner = nil,          -- 胜利方
        mode = "plan"      -- plan/audit/quest/end/assasin
    }

    return self
end

return M
