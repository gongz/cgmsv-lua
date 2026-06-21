local getWarpModule = ModuleBase:createModule('GetWarp')
function getWarpModule:onLoad()
    self:logInfo('load')
	self:regCallback('ProtocolOnRecv',Func.bind(self.get_warp,self),'get_warp')
	self:regCallback('ProtocolOnRecv',Func.bind(self.input_diy,self),'input_diy')
	self:regCallback('ProtocolOnRecv',Func.bind(self.del_diy,self),'del_diy')
    self:regCallback('ProtocolOnRecv',Func.bind(self.findnpc,self),'get_npc')
end
local function normalizeDirectionOrder(mapName)
    if not mapName or type(mapName) ~= "string" then return mapName end
    local orderPatterns = {
        {"����", "����"}, {"����", "����"},
        {"����", "����"}, {"�϶�", "����"},
    }
    local result = mapName
    for _, pattern in ipairs(orderPatterns) do
        result = result:gsub(pattern[1], pattern[2])
    end
    return result
end

local function distSq(p1, p2)
    local dx = p1.x - p2.x
    local dy = p1.y - p2.y
    return dx * dx + dy * dy
end

local function processGroup(groupPoints)
    if #groupPoints == 0 then return {} end
    if #groupPoints == 1 then return groupPoints end

    local minX, maxX = groupPoints[1].x, groupPoints[1].x
    local minY, maxY = groupPoints[1].y, groupPoints[1].y
    for _, pt in ipairs(groupPoints) do
        if pt.x < minX then minX = pt.x end
        if pt.x > maxX then maxX = pt.x end
        if pt.y < minY then minY = pt.y end
        if pt.y > maxY then maxY = pt.y end
    end

    local centerX = (minX + maxX) / 2
    local centerY = (minY + maxY) / 2
    local thresholdSq = 25
    local visited = {}
    local clusters = {}

    for i = 1, #groupPoints do
        if not visited[i] then
            local newCluster = {groupPoints[i]}
            visited[i] = true
            local queue = {i}
            local head = 1

            while head <= #queue do
                local currIdx = queue[head]
                head = head + 1
                for j = 1, #groupPoints do
                    if not visited[j] and distSq(groupPoints[currIdx], groupPoints[j]) <= thresholdSq then
                        visited[j] = true
                        table.insert(newCluster, groupPoints[j])
                        table.insert(queue, j)
                    end
                end
            end
            table.insert(clusters, newCluster)
        end
    end

    local result = {}
    for _, cluster in ipairs(clusters) do
        local representative = cluster[1]
        if #cluster > 1 then
            table.sort(cluster, function(a, b)
                if a.x == b.x then return a.y < b.y end
                return a.x < b.x
            end)
            representative = cluster[math.ceil(#cluster / 2)]
        end

        local diffX = representative.x - centerX
        local diffY = representative.y - centerY
        local minDiff = 2
        local dirH, dirV = "", ""

        if diffX > minDiff then dirH = "��"
        elseif diffX < -minDiff then dirH = "��" end

        if diffY > minDiff then dirV = "��"
        elseif diffY < -minDiff then dirV = "��" end

        local dirName = normalizeDirectionOrder(dirV .. dirH)
        if dirName ~= "" then
            representative.name = representative.name .. "(" .. dirName .. ")"
        end

        table.insert(result, representative)
    end

    return result
end

function getWarpModule:get_warp(fd,head,data)
	local player = tonumber(Protocol.GetCharByFd(fd))
    if not player or player < 0 then return nil end
    local maptype = Char.GetData(player, CONST.����_��ͼ����)
    local mapid = Char.GetData(player, CONST.����_��ͼ)
    if not maptype or not mapid then return nil end

    local maxx, maxy = Map.GetMapSize(maptype, mapid)
    if not maxx or not maxy then return nil end
    local result = {}
    for x = 1, maxx do
        for y = 1, maxy do
            local count, objtbl = Obj.GetObject(maptype, mapid, x, y)
            if count > 0 then
                for _, obj in ipairs(objtbl) do
                    local objtype = Obj.GetType(obj)
                    if objtype == 4 then
                        local warpMap = Obj.GetWarpMap(obj)
                        local warpFloor = Obj.GetWarpFloor(obj)
                        local name = string.split(NLG.GetMapName(warpMap, warpFloor), '|')[1]
                        table.insert(result, {name = name, x = x, y = y})
                    elseif objtype == 1 then
                        local charIndex = Obj.GetCharIndex(obj)
                        if charIndex and charIndex >= 0 then
                            local npcEventType = Char.GetData(charIndex, CONST.����_NPC_EVENT_TYPE)
                            if npcEventType == 3 then
                                local argNpc = NLG.GetArgNpc(charIndex)
                                local warpto = string.split(argNpc, '|')
                                if #warpto >= 2 then
                                    local warpMap = tonumber(warpto[1])
                                    local warpFloor = tonumber(warpto[2])
                                    local name = string.split(NLG.GetMapName(warpMap, warpFloor), '|')[1]
                                    table.insert(result, {name = name, x = x, y = y})
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #result == 0 then return nil end

    for i = 1, #result do
        result[i].name = normalizeDirectionOrder(result[i].name)
    end

    table.sort(result, function(a, b)
        if a.name == b.name then
            if a.x == b.x then return a.y < b.y end
            return a.x < b.x
        end
        return a.name < b.name
    end)

    local uniqueResult = {}
    local currentName = nil
    local groupPoints = {}

    for i = 1, #result do
        local name = result[i].name
        if name ~= currentName then
            local merged = processGroup(groupPoints)
            for _, v in ipairs(merged) do table.insert(uniqueResult, v) end
            currentName = name
            groupPoints = {}
        end
        table.insert(groupPoints, result[i])
    end

    local merged = processGroup(groupPoints)
    for _, v in ipairs(merged) do table.insert(uniqueResult, v) end


	if uniqueResult then
		local packet = ""
		for i, v in ipairs(uniqueResult) do
			if i == 1 then
				packet = v.name .. "|" .. v.x .. "|" .. v.y
			else
				packet = packet .. "|" .. v.name .. "|" .. v.x .. "|" .. v.y
			end
		end

		Protocol.Send(player, "allwarp", packet)
	end

	local diy = Char.GetExtData(player,mapid)

	if diy then
		Protocol.Send(player, "diywarp", diy)
	end


end



function getWarpModule:del_diy(fd,head,data)
	local player = tonumber(Protocol.GetCharByFd(fd))
	local mapid = Char.GetData(player, CONST.����_��ͼ)
	local diy = Char.GetExtData(player,mapid)

	if not diy then
		Protocol.Send(player, "diywarp", "")
		return
	end

	local index = tonumber(data[1])
	if not index or index <= 0 then
		Protocol.Send(player, "diywarp", diy)
		return
	end

	local arr = {}
	for v in string.gmatch(diy, "([^|]+)") do
		table.insert(arr, v)
	end

	local startIdx = (index - 1) * 3 + 1

	if startIdx > #arr then
		Protocol.Send(player, "diywarp", diy)
		return
	end

	table.remove(arr, startIdx)
	table.remove(arr, startIdx)
	table.remove(arr, startIdx)

	local newDiy = table.concat(arr, "|")
	Char.SetExtData(player,mapid,newDiy)
	Protocol.Send(player, "diywarp", newDiy)
end




function getWarpModule:input_diy(fd,head,data)
	local player = tonumber(Protocol.GetCharByFd(fd))
    local mapid = Char.GetData(player, CONST.����_��ͼ)
	local diy = Char.GetExtData(player,mapid)
	if diy then
		diy = diy.."|"..data[1]
	else
		diy = data[1]
	end
	Char.SetExtData(player,mapid,diy)
	Protocol.Send(player, "diywarp", diy)
end

function getWarpModule:findnpc(fd,head,data)
    local player = tonumber(Protocol.GetCharByFd(fd))
    local nametbl = {}
    local maptype = Char.GetData(player,CONST.����_��ͼ����)
    local mapid = Char.GetData(player,CONST.����_��ͼ)
    local maxx,maxy = Map.GetMapSize(maptype, mapid)

    if not maxx or not maxy then return 1 end

    for i = 1,maxx do
        for l = 1,maxy do
            local j,_objtbl = Obj.GetObject(maptype, mapid, i, l)
            if j > 0 then
                for key, v in ipairs(_objtbl) do
                    local _Index = Obj.GetCharIndex(v)
                    local _Name = Char.GetData(_Index,CONST.����_����)
                    local objtype = Obj.GetType(v)

                    if _Index ~= player then
                        if objtype == 1 then
                            if #_Name > 0 and _Name ~= " " then
                                table.insert(nametbl,{_Name,i,l})
                            end
                        end
                    end
                end
            end
        end
    end

    local �ȴ����͵ķ�� = ""
    if #nametbl > 0 then
        for i = 1,#nametbl do
            if i == 1 then
                �ȴ����͵ķ�� = nametbl[i][1]..'|'..nametbl[i][2]..'|'..nametbl[i][3]
            else
                �ȴ����͵ķ�� = �ȴ����͵ķ��..'|'..nametbl[i][1]..'|'..nametbl[i][2]..'|'..nametbl[i][3]
            end
        end
    end

    Protocol.Send(player, "allnpc", �ȴ����͵ķ��)
    return 1
end


function getWarpModule:onUnload()
    self:logInfo('unload')
end

return getWarpModule
