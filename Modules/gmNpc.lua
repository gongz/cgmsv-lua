local mName = 'gmNpc'
---@class GmNpc:ModuleType
local GmNpc = ModuleBase:createModule(mName)

-- =============================================================================
-- GM helper NPC.
--
-- One NPC that drives a menu:
--   talk -> "what do you want to do?" (only option: "show all commands")
--        -> list of available GM commands
--        -> "Give Item": a paginated item window; click a row to receive it.
--        -> "Give Pet" : a paginated pet window;  click a row to receive it.
--
-- The receiver is always whoever is talking to the NPC (no online-player list).
-- New command paths plug into `commandMenu` + a screen handler.
-- =============================================================================

-- ---- configuration (edit freely) -------------------------------------------

local NPC_NAME  = 'GM助手'
local NPC_IMAGE = 103010
local NPC_POS   = { x = 242, y = 88, mapType = 0, map = 1000, direction = 6 }

local PAGE_SIZE = 8 -- the select window shows at most 8 rows per page

-- Item catalog for the "Give Item" path. IDs MUST match this server's item data
-- (data/item table); the names below are placeholders to demonstrate pagination.
local itemCatalog = {
  { id = 1,  name = '道具1' },
  { id = 2,  name = '道具2' },
  { id = 3,  name = '道具3' },
  { id = 4,  name = '道具4' },
  { id = 5,  name = '道具5' },
  { id = 6,  name = '道具6' },
  { id = 7,  name = '道具7' },
  { id = 8,  name = '道具8' },
  { id = 9,  name = '道具9' },   -- page 2 starts here
  { id = 10, name = '道具10' },
  { id = 11, name = '道具11' },
  { id = 12, name = '道具12' },
}

-- Pet catalog for the "Give Pet" path. IDs MUST match this server's pet data.
local petCatalog = {
  { id = 1,  name = '宠物1' },
  { id = 2,  name = '宠物2' },
  { id = 3,  name = '宠物3' },
  { id = 4,  name = '宠物4' },
  { id = 5,  name = '宠物5' },
  { id = 6,  name = '宠物6' },
  { id = 7,  name = '宠物7' },
  { id = 8,  name = '宠物8' },
  { id = 9,  name = '宠物9' },   -- page 2 starts here
  { id = 10, name = '宠物10' },
}

-- ---- screens (the screen id + page are packed into the window SeqNo) --------

local SCREEN_ROOT     = 1
local SCREEN_COMMANDS = 2
local SCREEN_ITEMS    = 3
local SCREEN_PETS     = 4

-- "Show all commands" lists these; each row opens a screen.
local commandMenu = {
  { label = '给予道具 (Give Item)', screen = SCREEN_ITEMS },
  { label = '给予宠物 (Give Pet)',  screen = SCREEN_PETS },
}

local function encodeSeq(screen, page) return screen * 10000 + (page or 1) end
local function decodeSeq(seq)
  local s = math.floor(seq / 10000)
  return s, seq - s * 10000
end

-- pick prev/next/cancel buttons for a given page within `total` pages
local function pageButtons(page, total)
  if total <= 1 then return CONST.BUTTON_关闭 end
  if page == 1 then return CONST.BUTTON_下取消 end        -- next + cancel
  if page == total then return CONST.BUTTON_上取消 end    -- prev + cancel
  return CONST.BUTTON_上下取消                            -- prev + next + cancel
end

-- ---- screen renderers ------------------------------------------------------

---root menu: "what do you want to do?" (single option)
function GmNpc:showRoot(npc, player)
  local msg = self:NPC_buildSelectionText('请选择操作', { '显示所有命令 (Show all commands)' })
  NLG.ShowWindowTalked(player, npc, CONST.窗口_选择框, CONST.BUTTON_关闭, encodeSeq(SCREEN_ROOT, 1), msg)
end

---list of available commands
function GmNpc:showCommands(npc, player)
  local opts = {}
  for i = 1, #commandMenu do opts[i] = commandMenu[i].label end
  local msg = self:NPC_buildSelectionText('可用命令 (Commands)', opts)
  NLG.ShowWindowTalked(player, npc, CONST.窗口_选择框, CONST.BUTTON_关闭, encodeSeq(SCREEN_COMMANDS, 1), msg)
end

---one page of a {id,name} catalog as a select window
function GmNpc:showCatalog(npc, player, screen, catalog, title, page)
  local total = math.max(1, math.ceil(#catalog / PAGE_SIZE))
  if page < 1 then page = 1 elseif page > total then page = total end

  local opts = {}
  local start = (page - 1) * PAGE_SIZE
  for i = start + 1, math.min(start + PAGE_SIZE, #catalog) do
    opts[#opts + 1] = catalog[i].name
  end

  local msg = self:NPC_buildSelectionText(string.format('%s  第%d/%d页', title, page, total), opts)
  NLG.ShowWindowTalked(player, npc, CONST.窗口_选择框, pageButtons(page, total), encodeSeq(screen, page), msg)
end

function GmNpc:showItems(npc, player, page)
  self:showCatalog(npc, player, SCREEN_ITEMS, itemCatalog, '选择道具 (Give Item)', page)
end

function GmNpc:showPets(npc, player, page)
  self:showCatalog(npc, player, SCREEN_PETS, petCatalog, '选择宠物 (Give Pet)', page)
end

-- ---- actions ---------------------------------------------------------------

function GmNpc:giveItem(player, row, page)
  local it = itemCatalog[(page - 1) * PAGE_SIZE + row]
  if not it then return end
  local r = Char.GiveItem(player, it.id, 1, true)
  if r and r >= 0 then
    NLG.SystemMessage(player, '已给予道具: ' .. it.name)
  else
    NLG.SystemMessage(player, '给予失败(背包已满?): ' .. it.name)
  end
end

function GmNpc:givePet(player, row, page)
  local p = petCatalog[(page - 1) * PAGE_SIZE + row]
  if not p then return end
  local r = Char.GivePet(player, p.id, 1) -- FullBP = 1 -> max-grade pet
  if r and r >= 0 then
    NLG.SystemMessage(player, '已给予宠物: ' .. p.name)
  else
    NLG.SystemMessage(player, '给予失败(宠物栏已满?): ' .. p.name)
  end
end

-- ---- access control --------------------------------------------------------

---GM-only. If the admin module is loaded, non-admins are rejected; if it is not
---loaded, access is open (dev convenience). Remove this gate to let anyone use it.
function GmNpc:checkAdmin(player)
  local admin = getModule('admin')
  if admin and admin.isAdmin and not admin:isAdmin(player) then
    NLG.SystemMessage(player, '只有管理员可以使用GM助手')
    return false
  end
  return true
end

-- ---- lifecycle -------------------------------------------------------------

function GmNpc:onLoad()
  self:logInfo('load')

  local npc = self:NPC_createNormal(NPC_NAME, NPC_IMAGE, NPC_POS)
  if npc < 0 then
    self:logError('failed to create GM NPC')
    return
  end
  self.npc = npc

  -- open the root menu when talked to
  self:NPC_regTalkedEvent(npc, function(theNpc, player)
    if not self:checkAdmin(player) then return end
    if NLG.CanTalk(theNpc, player) ~= true then return end
    self:showRoot(theNpc, player)
  end)

  -- handle all window interactions; the screen is recovered from SeqNo
  self:NPC_regWindowTalkedEvent(npc, function(theNpc, player, seqno, select, data)
    if not self:checkAdmin(player) then return end
    local screen, page = decodeSeq(tonumber(seqno) or encodeSeq(SCREEN_ROOT, 1))

    if screen == SCREEN_ROOT then
      if select == 0 then -- "show all commands"
        self:showCommands(theNpc, player)
      end
      return

    elseif screen == SCREEN_COMMANDS then
      if select == 0 then
        local row = tonumber(data)
        local c = row and commandMenu[row]
        if c and c.screen == SCREEN_ITEMS then
          self:showItems(theNpc, player, 1)
        elseif c and c.screen == SCREEN_PETS then
          self:showPets(theNpc, player, 1)
        end
      end
      return

    elseif screen == SCREEN_ITEMS then
      if select > 0 then -- paging / cancel button
        if select == CONST.BUTTON_下一页 then
          self:showItems(theNpc, player, page + 1)
        elseif select == CONST.BUTTON_上一页 then
          self:showItems(theNpc, player, page - 1)
        end
        return -- any other button (cancel/close) just closes
      end
      local row = tonumber(data) -- a row was clicked
      if row then self:giveItem(player, row, page) end
      return

    elseif screen == SCREEN_PETS then
      if select > 0 then
        if select == CONST.BUTTON_下一页 then
          self:showPets(theNpc, player, page + 1)
        elseif select == CONST.BUTTON_上一页 then
          self:showPets(theNpc, player, page - 1)
        end
        return
      end
      local row = tonumber(data)
      if row then self:givePet(player, row, page) end
      return
    end
  end)
end

function GmNpc:onUnload()
  self:logInfo('unload')
end

return GmNpc
