#pragma semicolon 1
#include <sourcemod>
#include <csgo_colors>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#pragma newdecls required

#define PLUGIN_VERSION "1.2.0"

public Plugin myinfo = {
	name = "GhostStrike",
	author = "Kinsi55",
	description = "Custom CS:GO gamemode",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/kinsi"
}

#define COLLISION_GROUP_PUSHAWAY	17	// Nonsolid on client and server, pushaway in player code
#define SOLID_BBOX								2	// an AABB
#define EF_NODRAW									1 << 5

int BeamModelIndex = -1;
int g_bombZoneEnt = -1;

//Game States
bool isPlanted = false;
bool isWarmup = true;
int bombGiveTimer = -1;
bool unhideCT[MAXPLAYERS+1] = {false, ...};

//Settings / Cvars
bool active = false;

//Cvar Handles
ConVar g_hEnabled = null;
ConVar g_hDisableOnEnd = null;
ConVar g_hBlockInvisibleDamage = null;
ConVar g_hAllowTrolling = null;
ConVar g_hBlockAllInvisibleSounds = null;
ConVar g_hBombGiveDelay = null;
ConVar g_hC4Timer = null;
ConVar g_hDrawBombLine = null;

public void OnPluginStart() {
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_freeze_end", Event_FreezeTimeEnd);
	HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_PostNoCopy);
	HookEvent("cs_intermission", Event_Intermission, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

	AddNormalSoundHook(OnNormalSoundPlayed);

	CreateTimer(1.0, OnSecond, _, TIMER_REPEAT);

	//Cvars
	CreateConVar("ghoststrike_version", PLUGIN_VERSION, "GhostStrike Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hEnabled = CreateConVar("ghoststrike_enable", "1", "Enables/disables GhostStrike.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hEnabled.AddChangeHook(EnableCvarChange);

	g_hDisableOnEnd = CreateConVar("ghoststrike_autodisable", "0", "Automatically disable the gamemode on Intermission (Game end)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hBlockInvisibleDamage = CreateConVar("ghoststrike_block_invisible_damage", "0", "Block damage dealt to invisible counterterrorists", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hAllowTrolling = CreateConVar("ghoststrike_allow_trolling", "1", "Allow invisible Counter Terrorists to show themselves while holding R(Reload)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hBlockAllInvisibleSounds = CreateConVar("ghoststrike_block_all_invisible_sounds", "0", "Block all Sounds created by invisible terrorists (Not just steps, but jumps etc as well)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hC4Timer = CreateConVar("ghoststrike_c4timer", "60", "This value is piped into the mp_c4timer cvar when the gamemode is enabled", FCVAR_NONE, true, 10.0);
	g_hDrawBombLine = CreateConVar("ghoststrike_show_bomb_guidelines", "1", "Draw a Line from every Counterterrorist to the bomb when it is planted", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hBombGiveDelay = CreateConVar("ghoststrike_bomb_delay", "30", "The Delay in seconds after the roundstart when the bomb will be given out", FCVAR_NONE, true, 20.0, true, 60.0);

	AutoExecConfig(true, "ghoststrike");

	//Read Enabled Cvar on Load
	if(g_hEnabled.BoolValue) EnableCvarChange(g_hEnabled, "", "1");

	//Allows for Hot-Reloading of the plugin
	for(int i = 1; i <= MaxClients; i++)
		if(IsValidClient(i)) OnClientPutInServer(i);

	LoadTranslations("ghoststrike.phrases");
}

public void OnPluginEnd() {
	//Kill the possibly available global bombzone on Unload
	if(IsValidEntity(g_bombZoneEnt)) AcceptEntityInput(g_bombZoneEnt, "Kill");
	g_bombZoneEnt = -1;
}

public void OnMapEnd() {
	if(IsValidEntity(g_bombZoneEnt)) AcceptEntityInput(g_bombZoneEnt, "Kill");
	g_bombZoneEnt = -1;
}

public void EnableCvarChange(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	bool newState = StringToInt(newvalue) ? true : false;
	if(active != newState) {
		active = newState;
		//Call Init on Enable
		if(newState) init();
		//Remove the Global Bombzone on Disable
		else{
			if(IsValidEntity(g_bombZoneEnt)) AcceptEntityInput(g_bombZoneEnt, "Kill");
			g_bombZoneEnt = -1;
		}
	}
}

public void Event_Intermission(Handle event, const char[] name, bool dontBroadcast) {
	if(g_hDisableOnEnd.BoolValue) g_hEnabled.SetBool(false);
}

public Action OnNormalSoundPlayed(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed){
//public Action OnNormalSoundPlayed(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch)
	if(!active || isWarmup || isPlanted || entity < 1 || entity > 64)
		return Plugin_Continue;

	//Only block footsteps. Landing sounds are still supposed to be played per concept.
	if(IsValidClient(entity) && GetClientTeam(entity) == CS_TEAM_CT && !unhideCT[entity] && (g_hBlockAllInvisibleSounds.BoolValue || StrContains(sample, "footsteps") != -1)) {
		int ClientArrayIndex = 0;

		for(int i = 0; i < numClients; i++) {
			if(IsValidClient(clients[i]) && GetClientTeam(clients[i]) != CS_TEAM_T)
				clients[ClientArrayIndex++] = clients[i];
		}

		//Do any clients even still receive this sound?
		if(ClientArrayIndex != 0) {
			numClients = ClientArrayIndex;
			return Plugin_Changed;
		}else return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void OnMapStart() {
	PrecacheModel("models/props/cs_office/vending_machine.mdl", true);

	BeamModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
}

public void OnConfigsExecuted(){
	if(active) init();
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	//When the Timelimit is 999 it (apparently) means, warmup.
	//Please do not set a roundtime of 999 Seconds, or if you read this and know better, tell me :^)
	if(!active || (isWarmup = event.GetInt("timelimit") == 999)) return;

	isPlanted = false;
	int i;

	for(i = 1; i < MaxClients; i++) {
		if(IsValidClient(i)) if(GetClientTeam(i) == CS_TEAM_CT) {
			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %T", g_hBlockInvisibleDamage.BoolValue ? "Instructions_CT_1_Invincible" : "Instructions_CT_1_Not_Invincible", i);

			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %T", g_hBlockAllInvisibleSounds.BoolValue ? "Instructions_CT_2_NoSounds" : "Instructions_CT_2_NoSteps", i);

			if(g_hAllowTrolling.BoolValue) CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %T", "Instructions_CT_TrollingAllowed", i);

			//Prevent the client from Attacking
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", 99999999.0);
		} else {
			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %T", g_hBlockInvisibleDamage.BoolValue ? "Instructions_T_1_Invincible" : "Instructions_T_1_Not_Invincible", i);

			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %T", "Instructions_T_2_BombPlant", i);
		}
	}

	i = 0; //Incase its a hostage map, kill all hostages
	while((i = FindEntityByClassname(i, "hostage_entity")) != -1)
		AcceptEntityInput(i, "Kill");
}

public Action Event_FreezeTimeEnd(Event event, const char[] name, bool dontBroadcast) {
	if(active) bombGiveTimer = g_hBombGiveDelay.IntValue;
}

public void OnClientDisconnect(int client){
	unhideCT[client] = false;
}

//Dem Hooks
public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThinkPost, Hook_PostThinkPost);
	SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
	SDKHook(client, SDKHook_WeaponCanSwitchToPost, Hook_WeaponCanSwitchToPost);
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
}
//Hiding CT's to T's pre-plant
public Action Hook_SetTransmit(int entity, int client) {
	if(!active || isWarmup || isPlanted || client < 1 || client > 64)
		return Plugin_Continue;

	if(IsValidClient(entity) && GetClientTeam(entity) == CS_TEAM_CT && !unhideCT[entity] && IsValidClient(client) && GetClientTeam(client) == CS_TEAM_T)
		return Plugin_Stop;

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]){
	if(!active || isWarmup || !g_hAllowTrolling.BoolValue)
		return Plugin_Continue;

	if(IsValidClient(client) && GetClientTeam(client) == CS_TEAM_CT){
		bool shouldUnhide = !isPlanted && buttons & IN_RELOAD;
		if(shouldUnhide != unhideCT[client]){
			if(shouldUnhide){
				PrintHintText(client, "%T", "Trolling_NowVisible", client);
				SetEntityRenderColor(client, 255, 255, 255, 255);

			}else if(!isPlanted){
				PrintHintText(client, "%T", "Trolling_NowHidden", client);
				SetEntityRenderColor(client, 255, 255, 255, 100);
			}

			unhideCT[client] = shouldUnhide;
		}
	}

	return Plugin_Continue;
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup) {
	if(!g_hBlockInvisibleDamage.BoolValue || !active || isWarmup || isPlanted || attacker < 1 || attacker > 64)
		return Plugin_Continue;

	if(IsValidClient(victim) && GetClientTeam(victim) == CS_TEAM_CT)
		return Plugin_Stop;

	return Plugin_Continue;
}

//Hide CT's on the Radar because apparently blocking the Transmit is not enough
public void Hook_PostThinkPost(int client) {
  if(active && !isWarmup && !isPlanted && !unhideCT[client] && GetClientTeam(client) == CS_TEAM_CT)
  	SetEntProp(client, Prop_Send, "m_bSpotted", 0);
}

//Re-Set m_flNextAttack on weaponswitch
public void Hook_WeaponCanSwitchToPost(int client) {
	if(active && !isWarmup && !isPlanted && GetClientTeam(client) == CS_TEAM_CT)
		//Needs to be delayed by a tick, otherwise it wont work, eventhough its a post-hook.
		CreateTimer(0.0, Timer_RestrictNextAttack, client);
}

public Action Timer_RestrictNextAttack(Handle timer, int client) {
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", 99999999.0);
}

public Action OnSecond(Handle timer) {
	if(bombGiveTimer > 0) {
		if(GetTeamClientCount(CS_TEAM_T) > 0)
			PrintHintTextToAll("%T", "Bomb_DeployIn", LANG_SERVER, --bombGiveTimer);
	} else if(bombGiveTimer == 0) {
		int clientArray[MAXPLAYERS+1];
		int clientArrayIndex = 0;
		//Arrify all T Players
		for(int i = 1; i < MaxClients; i++) {
			if(IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T)
				clientArray[clientArrayIndex++] = i;
		}

		if(clientArrayIndex > 0) {
			clientArrayIndex = clientArray[GetRandomInt(0, clientArrayIndex - 1)];

			char escapedName[128]; Format(escapedName, sizeof(escapedName), "%N", clientArrayIndex);
			ReplaceString(escapedName, sizeof(escapedName), "<", "&lt;", true); ReplaceString(escapedName, sizeof(escapedName), ">", "&gt;", true);

			Format(escapedName, sizeof(escapedName), "<font color='#ff0000'>%s</font>", escapedName);

			PrintHintTextToAll("%s %T!", escapedName, "Bomb_ReceivedBy", LANG_SERVER);
			CGOPrintToChatAll("[{GREEN}GhostStrike{DEFAULT}]{RED} %N{DEFAULT} %T!", clientArrayIndex, "Bomb_ReceivedBy", LANG_SERVER);

			GivePlayerItem(clientArrayIndex, "weapon_c4");
			bombGiveTimer = -1;
		}
	}
}

float plantedBombOrigin[3];

public void Event_BombPlanted(Handle event, const char[] name, bool dontBroadcast) {
	if(!active || isWarmup) return;

	isPlanted = true;

	int c4 = g_hDrawBombLine.BoolValue ? FindEntityByClassname(-1, "planted_c4") : -1;

	if(c4 != -1) GetEntPropVector(c4, Prop_Send, "m_vecOrigin", plantedBombOrigin);

	for(int i = 1; i < MaxClients; i++) {
		if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_CT) {
			//Allow CT's to shoot as soon as the bomb is planted.
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", 0.0);

			SetEntityRenderColor(i, 255, 255, 255, 255);

			// PrintHintText(i, "<font color='#ffff00'>You are now visible to the Terrorists and can attack!</font>!");

			if(c4 != -1 && BeamModelIndex > 0)
				//Delay Beam otherwise game might crash because Source.
				CreateTimer(0.1, DelayedUserNotif, i);
		}
	}
}

public Action DelayedUserNotif(Handle timer, int client) {
	if(IsValidClient(client)){
		float clientOrigin[3];
		GetClientEyePosition(client, clientOrigin);
		clientOrigin[2] -= 4.0;

		TE_SetupBeamPoints(clientOrigin, plantedBombOrigin, BeamModelIndex, 0, 0, 0, 20.0, 5.0, 0.1, 1, 0.0, {128, 1, 1, 255}, 10);
		TE_SendToClient(client);

		clientOrigin[0] = plantedBombOrigin[0];
		clientOrigin[1] = plantedBombOrigin[1];
		clientOrigin[2] = plantedBombOrigin[2] + 32.0;

		TE_SetupBeamPoints(clientOrigin, plantedBombOrigin, BeamModelIndex, 0, 0, 0, 20.0, 3.0, 0.1, 1, 0.0, {128, 128, 1, 255}, 10);
		TE_SendToClient(client);
	}
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	if(active && !isWarmup) {
		int client = GetClientOfUserId(event.GetInt("userid"));
		//Setting the collision mode to Pushaway. This allows for "bouncy" collisions,
		//as well as prevents people from boosting into difficult to reach spots
		SetEntProp(client, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PUSHAWAY);

		if(GetClientTeam(client) == CS_TEAM_T){
			CreateTimer(1.0, DelayedBombRemoval, client);
		} else if(GetClientTeam(client) == CS_TEAM_CT) {
			SetEntityRenderMode(client, RENDER_TRANSCOLOR);
			SetEntityRenderColor(client, 255, 255, 255, 100);
		}
	}
}

public Action DelayedBombRemoval(Handle timer, int client) {
	if(!IsValidClient(client)) return;
	//Juuuust to be sure.
	int C4 = GetPlayerWeaponSlot(client, CS_SLOT_C4);
	if(C4 > MaxClients && IsValidEntity(C4)) {
		CS_DropWeapon(client, C4, false, true);
		AcceptEntityInput(C4, "kill");
	}
}

/* Internal Functions */

public void init() {
	if(IsValidEntity(g_bombZoneEnt)) return;

	//Create new global bomb zone
	if(IsModelPrecached("models/props/cs_office/vending_machine.mdl") && (g_bombZoneEnt = CreateEntityByName("func_bomb_target")) != -1) {
		DispatchSpawn(g_bombZoneEnt);
		ActivateEntity(g_bombZoneEnt);

		TeleportEntity(g_bombZoneEnt, view_as<float>({0.0, 0.0, 0.0}), NULL_VECTOR, NULL_VECTOR);

		//I dont even know. Apparently its needed.
		SetEntityModel(g_bombZoneEnt, "models/props/cs_office/vending_machine.mdl");

		//-32k - 32k, Max. CS:GO Map size. Should be 'nuff
		SetEntPropVector(g_bombZoneEnt, Prop_Send, "m_vecMins", view_as<float>({-32767.0, -32767.0, -32767.0}));
		SetEntPropVector(g_bombZoneEnt, Prop_Send, "m_vecMaxs", view_as<float>({32767.0,  32767.0,  32767.0}));

		SetEntProp(g_bombZoneEnt, Prop_Send, "m_nSolidType", SOLID_BBOX);

		SetEntProp(g_bombZoneEnt, Prop_Send, "m_fEffects", GetEntProp(g_bombZoneEnt, Prop_Send, "m_fEffects") | EF_NODRAW);

		ServerCommand("mp_give_player_c4 0");
		ServerCommand("mp_c4timer %i", g_hC4Timer.IntValue);
		ServerCommand("mp_restartgame 1");
		ServerCommand("sv_disable_immunity_alpha 1"); //Allow Ghosts to be semi-transparent

		LogMessage("Initialized on current Map");
	} else {
		LogError("Could not Init because spawning the global Bombzone failed!");
		g_hEnabled.SetBool(false);
	}
}

public bool IsValidClient(int client){
	return client <= MaxClients && client > 0 && IsClientConnected(client) && IsClientInGame(client);
}