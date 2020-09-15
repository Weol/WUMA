
WUMA.Restrictions = WUMA.Restrictions or {}

local function insertRestriction(restriction)
	WUMASQL(
		[[REPLACE INTO `WUMARestrictions` (`type`, `parent`, `item`, `is_anti`) VALUES ("%s", "%s", "%s", %s);]],
		restriction:GetType(),
		restriction:GetParent(),
		restriction:GetItem(),
		restriction:GetIsAnti() or "NULL"
	)
end

local function deleteRestriction(parent, type, item)
	WUMASQL(
		[[DELETE FROM `WUMARestrictions` WHERE `type` == "%s" AND `parent` == "%s" and `item` == "%s"]],
		type,
		parent,
		item
	)
end

function WUMA.AddRestriction(caller, parent, type, item, is_anti, scope)
	local preprocessor = WUMA.RestrictionTypes[type]:GetPreProcessor()
	if preprocessor then
		item = preprocessor(item)
	end

	local restriction = Restriction:New{type=type, item=item, parent=parent, is_anti=is_anti, scope=scope}

	if WUMA.Restrictions[parent] or player.GetBySteamID(parent) or WUMA.IsUsergroupConnected(parent) then
		WUMA.Restrictions[parent] = WUMA.Restrictions[parent] or {}
		WUMA.Restrictions[parent][type .. "_" .. item] = restriction
	end

	insertRestriction(restriction)

	hook.Call("WUMAOnRestrictionAdded", nil, caller, restriction)
end

function WUMA.RemoveRestriction(caller, parent, type, item)
	local preprocessor = WUMA.RestrictionTypes[type]:GetPreProcessor()
	if preprocessor then
		item = preprocessor(item)
	end

	if WUMA.Restrictions[parent] then
		WUMA.Restrictions[parent][type .. "_" .. item] = nil
		if table.IsEmpty(WUMA.Restrictions[parent]) then
			WUMA.Restrictions[parent] = nil
		end
	end

	deleteRestriction(parent, type, item)

	hook.Call("WUMAOnRestrictionRemoved", nil, caller, parent, type, item)
end

function WUMA.SetTypeRestriction(caller, parent, restriction_type, restrict)
	local key = "restrict_type_" .. restriction_type

	WUMA.SetSetting(parent, key, restrict)

	if restrict then
		hook.Call("WUMAOnTypeRestricted", nil, caller, parent, restriction_type)
	else
		hook.Call("WUMAOnTypeUnrestricted", nil, caller, parent, restriction_type)
	end
end

function WUMA.SetTypeIsWhitelist(caller, parent, restriction_type, iswhitelist)
	local key = "iswhitelist_type_" .. restriction_type

	WUMA.SetSetting(parent, key, iswhitelist)

	if iswhitelist then
		hook.Call("WUMATypeIsWhitelist", nil, caller, parent, restriction_type)
	else
		hook.Call("WUMATypeIsNotWhitelist", nil, caller, parent, restriction_type)
	end
end

function WUMA.ReadRestrictions(parent)
	local restrictions = WUMASQL([[SELECT * FROM `WUMARestrictions` WHERE `parent` == "%s"]], parent)
	if restrictions then
		local preprocessed = {}
		for _, args in pairs(restrictions) do
			args.is_anti = (args.is_anti ~= "NULL") and tobool(args.is_anti)
			local restriction = Restriction:New(args)
			preprocessed[restriction:GetType() .. "_" .. restriction:GetItem()] = restriction
		end
		return preprocessed
	end
end

local function userDisconnected(user)
	WUMA.Restrictions[user:SteamID()] = nil

	if not WUMA.IsUsergroupConnected(user:GetUserGroup()) then
		WUMA.Restrictions[user:GetUserGroup()] = nil
	end
end
hook.Add("PlayerDisconnected", "WUMA_RESTRICTIONS_PlayerDisconnected", userDisconnected)

local function playerInitialSpawn(player)
	if not WUMA.Restrictions[player:GetUserGroup()] then
		WUMA.Restrictions[player:GetUserGroup()] = WUMA.ReadRestrictions(player:GetUserGroup()) or {}
	end

	if not WUMA.Restrictions[player:SteamID()] then
		WUMA.Restrictions[player:SteamID()] = WUMA.ReadRestrictions(player:SteamID())
	end
end
hook.Add("PlayerInitialSpawn", "WUMA_RESTRICTIONS_PlayerInitialSpawn", playerInitialSpawn)