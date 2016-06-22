local Rule = require "rule"

local mt = {}
mt._index = mt

function mt:begin(userid)
    local ok,result = checkrule()
    if not ok then
        return false
    end

    local i = 1
    local user_tbl = R.info.user_tbl
    local uidlist = {}
    for uid, u in pairs(user_tbl) do
        if u.status == READY then
            u.identity = result[i]
            i = i + 1
            table.insert(uidlist, uid)
        end
    end
    table.sort(uidlist)
    R.status = "game"
    R.stage_per_round = rule.stage_per_round[#uidlist]
    R.vote = {}
    R.info = objproxy.new{
        user_tbl = user_tbl,
        round = 1,          -- 第n轮
        pass =1,            -- 第n次提案
        round_success = 0,  -- 成功任务数
        rules = R.info.rules,
        leader = uidlist[math.random(#uidlist)],
        uidlist = uidlist,
        stage = {},         -- 被提名的人
        history = {},
        mode = "plan"      -- plan/audit/quest
    }
end


local M = {}

function M.new()
end

return M

