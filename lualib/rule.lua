--[[ 规则列表
	"梅林+刺客",	-- 1
	"派西维尔", -- 2
	"莫甘娜", -- 3
	"莫德雷德", -- 4
	"奥伯伦", -- 5
	"兰斯洛特1", -- 6
	"兰斯洛特2", -- 7
	"兰斯洛特3", -- 8
]]

local M = {}

math.randomseed(os.time())

M.role = {
    [1] = {name = "梅林", camp = "正", desc = "看见除[莫德雷德]外的所有坏人"},
	[2] = {name = "派西维尔", camp = "正", desc = "看见[梅林]和[莫甘娜]"},
	[3] = {name = "正派的兰斯洛特", camp = "正", desc = ""},
    [4] = {name = "圆桌骑士", camp = "正", desc = "一个单纯的好人"},
    [5] = {name = "刺客", camp = "邪", desc = "刺杀梅林"},
    [6] = {name = "莫德雷德", camp = "邪", desc = "梅林看不到他"},
    [7] = {name = "莫甘娜", camp = "邪", desc = "假扮梅林，迷惑派西维尔"},
    [8] = {name = "兰斯洛特", camp = "邪", desc = ""},
    [9] = {name = "奥伯伦", camp = "邪", desc = "一个被鼓励的坏人"},
    [10] = {name = "爪牙", camp = "邪", desc = "一个单纯的坏人"},
}

-- 1: 显示梅林（派西维尔规则）
-- 4: 表示只能看见派别，不能看见身份
-- 3： 兰斯洛特规则
M.visible = {
--         梅林,    派西维尔,     兰(正),  骑士,    刺客,  莫德雷德,       莫甘娜,  兰(邪),  奥伯伦,  爪牙
   [1] = { false, false,     false,   false,  4,    false,         4,      4,     4,      4},   --梅林
   [2] = { 1    , false,     false,   false, false,  false,       1,       false,    false, false },  --派西维尔
   [3] = { false  , false,     false,   false, false, false,       false,   3,        false, false },  --兰(正)
   [4] = { false  , false,     false,   false, false, false,       false,  false,    false, false },  --正
   [5] = { false  , false,     false,   false, false, 4,            4,       true,     false, 4 },	  --刺客
   [6] = { false  , false,     false,   false, 4,      false,       4,       true,     false, 4 },   --莫德雷德
   [7] = { false  , false,     false,   false, 4,      4,            false,  true,     false, 4 },   --莫甘娜
   [8] = { false  , false,      3,      false, 3,      3,            3,       false,     false, 3 },      --兰(邪)
   [9] = { false  , false,     false,   false, false, false,       false,  false,    false, false },  --奥伯伦
   [10] = { false , false,     false,   false, false, 4,            4,      4,     4,        4 },	  --刺客
}

local camp_good = {
	0,0,0,0,	-- can't below 4
	3,	-- 5
	4,	-- 6
	4,	-- 7
	5,	-- 8
	6,	-- 9
	6,	-- 10
}

local function randomrole(roles)
	local n = #roles
	for i=1, n-1 do
		local c = math.random(i,n)
		roles[i],roles[c] = roles[c],roles[i]
	end
	return roles
end

-- 本函数会返回一个 table ， 包含有所有参于的角色；或返回出错信息。
function M.checkrules(rules, n)
	if n <5 or n>10 then
		return false, "游戏人数必须在 5 到 10 人之间"
	end
	if not rules[1] then
		for i=2,8 do
			if rules[i] then
				return false, "当去掉梅林时，不可以选择其他角色"
			end
		end
		local ret = {}
		for i=1,camp_good[n] do
			table.insert(ret, 4)
		end
		for i=1,n-camp_good[n] do
			table.insert(ret, 10)
		end
		return true, randomrole(ret)
	end
	local lancelot = 0
	for i=6,8 do
		if rules[i] then
			lancelot = lancelot + 1
		end
	end
	if lancelot > 1 then
		return false,"请从兰斯洛特规则里选择其中一个，或则不选"
	end
	local ret = {1,5}

	local good = 1	-- 梅林
	local evil = 1	-- 刺客
	if rules[2] then
		good = good + 1	--派西维尔
		table.insert(ret,2)
	end
	if lancelot == 1 then
		good = good + 1
		evil = evil + 1
		table.insert(ret,3)
		table.insert(ret,8)
	end
	if rules[3] then	-- 莫甘娜
		evil = evil + 1
		table.insert(ret, 7)
	end
	if rules[4] then
		evil = evil + 1	-- 莫德雷德
		table.insert(ret, 6)
	end
	if rules[5] then
		evil = evil + 1	-- 奥伯伦
		table.insert(ret, 9)
	end
	if good > camp_good[n] then
		return false, "好人身份太多"
	end
	if evil > n-camp_good[n]  then
		return false, "坏人身份太多"
	end
	for i = 1,camp_good[n] -  good do
		table.insert(ret, 4)
	end
	for i = 1,n-camp_good[n] -  evil do
		table.insert(ret, 10)
	end

	return true, randomrole(ret)
end

M.pass_limit = 5

-- 每轮任务需要的投票数，负数表示至少两张反对票该任务才失败
M.stage_per_round = {
    [5] = {2,3,2,3,3},
    [6] = {2,3,4,3,4},
    [7] = {2,3,3,-4,4},
    [8] = {3,4,4,-5,5},
    [9] = {3,4,4,-5,5},
    [10] = {3,4,4,-5,5},
}

M.nround = #select(2, next(M.stage_per_round))

M.camp_good = camp_good
return M
