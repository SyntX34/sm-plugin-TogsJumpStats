/*
To Do:
	* Add cfg option to disable hyperscroll detection...maybe if jumps is set to 0?
	* Code in natives to ignore a client. This would allow other plugins to ignore them, give them bhop hacks, later turn off hacks, then re-enable this plugin checking them.
	
need to add checks into togsjumpstats to see if sourcebans is loaded
RegPluginLibrary("sourcebans");
BanClient(
*/

#pragma semicolon 1
#define PLUGIN_VERSION "1.11.1"
#define TAG "{fullred}[TOGs Jump Stats] {default}"
#define CSGO_RED "\x07"
#define CSS_RED "\x07FF0000"

#include <sourcemod>
#include <morecolors>
#include <sdktools>
#include <autoexecconfig>
#include <togsjumpstats1>
#undef REQUIRE_PLUGIN
#include <sourcebanspp>
#include <discordWebhookAPI>

#undef REQUIRE_PLUGIN
#include <sourcebanschecker>
#define REQUIRE_PLUGIN

#pragma newdecls required

public Plugin myinfo = 
{
    name = "TOGs Jump Stats",
    author = "That One Guy (based on code from Inami), +SyntX",
    description = "Player bhop method analysis.",
    version = PLUGIN_VERSION,
    url = "http://www.togcoding.com"
}

Handle g_hOnClientDetected;
Handle g_hOnClientNerfed;
Handle ga_hNerfTimers[MAXPLAYERS + 1] = {null, ...};

ConVar g_hEnableLogs = null;
ConVar g_hReqMultRoundsHyp = null;
ConVar g_hAboveNumber = null;
ConVar g_hAboveNumberFlags = null;
ConVar g_hHypPerf = null;
ConVar g_hHacksPerf = null;
ConVar g_hCooldown = null;
ConVar g_hPatCount = null;
ConVar g_hStatsFlag = null;
char g_sStatsFlag[30];
ConVar g_hAdminFlag = null;
char g_sAdminFlag[30];
ConVar g_hNotificationFlag = null;
char g_sNotificationFlag[30];
ConVar g_hRelogDiff = null;
ConVar g_hFPSMaxMinValue = null;
ConVar g_hBanHacks = null;
ConVar g_hBanPat = null;
ConVar g_hBanHyp = null;
ConVar g_hBanFPSMax = null;
ConVar g_hMaxSpeedAfterFlag = null;
ConVar g_hCapSpeed = null;
ConVar g_cCountBots = null;
ConVar g_cvWebhook;
ConVar g_cvCapSpeedMethod = null;
ConVar g_cvSpeedCapTimer = null;

float ga_fAvgJumps[MAXPLAYERS + 1] = {1.0, ...};
float ga_fAvgSpeed[MAXPLAYERS + 1] = {250.0, ...};
float ga_fVel[MAXPLAYERS + 1][3];
float ga_fLastPos[MAXPLAYERS + 1][3];
float ga_fAvgPerfJumps[MAXPLAYERS + 1] = {0.3333, ...};
float ga_fMaxPerf[MAXPLAYERS + 1] = {0.0, ...};
float gaa_fLastSpeeds[MAXPLAYERS+1][30];
float gaa_fLastPerfJumps[MAXPLAYERS+1][30];
float ga_fNerfStartTime[MAXPLAYERS + 1];

bool ga_bFlagged[MAXPLAYERS + 1];
bool ga_bFlagHypCurrentRound[MAXPLAYERS + 1];
bool ga_bFlagHypLastRound[MAXPLAYERS + 1];
bool ga_bFlagHypTwoRoundsAgo[MAXPLAYERS + 1];
bool ga_bSurfCheck[MAXPLAYERS + 1];
bool ga_bNotificationsPaused[MAXPLAYERS + 1] = {false, ...};
bool ga_bNerfed[MAXPLAYERS + 1] = {false, ...};
bool g_bWaitingForRoundEnd[MAXPLAYERS+1] = {false, ...};
bool g_Plugin_SourceBans = false;
bool g_bRoundCapped[MAXPLAYERS + 1];

char g_sHypPath[PLATFORM_MAX_PATH];
char g_sHacksPath[PLATFORM_MAX_PATH];
char g_sPatPath[PLATFORM_MAX_PATH];

int ga_iJumps[MAXPLAYERS + 1] = {0, ...};
int ga_iPattern[MAXPLAYERS + 1] = {0, ...};
int ga_iPatternhits[MAXPLAYERS + 1] = {0, ...};
int ga_iAutojumps[MAXPLAYERS + 1] = {0, ...};
int ga_iIgnoreCount[MAXPLAYERS + 1];
int ga_iLastPos[MAXPLAYERS + 1] = {0, ...};
int ga_iNumberJumpsAbove[MAXPLAYERS + 1];
int g_iPendingSpectate[MAXPLAYERS + 1] = {0, ...};

int gaa_iLastJumps[MAXPLAYERS + 1][30];

int g_iTickCount = 1;
bool g_bDisableAdminMsgs = false;
bool g_bCSGO = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("TogsJumpStats");
    
    CreateNative("TJS_ClientDetected", Native_ClientDetected);
    CreateNative("TJS_ClientNerfed", Native_ClientNerfed);
    
    return APLRes_Success;
}

stock char[] GetPluginAuthor()
{
    char sAuthor[256];
    GetPluginInfo(INVALID_HANDLE, PlInfo_Author, sAuthor, sizeof(sAuthor));
    return sAuthor;
}

stock char[] GetPluginVersion()
{
    char sVersion[256];
    GetPluginInfo(INVALID_HANDLE, PlInfo_Version, sVersion, sizeof(sVersion));
    return sVersion;
}

stock char[] GetCurrentMapName()
{
    char sMap[128];
    GetCurrentMap(sMap, sizeof(sMap));
    return sMap;
}

stock char[] GetCurrentServerTime()
{
    char sTime[64];
    FormatTime(sTime, sizeof(sTime), "%d/%m/%Y @ %H:%M:%S", GetTime());
    return sTime;
}

stock char[] GetHostName()
{
    char hostname[256];
    FindConVar("hostname").GetString(hostname, sizeof(hostname));
    return hostname;
}

stock char[] HostIP() 
{ 
    char sIP[32], sPort[8], sResult[64];
    int ip = GetConVarInt(FindConVar("hostip"));
    if (ip == 0)
    {
        strcopy(sIP, sizeof(sIP), "Unknown");
    }
    else
    {
        Format(sIP, sizeof(sIP), "%d.%d.%d.%d",
            (ip >> 24) & 0xFF,
            (ip >> 16) & 0xFF,
            (ip >> 8) & 0xFF,
            ip & 0xFF);
    }
    GetConVarString(FindConVar("hostport"), sPort, sizeof(sPort));
    if (strlen(sPort) == 0)
    {
        strcopy(sPort, sizeof(sPort), "Unknown");
    }

    Format(sResult, sizeof(sResult), "%s:%s", sIP, sPort);
    return sResult;
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    
    AutoExecConfig_SetFile("togsjumpstats");
    AutoExecConfig_CreateConVar("tjs_version", PLUGIN_VERSION, "TOGs Jump Stats Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    g_hCooldown = AutoExecConfig_CreateConVar("tjs_gen_cooldown", "60", "Cooldown time between chat notifications to admins for any given clients that is flagged.", FCVAR_NONE, true, 0.0);
    
    g_hStatsFlag = AutoExecConfig_CreateConVar("tjs_flag_gen", "", "Players with this flag will be able to check stats. Set to \"public\" to let everyone use it.");
    g_hStatsFlag.AddChangeHook(OnCVarChange);
    g_hStatsFlag.GetString(g_sStatsFlag, sizeof(g_sStatsFlag));
    
    g_hAdminFlag = AutoExecConfig_CreateConVar("tjs_flag_adm", "b", "Players with this flag will be able to reset jump stats. Set to \"public\" to let everyone use it.");
    g_hAdminFlag.AddChangeHook(OnCVarChange);
    g_hAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
    
    g_hNotificationFlag = AutoExecConfig_CreateConVar("tjs_flag_notification", "b", "Players with this flag will see notifications when players are flagged. Set to \"public\" to let everyone use it.");
    g_hNotificationFlag.AddChangeHook(OnCVarChange);
    g_hNotificationFlag.GetString(g_sNotificationFlag, sizeof(g_sNotificationFlag));
    
    g_hRelogDiff = AutoExecConfig_CreateConVar("tjs_flag_relogdiff", "0.05", "Players are re-logged in the same map if they are flagged with a perf that is this much higher than the previous one.", FCVAR_NONE, true, 0.0, true, 1.0);
    
    g_hFPSMaxMinValue = AutoExecConfig_CreateConVar("tjs_fpsmax_minvalue", "60.0", "Minimum value of fps_max to enforce. Players below this will be flagged (other than zero).", FCVAR_NONE, true, 0.0, true, 1.0);
    
    g_hEnableLogs = AutoExecConfig_CreateConVar("tjs_gen_log", "1", "Enable logging player jump stats if a player is flagged (0 = Disabled, 1 = Enabled).", FCVAR_NONE, true, 0.0, true, 1.0);
    
    g_hReqMultRoundsHyp = AutoExecConfig_CreateConVar("tjs_hyp_mult_rounds", "1", "Clients will not be flagged (in logs and admin notifications) for hyperscrolling until they are noted 3 rounds in a row (0 = Disabled, 1 = Enabled).", FCVAR_NONE, true, 0.0, true, 1.0);
    
    g_hAboveNumber = AutoExecConfig_CreateConVar("tjs_hyp_numjumps", "16", "Number of jump commands to use as a threshold for flagging hyperscrollers.", FCVAR_NONE, true, 1.0);

    g_hAboveNumberFlags = AutoExecConfig_CreateConVar("tjs_hyp_threshold", "16", "Out of the last 30 jumps, the number of jumps that must be above tjs_numjumps to flag player for hyperscrolling.", FCVAR_NONE, true, 1.0);
    
    g_hHypPerf = AutoExecConfig_CreateConVar("tjs_hyp_perf", "0.6", "Above this perf ratio (in combination with the other hyperscroll cvars), players will be flagged for hyperscrolling.", FCVAR_NONE, true, 0.0, true, 1.0);

    g_hHacksPerf = AutoExecConfig_CreateConVar("tjs_hacks_perf", "0.8", "Above this perf ratio (ratios range between 0.0 - 1.0), players will be flagged for hacks.", FCVAR_NONE, true, 0.0, true, 1.0);
    
    g_hPatCount = AutoExecConfig_CreateConVar("tjs_pat_count", "18", "Number of jump out of the last 30 that must match to be flagged for pattern jumps (scripts).", FCVAR_NONE, true, 1.0);
    
    g_hBanHacks = AutoExecConfig_CreateConVar("tjs_ban_hacks", "0", "Ban length in minutes (0 = perm, -1 = disabled) for hacks detection.", FCVAR_NONE, true, -1.0);
    
    g_hBanPat = AutoExecConfig_CreateConVar("tjs_ban_pat", "-1", "Ban length in minutes (0 = perm, -1 = disabled) for pattern jumps detection.", FCVAR_NONE, true, -1.0);
    
    g_hBanHyp = AutoExecConfig_CreateConVar("tjs_ban_hyp", "-1", "Ban length in minutes (0 = perm, -1 = disabled) for hyperscroll detection.", FCVAR_NONE, true, -1.0);
    
    g_hBanFPSMax = AutoExecConfig_CreateConVar("tjs_ban_fpsmax", "-1", "Ban length in minutes (0 = perm, -1 = disabled) for FPS Max abuse detection.", FCVAR_NONE, true, -1.0);

	g_hMaxSpeedAfterFlag = AutoExecConfig_CreateConVar("tjs_maxspeed_detection", "400.0", "Maximum speed a flagged player can reach after being capped.", FCVAR_NONE, true, 100.0, true, 1000.0);

	g_hCapSpeed = AutoExecConfig_CreateConVar("tjs_cap_speed", "1", "Enable/disable speed capping for flagged players (1 = enable, 0 = disable).", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cCountBots = AutoExecConfig_CreateConVar("tjs_count_bots", "1", "Should we count bots as players ?[0 = No, 1 = Yes]", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cvWebhook = AutoExecConfig_CreateConVar("tjs_webhook", "https://discord.com/api/webhooks/1088457155092426873/Ac4yV9jq49N7KypZoA6Tlt2fu_AY7HFO6CZwcVC8lxmmRMqx0OjAQ6ZN63JwOXnyC06Q", "The webhook URL of your Discord channel.", FCVAR_NONE);

    g_cvCapSpeedMethod = AutoExecConfig_CreateConVar("tjs_cap_speed_method", "1", "Methods to cap speed for flagged players (1 = timer, 2 = perf rate).", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cvSpeedCapTimer = AutoExecConfig_CreateConVar("tjs_capspeed_timer", "30", "Timer to cap speed for flagged players (in seconds).", FCVAR_NONE, true, 0.0, true, 90.0);

    HookEvent("player_jump", Event_PlayerJump, EventHookMode_Post);
    
    BuildPath(Path_SM, g_sHypPath, sizeof(g_sHypPath), "logs/togsjumpstats/hyperscrollers.log");
    BuildPath(Path_SM, g_sHacksPath, sizeof(g_sHacksPath), "logs/togsjumpstats/hacks.log");
    BuildPath(Path_SM, g_sPatPath, sizeof(g_sPatPath), "logs/togsjumpstats/patterns.log");

    RegConsoleCmd("sm_jumps", Command_Jumps, "Gives statistics for player jumps.");
    RegConsoleCmd("sm_stopmsgs", Command_DisAdminMsgs, "Stops admin chat notifications when players are flagged for current map.");
    RegConsoleCmd("sm_enablemsgs", Command_EnableAdminMsgs, "Re-enables admin chat notifications when players are flagged.");
    RegConsoleCmd("sm_msgstatus", Command_MsgStatus, "Check enabled/disabled status of admin chat notifications.");
    RegConsoleCmd("sm_resetjumps", Command_ResetJumps, "Reset statistics for a player.");
    RegConsoleCmd("sm_observejumps", Command_ObserveJumps, "Observe a player's jumps in spectator mode.");
    RegConsoleCmd("sm_capplayer", Command_CapPlayer, "Cap a specific player's speed.");
    RegConsoleCmd("sm_removenerf", Command_RemoveNerf, "Removes nerf from a player");
    
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();

    char sGame[32];
    GetGameFolderName(sGame, sizeof(sGame));
    if(StrEqual(sGame, "csgo", false))
    {
        g_bCSGO = true;
    }
    else
    {
        g_bCSGO = false;
    }
    
    HookEvent("round_start", Event_RoundStart, EventHookMode_Pre);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            OnClientPutInServer(i);
        }
    }
    
    char sBuffer[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "logs/togsjumpstats/");
    if(!DirExists(sBuffer))
    {
        CreateDirectory(sBuffer, 777);
    }
	g_hOnClientDetected = CreateGlobalForward("TJS_ClientDetected", ET_Ignore, Param_Cell, Param_String);
	g_hOnClientNerfed = CreateGlobalForward("TJS_ClientNerfed", ET_Ignore, Param_Cell, Param_Cell);

	//CreateNative("TJS_ClientNerfed", Native_ClientNerfed);
	
	CreateTimer(0.1, Timer_CheckSpeed, _, TIMER_REPEAT);
}

public void OnAllPluginsLoaded()
{
	g_Plugin_SourceBans = LibraryExists("sourcebans++");
}

public void OnLibraryAdded(const char[] sName)
{
	if (strcmp(sName, "sourcebans++", false) == 0)
		g_Plugin_SourceBans = true;
}

public void OnLibraryRemoved(const char[] sName)
{
	if (strcmp(sName, "sourcebans++", false) == 0)
		g_Plugin_SourceBans = false;
}

stock bool SetClientNerfed(int client, bool set, bool isRoundCap = false)
{
    if(!IsValidClient(client))
    {
        return false;
    }

    if(ga_hNerfTimers[client] != null)
    {
        KillTimer(ga_hNerfTimers[client]);
        ga_hNerfTimers[client] = null;
    }

    ga_bNerfed[client] = set;
    g_bRoundCapped[client] = isRoundCap;

    if(set && IsPlayerAlive(client) && g_hCapSpeed.BoolValue)
    {
        float maxSpeed = g_hMaxSpeedAfterFlag.FloatValue;
        float velocity[3];
        GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
        float horizontalSpeed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
        if(horizontalSpeed > maxSpeed)
        {
            float scale = maxSpeed / horizontalSpeed;
            velocity[0] *= scale;
            velocity[1] *= scale;
            TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
        }

        char clientName[MAX_NAME_LENGTH];
        GetClientName(client, clientName, sizeof(clientName));
        
        if(g_cvCapSpeedMethod.IntValue == 1 && !isRoundCap)
        {
            float timerDuration = g_cvSpeedCapTimer.FloatValue;
            ga_fNerfStartTime[client] = GetGameTime();
            
            ga_hNerfTimers[client] = CreateTimer(timerDuration, Timer_RemoveNerf, client);
            
            CPrintToChat(client, "%s%sYou have been nerfed and speed capped to %.0f for %.0f seconds due to cheat detection!", 
                TAG, g_bCSGO ? CSGO_RED : CSS_RED, maxSpeed, timerDuration);
        }
        else
        {
            CPrintToChat(client, "%s%sYou have been %s and speed capped to %.0f!", 
                TAG, g_bCSGO ? CSGO_RED : CSS_RED, 
                isRoundCap ? "capped by an admin for the round" : "nerfed due to cheat detection",
                maxSpeed);
        }
    }
    else if(!set && IsPlayerAlive(client))
    {
        char clientName[MAX_NAME_LENGTH];
        GetClientName(client, clientName, sizeof(clientName));
        CPrintToChat(client, "%s%sYour %s has been removed!", 
            TAG, g_bCSGO ? CSGO_RED : CSS_RED,
            g_bRoundCapped[client] ? "round cap" : "nerf");
            
        g_bRoundCapped[client] = false;
    }

    return ga_bNerfed[client];
}

public Action Timer_RemoveNerf(Handle timer, int client)
{
    if(IsValidClient(client))
    {
        ga_hNerfTimers[client] = null;
        SetClientNerfed(client, false);
        
        char clientName[MAX_NAME_LENGTH];
        GetClientName(client, clientName, sizeof(clientName));
        CPrintToChat(client, "%s%sNerf timer expired - restrictions removed!", TAG, g_bCSGO ? CSGO_RED : CSS_RED);
    }
    
    return Plugin_Stop;
}

public Action Timer_CheckSpeed(Handle timer)
{
    if(!g_hCapSpeed.BoolValue)
    {
        return Plugin_Continue;
    }

    float maxSpeed = g_hMaxSpeedAfterFlag.FloatValue;
    float hacksPerfThreshold = g_hHacksPerf.FloatValue;
    int speedMethod = g_cvCapSpeedMethod.IntValue;

    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && IsPlayerAlive(i) && ga_bNerfed[i])
        {
            // Only check performance-based removal if using perf rate method (method 2)
            if(speedMethod == 2)
            {
                // Check if player's performance has dropped below the hacks threshold
                if(ga_fAvgPerfJumps[i] < hacksPerfThreshold)
                {
                    SetClientNerfed(i, false);
                    continue;
                }
            }
            if(GetEntityMoveType(i) == MOVETYPE_LADDER || 
               GetEntProp(i, Prop_Data, "m_nWaterLevel") > 1 || 
               GetEntProp(i, Prop_Data, "m_nOldButtons") & IN_JUMP)
            {
                continue;
            }

            // Apply speed cap
            float velocity[3];
            GetEntPropVector(i, Prop_Data, "m_vecVelocity", velocity);
            float horizontalSpeed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);

            if(horizontalSpeed > maxSpeed)
            {
                float scale = maxSpeed / horizontalSpeed;
                velocity[0] *= scale;
                velocity[1] *= scale;
                TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, velocity);

                char clientName[MAX_NAME_LENGTH];
                GetClientName(i, clientName, sizeof(clientName));
                
                // Show different messages based on method
                if(speedMethod == 1 && ga_hNerfTimers[i] != null)
                {
                    float timeRemaining = g_cvSpeedCapTimer.FloatValue - (GetGameTime() - ga_fNerfStartTime[i]);
                    if(timeRemaining > 0)
                    {
                        CPrintToChat(i, "%s%sSpeed capped to %.0f (%.0fs remaining)!", 
                            TAG, g_bCSGO ? CSGO_RED : CSS_RED, maxSpeed, timeRemaining);
                    }
                }
                else
                {
                    CPrintToChat(i, "%s%sSpeed capped to %.0f due to cheat detection!", 
                        TAG, g_bCSGO ? CSGO_RED : CSS_RED, maxSpeed);
                }
            }
        }
    }
    return Plugin_Continue;
}

public void OnCVarChange(ConVar hCVar, const char[] sOldValue, const char[] sNewValue)
{
    if(hCVar == g_hStatsFlag)
    {
        g_hStatsFlag.GetString(g_sStatsFlag, sizeof(g_sStatsFlag));
    }
    else if(hCVar == g_hAdminFlag)
    {
        g_hAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
    }
    else if(hCVar == g_hNotificationFlag)
    {
        g_hNotificationFlag.GetString(g_sNotificationFlag, sizeof(g_sNotificationFlag));
    }
}

public Action Event_RoundStart(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
    if(g_hReqMultRoundsHyp.IntValue)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(ga_bFlagHypLastRound[i])
            {
                ga_bFlagHypTwoRoundsAgo[i] = true;
            }
            else
            {
                ga_bFlagHypTwoRoundsAgo[i] = false;
            }
            
            if(ga_bFlagHypCurrentRound[i])
            {
                ga_bFlagHypLastRound[i] = true;
            }
            else
            {
                ga_bFlagHypLastRound[i] = false;
            }
            
            ga_bFlagHypCurrentRound[i] = false;
        }
    }
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            QueryClientConVar(i, "fps_max", ClientConVar, i);
        }
    }
    
    return Plugin_Continue;
}


public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_bWaitingForRoundEnd[client] && IsValidClient(client))
        {
            int target = GetClientOfUserId(g_iPendingSpectate[client]);
            if (IsValidClient(target) && IsPlayerAlive(target))
            {
                ChangeClientTeam(client, 1);
                RequestFrame(Frame_ObserveAfterTeamChange, GetClientUserId(client));
            }
            else
            {
                CPrintToChat(client, "%sYour observation target is no longer available.", TAG);
            }
            
            g_bWaitingForRoundEnd[client] = false;
            g_iPendingSpectate[client] = 0;
        }
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidClient(client) && g_bRoundCapped[client])
        {
            SetClientNerfed(client, false);
            g_bRoundCapped[client] = false;
        }
    }
}

public int ClientConVar(QueryCookie cookie, int client, ConVarQueryResult result, const char[] sCVarName, const char[] sCVarValue)
{
    float fValue = StringToFloat(sCVarValue);
    if((fValue < g_hFPSMaxMinValue.FloatValue) && fValue)
    {
        char sMsg[32];
        Format(sMsg, sizeof(sMsg), "fps_max-%s", sCVarValue);
        LogFlag(client, sMsg);
        if(!g_bDisableAdminMsgs)
        {
            NotifyAdmins(client, sMsg);
        }
        Call_StartForward(CreateGlobalForward("TJS_ClientDetected", ET_Ignore, Param_Cell, Param_String));
        Call_PushCell(client);
        Call_PushString(sMsg);
        Call_Finish();
        CPrintToChatAll("%s%s%N has been detected for %s!", TAG, g_bCSGO ? CSGO_RED : CSS_RED, client, sMsg);
        SetClientNerfed(client, true);
    }
    return 0;
}

public void OnClientPutInServer(int client)
{
    ga_bNotificationsPaused[client] = false;
    ga_bFlagged[client] = false;
    ga_bFlagHypCurrentRound[client] = false;
    ga_bFlagHypLastRound[client] = false;
    ga_bFlagHypTwoRoundsAgo[client] = false;
    ga_bNerfed[client] = false;
}

public void OnClientPostAdminCheck(int client)
{
    if(HasFlags(client, g_sAdminFlag))
    {
        CreateTimer(15.0, TimerCB_CheckForFlags, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action TimerCB_CheckForFlags(Handle hTimer, any iUserID)
{
    int client = GetClientOfUserId(iUserID);
    if(IsValidClient(client))
    {
        char sFlaggedPlayers[1024] = "";
        char sPlayerInfo[256];
        int iCount = 0;
        
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsValidClient(i) && ga_bFlagged[i])
            {
                iCount++;
                
                // Get player info
                char sName[MAX_NAME_LENGTH];
                char sSteamID[32];
                char sTeam[16];
                
                GetClientName(i, sName, sizeof(sName));
                GetClientAuthId(i, AuthId_Steam2, sSteamID, sizeof(sSteamID));
                
                switch(GetClientTeam(i))
                {
                    case 1: strcopy(sTeam, sizeof(sTeam), "SPEC");
                    case 2: strcopy(sTeam, sizeof(sTeam), "T");
                    case 3: strcopy(sTeam, sizeof(sTeam), "CT");
                    default: strcopy(sTeam, sizeof(sTeam), "UNK");
                }
                
                // Format player info line
                Format(sPlayerInfo, sizeof(sPlayerInfo), "#%d %d %s <%s> <%s>\n", 
                    iCount, 
                    GetClientUserId(i),
                    sName, 
                    sSteamID, 
                    sTeam);
                
                StrCat(sFlaggedPlayers, sizeof(sFlaggedPlayers), sPlayerInfo);
                
                // Add jump stats
                char sStats[300];
                GetClientStats(i, sStats, sizeof(sStats));
                StrCat(sFlaggedPlayers, sizeof(sFlaggedPlayers), sStats);
                StrCat(sFlaggedPlayers, sizeof(sFlaggedPlayers), "\n\n");
            }
        }
        
        if(iCount)
        {
            CPrintToChat(client, "%s%s%d players have been flagged for jump stats! Please check console for details!", 
                TAG, 
                g_bCSGO ? CSGO_RED : CSS_RED, 
                iCount);
                
            PrintToConsole(client, "\n=== Flagged Players ===\n%s", sFlaggedPlayers);
        }
    }
    return Plugin_Continue;
}

public void Event_PlayerJump(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    
    if (!IsValidClient(client))
    {
        return;
    }
    
    // Update jump statistics
    ga_fAvgJumps[client] = (ga_fAvgJumps[client] * 9.0 + float(ga_iJumps[client])) / 10.0;
    
    // Calculate speed
    float a_fVelVectors[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", a_fVelVectors);
    a_fVelVectors[2] = 0.0;
    float speed = GetVectorLength(a_fVelVectors);
    ga_fAvgSpeed[client] = (ga_fAvgSpeed[client] * 9.0 + speed) / 10.0;
    
    // Store last jumps, performance, and speed in circular buffer
    gaa_iLastJumps[client][ga_iLastPos[client]] = ga_iJumps[client];
    gaa_fLastPerfJumps[client][ga_iLastPos[client]] = ga_fAvgPerfJumps[client] * 100.0;
    gaa_fLastSpeeds[client][ga_iLastPos[client]] = ga_fAvgSpeed[client];
    ga_iLastPos[client]++;
    if (ga_iLastPos[client] == 30)
    {
        ga_iLastPos[client] = 0;
    }
    
    // Pattern jump detection
    if (ga_fAvgJumps[client] > 15.0)
    {
        if ((ga_iPatternhits[client] > 0) && (ga_iJumps[client] == ga_iPattern[client]))
        {
            ga_iPatternhits[client]++;
            if (ga_iPatternhits[client] > g_hPatCount.IntValue)
            {
                if (!ga_bNotificationsPaused[client])
                {
                    if (!g_bDisableAdminMsgs)
                    {
                        NotifyAdmins(client, "Pattern Jumps");
                    }
                    
                    SetClientNerfed(client, true);
                }
                
                if ((ga_fAvgPerfJumps[client] - g_hRelogDiff.FloatValue) > ga_fMaxPerf[client])
                {
                    LogFlag(client, "pattern jumps", ga_bFlagged[client]);
                    ga_fMaxPerf[client] = ga_fAvgPerfJumps[client];
                }
            }
        }
        else if ((ga_iPatternhits[client] > 0) && (ga_iJumps[client] != ga_iPattern[client]))
        {
            ga_iPatternhits[client] -= 2;
        }
        else
        {
            ga_iPattern[client] = ga_iJumps[client];
            ga_iPatternhits[client] = 2;
        }
    }
    
    // Hyperscroll detection
    if (ga_fAvgJumps[client] > 14.0)
    {
        ga_iNumberJumpsAbove[client] = 0;
        
        for (int i = 0; i < 29; i++)
        {
            if ((gaa_iLastJumps[client][i]) > (g_hAboveNumber.IntValue - 1))
            {
                ga_iNumberJumpsAbove[client]++;
            }
        }
        
        if ((ga_iNumberJumpsAbove[client] > (g_hAboveNumberFlags.IntValue - 1)) && (ga_fAvgPerfJumps[client] >= g_hHypPerf.FloatValue))
        {
            if (g_hReqMultRoundsHyp.IntValue)
            {
                if (ga_bFlagHypTwoRoundsAgo[client] && ga_bFlagHypLastRound[client])
                {                        
                    if (!ga_bNotificationsPaused[client])
                    {
                        if (!g_bDisableAdminMsgs)
                        {
                            NotifyAdmins(client, "Hyperscroll (3 rounds in a row)");
                        }
                        
                        SetClientNerfed(client, true);
                    }
                    
                    if ((ga_fAvgPerfJumps[client] - g_hRelogDiff.FloatValue) > ga_fMaxPerf[client])
                    {
                        LogFlag(client, "hyperscroll (3 rounds in a row)", ga_bFlagged[client]);
                        ga_fMaxPerf[client] = ga_fAvgPerfJumps[client];
                    }
                }
                else
                {
                    ga_bFlagHypCurrentRound[client] = true;
                }    
            }
            else
            {
                if (!ga_bNotificationsPaused[client])
                {
                    if (!g_bDisableAdminMsgs)
                    {
                        NotifyAdmins(client, "Hyperscroll");
                    }
                    
                    SetClientNerfed(client, true);
                }
                
                if ((ga_fAvgPerfJumps[client] - g_hRelogDiff.FloatValue) > ga_fMaxPerf[client])
                {
                    LogFlag(client, "hyperscroll", ga_bFlagged[client]);
                    ga_fMaxPerf[client] = ga_fAvgPerfJumps[client];
                }
            }
        }
    }
    else if (ga_iJumps[client] > 1)
    {
        ga_iAutojumps[client] = 0;
    }

    // Reset jump count for next detection
    ga_iJumps[client] = 0;
    
    // Check for small movements that might indicate autojumping
    float a_fTempVectors[3];
    a_fTempVectors = ga_fLastPos[client];
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", ga_fLastPos[client]);
    
    float len = GetVectorDistance(ga_fLastPos[client], a_fTempVectors, true);
    if (len < 30.0)
    {   
        ga_iIgnoreCount[client] = 2;
    }
    
    // Hacks detection
    if (ga_fAvgPerfJumps[client] >= g_hHacksPerf.FloatValue)
    {
        if (!ga_bNotificationsPaused[client])
        {
            if (!g_bDisableAdminMsgs)
            {
                NotifyAdmins(client, "Hacks");
            }
            
            SetClientNerfed(client, true);
        }
        
        if ((ga_fAvgPerfJumps[client] - g_hRelogDiff.FloatValue) > ga_fMaxPerf[client])
        {
            LogFlag(client, "hacks", ga_bFlagged[client]);
            ga_fMaxPerf[client] = ga_fAvgPerfJumps[client];
        }
    }
}

public Action Command_DisAdminMsgs(int client, int iArgs)
{
    if(!HasFlags(client, g_sAdminFlag) && IsValidClient(client))
    {
        CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
        return Plugin_Handled;
    }
    
    StopMsgs(client);
    
    return Plugin_Handled;
}

public Action Command_MsgStatus(int client, int iArgs)
{
    if(!HasFlags(client, g_sAdminFlag) && IsValidClient(client))
    {
        CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
        return Plugin_Handled;
    }
    
    if(g_bDisableAdminMsgs)
    {
        CReplyToCommand(client, "%sAdmin chat notifications for flagged players is currently disabled!", TAG);
    }
    else
    {
        CReplyToCommand(client, "%sAdmin chat notifications for flagged players is currently enabled.", TAG);
    }
    
    return Plugin_Handled;
}

public Action Command_CapPlayer(int client, int args)
{
    if(!HasFlags(client, g_sAdminFlag) && IsValidClient(client))
    {
        CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
        return Plugin_Handled;
    }

    if(args < 1)
    {
        CReplyToCommand(client, "%sUsage: sm_capplayer <player>", TAG);
        return Plugin_Handled;
    }
    
    char target[65];
    GetCmdArg(1, target, sizeof(target));
    
    int targetClient = FindTarget(client, target, true, false);
    if(targetClient == -1)
    {
        return Plugin_Handled;
    }
    
    if(ga_bNerfed[targetClient] && g_bRoundCapped[targetClient])
    {
        CReplyToCommand(client, "%sPlayer is already capped for the round.", TAG);
        return Plugin_Handled;
    }
    
    SetClientNerfed(targetClient, true, true);
    
    char clientName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
    GetClientName(client, clientName, sizeof(clientName));
    GetClientName(targetClient, targetName, sizeof(targetName));
    
    CReplyToCommand(client, "%sCapped player %s for the round", TAG, targetName);
    LogAction(client, targetClient, "\"%L\" capped player \"%L\" for the round", client, targetClient);
    
    return Plugin_Handled;
}

public Action Command_RemoveNerf(int client, int args)
{
    if(!HasFlags(client, g_sAdminFlag) && IsValidClient(client))
    {
        CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
        return Plugin_Handled;
    }

    if(args < 1)
    {
        CReplyToCommand(client, "%sUsage: sm_removenerf <player>", TAG);
        return Plugin_Handled;
    }
    
    char target[65];
    GetCmdArg(1, target, sizeof(target));
    
    int targetClient = FindTarget(client, target, true, false);
    if(targetClient == -1)
    {
        return Plugin_Handled;
    }
    
    if(!ga_bNerfed[targetClient])
    {
        CReplyToCommand(client, "%sPlayer is not currently nerfed.", TAG);
        return Plugin_Handled;
    }
    
    SetClientNerfed(targetClient, false);
    
    char clientName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
    GetClientName(client, clientName, sizeof(clientName));
    GetClientName(targetClient, targetName, sizeof(targetName));
    
    CReplyToCommand(client, "%sRemoved nerf from %s", TAG, targetName);
    LogAction(client, targetClient, "\"%L\" removed nerf from \"%L\"", client, targetClient);
    
    return Plugin_Handled;
}

void StopMsgs(any client)
{
    g_bDisableAdminMsgs = true;
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && CheckCommandAccess(i, "sm_admin", ADMFLAG_GENERIC, true) && !IsFakeClient(i))
        {
            if(i > 0)
            {
                CPrintToChat(i, "%s%s%N has disabled admin notices for bhop cheats until map changes!", TAG, g_bCSGO ? CSGO_RED : CSS_RED, client);
            }
        }
    }
}

void EnableMsgs(any client)
{
    g_bDisableAdminMsgs = false;
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && CheckCommandAccess(i, "sm_admin", ADMFLAG_GENERIC, true) && !IsFakeClient(i))
        {
            if(i > 0)
            {
                CPrintToChat(i, "%s%s%N has re-enabled admin notices for bhop cheats!", TAG, g_bCSGO ? CSGO_RED : CSS_RED, client);
            }
        }
    }
}

public Action Command_EnableAdminMsgs(int client, int iArgs)
{
    if(!HasFlags(client, g_sAdminFlag) && IsValidClient(client))
    {
        CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
        return Plugin_Handled;
    }
    
    EnableMsgs(client);
    
    return Plugin_Handled;
}

public void OnMapStart()
{
    g_bDisableAdminMsgs = false;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            ga_bNotificationsPaused[i] = false;
            ga_bFlagHypCurrentRound[i] = false;
            ga_bFlagHypLastRound[i] = false;
            ga_bFlagHypTwoRoundsAgo[i] = false;
            ga_bNerfed[i] = false;
        }
    }
}

void NotifyAdmins(int client, char[] sFlagType)
{
    if(!IsValidClient(client))
    {
        return;
    }

    char sStats[512];
    GetClientStats(client, sStats, sizeof(sStats));
    
    if(StrContains(sFlagType, "fps_max", false) == -1)
    {
        // Check if admin flag is set to "public" or empty - if so, notify everyone
        if (StrEqual(g_sAdminFlag, "public", false) || StrEqual(g_sAdminFlag, "", false))
        {
            char sSteamID[32];
            GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
            
            CPrintToChatAll("%s%s%N [%s] has been detected for %s! (Perf: %.1f%%, Speed: %.1f)", 
                TAG, 
                g_bCSGO ? CSGO_RED : CSS_RED, 
                client, 
                sSteamID,
                sFlagType,
                ga_fAvgPerfJumps[client]*100,
                ga_fAvgSpeed[client]);
        }
        else
        {
            // Only notify admins with the specified flag
            for(int i = 1; i <= MaxClients; i++)
            {
                if(IsValidClient(i) && HasFlags(i, g_sNotificationFlag))
                {
                    CPrintToChat(i, "%s {magenta}'%N' {default}has been {aqua}flagged for '%s'! {olive}Please check their jump stats!", 
                        TAG, 
                        client, 
                        sFlagType);
                        
                    PrintToConsole(i, "=== Flagged Player Details ===\n");
                    PrintToConsole(i, "Player: %N", client);
                    
                    char sSteamID[32];
                    if(GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
                    {
                        PrintToConsole(i, "SteamID: %s", sSteamID);
                    }
                    
                    PrintToConsole(i, "Detection: %s", sFlagType);
                    PrintToConsole(i, "Current Team: %s", GetClientTeam(client) == 2 ? "T" : GetClientTeam(client) == 3 ? "CT" : "SPEC");
                    PrintToConsole(i, "\nJump Stats:");
                    PerformStats(i, client);
                    PrintToConsole(i, "\n");
                }
            }
        }
        
        ga_bNotificationsPaused[client] = true;
        CreateTimer(g_hCooldown.FloatValue, UnPause_TimerMonitor, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        
        Call_StartForward(g_hOnClientDetected);
        Call_PushCell(client);
        Call_PushString(sFlagType);
        Call_Finish();
    }
    else
    {
        char a_sTempArray[2][32];
        ExplodeString(sFlagType, "-", a_sTempArray, sizeof(a_sTempArray), sizeof(a_sTempArray[]));
        
        if (StrEqual(g_sAdminFlag, "public", false) || StrEqual(g_sAdminFlag, "", false))
        {
            CPrintToChatAll("%s%s%N has been flagged for having fps_max set to %s! Minimum required: %.1f", 
                TAG, 
                g_bCSGO ? CSGO_RED : CSS_RED,
                client, 
                a_sTempArray[1], 
                g_hFPSMaxMinValue.FloatValue);
        }
        else
        {
            for(int i = 1; i <= MaxClients; i++)
            {
                if(IsValidClient(i) && HasFlags(i, g_sNotificationFlag))
                {
                    CPrintToChat(i, "%s {olive}'%N' {default}has been {red}flagged for having fps_max set to %s! {default}Please enforce a minimum value of {green}%5.1f.", 
                        TAG, 
                        client, 
                        a_sTempArray[1], 
                        g_hFPSMaxMinValue.FloatValue);
                        
                    PrintToConsole(i, "=== FPS Max Violation ===\n");
                    PrintToConsole(i, "Player: %N", client);
                    
                    char sSteamID[32];
                    if(GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
                    {
                        PrintToConsole(i, "SteamID: %s", sSteamID);
                    }
                    
                    PrintToConsole(i, "Current fps_max: %s", a_sTempArray[1]);
                    PrintToConsole(i, "Minimum required: %.1f", g_hFPSMaxMinValue.FloatValue);
                    PrintToConsole(i, "\nJump Stats:");
                    PerformStats(i, client);
                    PrintToConsole(i, "\n");
                }
            }
        }
        
        Call_StartForward(g_hOnClientDetected);
        Call_PushCell(client);
        Call_PushString(sFlagType);
        Call_Finish();
    }

    Discord_Notify(client, sFlagType, sStats);
}

void Discord_Notify(int client, const char[] reason, const char[] stats)
{
    char szWebhookURL[256];
    g_cvWebhook.GetString(szWebhookURL, sizeof(szWebhookURL));
    
    if (strlen(szWebhookURL) == 0)
    {
        LogError("[TOGs Jump Stats] Webhook URL is empty, cannot send notification");
        return;
    }

    char sPluginDeveloper[256], sPluginVersion[256], currentMap[PLATFORM_MAX_PATH], sTime[64], sServerIP[64];
    strcopy(sPluginDeveloper, sizeof(sPluginDeveloper), GetPluginAuthor());
    strcopy(sPluginVersion, sizeof(sPluginVersion), GetPluginVersion());
    strcopy(currentMap, sizeof(currentMap), GetCurrentMapName());
    strcopy(sTime, sizeof(sTime), GetCurrentServerTime());
    strcopy(sServerIP, sizeof(sServerIP), HostIP());
    
    char sAuth[32];
    if (!GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true))
    {
        strcopy(sAuth, sizeof(sAuth), "UNKNOWN");
    }

    char sPlayer[256];
    #if defined _sourcebanspp_included
    if (g_Plugin_SourceBans)
    {
        int iClientBans = 0;
        int iClientComms = 0;
        
        #if defined _sourcebanschecker_included
        iClientBans = SBPP_CheckerGetClientsBans(client);
        iClientComms = SBPP_CheckerGetClientsComms(client);
        #endif
        
        Format(sPlayer, sizeof(sPlayer), "%N (%d bans - %d comms) [%s]", 
            client, iClientBans, iClientComms, sAuth);
    }
    else
    #endif
    {
        Format(sPlayer, sizeof(sPlayer), "%N [%s]", client, sAuth);
    }

    int iMaxPlayers = MaxClients;
    int iConnected = GetClientCountEx(g_cCountBots.BoolValue);

    // Generate nerf status with timer information
    char sNerfStatus[128];
    if (ga_bNerfed[client])
    {
        int speedMethod = g_cvCapSpeedMethod.IntValue;
        if (speedMethod == 1 && ga_hNerfTimers[client] != null)
        {
            // Timer method - show remaining time
            float timeRemaining = g_cvSpeedCapTimer.FloatValue - (GetGameTime() - ga_fNerfStartTime[client]);
            if (timeRemaining > 0)
            {
                Format(sNerfStatus, sizeof(sNerfStatus), "Yes (%.0fs remaining)", timeRemaining);
            }
            else
            {
                Format(sNerfStatus, sizeof(sNerfStatus), "Yes (timer expired)");
            }
        }
        else if (speedMethod == 2)
        {
            // Performance method
            Format(sNerfStatus, sizeof(sNerfStatus), "Yes (perf-based)");
        }
        else
        {
            Format(sNerfStatus, sizeof(sNerfStatus), "Yes");
        }
    }
    else
    {
        Format(sNerfStatus, sizeof(sNerfStatus), "No");
    }

    // Clean Discord message with better formatting
    char sMessage[4096];
    Format(sMessage, sizeof(sMessage), 
        "🚨 **PLAYER DETECTION ALERT** 🚨\n\n" ...
        "```yaml\n" ...
        "Player Details:\n" ...
        "  Name: %s\n" ...
        "  Reason: %s\n" ...
        "  Flagged: %i round(s)\n" ...
        "  Nerfed: %s\n\n" ...
        "Server Info:\n" ...
        "  Name: %s\n" ...
        "  IP: %s\n" ...
        "  Map: %s\n" ...
        "  Players: %d/%d\n" ...
        "  Time: %s\n\n" ...
        "Performance Stats:\n" ...
        "%s\n\n" ...
        "Plugin Info:\n" ...
        "  TOGs Jump Stats (v%s) by %s\n" ...
        "```",
        sPlayer, reason, ga_bFlagged[client], sNerfStatus,
        GetHostName(), sServerIP, currentMap, iConnected, iMaxPlayers, sTime,
        stats, sPluginVersion, sPluginDeveloper);

    // Handle message length limit
    if (strlen(sMessage) >= 2000)
    {
        char sMessagePt1[2000], sMessagePt2[2000];
        
        Format(sMessagePt1, sizeof(sMessagePt1),
            "🚨 **PLAYER DETECTION ALERT** 🚨\n\n" ...
            "```yaml\n" ...
            "Player Details:\n" ...
            "  Name: %s\n" ...
            "  Reason: %s\n" ...
            "  Flagged: %i round(s)\n" ...
            "  Nerfed: %s\n\n" ...
            "Server Info:\n" ...
            "  Name: %s\n" ...
            "  IP: %s\n" ...
            "  Map: %s\n" ...
            "  Players: %d/%d\n" ...
            "  Time: %s\n" ...
            "```",
            sPlayer, reason, ga_bFlagged[client], sNerfStatus,
            GetHostName(), sServerIP, currentMap, iConnected, iMaxPlayers, sTime);

        Format(sMessagePt2, sizeof(sMessagePt2), 
            "```yaml\n" ...
            "Performance Stats:\n" ...
            "%s\n\n" ...
            "Plugin Info:\n" ...
            "  TOGs Jump Stats (v%s) by %s\n" ...
            "```",
            stats, sPluginVersion, sPluginDeveloper);
        
        Webhook webhookPt1 = new Webhook(sMessagePt1);
        webhookPt1.Execute(szWebhookURL, OnWebHookExecuted);
        delete webhookPt1;
        
        Webhook webhookPt2 = new Webhook(sMessagePt2);
        webhookPt2.Execute(szWebhookURL, OnWebHookExecuted);
        delete webhookPt2;
    }
    else
    {
        Webhook webhook = new Webhook(sMessage);
        webhook.Execute(szWebhookURL, OnWebHookExecuted);
        delete webhook;
    }
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
    if (response.Status != HTTPStatus_OK)
    {
        LogError("[TOGs Jump Stats] Failed to send webhook. Status: %d", response.Status);
    }
}

stock int GetClientCountEx(bool countBots)
{
	int iRealClients = 0;
	int iFakeClients = 0;

	for(int player = 1; player <= MaxClients; player++)
	{
		if(IsClientConnected(player))
		{
			if(IsFakeClient(player))
				iFakeClients++;
			else
				iRealClients++;
		}
	}
	return countBots ? iFakeClients + iRealClients : iRealClients;
}

public Action UnPause_TimerMonitor(Handle hTimer, any iUserID)
{
    int client = GetClientOfUserId(iUserID);
    if(IsValidClient(client))
    {
        ga_bNotificationsPaused[client] = false;
    }
    return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
    for (int i = 0; i < 30; i++)
    {
        gaa_fLastPerfJumps[client][i] = 0.0;
        gaa_fLastSpeeds[client][i] = 0.0;
        gaa_iLastJumps[client][i] = 0;
    }
    if(ga_hNerfTimers[client] != null)
    {
        KillTimer(ga_hNerfTimers[client]);
        ga_hNerfTimers[client] = null;
    }
    ga_fNerfStartTime[client] = 0.0;
    ga_iJumps[client] = 0;
    ga_fAvgJumps[client] = 0.0;
    ga_fAvgSpeed[client] = 0.0;
    ga_fAvgPerfJumps[client] = 0.0;
    ga_iPattern[client] = 0;
    ga_iPatternhits[client] = 0;
    ga_iAutojumps[client] = 0;
    ga_iIgnoreCount[client] = 0;
    ga_bFlagged[client] = false;
    ga_bFlagHypCurrentRound[client] = false;
    ga_bFlagHypLastRound[client] = false;
    ga_bFlagHypTwoRoundsAgo[client] = false;
    ga_bNerfed[client] = false;
    ga_fVel[client][2] = 0.0;
}

public void OnGameFrame()
{
    if(g_iTickCount > 1*MaxClients)
    {
        g_iTickCount = 1;
    }
    else
    {
        if(g_iTickCount % 1 == 0)
        {
            int client = g_iTickCount / 1;
            if(ga_bSurfCheck[client] && IsClientInGame(client) && IsPlayerAlive(client))
            {    
                GetEntPropVector(client, Prop_Data, "m_vecVelocity", ga_fVel[client]);
                if(ga_fVel[client][2] < -290)
                {
                    ga_iIgnoreCount[client] = 2;
                }
            }
        }
        g_iTickCount++;
    }
}

void LogFlag(int client, const char[] sType, bool bAlreadyFlagged = false)
{
    if(IsValidClient(client))
    {
        char sStats[512]; // Declare sStats here
        char sLogMsg[300];
        GetClientStatsForLogs(client, sStats, sizeof(sStats));
        Format(sLogMsg, sizeof(sLogMsg), "%s %s%s", sStats, sType, (bAlreadyFlagged ? " (already flagged this map)" : ""));

        if(StrEqual(sType, "hacks", false))
        {
            if(g_hEnableLogs.BoolValue)
            {
                LogToFileEx(g_sHacksPath, sLogMsg);
            }
            
            if(g_hBanHacks.IntValue != -1)
            {
                SBPP_BanPlayer(0, client, g_hBanHacks.IntValue, "[TOGs Jump Stats] Bhop hack Detected");
            }
        }
        else if(StrEqual(sType, "pattern jumps", false))
        {
            if(g_hEnableLogs.BoolValue)
            {
                LogToFileEx(g_sPatPath, sLogMsg);
            }
            
            if(g_hBanPat.IntValue != -1)
            {
                SBPP_BanPlayer(0, client, g_hBanPat.IntValue, "[TOGs Jump Stats] Pattern jump Detected");
            }
        }
        else if(StrEqual(sType, "hyperscroll", false) || StrEqual(sType, "hyperscroll (3 rounds in a row)", false))
        {
            if(g_hEnableLogs.BoolValue)
            {
                LogToFileEx(g_sHypPath, sLogMsg);
            }
            
            if(g_hBanHyp.IntValue != -1)
            {
                SBPP_BanPlayer(0, client, g_hBanHyp.IntValue, "[TOGs Jump Stats] Hyperscroll Detected");
            }
        }
        else if(StrContains(sType, "fps_max", false) != -1)
        {
            char a_sTempArray[2][32];
            ExplodeString(sType, "-", a_sTempArray, sizeof(a_sTempArray), sizeof(a_sTempArray[]));
            Format(sLogMsg, sizeof(sLogMsg), "%L has fps_max set to %s (min. accepted value set to %i)! This can be used as a glitch to get high perfect percentages!", client, a_sTempArray[1], g_hFPSMaxMinValue.IntValue);
            
            if(g_hEnableLogs.BoolValue)
            {
                LogToFileEx(g_sHacksPath, sLogMsg);
            }
            
            if(g_hBanFPSMax.IntValue != -1)
            {
                SBPP_BanPlayer(0, client, g_hBanFPSMax.IntValue, "[TOGs Jump Stats] FPS max Detected");
            }
        }
        ga_bFlagged[client] = true;
    }
}

public Action Command_Jumps(int client, int iArgs)
{
    if (iArgs != 1)
    {
        CReplyToCommand(client, "%sUsage: sm_jumps <#userid|name|@all>", TAG);
        return Plugin_Handled;
    }
    
    if (IsValidClient(client))
    {
        if (!HasFlags(client, g_sStatsFlag))
        {
            CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
            return Plugin_Handled;
        }
    }
    
    char sArg[65];
    GetCmdArg(1, sArg, sizeof(sArg));

    char sTargetName[MAX_TARGET_LENGTH];
    int a_iTargets[MAXPLAYERS], iTargetCount;
    bool bTN_Is_ML;

    if ((iTargetCount = ProcessTargetString(sArg, client, a_iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), bTN_Is_ML)) <= 0)
    {
        CReplyToCommand(client, "Not found or invalid parameter.");
        return Plugin_Handled;
    }

    SortedStats(client, a_iTargets, iTargetCount);
    
    if (IsValidClient(client))
    {
        CReplyToCommand(client, "%sCheck console for output!", TAG);
    }

    return Plugin_Handled;
}

public Action Command_ObserveJumps(int client, int args)
{
    if (!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if (!HasFlags(client, g_sAdminFlag))
    {
        CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
        return Plugin_Handled;
    }

    if (args != 1)
    {
        CReplyToCommand(client, "%sUsage: sm_observejumps <#userid|name>", TAG);
        return Plugin_Handled;
    }

    char arg[65];
    GetCmdArg(1, arg, sizeof(arg));

    char target_name[MAX_TARGET_LENGTH];
    int target_list[MAXPLAYERS];
    bool tn_is_ml;

    if (ProcessTargetString(
            arg,
            client,
            target_list,
            MAXPLAYERS,
            COMMAND_FILTER_NO_MULTI,
            target_name,
            sizeof(target_name),
            tn_is_ml) <= 0)
    {
        CReplyToCommand(client, "Player not found.");
        return Plugin_Handled;
    }

    int target = target_list[0];
    
    if (!IsValidClient(target) || !IsPlayerAlive(target))
    {
        CReplyToCommand(client, "%sTarget must be alive!", TAG);
        return Plugin_Handled;
    }

    if (IsPlayerAlive(client) && GetClientTeam(client) != 1)
    {
        Handle menu = CreateMenu(MenuHandler_ObserveChoice);
        SetMenuTitle(menu, "Move to spectator mode to observe jumps?");
        
        char targetUserId[12];
        IntToString(GetClientUserId(target), targetUserId, sizeof(targetUserId));
        
        AddMenuItem(menu, targetUserId, "Move Now");
        AddMenuItem(menu, targetUserId, "Move at Round End");
        AddMenuItem(menu, "cancel", "Cancel");
        SetMenuExitButton(menu, false);
        DisplayMenu(menu, client, 20);
    }
    else
    {
        PerformObservation(client, target);
    }

    return Plugin_Handled;
}

public void MenuHandler_ObserveChoice(Handle menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        GetMenuItem(menu, param2, info, sizeof(info));
        
        if (StrEqual(info, "cancel"))
        {
            return;
        }
        
        int target = GetClientOfUserId(StringToInt(info));
        if (!IsValidClient(target))
        {
            CPrintToChat(client, "%sTarget is no longer available.", TAG);
            return;
        }

        if (param2 == 0)
        {
            ChangeClientTeam(client, 1);
            RequestFrame(Frame_ObserveAfterTeamChange, GetClientUserId(client));
        }
        else if (param2 == 1)
        {
            g_iPendingSpectate[client] = GetClientUserId(target);
            g_bWaitingForRoundEnd[client] = true;
            CPrintToChat(client, "%sYou will be moved to spectator at round end to observe %N.", TAG, target);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
}

public void Frame_ObserveAfterTeamChange(int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidClient(client) && GetClientTeam(client) == 1)
    {
        int target = GetClientOfUserId(g_iPendingSpectate[client]);
        if (IsValidClient(target) && IsPlayerAlive(target))
        {
            PerformObservation(client, target);
        }
        else
        {
            target = FindAlivePlayer();
            if (IsValidClient(target))
            {
                PerformObservation(client, target);
            }
            else
            {
                CPrintToChat(client, "%sNo valid observation targets available.", TAG);
            }
        }
    }
}

void PerformObservation(int client, int target)
{
    SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
    
    float prevPerf = ga_fAvgPerfJumps[target];
    float prevSpeed = ga_fAvgSpeed[target];
    
    PrintToConsole(client, "Now observing %N's jumps:", target);
    PrintToConsole(client, "Current perf: %.1f%%, Current speed: %.1f", prevPerf * 100, prevSpeed);
    
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(GetClientUserId(target));
    pack.WriteFloat(prevPerf);
    pack.WriteFloat(prevSpeed);
    
    CreateTimer(0.5, Timer_UpdateObserver, pack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}


public Action Timer_UpdateObserver(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int target = GetClientOfUserId(pack.ReadCell());
    float prevPerf = pack.ReadFloat();
    float prevSpeed = pack.ReadFloat();
    
    if (!IsValidClient(client) || !IsValidClient(target))
    {
        return Plugin_Stop;
    }
    
    // Check if still observing
    if (GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != target)
    {
        return Plugin_Stop;
    }
    
    float currentPerf = ga_fAvgPerfJumps[target];
    float currentSpeed = ga_fAvgSpeed[target];
    
    if (currentPerf != prevPerf || currentSpeed != prevSpeed)
    {
        char perfChange[32], speedChange[32];
        
        if (currentPerf > prevPerf)
            Format(perfChange, sizeof(perfChange), "↑ +%.1f%%", (currentPerf - prevPerf) * 100);
        else if (currentPerf < prevPerf)
            Format(perfChange, sizeof(perfChange), "↓ -%.1f%%", (prevPerf - currentPerf) * 100);
        else
            Format(perfChange, sizeof(perfChange), "→ 0.0%%");
            
        if (currentSpeed > prevSpeed)
            Format(speedChange, sizeof(speedChange), "↑ +%.1f", currentSpeed - prevSpeed);
        else if (currentSpeed < prevSpeed)
            Format(speedChange, sizeof(speedChange), "↓ -%.1f", prevSpeed - currentSpeed);
        else
            Format(speedChange, sizeof(speedChange), "→ 0.0");
        
        PrintToConsole(client, "Perf: %.1f%% (%s) | Speed: %.1f (%s)", 
            currentPerf * 100, perfChange, 
            currentSpeed, speedChange);
            
        // Update stored values
        pack.Reset();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteCell(GetClientUserId(target));
        pack.WriteFloat(currentPerf);
        pack.WriteFloat(currentSpeed);
    }
    
    return Plugin_Continue;
}

public Action Command_ResetJumps(int client, int iArgs)
{
    if(iArgs != 1)
    {
        CReplyToCommand(client, "%sUsage: sm_resetjumps <#userid|name|@all>", TAG);
        return Plugin_Handled;
    }
    
    if(IsValidClient(client))
    {
        if(!HasFlags(client, g_sAdminFlag) && IsValidClient(client))
        {
            CReplyToCommand(client, "%sYou do not have access to this command!", TAG);
            return Plugin_Handled;
        }
    }
    
    char sArg[65];
    GetCmdArg(1, sArg, sizeof(sArg));

    char sTargetName[MAX_TARGET_LENGTH];
    int a_iTargets[MAXPLAYERS], iTargetCount;
    bool bTN_Is_ML;

    if((iTargetCount = ProcessTargetString(sArg, client, a_iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), bTN_Is_ML)) <= 0)
    {
        CReplyToCommand(client, "Not found or invalid parameter.");
        return Plugin_Handled;
    }
    
    for(int i = 0; i < iTargetCount; i++)
    {
        int target = a_iTargets[i];
        if(IsValidClient(target))
        {
            ResetJumps(target);
            CReplyToCommand(client, "%sStats are now reset for player %N.", TAG, target);
            SetClientNerfed(target, false);
        }
    }

    return Plugin_Handled;
}

void ResetJumps(int target)
{
    for(int i = 0; i < 29; i++)
    {
        gaa_iLastJumps[target][i] = 0;
    }
    ga_bFlagged[target] = false;
    ga_fAvgJumps[target] = 5.0;
    ga_fAvgPerfJumps[target] = 0.3333;
    ga_iPattern[target] = 0;
    ga_iPatternhits[target] = 0;
}

void PerformStats(int client, int target)
{
    char sStats[300];
    GetClientStats(target, sStats, sizeof(sStats));
    if(IsValidClient(client))
    {
        PrintToConsole(client, "Flagged: %i || %s", ga_bFlagged[target], sStats);
    }
    else
    {
        PrintToServer("Flagged: %i || %s", ga_bFlagged[target], sStats);
    }
}

void SortedStats(int client, int[] a_iTargets, int iCount)
{
    float[][] a_fStats = new float[iCount][3];
    int iValidCount = 0;
    for (int i = 0; i < iCount; i++)
    {
        if (IsValidClient(a_iTargets[i]))
        {
            a_fStats[i][0] = ga_fAvgPerfJumps[a_iTargets[i]] * 1000;
            a_fStats[i][1] = ga_fAvgSpeed[a_iTargets[i]];
            a_fStats[i][2] = float(a_iTargets[i]);
            iValidCount++;
        }
        else
        {
            a_fStats[i][0] = -1.0;
            a_fStats[i][1] = -1.0;
            a_fStats[i][2] = float(a_iTargets[i]);
        }
    }
    
    SortCustom2D(a_fStats, iCount, SortStats); 
    
    char[][] a_sStats = new char[iValidCount][512];
    int k = 0;
    char sMsg[512];
    for (int j = 0; j < iCount; j++)
    {
        int target = RoundFloat(a_fStats[j][2]);
        if (IsValidClient(target) && a_fStats[j][0] != -1.0)
        {
            char sStats[512];
            GetClientStats(target, sStats, sizeof(sStats));
            Format(sMsg, sizeof(sMsg), "Flagged: %d || %s", ga_bFlagged[target], sStats);
            strcopy(a_sStats[k], 512, sMsg);
            k++;
        }
    }
    
    if (IsValidClient(client))
    {
        for (int m = 0; m < iValidCount; m++)
        {
            PrintToConsole(client, a_sStats[m]);
        }
    }
    else
    {
        for (int m = 0; m < iValidCount; m++)
        {
            PrintToServer(a_sStats[m]);
        }
    }
}

public int SortStats(int[] x, int[] y, const int[][] aArray, Handle hHndl) 
{ 
    if (view_as<float>(x[0]) > view_as<float>(y[0])) 
    {
        return -1;
    }
    else if (view_as<float>(x[0]) < view_as<float>(y[0])) 
    {
        return 1;
    }
    else
    {
        if (view_as<float>(x[1]) > view_as<float>(y[1]))
        {
            return -1;
        }
        else if (view_as<float>(x[1]) < view_as<float>(y[1]))
        {
            return 1;
        }
        return 0;
    }
}

public int SortPerfs(int[] x, int[] y, const int[][] aArray, Handle hHndl) 
{ 
    if(view_as<float>(x[0]) > view_as<float>(y[0])) 
    {
        return -1;
    }
    return view_as<float>(x[0]) < view_as<float>(y[0]); 
} 

void GetClientStats(int client, char[] sStats, int iLength)
{
    char sMap[128];
    GetCurrentMap(sMap, sizeof(sMap));
    Format(sStats, iLength, "Flagged: %i || Perf: %4.1f || Avg: %-4.1f / %5.1f || %L || Map: %s",
        ga_bFlagged[client], ga_fAvgPerfJumps[client]*100, ga_fAvgJumps[client], ga_fAvgSpeed[client], client, sMap);
    
    Format(sStats, iLength, "%s\nJump Stats: ", sStats);
    for (int i = 0; i < 30; i++)
    {
        int index = (ga_iLastPos[client] - 1 - i + 30) % 30;
        Format(sStats, iLength, "%s%i ", sStats, gaa_iLastJumps[client][index]);
    }
    sStats[strlen(sStats) - 1] = '\0';
    
    Format(sStats, iLength, "%s\nPerf Stats: ", sStats);
    for (int i = 0; i < 30; i++)
    {
        int index = (ga_iLastPos[client] - 1 - i + 30) % 30;
        float perf = gaa_fLastPerfJumps[client][index];
        char perfStr[16];
        Format(perfStr, sizeof(perfStr), "%.1f", perf);
        if (i > 0)
        {
            int prevIndex = (ga_iLastPos[client] - 1 - (i - 1) + 30) % 30;
            float prevPerf = gaa_fLastPerfJumps[client][prevIndex];
            if (perf > prevPerf)
                Format(sStats, iLength, "%s>%s", sStats, perfStr);
            else if (perf < prevPerf)
                Format(sStats, iLength, "%s<%s", sStats, perfStr);
            else
                Format(sStats, iLength, "%s %s", sStats, perfStr);
        }
        else
        {
            Format(sStats, iLength, "%s%s", sStats, perfStr);
        }
    }
    
    // Speed Stats with >/< indicators (most recent first)
    Format(sStats, iLength, "%s\nSpeed Stats: ", sStats);
    for (int i = 0; i < 30; i++)
    {
        int index = (ga_iLastPos[client] - 1 - i + 30) % 30;
        float speed = gaa_fLastSpeeds[client][index];
        char speedStr[16];
        Format(speedStr, sizeof(speedStr), "%.1f", speed);
        if (i > 0)
        {
            int prevIndex = (ga_iLastPos[client] - 1 - (i - 1) + 30) % 30;
            float prevSpeed = gaa_fLastSpeeds[client][prevIndex];
            if (speed > prevSpeed)
                Format(sStats, iLength, "%s>%s", sStats, speedStr);
            else if (speed < prevSpeed)
                Format(sStats, iLength, "%s<%s", sStats, speedStr);
            else
                Format(sStats, iLength, "%s %s", sStats, speedStr);
        }
        else
        {
            Format(sStats, iLength, "%s%s", sStats, speedStr);
        }
    }
}

void GetClientStatsForLogs(int client, char[] sStats, int iLength)
{
    char sMap[128];
    GetCurrentMap(sMap, sizeof(sMap));
    Format(sStats, iLength, "Flagged: %i || Perf: %4.1f || Avg: %-4.1f / %5.1f || %L || Map: %s",
        ga_bFlagged[client], ga_fAvgPerfJumps[client]*100, ga_fAvgJumps[client], ga_fAvgSpeed[client], client, sMap);
    
    Format(sStats, iLength, "%s\nJump Stats: ", sStats);
    for (int i = 0; i < 30; i++)
    {
        int index = (ga_iLastPos[client] - 1 - i + 30) % 30; 
        Format(sStats, iLength, "%s%i ", sStats, gaa_iLastJumps[client][index]);
    }
    // Remove trailing space
    sStats[strlen(sStats) - 1] = '\0';
    
    Format(sStats, iLength, "%s\nPerf Stats: ", sStats);
    for (int i = 0; i < 30; i++)
    {
        int index = (ga_iLastPos[client] - 1 - i + 30) % 30;
        float perf = gaa_fLastPerfJumps[client][index];
        char perfStr[16];
        Format(perfStr, sizeof(perfStr), "%.1f", perf);
        if (i > 0)
        {
            int prevIndex = (ga_iLastPos[client] - 1 - (i - 1) + 30) % 30;
            float prevPerf = gaa_fLastPerfJumps[client][prevIndex];
            if (perf > prevPerf)
                Format(sStats, iLength, "%s>%s", sStats, perfStr);
            else if (perf < prevPerf)
                Format(sStats, iLength, "%s<%s", sStats, perfStr);
            else
                Format(sStats, iLength, "%s %s", sStats, perfStr);
        }
        else
        {
            Format(sStats, iLength, "%s%s", sStats, perfStr);
        }
    }
    
    Format(sStats, iLength, "%s\nSpeed Stats: ", sStats);
    for (int i = 0; i < 30; i++)
    {
        int index = (ga_iLastPos[client] - 1 - i + 30) % 30;
        float speed = gaa_fLastSpeeds[client][index];
        char speedStr[16];
        Format(speedStr, sizeof(speedStr), "%.1f", speed);
        if (i > 0)
        {
            int prevIndex = (ga_iLastPos[client] - 1 - (i - 1) + 30) % 30;
            float prevSpeed = gaa_fLastSpeeds[client][prevIndex];
            if (speed > prevSpeed)
                Format(sStats, iLength, "%s>%s", sStats, speedStr);
            else if (speed < prevSpeed)
                Format(sStats, iLength, "%s<%s", sStats, speedStr);
            else
                Format(sStats, iLength, "%s %s", sStats, speedStr);
        }
        else
        {
            Format(sStats, iLength, "%s%s", sStats, speedStr);
        }
    }
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float a_fVel[3], float a_fAngles[3], int &weapon)
{
    if(IsPlayerAlive(client))
    {
        static int bLastOnGround[MAXPLAYERS + 1];
        static bool bHoldingJump[MAXPLAYERS + 1];
        if(buttons & IN_JUMP)
        {
            if(!bHoldingJump[client])
            {
                bHoldingJump[client] = true;
                ga_iJumps[client]++;
                if(bLastOnGround[client] && (GetEntityFlags(client) & FL_ONGROUND))
                {
                    ga_fAvgPerfJumps[client] = (ga_fAvgPerfJumps[client] * 9.0 + 0) / 10.0;
                }
                else if(!bLastOnGround[client] && (GetEntityFlags(client) & FL_ONGROUND))
                {
                    ga_fAvgPerfJumps[client] = (ga_fAvgPerfJumps[client] * 9.0 + 1) / 10.0;
                }
            }
        }
        else if(bHoldingJump[client]) 
        {
            bHoldingJump[client] = false;
        }
        bLastOnGround[client] = GetEntityFlags(client) & FL_ONGROUND;  
    }
    
    return Plugin_Continue;
}

bool HasFlags(int client, char[] sFlags)
{
    if(StrEqual(sFlags, "public", false) || StrEqual(sFlags, "", false))
    {
        return true;
    }
    else if(StrEqual(sFlags, "none", false))
    {
        return false;
    }
    else if(!client)
    {
        return true;
    }
    else if(CheckCommandAccess(client, "sm_not_a_command", ADMFLAG_ROOT, true))
    {
        return true;
    }
    
    AdminId id = GetUserAdmin(client);
    if(id == INVALID_ADMIN_ID)
    {
        return false;
    }
    int flags, clientflags;
    clientflags = GetUserFlagBits(client);
    
    if(StrContains(sFlags, ";", false) != -1)
    {
        int i = 0, iStrCount = 0;
        while(sFlags[i] != '\0')
        {
            if(sFlags[i++] == ';')
            {
                iStrCount++;
            }
        }
        iStrCount++;
        
        char[][] a_sTempArray = new char[iStrCount][30];
        ExplodeString(sFlags, ";", a_sTempArray, iStrCount, 30);
        bool bMatching = true;
        
        for(i = 0; i < iStrCount; i++)
        {
            bMatching = true;
            flags = ReadFlagString(a_sTempArray[i]);
            for(int j = 0; j <= 20; j++)
            {
                if(bMatching)
                {
                    if(flags & (1<<j))
                    {
                        if(!(clientflags & (1<<j)))
                        {
                            bMatching = false;
                        }
                    }
                }
            }
            if(bMatching)
            {
                return true;
            }
        }
        return false;
    }
    else
    {
        flags = ReadFlagString(sFlags);
        for(int i = 0; i <= 20; i++)
        {
            if(flags & (1<<i))
            {
                if(!(clientflags & (1<<i)))
                {
                    return false;
                }
            }
        }
        return true;
    }
}

bool IsValidClient(int client, bool bAllowBots = false)
{
    if(!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client))
    {
        return false;
    }
    return true;
}

public int Native_ClientDetected(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if(!IsValidClient(client))
    {
        return 0;
    }

    int length;
    GetNativeStringLength(2, length);
    char[] reason = new char[length+1];
    GetNativeString(2, reason, length+1);

    char sStats[512];
    GetClientStats(client, sStats, sizeof(sStats));

    // Call forward
    Call_StartForward(g_hOnClientDetected);
    Call_PushCell(client);
    Call_PushString(reason);
    Call_PushString(sStats);
    Call_Finish();

    // Send Discord notification
    Discord_Notify(client, reason, sStats);

    // Show chat message
    char sSteamID[32];
    if(GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
    {
        CPrintToChatAll("%s%s%N [%s] has been detected for %s!", 
            TAG, 
            g_bCSGO ? CSGO_RED : CSS_RED, 
            client, 
            sSteamID,
            reason);
    }
    else
    {
        CPrintToChatAll("%s%s%N has been detected for %s!", 
            TAG, 
            g_bCSGO ? CSGO_RED : CSS_RED, 
            client, 
            reason);
    }

    // Nerf the player
    SetClientNerfed(client, true);

    return 1;
}

public int Native_ClientNerfed(Handle plugin, int numParams) 
{ 
	int client = GetNativeCell(1); 
	bool set = numParams >= 2 ? GetNativeCell(2) : false;

	bool result = SetClientNerfed(client, set);

	Call_StartForward(g_hOnClientNerfed);
	Call_PushCell(client);
	Call_PushCell(set);
	Call_Finish();

	return result;
}


int FindAlivePlayer()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && IsPlayerAlive(i))
        {
            return i;
        }
    }
    return -1;
}

/*
CHANGE LOG
----------------------------
1.3 05/17/14
	* Initial release.
	* Changelog started.
1.4:
	* Fixed issue with players still being flagged for hyperscroll after rejoining server (due to not clearing the "3 rounds in a row" booleans).
	* Made sm_jumps command public so that regular players can use it (per request).
1.5:
	* Removed commands to target all and converted to multi-target filters.
	* Converted all commands to console commands and to use the "HasFlags" filter.
	* Added a few lines to ignore bots.
	* Added a cvar for the number of identical jump numbers required to flag someone for pattern jumps. It was hard coded at 15 before.
	* Added cvar to set required flags for using stats commands.
	* When players are flagged and admins get the chat message, it now prints the stats to chat as well.
1.6:
	* Added code to make it so that after players are logged, it will add another log if they make it to higher perf rates, although there will still be a small cooldown time (10 sec).
	* Made a parallel version with no admin menu, since the admin menu can be made through the adminmenu_custom.txt file from sourcemod.
	* Reformatted stats output.
1.7:
	* Removed cool down time on re-log functionality, converting it to a cvar of what amount of a higher perf it must be to re-log.
	* Added CS:GO Support (chat colors, etc).
1.8:
	* Added tag at the end of logs if they were already flagged, and the log is just due to higher perf while still passing threshold.
	* Added check on round start for all players fps_max values to be above or equal to a set threshold (60 by default).
	* Fixed opposite sign needed for relogging if perf higher than when logged + cvar tolerance.
1.8.2.nm:
	* Added notifications for admins 30 seconds after connect to tell them if a player was flagged before they joined.
1.9.0.nm:
	* Removed <tog> include.
	* Changed g_iDisableAdminMsgs to boolean, since it was being used like one (only two options).
	* Replaced global cache of game folder name (for checking if CS:GO) with global cached boolean, thus not needing to check the game name each time, but rather check boolean value.
	* Cleaned up variable names all throughout the plugin and did general cleanup, deleting unneccesary code (havent touched this plugin in a long time).
1.9.1.nm
	* Broke apart GetClientStats formatting function to enforce 32 arg max (it had 35).
	* Converted to new syntax.
1.9.2
	* Made admin notification after connecting only show if a player has been flagged.
	* Added code to create log folder if it doesn't exist.
1.9.3
	* Fixed logs indication regarding whether a player has "already been flagged this map".
	* Changed console stats output from using %d to use %i for the "flagged" boolean output. Shouldn't make a difference as I can see, but made the change due to a report of the flag not functioning properly.
1.9.4
	* Added cvar for admin notification flags.
1.9.5
	* Minor edit to low fps_max detection - zero values were supposed to be allowed, but slipped through due to float decimals extending past string compared against. Fixed.
1.10.0
	* Added options to use sourcebans to ban for detections (defaults to bans for hacks only - scripts, hyperscroll, and fps_max abuse default to no ban).
1.10.1
	* Added alternative if sourcebans is not enabled. Renamed ban length CVars to no longer imply sourcebans (SB).
1.10.2
	* Moved notifications to its own flag cvar (tjs_flag_notification). Renamed flag cvars to update descriptions. Enforced new cvar.
	* Deleted tjs_gen_notifications, which is now redundant to tjs_flag_notification (set to "none" to disable - equivalent to tjs_gen_notifications 0).

1.10.3
	* Added 2 natives to allow other plugins to interact with this plugin.

1.10.4
	* Added logic to slow down bhop cheaters right after they are detected, so that they cannot continue to use their cheats.

1.10.5
	* Added a command called sm_observejumps.

1.10.6
	* Let the admin choose whether to move to spectator mode immediately or at round end to observe cheaters.

1.10.7 
    * Added Discord notifications for client detections.

1.10.8
    * Added some helper functions to get client count, get server name, get map name, etc.

1.10.9
    * Fixed a bug where it was showing "1" instead of client name.

1.11.0
    * Fixed discord notifications not working properly.

1.11.1
    * Added two commands: sm_capplayer and sm_removenerfs.
*/
