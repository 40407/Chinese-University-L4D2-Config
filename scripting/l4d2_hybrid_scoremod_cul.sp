#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <left4dhooks>
#include <sdktools>
#include <l4d2lib>
#include <l4d2util_stocks>

#define PLUGIN_TAG "" 

#define SM2_DEBUG    0

new Handle:hCvarBonusPerSurvivorMultiplier;
new Handle:hCvarPermanentHealthProportion;
new Handle:hCvarPillsHpFactor;
new Handle:hCvarPillsMaxBonus;

new Handle:hCvarValveSurvivalBonus;
new Handle:hCvarValveTieBreaker;

new Float:fMapBonus;
new Float:fMapHealthBonus;
new Float:fMapDamageBonus;
new Float:fMapTempHealthBonus;
new Float:fPermHpWorth;
new Float:fTempHpWorth;
new Float:fSurvivorBonus[2];
new Float:fMedMultiply;
new iMapDistance;
new iTeamSize;
new iPillWorth;
new iLostTempHealth[2];
new iTempHealth[MAXPLAYERS + 1];
new iSiDamage[2];
new Float:Penalty = 0.0;
new String:sSurvivorState[2][32];

new bool:bLateLoad;
new bool:bRoundOver;
new bool:bTiebreakerEligibility[2];

public APLRes:AskPluginLoad2(Handle:plugin, bool:late, String:error[], errMax)
{
    CreateNative("SMPlus_GetHealthBonus", Native_GetHealthBonus);
    CreateNative("SMPlus_GetDamageBonus", Native_GetDamageBonus);
    CreateNative("SMPlus_GetPillsBonus", Native_GetPillsBonus);
	CreateNative("SMPlus_GetMedBonus", Native_GetMedBonus);
    CreateNative("SMPlus_GetMaxHealthBonus", Native_GetMaxHealthBonus);
    CreateNative("SMPlus_GetMaxDamageBonus", Native_GetMaxDamageBonus);
    CreateNative("SMPlus_GetMaxPillsBonus", Native_GetMaxPillsBonus);
	CreateNative("SMPlus_GetMaxMedBonus", Native_GetMaxMedBonus);
    RegPluginLibrary("l4d2_hybrid_scoremod");
    bLateLoad = late;
    return APLRes_Success;
}

public OnPluginStart()
{
	hCvarBonusPerSurvivorMultiplier = CreateConVar("sm2_bonus_per_survivor_multiplier", "0.5", "Total Survivor Bonus = this * Number of Survivors * Map Distance");
	hCvarPermanentHealthProportion = CreateConVar("sm2_permament_health_proportion", "0.375", "Permanent Health Bonus = this * Map Bonus; rest goes for Temporary Health Bonus");
	hCvarPillsHpFactor = CreateConVar("sm2_pills_hp_factor", "6.0", "Unused pills HP worth = map bonus HP value / this");
	hCvarPillsMaxBonus = CreateConVar("sm2_pills_max_bonus", "30", "Unused pills cannot be worth more than this");
	
	hCvarValveSurvivalBonus = FindConVar("vs_survival_bonus");
	hCvarValveTieBreaker = FindConVar("vs_tiebreak_bonus");

	HookConVarChange(hCvarBonusPerSurvivorMultiplier, CvarChanged);
	HookConVarChange(hCvarPermanentHealthProportion, CvarChanged);

	HookEvent("round_start", RoundStartEvent, EventHookMode_PostNoCopy);
	HookEvent("player_ledge_grab", OnPlayerLedgeGrab);
	HookEvent("player_incapacitated", OnPlayerIncapped);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("revive_success", OnPlayerRevived, EventHookMode_Post);
	HookEvent("player_death", OnPlayerDeath);

	RegConsoleCmd("sm_health", CmdBonus);
	RegConsoleCmd("sm_damage", CmdBonus);
	RegConsoleCmd("sm_bonus", CmdBonus);
	RegConsoleCmd("sm_mapinfo", CmdMapInfo);

	if (bLateLoad) 
	{
		for (new i = 1; i <= MaxClients; i++) 
		{
			if (!IsClientInGame(i))
				continue;

			OnClientPutInServer(i);
		}
	}
}

public OnPluginEnd()
{
	ResetConVar(hCvarValveSurvivalBonus);
	ResetConVar(hCvarValveTieBreaker);
}

public OnConfigsExecuted()
{
	iTeamSize = GetConVarInt(FindConVar("survivor_limit"));
	SetConVarInt(hCvarValveTieBreaker, 0);

	iMapDistance = L4D2_GetMapValueInt("max_distance", L4D_GetVersusMaxCompletionScore());
	L4D_SetVersusMaxCompletionScore(iMapDistance);

	new Float:fPermHealthProportion = GetConVarFloat(hCvarPermanentHealthProportion);
	new Float:fTempHealthProportion = 1.0 - fPermHealthProportion;
	fMapBonus = iMapDistance * (GetConVarFloat(hCvarBonusPerSurvivorMultiplier) * iTeamSize);
	  fMapHealthBonus = fMapBonus * 0.5;
	  fMapDamageBonus = 0.0;
	fMapTempHealthBonus = iTeamSize * 100/* HP */ / fPermHealthProportion * fTempHealthProportion;
	fPermHpWorth = fMapHealthBonus / iTeamSize / 100;
	fTempHpWorth = fMapBonus * fTempHealthProportion / fMapTempHealthBonus; // this should be almost equal to the perm hp worth, but for accuracy we'll keep it separate
	iPillWorth = 0;
#if SM2_DEBUG
	PrintToChatAll("\x01Map health bonus: \x05%.1f\x01, temp health bonus: \x05%.1f\x01, perm hp worth: \x03%.1f\x01, temp hp worth: \x03%.1f\x01, pill worth: \x03%i\x01", fMapBonus, fMapTempHealthBonus, fPermHpWorth, fTempHpWorth, iPillWorth);
#endif
}

public OnMapStart()
{
	OnConfigsExecuted();

	iLostTempHealth[0] = 0;
	iLostTempHealth[1] = 0;
	iSiDamage[0] = 0;
	iSiDamage[1] = 0;
	bTiebreakerEligibility[0] = false;
	bTiebreakerEligibility[1] = false;
}

public CvarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	OnConfigsExecuted();
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

public void RoundStartEvent(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	for (new i = 0; i <= MAXPLAYERS; i++)
	{
		iTempHealth[i] = 0;
		Penalty = 0.0;
	}
	bRoundOver = false;
}

public Native_GetHealthBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorHealthBonus());
}
 
public Native_GetMaxHealthBonus(Handle:plugin, numParams)
{
    return RoundToFloor(fMapHealthBonus);
}
 
public Native_GetDamageBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorDamageBonus());
}
 
public Native_GetMaxDamageBonus(Handle:plugin, numParams)
{
    return RoundToFloor(fMapDamageBonus);
}
 
public Native_GetPillsBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorPillBonus());
}

 public Native_GetMedBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetFirstAidKitBonus());
}

public Native_GetMaxPillsBonus(Handle:plugin, numParams)
{
    return iPillWorth * iTeamSize;
}

public Native_GetMaxMedBonus(Handle:plugin, numParams)
{
    return (fMapHealthBonus * 0.8);
}

Float:GetGrenadeBonus()
{
    new Float:fGrenadeBonus = 0.0;
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsSurvivor(i) && IsPlayerAlive(i) && HasGrenade(i))
        {
            fGrenadeBonus += 0.0; 
        }
    }
    return fGrenadeBonus;
}
public Action:CmdBonus(client, args)
{
     if (bRoundOver || !client)
        return Plugin_Handled;

    decl String:sCmdType[64];
    GetCmdArg(1, sCmdType, sizeof(sCmdType));

    new Float:fHealthBonus = GetSurvivorHealthBonus();
    new Float:fPillsBonus = GetSurvivorPillBonus();
    new Float:fMaxPillsBonus = float(iPillWorth * iTeamSize);
    new Float:fGrenadeBonus = GetGrenadeBonus();
	new Float:fFirstAidKitBonus = GetFirstAidKitBonus(); 

	new Float:aliveSurvivors = GetUprightSurvivors() * 1.0;
    new Float:deathPenaltyMultiplier;
	new Float:deathPenalty = 0.0;
    if (aliveSurvivors < iTeamSize) 
    {
        deathPenaltyMultiplier = iTeamSize - aliveSurvivors;
        deathPenalty = deathPenaltyMultiplier * fMapHealthBonus/iTeamSize; 
    }

    if (StrEqual(sCmdType, "full"))
    {
        PrintToChat(client, "%s\x01R\x04#%i\x01 Bonus: \x05%d\x01 [HB: \x05%d\x01 | MB: \x05%.0f\x01 | DP: -\x05%.0f\x01]",
            PLUGIN_TAG, InSecondHalfOfRound() + 1, RoundToFloor(fHealthBonus + fFirstAidKitBonus),
            RoundToFloor(fHealthBonus), fFirstAidKitBonus, deathPenalty);
    }
    else if (StrEqual(sCmdType, "lite"))
    {
        // 移除百分比显示
        PrintToChat(client, "%s\x01R\x04#%i\x01 Bonus: \x05%d\x01", PLUGIN_TAG, InSecondHalfOfRound() + 1, RoundToFloor(fHealthBonus + fFirstAidKitBonus));
    }
    else
    {

     PrintToChat(client, "%s\x01R\x04#%i\x01 Bonus: \x05%d\x01 [HB: \x03%.0f\x01 | MB: \x03%.0f\x01 | DP: -\x05%.0f\x01]",
            PLUGIN_TAG, InSecondHalfOfRound() + 1, RoundToFloor(fHealthBonus + fFirstAidKitBonus),
            fHealthBonus, fFirstAidKitBonus, deathPenalty);
    }
    return Plugin_Handled;
}

public Action:CmdMapInfo(client, args)
{
	//new Float:fMaxPillsBonus = float(iPillWorth * iTeamSize);
	new Float:fTotalBonus = iMapDistance * 1.8;
	PrintToChat(client, "\x01[\x04Hybrid Bonus\x01 :: \x03%iv%i\x01] Map Info", iTeamSize, iTeamSize);
	PrintToChat(client, "\x01 Distance: \x05%d\x01", iMapDistance);
	PrintToChat(client, "\x01 Total Bonus: \x05%d\x01 ", RoundToFloor(fTotalBonus));
	PrintToChat(client, "\x01 Health Bonus: \x05%d\x01 ", RoundToFloor(fMapHealthBonus));
	//PrintToChat(client, "\x01 Damage Bonus: \x05%d\x01 ", RoundToFloor(fMapDamageBonus));
	PrintToChat(client, "\x01 Medkit Bonus: \x05%d\x01 ", RoundToFloor(fMapHealthBonus * 0.8));
	//PrintToChat(client, "\x01 Tiebreaker: \x05%d\x01", fMapHealthBonus/iTeamSize * 0.8);
	// [ScoreMod 2 :: 4v4] Map Info
	// Distance: 400
	// Bonus: 920 <100.0%>
	// Health Bonus: 600 <65.2%>
	// Damage Bonus: 200 <21.7%>
	// Pills Bonus: 30(max 120) <13.1%>
	// Tiebreaker: 30
	return Plugin_Handled;
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if (!IsSurvivor(victim) || IsPlayerIncap(victim)) return Plugin_Continue;

#if SM2_DEBUG
	if (GetSurvivorTemporaryHealth(victim) > 0) PrintToChatAll("\x04%N\x01 has \x05%d\x01 temp HP now(damage: \x03%.1f\x01)", victim, GetSurvivorTemporaryHealth(victim), damage);
#endif
	iTempHealth[victim] = GetSurvivorTemporaryHealth(victim);
	
	// Small failsafe/workaround for stuff that inflicts more than 100 HP damage (like tank hittables); we don't want to reward that more than it's worth
	if (!IsAnyInfected(attacker)) iSiDamage[InSecondHalfOfRound()] += (damage <= 100.0 ? RoundFloat(damage) : 100);
	
	return Plugin_Continue;
}

public OnPlayerLedgeGrab(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	iLostTempHealth[InSecondHalfOfRound()] += L4D2Direct_GetPreIncapHealthBuffer(client);
}

public OnPlayerIncapped(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsSurvivor(client))
	{
		iLostTempHealth[InSecondHalfOfRound()] += RoundToFloor((fMapDamageBonus / 100.0) * 5.0 / fTempHpWorth);
	} 
}

public void OnPlayerRevived(Handle:event, const String:name[], bool:dontBroadcast)
{
	bool bLedge = GetEventBool(event, "ledge_hang");
	if (!bLedge) {
		return;
	}
	
	int client = GetClientOfUserId(GetEventInt(event, "subject"));
	if (!IsSurvivor(client)) {
		return;
	}
	
	RequestFrame(Revival, client);
}

public void Revival(int client)
{
	iLostTempHealth[InSecondHalfOfRound()] -= GetSurvivorTemporaryHealth(client);
}

public Action:OnPlayerHurt(Handle:event, const String:name[], bool:dontBroadcast) 
{
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new damage = GetEventInt(event, "dmg_health");
	new damagetype = GetEventInt(event, "type");

	new fFakeDamage = damage;

	// Victim has to be a Survivor.
	// Attacker has to be a Survivor.
	// Player can't be Incapped.
	// Damage has to be from manipulated Shotgun FF. (Plasma)
	// Damage has to be higher than the Survivor's permanent health.
	if (!IsSurvivor(victim) || !IsSurvivor(attacker) || IsPlayerIncap(victim) || damagetype != DMG_PLASMA || fFakeDamage < GetSurvivorPermanentHealth(victim)) return Plugin_Continue;

	iTempHealth[victim] = GetSurvivorTemporaryHealth(victim);
	if (fFakeDamage > iTempHealth[victim]) fFakeDamage = iTempHealth[victim];

	iLostTempHealth[InSecondHalfOfRound()] += fFakeDamage;
	iTempHealth[victim] = GetSurvivorTemporaryHealth(victim) - fFakeDamage;

	return Plugin_Continue;
}

public OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype)
{
    // 移除所有与iLostTempHealth相关的代码
}
// Compatibility with Alternate Damage Mechanics plugin
// This plugin(i.e. Scoremod2) will work ideally fine with or without the aforementioned plugin
public L4D2_ADM_OnTemporaryHealthSubtracted(client, oldHealth, newHealth)
{
    // 留空或者删除这个函数，根据你的需要
}
public Action:L4D2_OnEndVersusModeRound(bool:countSurvivors)
{
#if SM2_DEBUG
    PrintToChatAll("CDirector::OnEndVersusModeRound() called. InSecondHalfOfRound(): %d, countSurvivors: %d", InSecondHalfOfRound(), countSurvivors);
#endif
    if (bRoundOver)
        return Plugin_Continue;

    new team = InSecondHalfOfRound();
    new iSurvivalMultiplier = GetUprightSurvivors();
    fSurvivorBonus[team] = GetSurvivorHealthBonus();

	new Float:fGrenadeBonus = 0.0;
    new bool:bHasGrenade[MAXPLAYERS + 1]; // 用于记录每个玩家是否持有投掷物
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsSurvivor(i) && IsPlayerAlive(i) && !IsPlayerIncap(i))
        {
            // 检查玩家是否持有投掷物，并且每人只计算一次
            if (!bHasGrenade[i] && HasGrenade(i))
            {
                fGrenadeBonus += 0.0; 
                bHasGrenade[i] = true; 
            }
        }
    }

    // 将投掷物分数加到团队奖励中
    fSurvivorBonus[team] += fGrenadeBonus;
	    // 重置医疗包分数和标记数组
   new Float: fFirstAidKitBonus = 0.0;
   new bool:bHasFirstAidKit[MAXPLAYERS + 1];

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsSurvivor(i) && IsPlayerAlive(i) && !IsPlayerIncap(i))
        {
            if (!bHasFirstAidKit[i] && HasFirstAidKit(i))
            {
			//fMedMultiply = (1.0 - 0.5)/iTeamSize;
                fFirstAidKitBonus += fMapHealthBonus/iTeamSize * 0.8; 
                bHasFirstAidKit[i] = true; 
            }
        }
    }

    // 将医疗包分数加到团队奖励中
    fSurvivorBonus[team] += fFirstAidKitBonus - Penalty;

	if (fSurvivorBonus[team] <= 0) 
        fSurvivorBonus[team] = 0;

	fSurvivorBonus[team] = float(RoundToFloor(fSurvivorBonus[team] / float(iTeamSize)) * iTeamSize); // make it a perfect divisor of team size value
	if (iSurvivalMultiplier > 0 && RoundToFloor(fSurvivorBonus[team] / iSurvivalMultiplier) >= iTeamSize) // anything lower than team size will result in 0 after division
	{
		SetConVarInt(hCvarValveSurvivalBonus, RoundToFloor(fSurvivorBonus[team] / iSurvivalMultiplier));
		fSurvivorBonus[team] = float(GetConVarInt(hCvarValveSurvivalBonus) * iSurvivalMultiplier);    // workaround for the discrepancy caused by RoundToFloor()
		Format(sSurvivorState[team], 32, "%s%i\x01/\x05%i\x01", (iSurvivalMultiplier == iTeamSize ? "\x05" : "\x04"), iSurvivalMultiplier, iTeamSize);
	}
	else
	{
		fSurvivorBonus[team] = 0.0;
		SetConVarInt(hCvarValveSurvivalBonus, 0);
		Format(sSurvivorState[team], 32, "\x04%s\x01", (iSurvivalMultiplier == 0 ? "wiped out" : "bonus depleted"));
		bTiebreakerEligibility[team] = (iSurvivalMultiplier == iTeamSize);
	}

	// Check if it's the end of the second round and a tiebreaker case
	if (team > 0 && bTiebreakerEligibility[0] && bTiebreakerEligibility[1])
	{
		GameRules_SetProp("m_iChapterDamage", iSiDamage[0], _, 0, true);
		GameRules_SetProp("m_iChapterDamage", iSiDamage[1], _, 1, true);
		
		// That would be pretty funny otherwise
		if (iSiDamage[0] != iSiDamage[1])
		{
			SetConVarInt(hCvarValveTieBreaker, iPillWorth);
		}
	}
	
	// Scores print
	CreateTimer(3.0, PrintRoundEndStats, _, TIMER_FLAG_NO_MAPCHANGE);

	bRoundOver = true;
	return Plugin_Continue;
}

public Action:PrintRoundEndStats(Handle:timer) 
{
	for (new i = 0; i <= InSecondHalfOfRound(); i++)
	{
		PrintToChatAll("%s\x01回合 \x04#%i\x01 奖励分: \x05%d\x01 [%s]", PLUGIN_TAG, (i + 1), RoundToFloor(fSurvivorBonus[i]), sSurvivorState[i]);
		// [EQSM :: Round 1] Bonus: 487/1200 <42.7%> [3/4]
	}
	
	int ScoreA = L4D2Direct_GetVSCampaignScore(0), ScoreB = L4D2Direct_GetVSCampaignScore(1);
	int iPointsDiff = (ScoreA > ScoreB) ? (ScoreA - ScoreB) : (ScoreB - ScoreA);
	PrintToChatAll("%s\x01回合 \x04#%i\x01 分差: \x05%i", PLUGIN_TAG, (InSecondHalfOfRound() + 1), iPointsDiff);

	new Float:fTotalGrenadeBonus = 0.0; // 用于存储团队的总投掷物分数

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsSurvivor(i) && HasGrenade(i))
        {
            fTotalGrenadeBonus += 0.0;
        }
    }

    PrintToChatAll("%s\x01回合 \x04#%i\x01 ", PLUGIN_TAG, (InSecondHalfOfRound() + 1));
	if (!InSecondHalfOfRound())
	{
		int iMaxScore = L4D_GetVersusMaxCompletionScore();
			PrintToChatAll("%s\x01回合 \x04#%i\x01 分数逆转: \x05%i \x01以上", PLUGIN_TAG, (InSecondHalfOfRound() + 1), iPointsDiff);
	}
	
	if (InSecondHalfOfRound() && bTiebreakerEligibility[0] && bTiebreakerEligibility[1])
	{
		PrintToChatAll("%s\x03决胜局\x01: 团队 \x04%#1\x01 - \x05%i\x01, 团队 \x04%#2\x01 - \x05%i\x01", PLUGIN_TAG, iSiDamage[0], iSiDamage[1]);
		if (iSiDamage[0] == iSiDamage[1])
		{
			PrintToChatAll("%s\x05两队平分秋色", PLUGIN_TAG);
		}
	}
	
	return Plugin_Stop;
}

Float:GetSurvivorHealthBonus()
{
	new Float:fHealthBonus;
	new survivorCount;
	new survivalMultiplier;
	for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
	{
		if (IsSurvivor(i))
		{
			survivorCount++;
			if (IsPlayerAlive(i) && !IsPlayerIncap(i) && !IsPlayerLedged(i))
			{
				survivalMultiplier++;
				fHealthBonus += GetSurvivorPermanentHealth(i) * fPermHpWorth;
			#if SM2_DEBUG
				PrintToChatAll("\x01Adding \x05%N's\x01 perm hp bonus contribution: \x05%d\x01 perm HP -> \x03%.1f\x01 bonus; new total: \x05%.1f\x01", i, GetSurvivorPermanentHealth(i), GetSurvivorPermanentHealth(i) * fPermHpWorth, fHealthBonus);
			#endif
			}
		}
	}
	return (fHealthBonus / iTeamSize * survivalMultiplier);
}

Float:GetSurvivorDamageBonus()
{
    return 0.0; // 返回0，取消虚血分数计算
}

Float:GetSurvivorPillBonus()
{			
	new pillsBonus;
	new survivorCount;
	for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
	{
		if (IsSurvivor(i))
		{
			survivorCount++;
			if (IsPlayerAlive(i) && !IsPlayerIncap(i) && HasPills(i))
			{
				pillsBonus += iPillWorth;
			#if SM2_DEBUG
				PrintToChatAll("\x01Adding \x05%N's\x01 pills contribution, total bonus: \x05%d\x01 pts", i, pillsBonus);
			#endif
			}
		}
	}
	return Float:float(pillsBonus);
}

Float:CalculateBonusPercent(Float:score, Float:maxbonus = -1.0)
{
	return score / (maxbonus == -1.0 ? (fMapBonus + float(iPillWorth * iTeamSize)) : maxbonus) * 100;
}

/************/
/** Stocks **/
/************/

InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound");
}

bool:IsSurvivor(client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2;
}

bool:IsAnyInfected(entity)
{
	if (entity > 0 && entity <= MaxClients)
	{
		return IsClientInGame(entity) && GetClientTeam(entity) == 3;
	}
	else if (entity > MaxClients)
	{
		decl String:classname[64];
		GetEdictClassname(entity, classname, sizeof(classname));
		if (StrEqual(classname, "infected") || StrEqual(classname, "witch")) 
		{
			return true;
		}
	}
	return false;
}

bool:IsPlayerIncap(client)
{
	return bool:GetEntProp(client, Prop_Send, "m_isIncapacitated");
}

bool:IsPlayerLedged(client)
{
	return bool:(GetEntProp(client, Prop_Send, "m_isHangingFromLedge") | GetEntProp(client, Prop_Send, "m_isFallingFromLedge"));
}

GetUprightSurvivors()
{
	new aliveCount;
	new survivorCount;
	for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
	{
		if (IsSurvivor(i))
		{
			survivorCount++;
			if (IsPlayerAlive(i) && !IsPlayerIncap(i) && !IsPlayerLedged(i))
			{
				aliveCount++;
			}
		}
	}
	return aliveCount;
}

GetSurvivorTemporaryHealth(client)
{
	new temphp = RoundToCeil(GetEntPropFloat(client, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * GetConVarFloat(FindConVar("pain_pills_decay_rate")))) - 1;
	return (temphp > 0 ? temphp : 0);
}

GetSurvivorPermanentHealth(client)
{
	// Survivors always have minimum 1 permanent hp
	// so that they don't faint in place just like that when all temp hp run out
	// We'll use a workaround for the sake of fair calculations
	// Edit 2: "Incapped HP" are stored in m_iHealth too; we heard you like workarounds, dawg, so we've added a workaround in a workaround
	return GetEntProp(client, Prop_Send, "m_currentReviveCount") > 0 ? 0 : (GetEntProp(client, Prop_Send, "m_iHealth") > 0 ? GetEntProp(client, Prop_Send, "m_iHealth") : 0);
}

bool:HasPills(client)
{
	new item = GetPlayerWeaponSlot(client, 4);
	if (IsValidEdict(item))
	{
		decl String:buffer[64];
		GetEdictClassname(item, buffer, sizeof(buffer));
		return StrEqual(buffer, "weapon_pain_pills") || StrEqual(buffer, "weapon_adrenaline");
	}
	return false;
}
bool:HasGrenade(int client)
{
    new item = GetPlayerWeaponSlot(client, 2); // 检查武器槽位0，通常用于投掷物
    if (IsValidEdict(item))
    {
        decl String:buffer[64];
        GetEdictClassname(item, buffer, sizeof(buffer));
        // 检查特定的投掷物代码
        return StrEqual(buffer, "weapon_pipe_bomb") ||
              StrEqual(buffer, "weapon_vomitjar") ||
              StrEqual(buffer, "weapon_molotov");
    }
    return false;
}
bool:HasFirstAidKit(int client)
{
    // 检查玩家槽位3是否有weapon_first_aid_kit
    new item = GetPlayerWeaponSlot(client, 3);
    if (IsValidEdict(item))
    {
        decl String:buffer[64];
        GetEdictClassname(item, buffer, sizeof(buffer));
        return StrEqual(buffer, "weapon_first_aid_kit");
    }
    return false;
}
Float:GetFirstAidKitBonus()
{
    new Float:fFirstAidKitBonus = 0.0;
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsSurvivor(i) && IsPlayerAlive(i) && HasFirstAidKit(i))
        {
			//fMedMultiply = (1.0 - 0.556)/iTeamSize;
            fFirstAidKitBonus += fMapHealthBonus/iTeamSize * 0.8;
        }
    }
    return fFirstAidKitBonus;
}

void OnPlayerDeath(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int victim = GetClientOfUserId(hEvent.GetInt("userid"));
	if (IsSurvivor(victim) && !bRoundOver)
	{
	 Penalty += fMapHealthBonus/iTeamSize;
	}
}