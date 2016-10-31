/*
	GhostStrike - Custom CS:GO Gamemode
	Copyright (C) 2016 Kinsi

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#pragma semicolon 1
#include <sourcemod>
#include <csgo_colors>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#pragma newdecls required

#define PLUGIN_VERSION "1.2.3"

public Plugin myinfo = {
	name = "GhostStrike",
	author = "Kinsi55",
	description = "Custom CS:GO gamemode",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/kinsi"
}

#define COLLISION_GROUP_PUSHAWAY	17	// Nonsolid on client and server, pushaway in player code
#define COLLISION_GROUP_DEBRIS_TRIGGER		2	// Same as debris, but hits triggers
#define COLLISION_GROUP_PLAYER				5
#define SOLID_BBOX								2	// an AABB
#define EF_NODRAW									1 << 5
#define NumSavedPlantPositions		8

int BeamModelIndex = -1;
int no_z_BeamModelIndex = -1;
int g_bombZoneEnt = -1;

//Game States
bool isPlanted = false;
bool isWarmup = true;
int bombGiveTimer = -1;
bool unhideCT[MAXPLAYERS+1] = {false, ...};

float previousPlants[NumSavedPlantPositions][3];
int previousPlantsIndex = 0;
int plantBlockSphereScroll = 0;

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
ConVar g_hFullNoblock = null;
ConVar g_hPlantPreventRadius = null;
ConVar g_hHPBonusFactor = null;

void resetPreviousPlants(bool clearArray = false) {
	previousPlantsIndex = 0;
	if(clearArray) for(int i = 0; i < NumSavedPlantPositions; i++){
		previousPlants[i][0] = 0.0;
		previousPlants[i][1] = 0.0;
		previousPlants[i][2] = 0.0;
	}
}

public void OnPluginStart() {
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_freeze_end", Event_FreezeTimeEnd);
	HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_PostNoCopy);
	HookEvent("bomb_beginplant", Event_BombPlant, EventHookMode_Post);
	HookEvent("cs_intermission", Event_Intermission, EventHookMode_PostNoCopy);
	HookEvent("announce_phase_end", Event_PhaseEnd, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

	AddNormalSoundHook(OnNormalSoundPlayed);

	CreateTimer(1.0, OnSecond, _, TIMER_REPEAT);
	CreateTimer(0.5, OnSphereTimer, _, TIMER_REPEAT);

	//Cvars
	CreateConVar("ghoststrike_version", PLUGIN_VERSION, "GhostStrike Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hEnabled = CreateConVar("ghoststrike_enable", "1", "Enables/disables GhostStrike", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hEnabled.AddChangeHook(EnableCvarChange);

	g_hDisableOnEnd = CreateConVar("ghoststrike_autodisable", "0", "Automatically disable the gamemode on Intermission (Game end)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hBlockInvisibleDamage = CreateConVar("ghoststrike_block_invisible_damage", "0", "Block damage dealt to invisible counterterrorists", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hAllowTrolling = CreateConVar("ghoststrike_allow_trolling", "1", "Allow invisible Counter Terrorists to show themselves while holding R(Reload)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hBlockAllInvisibleSounds = CreateConVar("ghoststrike_block_all_invisible_sounds", "0", "Block all Sounds created by invisible terrorists (Not just steps, but jumps etc as well)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hC4Timer = CreateConVar("ghoststrike_c4timer", "60", "This value is piped into the mp_c4timer cvar when the gamemode is enabled", FCVAR_NONE, true, 10.0);
	g_hDrawBombLine = CreateConVar("ghoststrike_show_bomb_guidelines", "1", "Draw a Line from every Counterterrorist to the bomb when it is planted", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hBombGiveDelay = CreateConVar("ghoststrike_bomb_delay", "30", "The Delay in seconds after the roundstart when the bomb will be given out", FCVAR_NONE, true, 20.0, true, 60.0);
	g_hFullNoblock = CreateConVar("ghoststrike_full_noblock", "0", "If full noblock should be active instead of using bouncy collisions", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hPlantPreventRadius = CreateConVar("ghoststrike_plant_block_radius", "350", "Minimum spherical distance you need to have to previous plant-positions to be able to plant (0 = Off) to prevent re-use of plant spots.", FCVAR_NONE, true, 0.0, true, 800.0);
	g_hHPBonusFactor = CreateConVar("ghoststrike_ct_hp_bonus", "15", "Multiplicator for the HP bonus for CT's for each Terrorist after the fifth one (0 = off).", FCVAR_NONE, true, 0.0, true, 50.0);

	AutoExecConfig(true, "ghoststrike");

	//Read Enabled Cvar on Load
	if(g_hEnabled.BoolValue) EnableCvarChange(g_hEnabled, "", "1");

	//Allows for Hot-Reloading of the plugin
	for(int i = 1; i <= MaxClients; i++)
		if(IsValidClient(i)) OnClientPutInServer(i);

	LoadTranslations("ghoststrike.phrases");

	resetPreviousPlants(true);
}

public void OnPluginEnd() { EnableCvarChange(g_hEnabled, "", "0"); }

public void OnMapEnd() { g_bombZoneEnt = -1; resetPreviousPlants(true); }

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
			resetPreviousPlants(true);

			//Make everyone fully opaque on disable
			for(int i = 1; i < MaxClients; i++) if(IsValidClient(i)) {
				SetEntityRenderColor(i, 255, 255, 255, 255);
				SetEntProp(i, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PLAYER);
			}
		}
	}
}

public void Event_Intermission(Handle event, const char[] name, bool dontBroadcast) {
	if(g_hDisableOnEnd.BoolValue) g_hEnabled.SetBool(false);
	resetPreviousPlants(true);
}

public void Event_PhaseEnd(Handle event, const char[] name, bool dontBroadcast) {
	resetPreviousPlants(true);
}

public Action OnNormalSoundPlayed(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed) {
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
	PrecacheSound("buttons/button8.wav", true);

	BeamModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	no_z_BeamModelIndex = PrecacheModel("materials/sprites/radar.vmt", true);
}

public void OnConfigsExecuted(){
	if(active) init();
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	bombGiveTimer = -1;
	//When the Timelimit is 999 it (apparently) means, warmup.
	//Please do not set a roundtime of 999 Seconds, or if you read this and know better, tell me :^)
	if(!active || (isWarmup = event.GetInt("timelimit") == 999)) return;

	isPlanted = false;
	int i;
	int CT_HP_Bonus = GetTeamClientCount(CS_TEAM_T);
	if(CT_HP_Bonus > 5) CT_HP_Bonus *= g_hHPBonusFactor.IntValue; else CT_HP_Bonus = 0;

	for(i = 1; i < MaxClients; i++) {
		if(IsValidClient(i)) if(GetClientTeam(i) == CS_TEAM_CT) {
			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %t", g_hBlockInvisibleDamage.BoolValue ? "Instructions_CT_1_Invincible" : "Instructions_CT_1_Not_Invincible");

			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %t", g_hBlockAllInvisibleSounds.BoolValue ? "Instructions_CT_2_NoSounds" : "Instructions_CT_2_NoSteps");

			if(g_hAllowTrolling.BoolValue) CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %t", "Instructions_CT_TrollingAllowed");

			//Prevent the client from Attacking
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", 99999999.0);

			if(CT_HP_Bonus > 100) SetEntityHealth(i, CT_HP_Bonus);
		} else {
			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %t", g_hBlockInvisibleDamage.BoolValue ? "Instructions_T_1_Invincible" : "Instructions_T_1_Not_Invincible");

			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] %t", "Instructions_T_2_BombPlant");
		}
	}

	i = -1; //Incase its a hostage map, kill all hostages
	while((i = FindEntityByClassname(i, "hostage_entity")) != -1)
		AcceptEntityInput(i, "Kill");
}

public Action Event_FreezeTimeEnd(Event event, const char[] name, bool dontBroadcast) {
	if(active) bombGiveTimer = g_hBombGiveDelay.IntValue;
}

public void OnClientDisconnect(int client) {
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if(!active || isWarmup || !g_hAllowTrolling.BoolValue)
		return Plugin_Continue;

	if(IsValidClient(client) && GetClientTeam(client) == CS_TEAM_CT) {
		bool shouldUnhide = !isPlanted && buttons & IN_RELOAD && IsPlayerAlive(client);
		if(shouldUnhide != unhideCT[client]) {
			if(shouldUnhide){
				PrintHintText(client, "%t", "Trolling_NowVisible");
				SetEntityRenderColor(client, 255, 255, 255, 255);
			}else if(!isPlanted){
				PrintHintText(client, "%t", "Trolling_NowHidden");
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

int bombClient = 1;

public Action OnSecond(Handle timer) {
	if(active && !isWarmup && bombGiveTimer > 0) {
		if(GetTeamClientCount(CS_TEAM_T) > 0)
			PrintHintTextToAll("%t", "Bomb_DeployIn", --bombGiveTimer);
	} else if(active && bombGiveTimer == 0) {
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

			PrintHintTextToAll("%s %t!", escapedName, "Bomb_ReceivedBy");
			bombClient = clientArrayIndex;
			CGOPrintToChatAll("[{GREEN}GhostStrike{DEFAULT}]{RED} %N{DEFAULT} %t!", clientArrayIndex, "Bomb_ReceivedBy");

			GivePlayerItem(clientArrayIndex, "weapon_c4");
			bombGiveTimer = -1;
		}
	}
}
float planterPos[3];

public Action OnSphereTimer(Handle timer) {
	int tehRadius = g_hPlantPreventRadius.IntValue;

	if(active && !isWarmup && bombGiveTimer == -1 && tehRadius > 0 && !isPlanted && IsValidClient(bombClient) && IsPlayerAlive(bombClient)) {
		int tehDiameter = tehRadius * 2;
		const float numRings = 13.0;
		float numHalfRings = (numRings - 1) / 2;

		float tehFreeSpace = float(tehRadius) / numRings;
		plantBlockSphereScroll = (plantBlockSphereScroll + 3) % RoundFloat(tehFreeSpace);
		float offset_abs = float(plantBlockSphereScroll) / tehFreeSpace;

		GetClientAbsOrigin(bombClient, planterPos);

		for(int i = 0; i < NumSavedPlantPositions; i++) {
			if(previousPlants[i][0] != 0.0 && GetVectorDistance(previousPlants[i], planterPos) <= tehRadius * 2) {
				planterPos = previousPlants[i];
				planterPos[2] += tehRadius;

				TE_SetupBeamPoints(planterPos, previousPlants[i], BeamModelIndex, 0, 0, 0, 0.5, 1.0, 4.0, 1, 0.0, {128, 128, 1, 200}, 10);
				TE_SendToClient(bombClient);

				//Do you want this?
				//I will release it in form of an include soon with integrated auto-updating etc.
				//Stay tuned!
				for(float x = -numHalfRings; x <= numHalfRings; x += 1.0) {
					float pos = (tehDiameter / numRings) * (x + offset_abs);

					planterPos[2] = previousPlants[i][2] + pos;

					if(pos < 0) pos *= -1;
					pos = tehRadius - pos;

					float t2 = x + offset_abs;

					t2 = t2 / numHalfRings;
					if(t2 > 1.0 || t2 < -1.0) t2 = 1.0;

					float y = tehDiameter * SquareRoot(1.0 - (t2 * t2));

					if(y < 2) continue;

					TE_SetupBeamRingPoint(planterPos, y, y + 0.1, BeamModelIndex, 0, 0, 0, 0.5, 2.0, 0.0, {128, 255, 0, 170}, 0, 0);
					TE_SendToClient(bombClient);

					TE_SetupBeamRingPoint(planterPos, y, y + 0.1, no_z_BeamModelIndex, 0, 0, 0, 0.5, 2.0, 0.0, {0, 255, 0, 60}, 10, 0);
					TE_SendToClient(bombClient);
				}
			}
		}
	}
}

float plantedBombOrigin[3];

public void Event_BombPlant(Event event, const char[] name, bool dontBroadcast) {
	if(active && !isWarmup) {
		bombClient = GetClientOfUserId(event.GetInt("userid"));

		GetClientAbsOrigin(bombClient, plantedBombOrigin);

		for(int i = 0; i < NumSavedPlantPositions; i++) {
			if(previousPlants[i][0] != 0.0 && GetVectorDistance(previousPlants[i], plantedBombOrigin) <= g_hPlantPreventRadius.FloatValue) {
				SetEntPropFloat(GetEntPropEnt(bombClient, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_fArmedTime", 99999999.0);

				EmitSoundToClient(bombClient, "buttons/button8.wav");
				PrintCenterText(bombClient, "%t", "Cannot_Plant_Region");
				break;
			}
		}
	}
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast) {
	if(!active || isWarmup) return;

	isPlanted = true;

	int c4 = FindEntityByClassname(-1, "planted_c4");

	if(c4 != -1) {
		GetEntPropVector(c4, Prop_Send, "m_vecOrigin", plantedBombOrigin);
		previousPlants[previousPlantsIndex++] = plantedBombOrigin;
		if(previousPlantsIndex >= NumSavedPlantPositions) previousPlantsIndex = 0;
	}

	for(int i = 1; i < MaxClients; i++) {
		if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_CT) {
			//Allow CT's to shoot as soon as the bomb is planted.
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", 0.0);

			SetEntityRenderColor(i, 255, 255, 255, 255);

			if(c4 != -1 && g_hDrawBombLine.BoolValue && BeamModelIndex > 0)
				//Delay Beam otherwise game might crash because Source.
				CreateTimer(0.1, DelayedUserNotif, i);

			if(GetClientHealth(i) > 100) SetEntityHealth(i, 100);
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
		SetEntProp(client, Prop_Data, "m_CollisionGroup", g_hFullNoblock.BoolValue ? COLLISION_GROUP_DEBRIS_TRIGGER : COLLISION_GROUP_PUSHAWAY);

		if(GetClientTeam(client) == CS_TEAM_T) {
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
		DispatchSpawn(g_bombZoneEnt); ActivateEntity(g_bombZoneEnt);

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