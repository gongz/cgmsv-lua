local mName = 'gmNpc'
---@class GmNpc:ModuleType
local GmNpc = ModuleBase:createModule(mName)

-- =============================================================================
-- GM helper NPC — generic command dispatcher.
--
--   talk -> "what do you want to do?" (only option: "show all commands")
--        -> paginated list of every command in `commands`
--        -> input box: type the primitive args -> the command runs on the talker
--
-- Each command is { label, hint, run(player, args) } where `args` is the list of
-- whitespace-separated tokens the GM typed. Add a new GM action = add one row.
-- The receiver is always whoever is talking to the NPC (except Add/Remove GM,
-- which take a target account CDK as input).
-- =============================================================================

-- ---- configuration ---------------------------------------------------------

local NPC_NAME  = 'GM助手'
local NPC_IMAGE = 103010
local NPC_POS   = { x = 242, y = 88, mapType = 0, map = 1000, direction = 6 }

local PAGE_SIZE = 8 -- select window shows at most 8 rows per page

-- ---- helpers ---------------------------------------------------------------

local function msg(player, text) NLG.SystemMessage(player, text) end

local function tokenize(s)
  local t = {}
  for w in tostring(s or ''):gmatch('%S+') do t[#t + 1] = w end
  return t
end

local function pageButtons(page, total)
  if total <= 1 then return CONST.BUTTON_关闭 end
  if page == 1 then return CONST.BUTTON_下取消 end     -- next + cancel
  if page == total then return CONST.BUTTON_上取消 end -- prev + cancel
  return CONST.BUTTON_上下取消                          -- prev + next + cancel
end

-- ---- command registry (the "API list") -------------------------------------
-- Each row maps a menu entry to a direct API call. `a` = typed arg tokens.

local commands = {
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
  { label = '传送 Warp', hint = 'mapType floor x y', run = function(p, a)
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
}

-- ---- SeqNo scheme (encodes which screen the window belongs to) --------------
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
  NLG.ShowWindowTalked(player, npc, CONST.窗口_输入框, CONST.BUTTON_确定关闭, SEQ_IN_BASE + index,
    '\\n' .. c.label .. '\\n请输入: ' .. c.hint)
end

function GmNpc:runCommand(player, index, data)
  local c = commands[index]; if not c then return end
  local ok, err = pcall(c.run, player, tokenize(data))
  if not ok then msg(player, '执行出错: ' .. tostring(err)) end
end

-- ---- lifecycle -------------------------------------------------------------

function GmNpc:checkAdmin(player)
  local admin = getModule('admin')
  if admin and admin.isAdmin and not admin:isAdmin(player) then
    NLG.SystemMessage(player, '只有管理员可以使用GM助手')
    return false
  end
  return true
end

function GmNpc:onLoad()
  self:logInfo('load')

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

    if seq == SEQ_ROOT then
      if select == 0 then self:showCommands(theNpc, player, 1) end
      return

    elseif seq >= SEQ_CMD_BASE and seq < SEQ_IN_BASE then -- command list
      local page = seq - SEQ_CMD_BASE
      if select > 0 then
        if select == CONST.BUTTON_下一页 then
          self:showCommands(theNpc, player, page + 1)
        elseif select == CONST.BUTTON_上一页 then
          self:showCommands(theNpc, player, page - 1)
        end
        return -- cancel/close
      end
      local row = tonumber(data)
      if row then self:showCommandInput(theNpc, player, (page - 1) * PAGE_SIZE + row) end
      return

    elseif seq >= SEQ_IN_BASE then -- input box for a command
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
