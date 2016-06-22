local Log = require"log"
local Rule = require "rule"

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
    leader = function (self) return self.users[self.leader].name end,
    stage = function (self)
        local l = {}
        for _,uid in ipairs(self.stage) do
            table.insert(l, self.users[uid].name)
        end
        return _seri(l)
    end,

    vote_yes = function ()
        local l = {}
        for uid,flag in pairs(self.votes) do
            if flag then table.insert(l, self.users[uid].name) end
        end
        return _seri(l)
    end,

    vote_no = function ()
        local l = {}
        for uid,flag in pairs(self.votes) do
            if not flag then table.insert(l, self.users[uid].name) end
        end
        return _seri(l)
    end
}

function mt:add_history()
    local l = {...}
    for i,s in ipairs(l) do
        l[i] = string.gsub(s, "{([%w_]+)}", function (w) return hist_handles[w]() end)
    end

    local hist = ("%d.%d  "):format(self.round, self.pass) .. table.concat(l, "\n\t")
    table.insert(self.history, hist)
end

function mt:vote_in_audit(userid, approve)
    self.votes[userid] = approve
    local total, yes = _total()
    if total < #self.uidlist then
        return
    end

    if yes > total/2 then
        add_history("提议通过. {leader} 提议 {stage}", "赞同者: {vote_yes}", "反对者: {vote_no}")
        self:enter_quest()
    else
        add_history("提议否决! {leader} 提议 {stage}", "赞同者: {vote_yes}", "反对者: {vote_no}")
        self:next_pass()
    end
end

function mt:end_game()
    self.mode = "end"
end

function mt:next_pass()
    if self.pass >= Rule.pass_limit then
        self:add_history("任务失败! 提案连续{pass_limit}次没有通过")
        return self:next_round(false)
    end

    self.mode = "plan"
    self.stage = {}
    self.votes = {}
    self.pass = self.pass + 1

    for i,uid in ipairs(self.uidlist) do
        if uid == self.leader then
            local j = i == #self.uidlist and 1 or i+1
            self.leader = self.uidlist[j]
            break
        end
    end
end

function mt:next_round(success)
    if self.round == #self.stage_per_round then
        self:end_game()
        return
    end

    self.round = self.round + 1
    self.pass = 0
    if success then
        self.round_success = self.round_success + 1
    end

    if self.round > #self.stage_per_round then
        self:end_game()
    else
        self:next_pass()
    end
end

function mt:vote_in_quest(userid, approve)
    if not self:in_stage(userid) then
        return false
    end

    self.votes[userid] = approve
    local total, yes = _total()
    if total ~= #self.stage then
        return
    end

    local needtwo = self.stage_per_round[self.round] < 0
    if yes == total or needtwo and yes == total - 1 then
        self:add_history("任务成功.  参与者: {stage}", ("出现%d张失败票"):format(total-yes))
        self:next_round(true)
    else
        self:add_history("任务失败! 参与者: {stage}", ("出现%d张失败票"):format(total-yes))
        self:next_round(false)
    end
end

function mt:vote(userid, approve)
    local function in_stage()
        for _,uid in ipairs(self.stage) do
            if uid == userid then return true end
        end
        return false
    end

    if self.mode == "audit" then
        self:vote_in_audit(userid, approve)
    elseif self.mode == "quest" then
        self:vote_in_quest(userid, approve)
    end
end

function mt:visible_info(userid)
    local ret = {}
    local u = self.users[userid]
    local role_visible = u and Rule.visible[u.role] or true -- u未nil时，为旁观者

    for _, u in pairs(self.users) do
        local visible = role_visible == true and true or role_visible[u.role]
        if visible then
            local role_name
            if visible == true then
                role_name = Rule.role[u.role]
            elseif visible == 4 then -- 只能看见阵营名
                role_name = Rule.camp_name[u.role]
            elseif visible == 3 and self.rules[8] then -- 兰斯洛特规则
                role_name = Rule.role[u.role]
            end
            if role_name then
                table.insert(ret, {username = u.name, role = role_name})
            end
        end
    end

    return ret
end

function mt:hash()
    local t = {
        self.round,
        self.pass,
        self.leader,
        self.stage,
        self.mode,
        self.stage_per_round[self.round],
        self.round_success,
        self.mode,
    }
end

function mt:info(userid)
    local ret = {}
    return {
        visible = self:visible_info(userid),
        role = self.users[userid] and self.users[userid].name,
        evil_count = #self.uidlist - Rule.camp_good[#self.uidlist],
        history = self.history,

        round = self.round,
        pass = self.pass,
        leader = self.leader,
        stage = self.stage,
        mode = self.mode,
        need = self.stage_per_round[self.round],
        round_success = self.round_success,
        mode = self.mode,
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

    self.stage_per_round = Rule.stage_per_round[#self.uidlist] -- 每轮的任务投票数
    self.votes = {}          -- 投票统计，选举阶段和任务阶段共用
    self.round = 1,          -- 第n轮
    self.pass =1,            -- 第n次提案
    self.round_success = 0,  -- 成功任务数
    self.leader = self.uidlist[1], -- 选举阶段的领袖
    self.stage = {},         -- 被提名的人
    self.history = {},
    self.mode = "plan"      -- plan/audit/quest/end

    return self
end

return M
