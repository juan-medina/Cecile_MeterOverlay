----------------------------------------------------------------------------------------------------
-- meter module, manage the meters
--

--get the engine and create the module
local Engine = select(2,...);
local mod = Engine.AddOn:NewModule("meter");

--debug
local debug = Engine.AddOn:GetModule("debug")

--default toggle function do nothing
function mod.defaultToggle()
	return;
end

--default getMeterSumtable return empty values
function mod.defaultMeterGetSumtable()
	return {},0,0;
end

--default get segment name return empty
function mod.defaultGetMeterSegmentName()
	return "";
end

--event when we enter combat
function mod.InCombat()
	mod.combat = true;
	--set the boss name for the already seen boss (empty if none)
	mod.bossName = mod.NextCombatBoss;

	--hide out of combat
	mod.datatext.ControlVisibility();

end

--event when we exit combat
function mod.OutOfCombat()
	mod.combat = false;
	mod.NextCombatBoss = "";

	--hide out of combat
	mod.datatext.ControlVisibility();

	--ONLY FOR TESTING ENCOUNTER RECORDS
	--local encounters = Engine.AddOn:GetModule("encounters");
	--local encounterName = mod.getSegmentName(Engine.CURRENT_DATA);
	--encounters:recordEncounter(encounterName);

end

--event when we engage a boss
function mod.EngageBoss(...)
	--get the boss name and store it
	local victim = UnitName("boss1")

	--guard against secret values from UnitName during combat (12.0.0+)
	if issecretvalue and issecretvalue(victim) then
		victim = nil
	end

	if victim then

		--get the localized difficult name
		local name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID = GetInstanceInfo()

		if not difficultyName then
			difficultyName = ""
		end

		--if we are not in combat the next combat event will set the boss name, ifnot set it now
		if not mod.combat then
			mod.NextCombatBoss = victim.." - "..difficultyName
		else
			mod.NextCombatBoss = ""
			mod.bossName = victim.." - "..difficultyName
		end
	end

end

--get the segment name
function mod.getSegmentName(tablename)

	local result = ""

	--if get the current data, if not get the localize segment name
	if tablename == Engine.CURRENT_DATA then

		--if we have a boss name set it, if not return segment name
		--guard against secret values (12.0.0+): treat secret bossName as empty
		local bossName = mod.bossName
		if issecretvalue and issecretvalue(bossName) then
			bossName = nil
		end

		if bossName and bossName ~= "" then
			result = bossName
		else
			result = mod.getMeterSegmentName()
		end
		--if we do not have a segment name
		if result == "" then
			--return just the localized name
			result = Engine.ConvertDataSet[tablename]
		end

	else
		result = Engine.ConvertDataSet[tablename]
	end

	return result

end

--get the sum table, and perform sorting
function mod.getSumtable(dataset, mode, sortData, sortType)
	local sumtable, totalsum, totalpersec = mod.getMeterSumtable(dataset, mode);

	--sort the results
	if sortData then

		if mode == Engine.TYPE_DPS then

			if(sortType==Engine.SORT_PERSEC) then
				table.sort(sumtable, function(a,b) return a.dps > b.dps end);
			else
				table.sort(sumtable, function(a,b) return a.damage > b.damage end);
			end

		elseif mode == Engine.TYPE_HEAL then

			if(sortType==Engine.SORT_PERSEC) then
				table.sort(sumtable, function(a,b) return a.hps > b.hps end);
			else
				table.sort(sumtable, function(a,b) return a.healing > b.healing end);
			end
		end

	end

	--return the values
	return sumtable, totalsum, totalpersec;
end

--initialize module
function mod:OnInitialize()

	--store the datatext
	mod.datatext = Engine.AddOn:GetModule("datatext");

	--we do not have any meter so set defaults
	mod.desc = Engine.Locale["NO_DATA"];
	mod.toggle = mod.defaultToggle;
	mod.getMeterSumtable = mod.defaultMeterGetSumtable;
	mod.getMeterSegmentName = mod.defaultGetMeterSegmentName;
	mod.registered=false;

	--get player and non localized class for latter use
	mod.myname = GetUnitName("player");
	mod.localclass,mod.myclass = UnitClass("player");

	--this will store the values for the tags
	mod.values = {};

	--In/Out Combat & boss name
	mod.combat = false;
	mod.bossName = "";
	mod.NextCombatBoss = "";

	Engine.AddOn:RegisterEvent("PLAYER_REGEN_ENABLED",mod.OutOfCombat);
	Engine.AddOn:RegisterEvent("PLAYER_REGEN_DISABLED",mod.InCombat);
	Engine.AddOn:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT",mod.EngageBoss);

end

--set a value for the tags, we could set a var o a function and color
function mod:SetValue(name,value,color)

	mod.values[name] = {value = value, color = color};

end

--set a tag value using human readable format
function mod:SetNumberValue(name,value,color)

	mod:SetValue(name,mod:FormatNumber(value),color);

end

--set a tag value appending the ordinal of that number
function mod:SetOrdinalValue(name,value,color)
	if value == nil then value = 0 end
	mod:SetValue(name,tostring(value)..Engine:OrdinalSuffix(value),color);

end

--register a damage meter, if is not registered yet
function mod:RegisterMeter(desc,getSumtable,getSegmentName,toggle)

	if not(mod.registered) then

		mod.desc = desc;
		mod.toggle = toggle;
		mod.getMeterSumtable = getSumtable;
		mod.getMeterSegmentName = getSegmentName;

		--set the tag value for the meter name
		mod:SetValue("meter",mod.desc,Engine.CONFIG_COLOR_OTHER);

		--set the tag value for get the current segment name
		mod:SetValue("combat",function ()
				return mod.getSegmentName(Engine.Profile.segment)
			end,Engine.CONFIG_COLOR_OTHER);

		--set the tag value for get the current datatext
		mod:SetValue("dataset",function ()
				return Engine.ConvertDataSet[Engine.Profile.segment]
			end,Engine.CONFIG_COLOR_OTHER);

		--set the tag for player name, using his class color
		mod:SetValue("player",mod.myname,"|c".._G["RAID_CLASS_COLORS"][mod.myclass].colorStr );

		--we have a meter registered
		mod.registered = true;

		debug("Meter %s registered",desc);
	end

end

--return values per second using a table set and mode
function mod:ValuePerSecond(tablename, mode)

	--default values
	local value,persec,StatsTable,totalsum,totalpersec,mypos=0,0,nil,0,0,1;

	--get the table and totals, we do need sorting the table
	StatsTable,totalsum,totalpersec = mod.getSumtable(tablename, mode,true,Engine.SORT_RAW);

	--loop the table
	local numofcombatants = #StatsTable;

	for i = 1, numofcombatants do

		--check if we want the dps o hps data until we found our player data
		if StatsTable[i].name == mod.myname then
			if mode == Engine.TYPE_DPS then
				persec = StatsTable[i].formattedDps or StatsTable[i].dps;
				value  = StatsTable[i].formattedDamage or StatsTable[i].damage;
				mypos = i;
			else
				persec = StatsTable[i].formattedHps or StatsTable[i].hps;
				value  = StatsTable[i].formattedHealing or StatsTable[i].healing;
				mypos = i;
			end
			break;
		end

	end

	return totalsum,totalpersec,persec,value,mypos;
end

--return top player data using a table set and mode
function mod:GetTopPlayerData(tablename, mode)


	--default values
	local result = nil;

	--get the table and totals, we need sorting
	StatsTable,totalsum,totalpersec = mod.getSumtable(tablename, mode, true, Engine.SORT_RAW);

	--loop the table
	local numofcombatants = #StatsTable;

	if numofcombatants>0 then
		result = StatsTable[1];
	end


	return result;
end

--return the player data using a table set and mode
function mod:GetPlayerData(tablename,mode)

	--default values
	local result = nil;

	--get the table and totals, we don't need sorting the table
	StatsTable,totalsum,totalpersec = mod.getSumtable(tablename, mode, false);

	--loop the table
	local numofcombatants = #StatsTable;

	for i = 1, numofcombatants do

		--until we found our player data
		if StatsTable[i].name == mod.myname then
			result = StatsTable[i];
			break;
		end

	end

	return result;
end

-- Formats a number into human readable format
-- If value is already a string (pre-formatted by meter override), return it as-is
function mod:FormatNumber(number)
	if issecretvalue and issecretvalue(number) then
		local ok, text = pcall(tostring, number)
		if ok and text then return text end
		return "?"
	end
	if number then
		if type(number) == "string" then return number; end
		if number > 1000000 then
			return 	("%02.2fM"):format(number / 1000000);
		else
			if number > 1000 then
				return 	("%02.1fK"):format(number / 1000);
			else
				return tostring(math.floor(number));
			end
		end
	else
		return "0";
	end
end

--returna a color string for a giving color in rgba(floats)
function mod:getColorString(color)

	local result = string.format("|c%02X%02X%02X%02X",
		color.a and color.a*255 or 255,
		color.r*255,
		color.g*255,
		color.b*255)

	return result;
end

--return a configurable color
function mod:getConfigurableColor(name)

	local configValue = Engine.Profile.datatext.colors[name];

	local result = configValue and mod:getColorString(configValue) or name;

	return result

end

--parse a tage string returing a string with the values
function mod:PaseString(taged)

	--get the general color
	local generalColor = mod:getConfigurableColor(Engine.CONFIG_COLOR_GENERAL);

	--make a copy of the origina string
	local result = generalColor..taged;

	--temporal var
	local v,k,c;

	--find any [key] in a string
	for k in string.gmatch(taged, "%[%w+%]") do

		--default value
		v = "";
		--lowercase the key
		k = string.lower(k);

		--remove the brackets
		k = string.gsub(k,"%[","");
		k = string.gsub(k,"%]","");

		--check if we have a value for that key
		if(mod.values[k]) then

			--get the current value
			v = mod.values[k].value;

			--if is a function call to it
			if(type(v)=="function") then
				v = v();
			end

			--if has color, colorize it
			if mod.values[k].color then
				c = mod:getConfigurableColor(mod.values[k].color)
				v = FONT_COLOR_CODE_CLOSE..c..v..FONT_COLOR_CODE_CLOSE..generalColor;
			end

		end

		--replace the tag in the result string (ensure v is a string for gsub)
		k = "%["..k.."%]";
		local replacementValue = tostring(v or "")
		local ok, newResult = pcall(string.gsub, result, k, replacementValue)
		if ok then
			result = newResult
		end

	end

	result = result .. FONT_COLOR_CODE_CLOSE;

	--remove unwanted color strings
	result = string.gsub(result,generalColor..FONT_COLOR_CODE_CLOSE,"");
	result = string.gsub(result,generalColor.." "..FONT_COLOR_CODE_CLOSE," ");

	--return the new string
	return result;
end

--return a formated string for the selected table set
function mod:GetValues(tablename,taged)

	-- Pre-populate all tags with safe defaults FIRST so they always get replaced
	-- even if the meter data calls below error out
	mod:SetValue("dps", "0", Engine.CONFIG_COLOR_DAMAGE)
	mod:SetValue("rdps", "0", Engine.CONFIG_COLOR_DAMAGE)
	mod:SetValue("damage", "0", Engine.CONFIG_COLOR_DAMAGE)
	mod:SetValue("rdamage", "0", Engine.CONFIG_COLOR_DAMAGE)
	mod:SetValue("pdps", "0", Engine.CONFIG_COLOR_DAMAGE)
	mod:SetValue("ndps", "0", Engine.CONFIG_COLOR_DAMAGE)
	mod:SetValue("hps", "0", Engine.CONFIG_COLOR_HEALING)
	mod:SetValue("rhps", "0", Engine.CONFIG_COLOR_HEALING)
	mod:SetValue("healing", "0", Engine.CONFIG_COLOR_HEALING)
	mod:SetValue("rhealing", "0", Engine.CONFIG_COLOR_HEALING)
	mod:SetValue("pheal", "0", Engine.CONFIG_COLOR_HEALING)
	mod:SetValue("nhealer", "0", Engine.CONFIG_COLOR_HEALING)

	--get the values from the meter (protected — may fail with secret values during combat)
	local ok1, rdamage,rdps,dps,damage,ndps = pcall(mod.ValuePerSecond, mod, tablename, Engine.TYPE_DPS);
	if not ok1 then rdamage,rdps,dps,damage,ndps = 0,0,0,0,1 end
	local ok2, rhealing,rhps,hps,healing,nhps = pcall(mod.ValuePerSecond, mod, tablename, Engine.TYPE_HEAL);
	if not ok2 then rhealing,rhps,hps,healing,nhps = 0,0,0,0,1 end

	--calculate % dps (skip if values are pre-formatted strings from C_DamageMeter)
	local pdps = 100;
	if type(damage) == "number" and type(rdamage) == "number" and (rdamage~=0) then
		pdps = math.floor(1000*damage/rdamage)/10;
	end

	--calculate % heal (skip if values are pre-formatted strings from C_DamageMeter)
	local pheal = 100;
	if type(healing) == "number" and type(rhealing) == "number" and (rhealing~=0) then
		pheal = math.floor(1000*healing/rhealing)/10;
	end

	--set the tag values (protected - any single failure shouldn't prevent others)
	pcall(mod.SetNumberValue, mod, "dps", dps, Engine.CONFIG_COLOR_DAMAGE)
	pcall(mod.SetNumberValue, mod, "rdps", rdps, Engine.CONFIG_COLOR_DAMAGE)
	pcall(mod.SetNumberValue, mod, "damage", damage, Engine.CONFIG_COLOR_DAMAGE)
	pcall(mod.SetNumberValue, mod, "rdamage", rdamage, Engine.CONFIG_COLOR_DAMAGE)
	pcall(mod.SetNumberValue, mod, "pdps", pdps, Engine.CONFIG_COLOR_DAMAGE)
	pcall(mod.SetOrdinalValue, mod, "ndps", ndps, Engine.CONFIG_COLOR_DAMAGE)

	pcall(mod.SetNumberValue, mod, "hps", hps, Engine.CONFIG_COLOR_HEALING)
	pcall(mod.SetNumberValue, mod, "rhps", rhps, Engine.CONFIG_COLOR_HEALING)
	pcall(mod.SetNumberValue, mod, "healing", healing, Engine.CONFIG_COLOR_HEALING)
	pcall(mod.SetNumberValue, mod, "rhealing", rhealing, Engine.CONFIG_COLOR_HEALING)
	pcall(mod.SetNumberValue, mod, "pheal", pheal, Engine.CONFIG_COLOR_HEALING)
	pcall(mod.SetOrdinalValue, mod, "nhealer", nhps, Engine.CONFIG_COLOR_HEALING)

	--return the string
	return mod:PaseString(taged);
end