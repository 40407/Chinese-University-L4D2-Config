#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <left4dhooks>
#include <l4d2lib>
#include <l4d2util_stocks>
#undef REQUIRE_PLUGIN
#include <readyup>
#define TEAM_SURVIVOR   2

new Handle: hTeamSize;
new Handle: hSurvivalBonusCvar;
new         iSurvivalBonusDefault;
new Handle: hTieBreakBonusCvar;
new         iTieBreakBonusDefault;
new Handle: hMaxDamageCvar;
new         iHealth[MAXPLAYERS + 1];
new         bTookDamage[MAXPLAYERS + 1];
new         iTotalDamage[2];
new bool:   bHasWiped[2];                   // true if they didn't get the bonus...
new bool:   bRoundOver[2];                  // whether the bonus will still change or not
new         iStoreBonus[2];                 // what was the actual bonus?
new         iStoreSurvivors[2];             // how many survived that round?
new bool:   readyUpIsAvailable;
new         iMapDistance;
new         iTeamSize;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("DamageBonus_GetCurrentBonus", Native_GetCurrentBonus);
	CreateNative("DamageBonus_GetRoundBonus", Native_GetRoundBonus);
	CreateNative("DamageBonus_GetRoundDamage", Native_GetRoundDamage);
	RegPluginLibrary("l4d2_damagebonus");

	MarkNativeAsOptional("IsInReady");
	return APLRes_Success;
}

public OnPluginStart()
{
	HookEvent("door_close", DoorClose_Event);
	HookEvent("player_death", PlayerDeath_Event);
	HookEvent("finale_vehicle_leaving", FinaleVehicleLeaving_Event, EventHookMode_PostNoCopy);
	HookEvent("player_ledge_grab", PlayerLedgeGrab_Event);
	HookEvent("round_end", RoundEnd_Event);
	HookEvent("player_incapacitated", OnPlayerIncapped);

	hSurvivalBonusCvar = FindConVar("vs_survival_bonus");
	iSurvivalBonusDefault = GetConVarInt(hSurvivalBonusCvar);
	hTieBreakBonusCvar = FindConVar("vs_tiebreak_bonus");
	iTieBreakBonusDefault = GetConVarInt(hTieBreakBonusCvar);
	hTeamSize = FindConVar("survivor_limit");
	hMaxDamageCvar = CreateConVar("sm_max_damage", "540.0");
	
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");

	RegConsoleCmd("sm_damage", Damage_Cmd);
	RegConsoleCmd("sm_health", Damage_Cmd);
}

public OnPluginEnd()
{
	SetConVarInt(hSurvivalBonusCvar, iSurvivalBonusDefault);
	SetConVarInt(hTieBreakBonusCvar, iTieBreakBonusDefault);
}

public OnAllPluginsLoaded()
{
	readyUpIsAvailable = LibraryExists("readyup");
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "readyup")) readyUpIsAvailable = false;
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "readyup")) readyUpIsAvailable = true;
}

public Native_GetCurrentBonus(Handle:plugin, numParams)
{
	return CalculateSurvivalBonus() * GetAliveSurvivors();
}

public Native_GetRoundBonus(Handle:plugin, numParams)
{
	return iStoreBonus[GetNativeCell(1)];
}

public Native_GetRoundDamage(Handle:plugin, numParams)
{
	return iTotalDamage[GetNativeCell(1)];
}

public OnMapStart()
{
	for (new i = 0; i < 2; i++)
	{
		iTotalDamage[i] = 0;
		iStoreBonus[i] = 0;
		iStoreSurvivors[i] = 0;
		bRoundOver[i] = false;
		bHasWiped[i] = false;
	}
	iTeamSize = GetConVarInt(FindConVar("survivor_limit"));
    iMapDistance = L4D2_GetMapValueInt("max_distance", L4D_GetVersusMaxCompletionScore());
    L4D_SetVersusMaxCompletionScore(iMapDistance);
	SetConVarInt(hTieBreakBonusCvar, 0);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public Action:Damage_Cmd(client, args)
{
	DisplayBonus(client);
	return Plugin_Handled;
}

public RoundEnd_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetUprightSurvivors()) 
		bHasWiped[GameRules_GetProp("m_bInSecondHalfOfRound")] = true;

	bRoundOver[GameRules_GetProp("m_bInSecondHalfOfRound")] = true;

	new reason = GetEventInt(event, "reason");
	if (reason == 5)
	{
		DisplayBonus();
		if (readyUpIsAvailable && bRoundOver[0] && !GameRules_GetProp("m_bInSecondHalfOfRound"))
		{
			decl String:readyMsgBuff[65];
			if (bHasWiped[0])
				FormatEx(readyMsgBuff, sizeof(readyMsgBuff), "R#1: Wiped (%d DMG)", iTotalDamage[0]);
			else
				FormatEx(readyMsgBuff, sizeof(readyMsgBuff), "R#1: %d (%d DMG)", iStoreBonus[0], iTotalDamage[0]);
		}
	}
}

public DoorClose_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetEventBool(event, "checkpoint"))
	{
		SetConVarInt(hSurvivalBonusCvar, CalculateSurvivalBonus());
		StoreBonus();
	}
}

public PlayerDeath_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client && IsSurvivor(client))
	{
		SetConVarInt(hSurvivalBonusCvar, CalculateSurvivalBonus());
		StoreBonus();
	}
}

public FinaleVehicleLeaving_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsSurvivor(i) && IsPlayerIncap(i))
			ForcePlayerSuicide(i);
	}
	SetConVarInt(hSurvivalBonusCvar, CalculateSurvivalBonus());
	StoreBonus();
}

public OnTakeDamage(victim, attacker, inflictor, Float:damage, damagetype)
{
	iHealth[victim] = (!IsSurvivor(victim) || IsPlayerIncap(victim)) ? 0 : (GetSurvivorPermanentHealth(victim) + GetSurvivorTempHealth(victim));
	bTookDamage[victim] = true;
}

public PlayerLedgeGrab_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new health = L4D2Direct_GetPreIncapHealth(client);
	new temphealth = L4D2Direct_GetPreIncapHealthBuffer(client);
	iTotalDamage[GameRules_GetProp("m_bInSecondHalfOfRound")] += health + temphealth;
}

public void L4D2_OnRevived(client)
{
	new health = GetSurvivorPermanentHealth(client);
	new temphealth = GetSurvivorTempHealth(client);
	iTotalDamage[GameRules_GetProp("m_bInSecondHalfOfRound")] -= (health + temphealth);
}

public OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype)
{
	if (iHealth[victim])
	{
		if (!IsPlayerAlive(victim) || (IsPlayerIncap(victim) && !IsPlayerHanging(victim)))
			iTotalDamage[GameRules_GetProp("m_bInSecondHalfOfRound")] += iHealth[victim];
		else if (!IsPlayerHanging(victim))
			iTotalDamage[GameRules_GetProp("m_bInSecondHalfOfRound")] += iHealth[victim] - (GetSurvivorPermanentHealth(victim) + GetSurvivorTempHealth(victim));
		iHealth[victim] = (!IsSurvivor(victim) || IsPlayerIncap(victim)) ? 0 : (GetSurvivorPermanentHealth(victim) + GetSurvivorTempHealth(victim));
	}
}

public Action:Command_Say(client, const String:command[], args)
{
	if (IsChatTrigger())
	{
		decl String:sMessage[MAX_NAME_LENGTH];
		GetCmdArg(1, sMessage, sizeof(sMessage));
		if (StrEqual(sMessage, "!damage")) return Plugin_Handled;
		else if (StrEqual (sMessage, "!sm_damage")) return Plugin_Handled;
		else if (StrEqual (sMessage, "!health")) return Plugin_Handled;
		else if (StrEqual (sMessage, "!sm_health")) return Plugin_Handled;
	}
	return Plugin_Continue;
}

stock GetDamage(round=-1)
{
	return (round == -1) ? iTotalDamage[GameRules_GetProp("m_bInSecondHalfOfRound")] : iTotalDamage[round];
}

stock StoreBonus()
{
	new round = GameRules_GetProp("m_bInSecondHalfOfRound");
	new aliveSurvs = GetAliveSurvivors();
	iStoreBonus[round] = GetConVarInt(hSurvivalBonusCvar) * aliveSurvs;
	iStoreSurvivors[round] = GetAliveSurvivors();
}

stock DisplayBonus(client=-1)
{
	decl String:msgPartHdr[128];
	decl String:msgPartDmg[128];
	for (new round = 0; round <= GameRules_GetProp("m_bInSecondHalfOfRound"); round++)
	{
		if (bRoundOver[round])
			FormatEx(msgPartHdr, sizeof(msgPartHdr), "R#\x05%i\x01 Bonus", round+1);
		else
			FormatEx(msgPartHdr, sizeof(msgPartHdr), "Current Bonus");
		if (bHasWiped[round])
			FormatEx(msgPartDmg, sizeof(msgPartDmg), "\x03Wiped\x01 (\x05%d\x01 DMG)", iTotalDamage[round]);
		else
		{
		    if (bRoundOver[round])
			FormatEx(msgPartDmg, sizeof(msgPartDmg), "\x04%d\x01 (\x05%d\x01 DMG) ", 
			iStoreBonus[round],
			iTotalDamage[round]
			);

			else
			FormatEx(msgPartDmg, sizeof(msgPartDmg), "\x04%d\x01 (\x05%d\x01 DMG) [ DB: \x05%d\x01 | MB: \x05%d\x01 | PB: \x05%d\x01 ]", 
			CalculateSurvivalBonus() * GetAliveSurvivors(),
			iTotalDamage[round],
			RoundToFloor(CalculateSurvivalBonus() * GetAliveSurvivors() - GetSurvivorMedBonus() - GetSurvivorPillBonus()),
			RoundToFloor(GetSurvivorMedBonus()), 
			RoundToFloor(GetSurvivorPillBonus())
			);
		}
		if (client == -1)
		{
			PrintToChatAll("Map Distance: \x05%d\x01", L4D_GetVersusMaxCompletionScore());
			PrintToChatAll("\x01%s: %s", msgPartHdr, msgPartDmg);
		}
		else if (client)
		{
			PrintToChat(client, "Map Distance: \x05%d\x01", L4D_GetVersusMaxCompletionScore());
			PrintToChat(client, "\x01%s: %s", msgPartHdr, msgPartDmg);
		}
		else
		{
			PrintToServer("Map Distance: \x05%d\x01", L4D_GetVersusMaxCompletionScore());
			PrintToServer("\x01%s: %s", msgPartHdr, msgPartDmg);
		}
	}
}

stock bool:IsPlayerIncap(client) return bool:GetEntProp(client, Prop_Send, "m_isIncapacitated");
stock bool:IsPlayerHanging(client) return bool:GetEntProp(client, Prop_Send, "m_isHangingFromLedge");
stock bool:IsPlayerLedgedAtAll(client) return bool:(GetEntProp(client, Prop_Send, "m_isHangingFromLedge") | GetEntProp(client, Prop_Send, "m_isFallingFromLedge"));
stock GetSurvivorPermanentHealth(client) return GetEntProp(client, Prop_Send, "m_iHealth");
stock bool:IsClientAndInGame(index) return (index > 0 && index <= MaxClients && IsClientInGame(index));

stock GetSurvivorTempHealth(client)
{
	new temphp = RoundToCeil(GetEntPropFloat(client, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * GetConVarFloat(FindConVar("pain_pills_decay_rate")))) - 1;
	return (temphp > 0 ? temphp : 0);
}

stock CalculateSurvivalBonus()
{
   if(GetDamage() < 540)
	  return RoundToFloor((GetConVarFloat(hMaxDamageCvar) - GetDamage()) * iMapDistance / 1200 + (GetSurvivorPillBonus() + GetSurvivorMedBonus()) / GetAliveSurvivors());
   else
      return RoundToFloor((GetSurvivorPillBonus() + GetSurvivorMedBonus()) / GetAliveSurvivors());
}

stock GetAliveSurvivors()
{
	new iAliveCount;
	new iSurvivorCount;
	new maxSurvs = (hTeamSize != INVALID_HANDLE) ? GetConVarInt(hTeamSize) : 4;
	for (new i = 1; i <= MaxClients && iSurvivorCount < maxSurvs; i++)
	{
		if (IsSurvivor(i))
		{
			iSurvivorCount++;
			if (IsPlayerAlive(i)) iAliveCount++;
		}
	}
	return iAliveCount;
}

stock GetUprightSurvivors()
{
	new iAliveCount;
	new iSurvivorCount;
	new maxSurvs = (hTeamSize != INVALID_HANDLE) ? GetConVarInt(hTeamSize) : 4;
	for (new i = 1; i <= MaxClients && iSurvivorCount < maxSurvs; i++)
	{
		if (IsSurvivor(i))
		{
			iSurvivorCount++;
			if (IsPlayerAlive(i) && !IsPlayerIncap(i) && !IsPlayerLedgedAtAll(i))
				iAliveCount++;
		}
	}
	return iAliveCount;
}

stock bool:IsSurvivor(client)
{
	return IsClientAndInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR;
}

Float:GetSurvivorPillBonus()
{			
	new Float:pillsBonus = 0.0;
	new survivorCount;
	for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
	{
		if (IsSurvivor(i))
		{
			survivorCount++;
			if (IsPlayerAlive(i) && !IsPlayerIncap(i) && HasPills(i))
				pillsBonus += iMapDistance / 20.0;
		}
	}
	return pillsBonus;
}

Float:GetSurvivorMedBonus()
{			
	new Float:medsBonus = 0.0;
	new survivorCount;
	for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
	{
		if (IsSurvivor(i))
		{
			survivorCount++;
			if (IsPlayerAlive(i) && !IsPlayerIncap(i) && HasMeds(i))
				medsBonus += iMapDistance / 10.0;
		}
	}
	return medsBonus;
}

stock bool:HasPills(client)
{
	new item = GetPlayerWeaponSlot(client, 4);
	if (IsValidEdict(item))
	{
		decl String:buffer[64];
		GetEdictClassname(item, buffer, sizeof(buffer));
		return StrEqual(buffer, "weapon_pain_pills");
	}
	return false;
}

stock bool:HasMeds(client)
{
	new item = GetPlayerWeaponSlot(client, 3);
	if (IsValidEdict(item))
	{
		decl String:buffer[64];
		GetEdictClassname(item, buffer, sizeof(buffer));
		return StrEqual(buffer, "weapon_first_aid_kit");
	}
	return false;
}

void OnPlayerIncapped(Handle:event, const String:name[], bool:dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsSurvivor(victim))
	    iTotalDamage[GameRules_GetProp("m_bInSecondHalfOfRound")] += 54;
}