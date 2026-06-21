-- Server side for the Give-Item UI panel (client: UIMAP/gmitem.lua).
-- Receives gmitem_search / gmitem_give packets; reuses gmNpc item data.
local GmItemUI = ModuleBase:createModule('gmItemUI')

function GmItemUI:onLoad()
  self:logInfo('load')
  self:regCallback('ProtocolOnRecv', Func.bind(self.onSearch, self), 'gmitem_search')
  self:regCallback('ProtocolOnRecv', Func.bind(self.onGive, self), 'gmitem_give')
end

function GmItemUI:onSearch(fd, head, data)
  local player = tonumber(Protocol.GetCharByFd(fd))
  if not player or player < 0 then return end
  local gm = getModule('gmNpc')
  if not gm then return end
  local packet = gm:uiItemSearch(data[1])
  Protocol.Send(player, 'gmitem_list', packet)
end

function GmItemUI:onGive(fd, head, data)
  local player = tonumber(Protocol.GetCharByFd(fd))
  if not player or player < 0 then return end
  local id = tonumber(data[1])
  if not id then return end
  local idx = Char.GiveItem(player, id, 1, true)
  if idx and idx >= 0 then
    Item.SetData(idx, CONST.道具_已鉴定, 1)
    Item.UpItem(player, Char.GetItemSlot(player, idx))
  end
  NLG.SystemMessage(player, '[GM] ' .. tostring(Item.GetNameFromNumber(id) or id))
end

function GmItemUI:onUnload() self:logInfo('unload') end
return GmItemUI
