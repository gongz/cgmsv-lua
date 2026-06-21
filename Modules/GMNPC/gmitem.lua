-- ============================================================================
-- Give-Item GM panel (CLIENT-side UI). Deploy next to GMSVLC like UIMAP/map.lua.
-- Server side: Modules/gmItemUI.lua (handles gmitem_search / gmitem_give).
-- Open: type 'gmitem' in chat.  Search by name -> click a row to receive 1.
-- Reuses UIMAP's ASCII-named PNGs only (no Chinese filenames).
-- NOTE: POC, untested in-client; tweak coordinates/sizes to taste.
-- ============================================================================
local GmItem = ModuleBase:extend('gmItemPanel')

local WIN_ID  = 2050
local COMMAND = 'gmitem'
local ROWS    = 10

local bg        = 'images/map/bg.png'
local row_bg    = 'images/map/warp_select.png'
local row_h     = 'images/map/warp_select_h.png'
local row_p     = 'images/map/warp_select_p.png'
local ok_btn    = 'images/map/640022.png'
local ok_btn_h  = 'images/map/640023.png'
local ok_btn_p  = 'images/map/640024.png'
local close_btn = 'images/map/640016.png'
local close_h   = 'images/map/640017.png'
local close_p   = 'images/map/640018.png'
local l_arrow   = 'images/map/245066.png'
local l_arrow_h = 'images/map/245068.png'
local l_arrow_p = 'images/map/245067.png'
local r_arrow   = 'images/map/245063.png'
local r_arrow_h = 'images/map/245065.png'
local r_arrow_p = 'images/map/245064.png'

local function splitPipe(s)
	local t = {}
	for v in string.gmatch(s or '', '([^|]+)') do t[#t + 1] = v end
	return t
end

function GmItem:onLoad()
	self.win = nil
	self.items = {}     -- { {name, id, lv}, ... }
	self.page = 1
	self.rows = {}
	self.searchInput = nil
	self.pageText = nil
	self.listEvt = WinMgr.OnPacketRecv('gmitem_list', function(h, p) self:onList(h, p) end)
	self:onChatMessage(function(text)
		if text == COMMAND then self:toggle(); return 1 end
		return true
	end)
end

function GmItem:toggle()
	if self.win and self.win.valid then
		self.win:Close(); self.win = nil; return
	end
	self:open()
end

function GmItem:open()
	local W, H = 300, 400
	local x = (CONST.Screen.Width - W) / 2
	local y = (CONST.Screen.Height - H) / 2
	local status, win = self:newWindow({ id = WIN_ID, x = x, y = y, width = W, height = H, layer = 4, dragMove = 1 })
	self.win = win
	if not win then return end

	win:AddPngImage({ x = 0, y = 0, width = W, height = H, image = bg, color = -1, hitable = false })
	win:AddText({ x = 14, y = 10, width = 120, height = 18, text = 'Give Item', font = 1, color = 5, hitable = false })

	-- search box + button
	win:AddPngImage({ x = 12, y = 34, width = 200, height = 20, image = row_bg, color = -1, hitable = false })
	self.searchInput = win:AddTextInput({ x = 16, y = 36, width = 192, height = 16, text = '', font = 1, color = 0, maxLength = 32 })
	win:AddPngImage({ x = 222, y = 33, width = 52, height = 20, image = ok_btn, imageHover = ok_btn_h, imagePress = ok_btn_p,
		color = -1, hitable = true, onClick = function() self:doSearch(); return true end })

	-- result rows
	self.rows = {}
	local LY = 64
	for i = 1, ROWS do
		win:AddPngImage({ x = 12, y = LY + (i - 1) * 28, width = 276, height = 24, image = row_bg, imageHover = row_h, imagePress = row_p,
			color = -1, hitable = true, onClick = function() self:onRow(i); return true end })
		self.rows[i] = win:AddText({ x = 18, y = LY + (i - 1) * 28 + 4, width = 264, height = 18, text = '', font = 1, color = 0, hitable = false, visible = true })
	end

	-- paging
	local PY = LY + ROWS * 28 + 8
	win:AddPngImage({ x = 100, y = PY, width = 20, height = 20, image = l_arrow, imageHover = l_arrow_h, imagePress = l_arrow_p,
		color = -1, hitable = true, onClick = function() self:prev(); return true end })
	self.pageText = win:AddText({ x = 130, y = PY + 2, width = 50, height = 18, text = '1/1', font = 1, color = 0, hitable = false })
	win:AddPngImage({ x = 180, y = PY, width = 20, height = 20, image = r_arrow, imageHover = r_arrow_h, imagePress = r_arrow_p,
		color = -1, hitable = true, onClick = function() self:next(); return true end })

	-- close
	win:AddPngImage({ x = 262, y = 8, width = 24, height = 24, image = close_btn, imageHover = close_h, imagePress = close_p,
		color = -1, hitable = true, onClick = function() self.win:Close(); self.win = nil; return true end })

	WinMgr.Focus(WIN_ID)
end

function GmItem:doSearch()
	if not self.searchInput or not self.searchInput.valid then return end
	WinMgr.SendPacket('gmitem_search', self.searchInput.text or '')
end

function GmItem:onList(h, params)
	local parts = splitPipe(params[1])
	self.items = {}
	for i = 1, #parts, 3 do
		if parts[i] then
			self.items[#self.items + 1] = { name = parts[i], id = tonumber(parts[i + 1]) or 0, lv = tonumber(parts[i + 2]) or 0 }
		end
	end
	self.page = 1
	self:refresh()
end

function GmItem:refresh()
	if not self.win or not self.win.valid then return end
	local startIdx = (self.page - 1) * ROWS
	for i = 1, ROWS do
		local it = self.items[startIdx + i]
		local r = self.rows[i]
		if r and r.valid then
			if it then r:Set({ text = it.name .. '  Lv' .. it.lv, visible = true })
			else r:Set({ text = '', visible = false }) end
		end
	end
	if self.pageText and self.pageText.valid then
		local total = math.ceil(#self.items / ROWS); if total <= 0 then total = 1 end
		self.pageText:Set({ text = string.format('%d/%d', self.page, total) })
	end
end

function GmItem:onRow(i)
	local it = self.items[(self.page - 1) * ROWS + i]
	if it then WinMgr.SendPacket('gmitem_give', tostring(it.id)) end
end

function GmItem:prev()
	if self.page > 1 then self.page = self.page - 1; self:refresh() end
end

function GmItem:next()
	local total = math.ceil(#self.items / ROWS)
	if self.page < total then self.page = self.page + 1; self:refresh() end
end

function GmItem:onUnload()
	if self.listEvt then self.listEvt:Unregister() end
	if self.win and self.win.valid then self.win:Close() end
end

return GmItem
