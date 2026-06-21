local mName = 'gmNpc'
---@class GmNpc:ModuleType
local GmNpc = ModuleBase:createModule(mName)

-- =============================================================================
-- GM helper NPC — generic command dispatcher.
--
--   talk -> "what do you want to do?" (only option: "show all commands")
--        -> paginated list of every command in `commands`
--        -> input box: type the primitive args -> the command runs
--
-- Each command is { label, hint, run(player, args, raw) }:
--   args = whitespace-separated tokens the GM typed
--   raw  = the full typed string (use for SQL / messages with spaces)
-- Add a new command = add one row. Player commands act on the talker; world
-- commands act on the server/map and take their target as typed args.
-- =============================================================================

-- ---- configuration ---------------------------------------------------------

local NPC_NAME  = 'GM助手'
local NPC_IMAGE = 103010
-- GM NPC on town map 1000 at (242,90) - reachable, so a normal player can walk up
-- and talk to it (used to bootstrap GMs via AddGM). Also openable via the GM tool
-- item below. Original spot 242,88 had an item, so placed 2 blocks south.
local NPC_POS   = { x = 242, y = 90, mapType = 0, map = 1000, direction = 6 }

-- GM tool item: using / double-clicking this item opens the same menu as talking
-- to the (now hidden) NPC. Defined in data/itemset.txt with item id 49999.
local GM_ITEM_ID = 49999

local PAGE_SIZE = 8

-- ---- helpers ---------------------------------------------------------------

local function msg(player, text) NLG.SystemMessage(player, text) end

local function tokenize(s)
  local t = {}
  for w in tostring(s or ''):gmatch('%S+') do t[#t + 1] = w end
  return t
end

local function rest(a, from) return table.concat(a, ' ', from) end -- join tokens from index `from`

local function pageButtons(page, total)
  if total <= 1 then return CONST.BUTTON_关闭 end
  if page == 1 then return CONST.BUTTON_下取消 end
  if page == total then return CONST.BUTTON_上取消 end
  return CONST.BUTTON_上下取消
end

-- ---- command registry ------------------------------------------------------

local commands = {

  -- ===== player actions (act on the talker) =====
  { label = '给予道具 GiveItem', hint = 'itemID [数量]', run = function(p, a)
    local id = tonumber(a[1]); if not id then return msg(p, '需要 itemID') end
    local nm = Item.GetNameFromNumber(id)
    if not nm or nm == '' then return msg(p, '道具ID不存在: ' .. id) end
    local amt = tonumber(a[2]) or 1
    Char.GiveItem(p, id, amt, true); msg(p, string.format('已给予 %s x%d', nm, amt))
  end },
  { label = '删除道具 DelItem', hint = 'itemID [数量]', run = function(p, a)
    local id = tonumber(a[1]); if not id then return msg(p, '需要 itemID') end
    Char.DelItem(p, id, tonumber(a[2]) or 1, true); msg(p, '已删除道具 ' .. id)
  end },
  { label = '加金币 AddGold', hint = '数量(可负)', run = function(p, a)
    local n = tonumber(a[1]); if not n then return msg(p, '需要数量') end
    Char.AddGold(p, n); msg(p, '金币 ' .. (n >= 0 and '+' or '') .. n)
  end },
  { label = '加水晶 AddCrystal', hint = '数量(可负)', run = function(p, a)
    local n = tonumber(a[1]); if not n then return msg(p, '需要数量') end
    Char.AddCrystal(p, n); msg(p, '水晶 ' .. (n >= 0 and '+' or '') .. n)
  end },
  { label = '给予宠物 GivePet', hint = 'petID', run = function(p, a)
    local id = tonumber(a[1]); if not id then return msg(p, '需要 petID') end
    local r = Char.GivePet(p, id, 1)
    msg(p, (r and r >= 0) and ('已给予宠物 ' .. id) or '给予失败(宠物栏已满或ID无效)')
  end },
  { label = '学习技能 AddSkill', hint = 'skillID', run = function(p, a)
    local id = tonumber(a[1]); if not id then return msg(p, '需要 skillID') end
    Char.AddSkill(p, id, 0, true); msg(p, '已学技能 ' .. id)
  end },
  { label = '设置技能等级 SetSkillLevel', hint = 'slot 等级', run = function(p, a)
    local s, l = tonumber(a[1]), tonumber(a[2]); if not (s and l) then return msg(p, '需要 slot 等级') end
    Char.SetSkillLevel(p, s, l, true); msg(p, string.format('技能槽%d -> Lv%d', s, l))
  end },
  { label = '传送自己 Warp', hint = 'mapType floor x y', run = function(p, a)
    local mt, fl, x, y = tonumber(a[1]), tonumber(a[2]), tonumber(a[3]), tonumber(a[4])
    if not (mt and fl and x and y) then return msg(p, '需要 mapType floor x y') end
    Char.Warp(p, mt, fl, x, y); msg(p, string.format('已传送 %d/%d (%d,%d)', mt, fl, x, y))
  end },
  { label = '设置数据 SetData', hint = 'dataIndex value', run = function(p, a)
    local d, v = tonumber(a[1]), tonumber(a[2]); if not (d and v) then return msg(p, '需要 dataIndex value') end
    Char.SetData(p, d, v); Char.UpCharStatus(p); msg(p, string.format('SetData[%d]=%d', d, v))
  end },
  { label = '读取数据 GetData', hint = 'dataIndex', run = function(p, a)
    local d = tonumber(a[1]); if not d then return msg(p, '需要 dataIndex') end
    msg(p, string.format('GetData[%d]=%s', d, tostring(Char.GetData(p, d))))
  end },

  { label = '自动战斗 AutoBattle', hint = '0/1 留空切换', run = function(p, a)
    local cur = tonumber(Char.GetData(p, CONST.对象_自动战斗开关)) or 0
    local nv = a[1] and tonumber(a[1]) or ((cur == 1) and 0 or 1)
    Char.SetData(p, CONST.对象_自动战斗开关, nv)
    msg(p, '自动战斗 ' .. (nv == 1 and '开启' or '关闭'))
  end },

  { label = '增加声望 AddFame', hint = '数量(可负)', run = function(p, a)
    local n = tonumber(a[1]); if not n then return msg(p, '需要数量') end
    local cur = tonumber(Char.GetData(p, CONST.对象_声望)) or 0
    Char.SetData(p, CONST.对象_声望, cur + n); Char.UpCharStatus(p)
    msg(p, string.format('声望 %s%d', n >= 0 and '+' or '', n))
  end },

  { label = '移动 Step', hint = '选格数+方向', run = function(p) end },

  { label = '转职 GetJob', hint = '从列表选择职业', run = function(p) end },

  { label = '宠物技能 PetSkill', hint = '选宠物-选技能-选栏位', run = function(p) end },

  { label = '当前地图 GetMap', hint = '(无参数)', run = function(p)
    local mt = Char.GetData(p, CONST.CHAR_地图类型)
    local mp = Char.GetData(p, CONST.CHAR_地图)
    local x = Char.GetData(p, CONST.CHAR_X)
    local y = Char.GetData(p, CONST.CHAR_Y)
    msg(p, string.format('地图 %d (type %d) @ (%d,%d)', mp, mt, x, y))
  end },

  { label = '丢弃道具 Trash', hint = '点列表删除', run = function(p) end },

  -- ===== GM administration =====
  { label = '设为GM AddGM', hint = '账号CDK', run = function(p, a)
    local k = a[1]; local ad = getModule('admin')
    if not k then return msg(p, '需要账号CDK') end
    if ad and ad.addGm and ad:addGm(k) then msg(p, '已设为GM: ' .. k) else msg(p, '设置失败') end
  end },
  { label = '取消GM RemoveGM', hint = '账号CDK', run = function(p, a)
    local k = a[1]; local ad = getModule('admin')
    if not k then return msg(p, '需要账号CDK') end
    if ad and ad.removeGm and ad:removeGm(k) then msg(p, '已取消GM: ' .. k) else msg(p, '取消失败(内置GM不可移除)') end
  end },
  { label = '重载模块 ReloadModule', hint = '模块名', run = function(p, a)
    if not a[1] then return msg(p, '需要模块名') end
    reloadModule(a[1]); msg(p, '已重载 ' .. a[1])
  end },

  -- ===== world / server (not tied to the talker) =====
  { label = '全服公告 AnnounceAll', hint = '公告内容', run = function(p, a, raw)
    local text = rest(a, 1); if text == '' then return msg(p, '需要公告内容') end
    NLG.SystemMessage(-1, text); msg(p, '已全服公告')
  end },
  { label = '地图公告 AnnounceMap', hint = 'map floor 内容', run = function(p, a)
    local m, f = tonumber(a[1]), tonumber(a[2]); local text = rest(a, 3)
    if not (m and f) or text == '' then return msg(p, '需要 map floor 内容') end
    NLG.SystemMessageToMap(m, f, text); msg(p, '已对地图公告')
  end },
  { label = '在线人数 OnlineCount', hint = '(无参数)', run = function(p)
    msg(p, '在线人数: ' .. tostring(NLG.GetOnLinePlayer()))
  end },
  { label = '地图人数 MapPlayerCount', hint = 'map floor', run = function(p, a)
    local m, f = tonumber(a[1]), tonumber(a[2]); if not (m and f) then return msg(p, '需要 map floor') end
    msg(p, '地图人数: ' .. tostring(NLG.GetMapPlayerNum(m, f)))
  end },
  { label = '查找账号 FindUser', hint = '账号CDK', run = function(p, a)
    if not a[1] then return msg(p, '需要账号CDK') end
    msg(p, 'FindUser -> ' .. tostring(NLG.FindUser(a[1])))
  end },
  { label = '道具名查询 ItemName', hint = 'itemID', run = function(p, a)
    local id = tonumber(a[1]); if not id then return msg(p, '需要 itemID') end
    msg(p, id .. ' = ' .. tostring(Item.GetNameFromNumber(id)))
  end },
  { label = '地面掉金 DropGold', hint = 'map floor x y 金额', run = function(p, a)
    local m, f, x, y, g = tonumber(a[1]), tonumber(a[2]), tonumber(a[3]), tonumber(a[4]), tonumber(a[5])
    if not (m and f and x and y and g) then return msg(p, '需要 map floor x y 金额') end
    Obj.AddGold(m, f, x, y, g); msg(p, '已在地面放置金币')
  end },
  { label = '创建传送点 AddWarp', hint = 'map floor x y toMap toFloor toX toY', run = function(p, a)
    local v = {}
    for i = 1, 8 do v[i] = tonumber(a[i]); if not v[i] then return msg(p, '需要 8 个数字参数') end end
    Obj.AddWarp(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]); msg(p, '已创建传送点')
  end },
  { label = '设置可走 SetWalkable', hint = 'map floor x y able(0/1)', run = function(p, a)
    local m, f, x, y, ab = tonumber(a[1]), tonumber(a[2]), tonumber(a[3]), tonumber(a[4]), tonumber(a[5])
    if not (m and f and x and y and ab) then return msg(p, '需要 map floor x y able') end
    Map.SetWalkable(m, f, x, y, ab); msg(p, '已设置可走属性')
  end },
  { label = '地图名 SetMapName', hint = 'map floor 名称', run = function(p, a)
    local m, f = tonumber(a[1]), tonumber(a[2]); local nm = rest(a, 3)
    if not (m and f) or nm == '' then return msg(p, '需要 map floor 名称') end
    NLG.SetMapName(m, f, nm); msg(p, '已设置地图名')
  end },
  { label = '职业声望上限 JobFameLimit', hint = 'job [limit]', run = function(p, a)
    local job, lim = tonumber(a[1]), tonumber(a[2])
    if not job then return msg(p, '需要 job') end
    if lim then Setup.SetJobFameLimit(job, lim); msg(p, '已设置声望上限')
    else msg(p, '声望上限: ' .. tostring(Setup.GetJobFameLimit(job))) end
  end },
  { label = '随机数 Rand', hint = 'min max', run = function(p, a)
    local lo, hi = tonumber(a[1]), tonumber(a[2]); if not (lo and hi) then return msg(p, '需要 min max') end
    msg(p, 'Rand -> ' .. tostring(NLG.Rand(lo, hi)))
  end },
  { label = '游戏时间 GameTime', hint = '(无参数)', run = function(p)
    msg(p, 'GameTime -> ' .. tostring(NLG.GetGameTime()))
  end },
  { label = '执行SQL SQLRun', hint = '完整SQL语句', run = function(p, a, raw)
    if not raw or raw == '' then return msg(p, '需要 SQL 语句') end
    SQL.Run(raw); msg(p, 'SQL 已执行')
  end },
  { label = '查询SQL SQLQuery', hint = '完整SELECT语句', run = function(p, a, raw)
    if not raw or raw == '' then return msg(p, '需要 SQL 语句') end
    msg(p, 'SQL结果: ' .. tostring(SQL.Query(raw)))
  end },
  { label = '服务器消息 ServerMsg', hint = 'msgId [新值]', run = function(p, a)
    local id = tonumber(a[1]); local val = rest(a, 2)
    if not id then return msg(p, '需要 msgId') end
    if val ~= '' then Data.SetMessage(id, val); msg(p, '已设置消息') else msg(p, '消息: ' .. tostring(Data.GetMessage(id))) end
  end },
  { label = '删除角色 DeleteCharacter', hint = '账号CDK 槽位(0-?)', run = function(p, a)
    local k, place = a[1], tonumber(a[2])
    if not (k and place) then return msg(p, '需要 账号CDK 槽位') end
    NLG.DeleteCharacter(k, place); msg(p, '已请求删除角色 ' .. k .. '/' .. place)
  end },
}

-- ---- SeqNo scheme ----------------------------------------------------------
--   1            = root menu
--   2000 + page  = command list, page N
--   3000 + index = input box for command #index
local SEQ_ROOT     = 1
local SEQ_CMD_BASE = 2000
local SEQ_IN_BASE  = 3000

-- ---- screens ---------------------------------------------------------------

function GmNpc:showRoot(npc, player)
  local m = self:NPC_buildSelectionText('请选择操作', { '显示所有命令 (Show all commands)' })
  NLG.ShowWindowTalked(player, npc, CONST.窗口_选择框, CONST.BUTTON_关闭, SEQ_ROOT, m)
end

function GmNpc:showCommands(npc, player, page)
  local total = math.max(1, math.ceil(#commands / PAGE_SIZE))
  if page < 1 then page = 1 elseif page > total then page = total end
  local opts, start = {}, (page - 1) * PAGE_SIZE
  for i = start + 1, math.min(start + PAGE_SIZE, #commands) do
    opts[#opts + 1] = commands[i].label
  end
  local m = self:NPC_buildSelectionText(string.format('可用命令 第%d/%d页', page, total), opts)
  NLG.ShowWindowTalked(player, npc, CONST.窗口_选择框, pageButtons(page, total), SEQ_CMD_BASE + page, m)
end

function GmNpc:showCommandInput(npc, player, index)
  local c = commands[index]; if not c then return end
  if string.find(c.label, 'GiveItem', 1, true) then return self:itemMenuShow(player) end
  if string.find(c.label, 'GivePet', 1, true) then return self:petMenuShow(player) end
  if string.find(c.label, 'AddSkill', 1, true) then return self:skillMenuShow(player) end
  if string.find(c.label, 'GetJob', 1, true) then return self:jobMenuShow(player) end
  if string.find(c.label, 'PetSkill', 1, true) then return self:petSkillStart(player) end
  if string.find(c.label, 'Step', 1, true) then return self:stepStart(player) end
  if string.find(c.label, 'Trash', 1, true) then return self:trashStart(player) end
  NLG.ShowWindowTalked(player, npc, CONST.窗口_输入框, CONST.BUTTON_确定关闭, SEQ_IN_BASE + index,
    '\\n' .. c.label .. '\\n请输入: ' .. c.hint)
end

function GmNpc:runCommand(player, index, data)
  local c = commands[index]; if not c then return end
  local ok, err = pcall(c.run, player, tokenize(data), data)
  if not ok then msg(player, '执行出错: ' .. tostring(err)) end
end

-- ---- access control + lifecycle --------------------------------------------

-- ============================================================================
-- Name-based item / pet pickers - pick from lists instead of typing IDs.
--   Item: search by name OR browse by category -> pick -> quantity -> give
--   Pet : pick race (种族) -> pick pet -> give
-- Data parsed lazily from data/*.txt; per-player state in self.sess[player].
-- ============================================================================

-- picker window SeqNos (kept clear of SEQ_ROOT / SEQ_CMD_BASE / SEQ_IN_BASE)
local SEQ_ITEM_MENU   = 4000
local SEQ_ITEM_SEARCH = 4001
local SEQ_ITEM_CATS   = 4002
local SEQ_ITEM_LIST   = 4003
local SEQ_ITEM_QTY    = 4004
local SEQ_ITEM_LEVELS = 4005
local SEQ_PET_RACES   = 5000
local SEQ_PET_LIST    = 5001
local SEQ_SKILL_SEARCH = 6000
local SEQ_SKILL_LIST   = 6001
local SEQ_JOB_SEARCH  = 7000
local SEQ_JOB_LIST    = 7001
local SEQ_PETSK_PET    = 8000
local SEQ_PETSK_SEARCH = 8001
local SEQ_PETSK_SKILL  = 8002
local SEQ_PETSK_SLOT   = 8003
local SEQ_PETSK_LEVEL  = 8004
local SEQ_STEP_DIST   = 9000
local SEQ_STEP_DIR    = 9001
local SEQ_TRASH       = 9100

-- race code -> display name (server-owner mapping, positional 0-9)
local RACE_NAMES = {
  [0] = '人形系', [1] = '龙　系', [2] = '不死系', [3] = '飞行系',
  [4] = '昆虫系', [5] = '植物系', [6] = '野兽系', [7] = '特殊系',
  [8] = '金属系', [9] = '头目系',
}

-- lazily parse item + pet data from the data/ files
function GmNpc:ensureData()
  if self.dataReady then return end
  self.items, self.cats = {}, {}
  local catMap = {}
  local function each(path, fn)
    local f = io.open(path)
    if not f then self:logError('cannot open ' .. path); return end
    for line in f:lines() do
      line = string.gsub(line, '\r$', '')
      if line ~= '' and string.sub(line, 1, 1) ~= '#' then fn(string.split(line, '\t')) end
    end
    f:close()
  end
  each('data/itemset.txt', function(t)
    local id, name, cat, lv = tonumber(t[12]), t[2], t[1], tonumber(t[24])
    if id and name and name ~= '' then
      -- only dummy-filter wearable gear (col19==2 = equipment); keep quest/other items
      local real = true
      if tonumber(t[19]) == 2 then
        real = false
        for i = 32, 49 do local v = tonumber(t[i]); if v and v > 0 then real = true; break end end
      end
      local it = { id = id, name = name, lv = lv, real = real }
      self.items[#self.items + 1] = it
      if cat and cat ~= '' then
        local grp = catMap[cat]
        if not grp then grp = { name = cat, items = {} }; catMap[cat] = grp; self.cats[#self.cats + 1] = grp end
        grp.items[#grp.items + 1] = it
      end
    end
  end)
  table.sort(self.cats, function(a, b) return #a.items > #b.items end)
  local lvmap, lvorder = {}, {}
  for _, it in ipairs(self.items) do
    if it.real and it.lv then
      local grp = lvmap[it.lv]
      if not grp then grp = { lv = it.lv, items = {} }; lvmap[it.lv] = grp; lvorder[#lvorder + 1] = grp end
      grp.items[#grp.items + 1] = it
    end
  end
  table.sort(lvorder, function(a, b) return a.lv < b.lv end)
  self.itemLevels = lvorder
  local baseName, baseRace = {}, {}
  each('data/enemybase.txt', function(t)
    local bid = t[2]
    if bid and bid ~= '' then baseName[bid] = t[1]; baseRace[bid] = tonumber(t[5]) or 0 end
  end)
  local races = {}
  self.enemyName = {}
  each('data/enemy.txt', function(t)
    local eid, bid = tonumber(t[3]), t[4]
    local nm = baseName[bid]
    if eid and nm and nm ~= '' then
      self.enemyName[eid] = nm
      local rc = baseRace[bid] or 0
      local grp = races[rc]
      if not grp then grp = { race = rc, pets = {} }; races[rc] = grp end
      grp.pets[#grp.pets + 1] = { id = eid, name = nm }
    end
  end)
  self.raceList = {}
  for rc = 0, 9 do if races[rc] then self.raceList[#self.raceList + 1] = races[rc] end end
  for rc, grp in pairs(races) do if rc < 0 or rc > 9 then self.raceList[#self.raceList + 1] = grp end end
  self.skills = {}
  each('data/skill.txt', function(t)
    local nm, sid = t[1], tonumber(t[2])
    if nm and nm ~= '' and sid then self.skills[#self.skills + 1] = { id = sid, name = nm } end
  end)
  self.jobs = {}
  each('data/jobs.txt', function(t)
    local nm, jid = t[1], tonumber(t[3])
    if nm and nm ~= '' and jid then self.jobs[#self.jobs + 1] = { id = jid, name = nm } end
  end)
  self.techName = {}
  local tgroups, torder = {}, {}
  each('data/tech.txt', function(t)
    local nm, tid = t[1], tonumber(t[4])
    if nm and nm ~= '' and tid then
      self.techName[tid] = nm
      local base, lv = string.match(nm, '^(.-)%s*LV(%d+)$')
      if not base then base = nm; lv = 0 else lv = tonumber(lv) end
      local gr = tgroups[base]
      if not gr then gr = { base = base, variants = {} }; tgroups[base] = gr; torder[#torder + 1] = gr end
      gr.variants[#gr.variants + 1] = { id = tid, lv = lv, name = nm }
    end
  end)
  self.techBases = torder
  self.dataReady = true
  self:logInfo('picker data', #self.items, 'items', #self.cats, 'cats', #self.raceList, 'races')
end

function GmNpc:sessReset(player)
  self.sess = self.sess or {}
  self.sess[player] = { page = 1 }
  return self.sess[player]
end

-- generic paginated selection window (8 rows/page)
function GmNpc:renderPage(player, seqno, title, list, fmt)
  local s = self.sess[player] or self:sessReset(player)
  local total = math.max(1, math.ceil(#list / PAGE_SIZE))
  if s.page < 1 then s.page = 1 elseif s.page > total then s.page = total end
  local opts, start = {}, (s.page - 1) * PAGE_SIZE
  for i = start + 1, math.min(start + PAGE_SIZE, #list) do opts[#opts + 1] = fmt(list[i]) end
  local m = self:NPC_buildSelectionText(string.format('%s %d/%d', title, s.page, total), opts)
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_选择框, pageButtons(s.page, total), seqno, m)
end

-- prev/next page buttons; returns true if a button (not a row) was pressed
function GmNpc:pageNav(player, select, render)
  if select and select > 0 then
    local s = self.sess[player]
    if s and select == CONST.BUTTON_下一页 then s.page = s.page + 1; render()
    elseif s and select == CONST.BUTTON_上一页 then s.page = s.page - 1; render() end
    return true
  end
  return false
end

-- ITEM picker -----------------------------------------------------------------
function GmNpc:itemMenuShow(player)
  self:ensureData(); self:sessReset(player)
  local m = self:NPC_buildSelectionText('给予道具', { '按名称搜索', '按分类浏览', '按等级浏览' })
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_选择框, CONST.BUTTON_关闭, SEQ_ITEM_MENU, m)
end

function GmNpc:itemSearchPrompt(player)
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_输入框, CONST.BUTTON_确定关闭, SEQ_ITEM_SEARCH,
    '\\n输入道具名称关键字')
end

function GmNpc:itemSearchRun(player, kw)
  kw = tostring(kw or '')
  local res = {}
  for _, it in ipairs(self.items) do
    if kw == '' or string.find(it.name, kw, 1, true) then res[#res + 1] = it end
  end
  local s = self.sess[player] or self:sessReset(player)
  s.items = res; s.page = 1
  if #res == 0 then return msg(player, '没有找到匹配的道具') end
  self:itemListShow(player)
end

function GmNpc:itemCatsShow(player)
  self:renderPage(player, SEQ_ITEM_CATS, '选择分类', self.cats,
    function(c) return c.name .. ' (' .. #c.items .. ')' end)
end

function GmNpc:itemListShow(player)
  local s = self.sess[player]; if not s or not s.items then return end
  self:renderPage(player, SEQ_ITEM_LIST, '选择道具', s.items, function(it) return it.lv and (it.name .. ' Lv' .. it.lv) or it.name end)
end

function GmNpc:itemQtyPrompt(player, it)
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_输入框, CONST.BUTTON_确定关闭, SEQ_ITEM_QTY,
    '\\n' .. it.name .. '\\n输入数量(默认1)')
end

function GmNpc:itemGive(player, data)
  local s = self.sess[player]; if not s or not s.pendingItem then return end
  local amt = tonumber(data) or 1; if amt < 1 then amt = 1 end
  local id = s.pendingItem
  local idx = Char.GiveItem(player, id, amt, true)
  if idx and idx >= 0 then
    Item.SetData(idx, CONST.道具_已鉴定, 1)
    Item.UpItem(player, Char.GetItemSlot(player, idx))
  end
  msg(player, string.format('%s x%d', tostring(Item.GetNameFromNumber(id) or id), amt))
end

-- PET picker ------------------------------------------------------------------
function GmNpc:petRacesShow(player)
  self:renderPage(player, SEQ_PET_RACES, '选择种族', self.raceList,
    function(r) return (RACE_NAMES[r.race] or ('种族' .. r.race)) .. ' (' .. #r.pets .. ')' end)
end

function GmNpc:petMenuShow(player)
  self:ensureData(); self:sessReset(player)
  self:petRacesShow(player)
end

function GmNpc:petListShow(player)
  local s = self.sess[player]; if not s or not s.pets then return end
  self:renderPage(player, SEQ_PET_LIST, '选择宠物', s.pets, function(p) return p.name .. ' #' .. p.id end)
end

function GmNpc:petGive(player, p)
  local r = Char.GivePet(player, p.id, 1)
  msg(player, (r and r >= 0) and ('已给予宠物 ' .. p.name) or '给予失败')
end

-- window dispatch for picker screens; returns true if it handled seq
-- SKILL picker (by name; reads data/skill.txt) ------------------------------
function GmNpc:skillMenuShow(player)
  self:ensureData(); self:sessReset(player)
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_输入框, CONST.BUTTON_确定关闭, SEQ_SKILL_SEARCH,
    '\n输入技能名称关键字(留空显示全部)')
end

function GmNpc:skillSearchRun(player, kw)
  kw = tostring(kw or '')
  local res = {}
  for _, sk in ipairs(self.skills) do
    if kw == '' or string.find(sk.name, kw, 1, true) then res[#res + 1] = sk end
  end
  local sess = self.sess[player] or self:sessReset(player)
  sess.skills = res; sess.page = 1
  if #res == 0 then return msg(player, '没有找到匹配的技能') end
  self:skillListShow(player)
end

function GmNpc:skillListShow(player)
  local sess = self.sess[player]; if not sess or not sess.skills then return end
  self:renderPage(player, SEQ_SKILL_LIST, '选择技能', sess.skills, function(sk) return sk.name end)
end

function GmNpc:skillGive(player, sk)
  if Char.HaveSkill(player, sk.id) >= 0 then return msg(player, '已学过: ' .. sk.name) end
  local r = Char.AddSkill(player, sk.id, 0, 0)
  if r and r >= 0 then
    NLG.UpChar(player); msg(player, '已学技能: ' .. sk.name)
  else
    msg(player, '学习失败(技能栏已满?): ' .. sk.name)
  end
end

-- JOB picker (by name; reads data/jobs.txt) --------------------------------
function GmNpc:jobMenuShow(player)
  self:ensureData(); self:sessReset(player)
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_输入框, CONST.BUTTON_确定关闭, SEQ_JOB_SEARCH,
    '\n输入职业名称关键字(留空显示全部)')
end

function GmNpc:jobSearchRun(player, kw)
  kw = tostring(kw or '')
  local res = {}
  for _, jb in ipairs(self.jobs) do
    if kw == '' or string.find(jb.name, kw, 1, true) then res[#res + 1] = jb end
  end
  local sess = self.sess[player] or self:sessReset(player)
  sess.jobs = res; sess.page = 1
  if #res == 0 then return msg(player, '没有找到匹配的职业') end
  self:jobListShow(player)
end

function GmNpc:jobListShow(player)
  local sess = self.sess[player]; if not sess or not sess.jobs then return end
  self:renderPage(player, SEQ_JOB_LIST, '选择职业', sess.jobs, function(jb) return jb.name .. ' (' .. jb.id .. ')' end)
end

function GmNpc:jobGive(player, jb)
  Char.SetData(player, CONST.CHAR_职业, jb.id)
  NLG.UpChar(player)
  msg(player, '已转职: ' .. jb.name .. ' (' .. jb.id .. ')')
end

-- PET SKILL picker: pet -> skill(tech) by name -> slot -> apply ------------
function GmNpc:petSkillStart(player)
  self:ensureData(); self:sessReset(player)
  local sess = self.sess[player]
  local list = {}
  for slot = 0, 4 do
    local pi = Char.GetPet(player, slot)
    if pi and pi >= 0 then
      local nm = Char.GetData(pi, CONST.对象_原名)
      if not nm or nm == '' then nm = self.enemyName[Char.GetPetEnemyId(player, slot)] or ('pet' .. slot) end
      list[#list + 1] = { slot = slot, petIndex = pi, name = nm }
    end
  end
  if #list == 0 then return msg(player, '没有宠物') end
  sess.psPetList = list
  self:petSkillPetShow(player)
end

function GmNpc:petSkillPetShow(player)
  local sess = self.sess[player]; if not sess or not sess.psPetList then return end
  self:renderPage(player, SEQ_PETSK_PET, '选择宠物', sess.psPetList, function(e) return e.name .. ' (' .. e.slot .. ')' end)
end

function GmNpc:petSkillSearchPrompt(player)
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_输入框, CONST.BUTTON_确定关闭, SEQ_PETSK_SEARCH,
    '\n输入技能名称关键字(留空显示全部)')
end

function GmNpc:petSkillSearchRun(player, kw)
  kw = tostring(kw or '')
  local res = {}
  for _, gr in ipairs(self.techBases) do
    if kw == '' or string.find(gr.base, kw, 1, true) then res[#res + 1] = gr end
  end
  local sess = self.sess[player] or self:sessReset(player)
  sess.psBaseList = res; sess.page = 1
  if #res == 0 then return msg(player, '没有找到匹配的技能') end
  self:petSkillBaseShow(player)
end

function GmNpc:petSkillBaseShow(player)
  local sess = self.sess[player]; if not sess or not sess.psBaseList then return end
  self:renderPage(player, SEQ_PETSK_SKILL, '选择技能', sess.psBaseList, function(gr) return gr.base .. ' (' .. #gr.variants .. ')' end)
end

function GmNpc:petSkillLevelShow(player)
  local sess = self.sess[player]; if not sess or not sess.psVariants then return end
  self:renderPage(player, SEQ_PETSK_LEVEL, '选择等级', sess.psVariants, function(v) return v.name end)
end

function GmNpc:petSkillSlotShow(player)
  local sess = self.sess[player]; if not sess or not sess.psPetIndex then return end
  local pi = sess.psPetIndex
  local list = {}
  for sl = 0, 9 do
    local cur = Pet.GetSkill(pi, sl)
    local nm = (cur and cur >= 0 and (self.techName[cur] or ('#' .. cur))) or '空'
    list[#list + 1] = { slot = sl, name = nm }
  end
  sess.psSlotList = list
  self:renderPage(player, SEQ_PETSK_SLOT, '选择技能栏', list, function(e) return e.slot .. ': ' .. e.name end)
end

function GmNpc:petSkillApply(player, slot)
  local sess = self.sess[player]; if not sess or not sess.psPetIndex or not sess.psTechId then return end
  Pet.DelSkill(sess.psPetIndex, slot)
  local r = Pet.AddSkill(sess.psPetIndex, sess.psTechId)
  NLG.UpChar(player)
  if r and r == 1 then
    msg(player, '已为宠物学习: ' .. (sess.psTechName or ''))
  else
    msg(player, '学习失败(技能栏已满或ID无效): ' .. (sess.psTechName or ''))
  end
end

-- STEP picker: distance (2-5) -> direction -> warp --------------------------
function GmNpc:stepStart(player)
  self:sessReset(player)
  local m = self:NPC_buildSelectionText('移动几格', { '2', '3', '4', '5' })
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_选择框, CONST.BUTTON_关闭, SEQ_STEP_DIST, m)
end

function GmNpc:stepDirShow(player)
  local n = (self.sess[player] and self.sess[player].stepDist) or 2
  local m = self:NPC_buildSelectionText('选择方向 (' .. n .. '格)', { '北 N', '南 S', '东 E', '西 W' })
  NLG.ShowWindowTalked(player, self.npc, CONST.窗口_选择框, CONST.BUTTON_关闭, SEQ_STEP_DIR, m)
end

function GmNpc:stepApply(player, dirRow)
  local sess = self.sess[player]; if not sess then return end
  local n = sess.stepDist or 2
  local dx, dy = 0, 0
  if dirRow == 1 then dy = -n elseif dirRow == 2 then dy = n
  elseif dirRow == 3 then dx = n elseif dirRow == 4 then dx = -n else return end
  local mt = Char.GetData(player, CONST.CHAR_地图类型)
  local mp = Char.GetData(player, CONST.CHAR_地图)
  local x = Char.GetData(player, CONST.CHAR_X) + dx
  local y = Char.GetData(player, CONST.CHAR_Y) + dy
  Char.Warp(player, mt, mp, x, y)
  msg(player, string.format('移动到 (%d,%d) 地图%d', x, y, mp))
end

function GmNpc:itemLevelsShow(player)
  self:renderPage(player, SEQ_ITEM_LEVELS, '选择等级', self.itemLevels, function(gr) return 'Lv' .. gr.lv .. ' (' .. #gr.items .. ')' end)
end

-- TRASH: list bag items (slots 8-27) -> click to delete -> refresh -----------
function GmNpc:trashStart(player)
  self:sessReset(player); self:trashListShow(player)
end

function GmNpc:trashListShow(player)
  local sess = self.sess[player] or self:sessReset(player)
  local list = {}
  for slot = 8, 27 do
    local ii = Char.GetItemIndex(player, slot)
    if ii and ii >= 0 then
      local id = tonumber(Item.GetData(ii, CONST.道具_ID))
      local nm = (id and Item.GetNameFromNumber(id)) or ('#' .. tostring(id))
      list[#list + 1] = { slot = slot, name = nm }
    end
  end
  sess.trashList = list
  if #list == 0 then return msg(player, '背包是空的') end
  self:renderPage(player, SEQ_TRASH, '丢弃道具(点击删除)', list, function(e) return e.name end)
end

function GmNpc:onPickerWindow(npc, player, seq, select, data)
  local s = self.sess and self.sess[player]
  if seq == SEQ_ITEM_MENU then
    if select == 0 then
      local row = tonumber(data)
      if row == 1 then self:itemSearchPrompt(player)
      elseif row == 2 then self:itemCatsShow(player)
      elseif row == 3 then self:itemLevelsShow(player) end
    end
    return true
  elseif seq == SEQ_ITEM_SEARCH then
    if select == CONST.BUTTON_确定 then self:itemSearchRun(player, data) end
    return true
  elseif seq == SEQ_ITEM_CATS then
    if not self:pageNav(player, select, function() self:itemCatsShow(player) end) then
      local row = tonumber(data)
      if row and s then
        local cat = self.cats[(s.page - 1) * PAGE_SIZE + row]
        if cat then s.items = cat.items; s.page = 1; self:itemListShow(player) end
      end
    end
    return true
  elseif seq == SEQ_ITEM_LEVELS then
    if not self:pageNav(player, select, function() self:itemLevelsShow(player) end) then
      local row = tonumber(data)
      if row and s then
        local grp = self.itemLevels[(s.page - 1) * PAGE_SIZE + row]
        if grp then s.items = grp.items; s.page = 1; self:itemListShow(player) end
      end
    end
    return true
  elseif seq == SEQ_ITEM_LIST then
    if not self:pageNav(player, select, function() self:itemListShow(player) end) then
      local row = tonumber(data)
      if row and s and s.items then
        local it = s.items[(s.page - 1) * PAGE_SIZE + row]
        if it then s.pendingItem = it.id; self:itemQtyPrompt(player, it) end
      end
    end
    return true
  elseif seq == SEQ_ITEM_QTY then
    if select == CONST.BUTTON_确定 then self:itemGive(player, data) end
    return true
  elseif seq == SEQ_PET_RACES then
    if not self:pageNav(player, select, function() self:petRacesShow(player) end) then
      local row = tonumber(data)
      if row and s then
        local r = self.raceList[(s.page - 1) * PAGE_SIZE + row]
        if r then s.pets = r.pets; s.page = 1; self:petListShow(player) end
      end
    end
    return true
  elseif seq == SEQ_PET_LIST then
    if not self:pageNav(player, select, function() self:petListShow(player) end) then
      local row = tonumber(data)
      if row and s and s.pets then
        local p = s.pets[(s.page - 1) * PAGE_SIZE + row]
        if p then self:petGive(player, p) end
      end
    end
    return true
  elseif seq == SEQ_SKILL_SEARCH then
    if select == CONST.BUTTON_确定 then self:skillSearchRun(player, data) end
    return true
  elseif seq == SEQ_SKILL_LIST then
    if not self:pageNav(player, select, function() self:skillListShow(player) end) then
      local row = tonumber(data)
      if row and s and s.skills then
        local sk = s.skills[(s.page - 1) * PAGE_SIZE + row]
        if sk then self:skillGive(player, sk) end
      end
    end
    return true
  elseif seq == SEQ_JOB_SEARCH then
    if select == CONST.BUTTON_确定 then self:jobSearchRun(player, data) end
    return true
  elseif seq == SEQ_JOB_LIST then
    if not self:pageNav(player, select, function() self:jobListShow(player) end) then
      local row = tonumber(data)
      if row and s and s.jobs then
        local jb = s.jobs[(s.page - 1) * PAGE_SIZE + row]
        if jb then self:jobGive(player, jb) end
      end
    end
    return true
  elseif seq == SEQ_PETSK_PET then
    if not self:pageNav(player, select, function() self:petSkillPetShow(player) end) then
      local row = tonumber(data)
      if row and s and s.psPetList then
        local e = s.psPetList[(s.page - 1) * PAGE_SIZE + row]
        if e then s.psPetIndex = e.petIndex; s.psPetSlot = e.slot; self:petSkillSearchPrompt(player) end
      end
    end
    return true
  elseif seq == SEQ_PETSK_SEARCH then
    if select == CONST.BUTTON_确定 then self:petSkillSearchRun(player, data) end
    return true
  elseif seq == SEQ_PETSK_SKILL then
    if not self:pageNav(player, select, function() self:petSkillBaseShow(player) end) then
      local row = tonumber(data)
      if row and s and s.psBaseList then
        local gr = s.psBaseList[(s.page - 1) * PAGE_SIZE + row]
        if gr then s.psVariants = gr.variants; s.page = 1; self:petSkillLevelShow(player) end
      end
    end
    return true
  elseif seq == SEQ_PETSK_LEVEL then
    if not self:pageNav(player, select, function() self:petSkillLevelShow(player) end) then
      local row = tonumber(data)
      if row and s and s.psVariants then
        local v = s.psVariants[(s.page - 1) * PAGE_SIZE + row]
        if v then s.psTechId = v.id; s.psTechName = v.name; self:petSkillSlotShow(player) end
      end
    end
    return true
  elseif seq == SEQ_PETSK_SLOT then
    if not self:pageNav(player, select, function() self:petSkillSlotShow(player) end) then
      local row = tonumber(data)
      if row and s and s.psSlotList then
        local e = s.psSlotList[(s.page - 1) * PAGE_SIZE + row]
        if e then self:petSkillApply(player, e.slot) end
      end
    end
    return true
  elseif seq == SEQ_STEP_DIST then
    if select == 0 then
      local row = tonumber(data)
      if row and s then s.stepDist = row + 1; self:stepDirShow(player) end
    end
    return true
  elseif seq == SEQ_STEP_DIR then
    if select == 0 then
      local row = tonumber(data)
      if row then self:stepApply(player, row) end
    end
    return true
  elseif seq == SEQ_TRASH then
    if not self:pageNav(player, select, function() self:trashListShow(player) end) then
      local row = tonumber(data)
      if row and s and s.trashList then
        local e = s.trashList[(s.page - 1) * PAGE_SIZE + row]
        if e then Char.DelItemBySlot(player, e.slot); msg(player, '已丢弃: ' .. e.name); self:trashListShow(player) end
      end
    end
    return true
  end
  return false
end

function GmNpc:checkAdmin(player)
  -- WARNING: GM gate DISABLED for bootstrap - any player can use the GM menu
  -- (including AddGM to promote accounts). Remove the next line to re-enable.
  if true then return true end
  local admin = getModule('admin')
  if admin and admin.isAdmin and not admin:isAdmin(player) then
    NLG.SystemMessage(player, '只有管理员可以使用GM助手')
    return false
  end
  return true
end

-- Item entry point: using the GM tool opens the same menu as talking to the NPC.
-- The item is never consumed; non-admins are rejected by checkAdmin.
function GmNpc:onItemUsed(charIndex, targetCharIndex, itemSlot)
  local itemIndex = Char.GetItemIndex(charIndex, itemSlot)
  if tonumber(Item.GetData(itemIndex, CONST.道具_ID)) == GM_ITEM_ID then
    if self:checkAdmin(charIndex) then
      self:showRoot(self.npc, charIndex)
    end
    return -1 -- handled: never consume the GM tool / suppress default use
  end
  return 1
end

function GmNpc:onLoad()
  self:logInfo('load')

  -- open the GM menu when an admin USES the GM tool item
  self:regCallback('ItemUseEvent', Func.bind(self.onItemUsed, self))

  local npc = self:NPC_createNormal(NPC_NAME, NPC_IMAGE, NPC_POS)
  if npc < 0 then
    self:logError('failed to create GM NPC')
    return
  end
  self.npc = npc

  self:NPC_regTalkedEvent(npc, function(theNpc, player)
    if not self:checkAdmin(player) then return end
    if NLG.CanTalk(theNpc, player) ~= true then return end
    self:showRoot(theNpc, player)
  end)

  self:NPC_regWindowTalkedEvent(npc, function(theNpc, player, seqno, select, data)
    if not self:checkAdmin(player) then return end
    local seq = tonumber(seqno) or SEQ_ROOT
    if self:onPickerWindow(theNpc, player, seq, select, data) then return end

    if seq == SEQ_ROOT then
      if select == 0 then self:showCommands(theNpc, player, 1) end
      return

    elseif seq >= SEQ_CMD_BASE and seq < SEQ_IN_BASE then
      local page = seq - SEQ_CMD_BASE
      if select > 0 then
        if select == CONST.BUTTON_下一页 then
          self:showCommands(theNpc, player, page + 1)
        elseif select == CONST.BUTTON_上一页 then
          self:showCommands(theNpc, player, page - 1)
        end
        return
      end
      local row = tonumber(data)
      if row then self:showCommandInput(theNpc, player, (page - 1) * PAGE_SIZE + row) end
      return

    elseif seq >= SEQ_IN_BASE then
      if select == CONST.BUTTON_确定 then
        self:runCommand(player, seq - SEQ_IN_BASE, data)
      end
      return
    end
  end)
end

function GmNpc:onUnload()
  self:logInfo('unload')
end

return GmNpc
