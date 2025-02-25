#pragma semicolon 1

#pragma newdecls required
#include <sourcemod>

bool RoundStart;

public void OnPluginStart()
{
	HookEvent("round_start",			Event_RoundStart,			EventHookMode_PostNoCopy);
	HookEvent("player_left_safe_area",	Event_PlayerLeftSafeArea,	EventHookMode_PostNoCopy);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    RoundStart = true;
}

void Event_PlayerLeftSafeArea(Event event, const char[] name, bool dontBroadcast)
{
    if (RoundStart)
    {
        GiveAllSurvivorAmmo();
        RoundStart = false;
    }
}

void GiveAllSurvivorAmmo()
{
    int flags = GetCommandFlags("give");
    SetCommandFlags("give", flags & ~FCVAR_CHEAT);
    for (int i = 1; i <= MaxClients ; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
        {
            FakeClientCommand(i, "give first_aid_kit");
        }
    }
    SetCommandFlags("give", flags|FCVAR_CHEAT);
}