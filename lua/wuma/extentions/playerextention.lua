
local ENT = FindMetaTable("Player")

if CLIENT then
	local exclude_limits = CreateConVar("wuma_exclude_limits", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Exclude wuma limits from normal gamemode limits")

	function ENT:GetCount(str)
		if exclude_limits:GetBool() then
			return self:GetNWInt("Count." .. str, 0) - self:GetNWInt("Count.TotalLimits." .. str, 0)
		else
			return self:GetNWInt("Count." .. str, 0)
		end
	end
	return
end

local function shouldIgnore(str, id)
	if not id then
		if (str == "props") or (str == "vehicles") or (str == "sents") or (str == "ragdolls") or (str == "npcs") or (str == "effects") then
			return true
		end
	end
	return false
end

function ENT:FindLimit(str, id)
	local id_limit = WUMA.Limits[self:SteamID()] and WUMA.Limits[self:SteamID()][id]
	local str_limit = WUMA.Limits[self:SteamID()] and WUMA.Limits[self:SteamID()][str]

	local usergroup = self:GetUserGroup()
	while usergroup do
		WUMA.Limits[usergroup] = WUMA.Limits[usergroup] or WUMA.ReadLimits(usergroup) or {}

		id_limit = id_limit or WUMA.Limits[usergroup][id]
		str_limit = str_limit or WUMA.Limits[usergroup][str]

		usergroup = WUMA.GetInheritsLimitsFrom(usergroup)
	end

	local next = id_limit or str_limit
	local last_non_exclusive = next
	while next and isstring(next:GetLimit()) do
		next = self:FindLimit(next:GetLimit())

		if next and not next:GetIsExclusive() then
			last_non_exclusive = next
		end
	end

	return id_limit or str_limit, last_non_exclusive, next
end

ENT.old_CheckLimit = ENT.old_CheckLimit or ENT.CheckLimit
function ENT:CheckLimit(str, id)
	if shouldIgnore(str, id) then return true end

	local limit, last_non_exclusive, last_exclusive = self:FindLimit(str, id)

	if limit and not last_non_exclusive:Check(self, last_exclusive:GetLimit()) then
		return false
	end

	return self:old_CheckLimit(str, id)
end

ENT.old_AddCount = ENT.old_AddCount or ENT.AddCount
function ENT:AddCount(str, ent, id)
	if shouldIgnore(str, id) then return end

	WUMADebug("AddCount(%s, %s, %s)", tostring(str) or "nil", tostring(ent) or "nil", tostring(id) or "nil")

	local limit, last_non_exclusive = self:FindLimit(str, id)

	if limit then
		if (last_non_exclusive:GetItem() ~= str) then
			local steamid = self:SteamID()
			WUMA.ChangeTotalLimits(steamid, str, 1)
			ent:CallOnRemove("WUMATotalLimitChange", function(_, steamid, str) WUMA.ChangeTotalLimits(steamid, str, -1) end, steamid, str)
		end

		last_non_exclusive:AddEntity(self, ent)
	end

	return self:old_AddCount(str, ent, id)
end

ENT.old_GetCount = ENT.old_GetCount or ENT.GetCount
function ENT:GetCount(str, minus, id)
	minus = minus or 0

	if not self:IsValid() then
		return
	end

	local totalLimit = WUMA.GetTotalLimits(self:SteamID(), str)

	local limit, last_non_exclusive = self:FindLimit(id or str)
	if id and limit and (limit:GetItem() == id) then
		return last_non_exclusive:GetCount(self)
	elseif limit and (limit:GetItem() == str) then
		return last_non_exclusive:GetCount(self) - totalLimit
	else
		return self:old_GetCount(str, minus) - totalLimit
	end
end

function ENT:LimitHit(string)
	self:SendLua(string.format([[WUMA.NotifyLimitHit("%s")]], string))
end

function ENT:RestrictionHit(type, item)
	if (type ~= "pickup") then
		if item then
			self:SendLua(string.format([[WUMA.NotifyRestriction("%s", "%s")]], type, item))
		else
			self:SendLua(string.format([[WUMA.NotifyTypeRestriction("%s")]], type))
		end
	end
end

local function isTypeRestricted(steamid, usergroup, type)
	local type_restricted = WUMA.Settings[steamid] and WUMA.Settings[steamid]["restrict_type_" .. type] and steamid
	local is_whitelist = WUMA.Settings[steamid] and WUMA.Settings[steamid]["iswhitelist_type_" .. type] and steamid

	local current = usergroup
	while current and (not type_restricted and not is_whitelist) do
		type_restricted = type_restricted or (WUMA.Settings[current] and WUMA.Settings[current]["restrict_type_" .. type] and current)
		is_whitelist = is_whitelist or (WUMA.Settings[current] and WUMA.Settings[current]["iswhitelist_type_" .. type] and current)

		current = WUMA.Inheritance["restrictions"] and WUMA.Inheritance["restrictions"][current]
	end

	return type_restricted, is_whitelist
end

function ENT:CheckRestriction(type, item)
	WUMADebug("CheckRestriction(%s, %s)", type, item)
	local usergroup = self:GetUserGroup()
	local steamid = self:SteamID()

	local key = type .. "_" .. item

	local type_restricted, is_whitelist = isTypeRestricted(steamid, usergroup, type)

	if type_restricted then
		return false, self:RestrictionHit(type)
	end

	local restriction = WUMA.Restrictions[steamid] and WUMA.Restrictions[steamid][key]

	local current = usergroup
	while not restriction and current do
		restriction = WUMA.Restrictions[current] and WUMA.Restrictions[current][key]
		current = WUMA.Inheritance["restrictions"] and WUMA.Inheritance["restrictions"][current]
	end

	if is_whitelist then
		if restriction then
			return true
		else
			return false, self:RestrictionHit(type, item)
		end
	elseif restriction then
		return restriction:Check(self), self:RestrictionHit(type, item)
	end
end

local old_Loadout = ENT.Loudout
function ENT:Loadout()
	local weapons = {}
	for _, weapon in pairs(self:GetWeapons()) do
		weapons[weapon:GetClass()] = 1
	end

	local result = old_Loadout(self)

	for _, weapon in pairs(self:GetWeapons()) do
		if not weapons[weapon:GetClass()] then
			weapon.SpawnedByDefault = true
		end
	end

	return result
end