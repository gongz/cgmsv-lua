---@class Admin:ModuleBase|ModuleType
local Admin = ModuleBase:createModule('admin')
-- gm命令
local commands = {}
--GM账号列表
local gmList = { 'u01', 'u02', 'u03', 'u04', 'u05', 'aaa' };
local gmDict = {};
table.forEach(gmList, function(e)
  gmDict[e] = true
end)

-- 运行时新增的GM(持久化到文件)。hardcoded为内置不可移除集合。
local GM_FILE = 'gm_extra.txt' -- 每行一个账号CDK
local hardcoded = {};
table.forEach(gmList, function(e) hardcoded[e] = true end)
local persisted = {};

local function saveGmFile()
  local f = io.open(GM_FILE, 'w')
  if not f then return end
  for k in pairs(persisted) do f:write(k .. '\n') end
  f:close()
end

local function loadGmFile()
  local f = io.open(GM_FILE, 'r')
  if not f then return end
  for line in f:lines() do
    local k = line and line:match('^%s*(%S+)%s*$')
    if k and k:sub(1, 1) ~= '#' then
      persisted[k] = true
      gmDict[k] = true
    end
  end
  f:close()
end
loadGmFile()

function commands.module(charIndex, args)
  if args[1] == 'reload' then
    reloadModule(args[2]);
  elseif args[1] == 'unload' then
    unloadModule(args[2]);
  elseif args[1] == 'load' then
    loadModule(args[2]);
  end
end

function commands.dofile(charIndex, args)
  local r, msg = pcall(dofile, args[1]);
  if not r then
    NLG.TalkToCli(charIndex, -1, tostring(msg));
  end
end

---是否管理员
---@param charIndex CharIndex
---@return boolean
function Admin:isAdmin(charIndex)
  local cdKey = Char.GetData(charIndex, CONST.CHAR_CDK)
  if not gmDict[cdKey] then
    return false
  end
  return true;
end

---把某账号CDK设为GM(持久化)。
---@param cdKey string 目标玩家的账号CDK(CONST.CHAR_CDK)
---@return boolean
function Admin:addGm(cdKey)
  if not cdKey or cdKey == '' then
    return false
  end
  gmDict[cdKey] = true
  persisted[cdKey] = true
  saveGmFile()
  return true
end

---取消某账号CDK的GM(内置gmList无法在运行时永久移除)。
---@param cdKey string 目标玩家的账号CDK
---@return boolean
function Admin:removeGm(cdKey)
  if not cdKey or cdKey == '' or hardcoded[cdKey] then
    return false
  end
  gmDict[cdKey] = nil
  persisted[cdKey] = nil
  saveGmFile()
  return true
end

---读取某对象index对应账号的CDK(用于设为GM)。
---@param charIndex CharIndex
---@return string
function Admin:getCdKey(charIndex)
  return Char.GetData(charIndex, CONST.CHAR_CDK)
end

function Admin:handleChat(charIndex, msg, color, range, size)
  if not self:isAdmin(charIndex) then
    return 1
  end
  local command = msg:match('^/([%w]+)')
  if commands[command] then
    local arg = msg:match('^/[%w]+ +(.+)$')
    arg = arg and string.split(arg, ' ') or {}
    commands[command](charIndex, arg);
    return 0
  end
  return 1
end

function Admin:onLoad()
  self:logInfo('load')
  self:regCallback('TalkEvent', Func.bind(Admin.handleChat, self))
end

function Admin:onUnload()
  self:logInfo('unload')
end

return Admin;
