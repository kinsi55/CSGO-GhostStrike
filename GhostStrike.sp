#pragma semicolon 1
#include <sourcemod>
#include <csgo_colors>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>

#define PLUGIN_VERSION "1.0.4"

public Plugin:myinfo = {
	name = "GhostStrike",
	author = "Kinsi55",
	description = "Custom CS:GO gamemode",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/kinsi"
}

#define COLLISION_GROUP_PUSHAWAY	17	// Nonsolid on client and server, pushaway in player code
#define SOLID_BBOX								2	// an AABB
#define EF_NODRAW									1 << 5
new BeamModelIndex;

//Game States
new bool:isPlanted = false,
		bool:isWarmup = true,
		bombGiveTimer = -1,
		bool:inited = false,
		bool:unhideCT[MAXPLAYERS+1] = {false, ...};

//Settings / Cvars
new bool:active = false,
		bool:blockInvisibleDamage = false,
		bool:disableOnIntermission = false,
		bool:allowTrolling = false,
		bool:blockAllInvisibleSounds = false,
		bool:drawBombGuideLines = true,
		bombGiveDelay = 40,
		c4TimerTarget = 60;

//Cvar Handles
new Handle:g_hEnabled = INVALID_HANDLE,
		Handle:g_hDisableOnEnd = INVALID_HANDLE,
		Handle:g_hBlockInvisibleDamage = INVALID_HANDLE,
		Handle:g_hAllowTrolling = INVALID_HANDLE,
		Handle:g_hBlockAllInvisibleSounds = INVALID_HANDLE,
		Handle:g_hBombGiveDelay = INVALID_HANDLE,
		Handle:g_hC4Timer = INVALID_HANDLE,
		Handle:g_hDrawBombLine = INVALID_HANDLE;

public OnPluginStart() {
	BeamModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);

	HookEvent("round_start", Event_RoundStart);
	HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_PostNoCopy);
	HookEvent("cs_intermission", Event_Intermission, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

	AddNormalSoundHook(OnNormalSoundPlayed);

	CreateTimer(1.0, OnSecond, _, TIMER_REPEAT);

	//Cvars
	CreateConVar("ghoststrike_version", PLUGIN_VERSION, "GhostStrike Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hEnabled = CreateConVar("ghoststrike_enable", "1", "Enables/disables GhostStrike. After disabling you are required to reload the Map, otherwise there is a global bomzone.", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hEnabled, OnSettingsChange);
	g_hDisableOnEnd = CreateConVar("ghoststrike_autodisable", "0", "Automatically disable the gamemode on Intermission (Game end)", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hDisableOnEnd, OnSettingsChange);
	g_hBlockInvisibleDamage = CreateConVar("ghoststrike_block_invisible_damage", "0", "Block damage dealt to invisible counterterrorists", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hBlockInvisibleDamage, OnSettingsChange);
	g_hAllowTrolling = CreateConVar("ghoststrike_allow_trolling", "1", "Allow invisible Counter Terrorists to show themselves while holding R(Reload)", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hAllowTrolling, OnSettingsChange);
	g_hBlockAllInvisibleSounds = CreateConVar("ghoststrike_block_all_invisible_sounds", "0", "Block all Sounds created by invisible terrorists (Not just steps, but jumps etc as well)", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hBlockAllInvisibleSounds, OnSettingsChange);
	g_hC4Timer = CreateConVar("ghoststrike_c4timer", "60", "This value is piped into the mp_c4timer cvar when the gamemode is enabled", FCVAR_NONE, true, 10.0);
	HookConVarChange(g_hC4Timer, OnSettingsChange);
	g_hDrawBombLine = CreateConVar("ghoststrike_show_bomb_guidelines", "1", "Draw a Line from every Counterterrorist to the bomb when it is planted", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hDrawBombLine, OnSettingsChange);
	g_hBombGiveDelay = CreateConVar("ghoststrike_bomb_delay", "40", "The Delay in seconds after the roundstart when the bomb will be given out", FCVAR_NONE, true, 30.0, true, 60.0);
	HookConVarChange(g_hBombGiveDelay, OnSettingsChange);

	AutoExecConfig(true, "ghoststrike");

	//Read Cvar values on Load
	active = GetConVarInt(g_hEnabled) ? true : false;
	disableOnIntermission = GetConVarInt(g_hDisableOnEnd) ? true : false;
	blockInvisibleDamage = GetConVarInt(g_hBlockInvisibleDamage) ? true : false;
	allowTrolling = GetConVarInt(g_hAllowTrolling) ? true : false;
	blockAllInvisibleSounds = GetConVarInt(g_hBlockAllInvisibleSounds) ? true : false;
	bombGiveDelay = GetConVarInt(g_hBombGiveDelay);
	c4TimerTarget = GetConVarInt(g_hC4Timer);
	drawBombGuideLines = GetConVarInt(g_hDrawBombLine) ? true : false;
}

public OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[]) {
	if(cvar == g_hEnabled){
		new bool:newState = StringToInt(newvalue) ? true : false;

		if(active != newState && (active = newState) && newState) init();
	}else if(cvar == g_hDisableOnEnd){
		disableOnIntermission = StringToInt(newvalue) ? true : false;
	}else if(cvar == g_hBlockInvisibleDamage){
		blockInvisibleDamage = StringToInt(newvalue) ? true : false;
	}else if(cvar == g_hAllowTrolling){
		allowTrolling = StringToInt(newvalue) ? true : false;
	}else if(cvar == g_hBlockAllInvisibleSounds){
		blockAllInvisibleSounds = StringToInt(newvalue) ? true : false;
	}else if(cvar == g_hBlockAllInvisibleSounds){
		c4TimerTarget = StringToInt(newvalue);
	}else if(cvar == g_hDrawBombLine){
		drawBombGuideLines = StringToInt(newvalue) ? true : false;
	}else if(cvar == g_hBombGiveDelay){
		bombGiveDelay = StringToInt(newvalue);
	}
}

public Event_Intermission(Handle:event, const String:name[], bool:dontBroadcast) {
	if(disableOnIntermission) active = false;
}

public Action:OnNormalSoundPlayed(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags) {
	if(!active || isWarmup || isPlanted || entity < 1 || entity > 64)
		return Plugin_Continue;

	//Only block footsteps. Landing sounds are still supposed to be played per concept.
	if(IsValidClient(entity) && GetClientTeam(entity) == CS_TEAM_CT && (blockAllInvisibleSounds || StrContains(sample, "footsteps") == -1)) {
		new ClientArrayIndex = 0;

		for(new i = 0; i < numClients; i++) {
			if(IsValidClient(clients[i]) && GetClientTeam(clients[i]) == CS_TEAM_CT)
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

public OnMapStart() {
	PrecacheModel("models/props/cs_office/vending_machine.mdl", true);

	inited = false; //Need to re-init on Mapchange
	if(active) init();

	//Allows for Hot-Reloading of the plugin
	for(new i = 1; i <= MaxClients; i++)
		if(IsValidClient(i)) OnClientPutInServer(i);
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	//When the Timelimit is 999 it (apparently) means, warmup.
	//Please do not set a roundtime of 999 Seconds, or if you read this and know better, tell me :^)
	if(!active || (isWarmup = GetEventInt(event, "timelimit") == 999)) return;

	isPlanted = false;
	bombGiveTimer = bombGiveDelay;

	for(new i = 1; i < MaxClients; i++) {
		if(IsValidClient(i)) if(GetClientTeam(i) == CS_TEAM_CT) {
			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] You are{GREEN} invisible{DEFAULT} and your steps are{GREEN} inaudible{DEFAULT} to the{RED} Terrorists.{DEFAULT} You are%s invincible{DEFAULT}.",
				blockInvisibleDamage ? "{GREEN}" : "{RED} not");

			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] You{RED} can't{DEFAULT} shoot until the bomb has been planted!%s",
				!blockAllInvisibleSounds ? " While steps are inaudible, any other sounds (e.g. Jumps) are{RED} not{DEFAULT}!" : " Any Sound produced by you{GREEN} can't{DEFAULT} be heard by the Terrorists.");

			if(allowTrolling) CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] While you are invisible you can show yourself to the Terrorists by holding the reload key.");

			//Prevent the client from Attacking
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", 99999999.0);
		} else {
			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] The{LIGHTBLUE} Counterterrorists{DEFAULT} are{RED} invisible{DEFAULT}%s invincible{DEFAULT} until you plant the bomb!",
				blockInvisibleDamage ? " and{RED}" : ", but{GREEN} not");
			CGOPrintToChat(i, "[{GREEN}GhostStrike{DEFAULT}] You can plant the bomb{GREEN} anywhere{DEFAULT} on the map, but keep in mind there might always be a{LIGHTBLUE} CT{RED} right next to you.");
		}
	}
}

public OnClientDisconnect(client){
	unhideCT[client] = false;
}

//Dem Hooks
public OnClientPutInServer(client) {
	SDKHook(client, SDKHook_PostThinkPost, Hook_PostThinkPost);
	SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
	SDKHook(client, SDKHook_WeaponCanSwitchToPost, Hook_WeaponCanSwitchToPost);
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
}
//Hiding CT's to T's pre-plant
public Action:Hook_SetTransmit(entity, client) {
	if(!active || isWarmup || isPlanted || client < 1 || client > 64)
		return Plugin_Continue;

	if(IsValidClient(entity) && GetClientTeam(entity) == CS_TEAM_CT && !unhideCT[entity] && IsValidClient(client) && GetClientTeam(client) == CS_TEAM_T)
		return Plugin_Stop;

	return Plugin_Continue;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2]){
	if(!active || isWarmup || !allowTrolling)
		return Plugin_Continue;

	if(IsValidClient(client) && GetClientTeam(client) == CS_TEAM_CT){
		new bool:shouldUnhide = !isPlanted && buttons & IN_RELOAD;
		if(shouldUnhide != unhideCT[client]){
			if(shouldUnhide)
				PrintHintText(client, "<font color='#00ff00'>You are now visible to the Terrorists</font>!");
			else if(!isPlanted) PrintHintText(client, "<font color='#ff0000'>You are invisible again</font>!");

			unhideCT[client] = shouldUnhide;
		}
	}

	return Plugin_Continue;
}

public Action:OnTraceAttack(victim, &attacker, &inflictor, &Float:damage, &damagetype, &ammotype, hitbox, hitgroup) {
	if(!blockInvisibleDamage || !active || isWarmup || isPlanted || attacker < 1 || attacker > 64)
		return Plugin_Continue;

	if(IsValidClient(victim) && GetClientTeam(victim) == CS_TEAM_CT)
		return Plugin_Stop;

	return Plugin_Continue;
}

//Hide CT's on the Radar because apparently blocking the Transmit is not enough
public Hook_PostThinkPost(client) {
  if(active && !isWarmup && !isPlanted && !unhideCT[client] && GetClientTeam(client) == CS_TEAM_CT)
  	SetEntProp(client, Prop_Send, "m_bSpotted", 0);
}

//Re-Set m_flNextAttack on weaponswitch
public Hook_WeaponCanSwitchToPost(client) {
	if(active && !isWarmup && !isPlanted && GetClientTeam(client) == CS_TEAM_CT)
		//Needs to be delayed by a tick, otherwise it wont work, eventhough its a post-hook.
		CreateTimer(0.0, Timer_RestrictNextAttack, client);
}

public Action:Timer_RestrictNextAttack(Handle:timer, any:client) {
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", 99999999.0);
}

public Action:OnSecond(Handle:timer) {
	if(bombGiveTimer > 0) {
		if(GetTeamClientCount(CS_TEAM_T) > 0) PrintHintTextToAll("The bomb will be given to a random Terrorist in <font color='#edda74'>%i second(s)</font>!", --bombGiveTimer);
	} else if(bombGiveTimer == 0) {
		decl clientArray[MAXPLAYERS+1];
		new clientArrayIndex = 0;
		//Arrify all T Players
		for(new i = 1; i < MaxClients; i++) {
			if(IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T)
				clientArray[clientArrayIndex++] = i;
		}

		if(clientArrayIndex > 0) {
			clientArrayIndex = clientArray[GetRandomInt(0, clientArrayIndex - 1)];

			PrintHintTextToAll("<font color='#ff0000'>%N</font> has received the bomb!", clientArrayIndex);
			CGOPrintToChatAll("[{GREEN}GhostStrike{DEFAULT}]{RED} %N{DEFAULT} has received the bomb!", clientArrayIndex);

			GivePlayerItem(clientArrayIndex, "weapon_c4");
			bombGiveTimer = -1;
		}
	}
}

new Float:plantedBombOrigin[3];

public Event_BombPlanted(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!active || isWarmup) return;

	isPlanted = true;

	new c4 = drawBombGuideLines ? FindEntityByClassname(-1, "planted_c4") : -1;

	if(c4 != -1) GetEntPropVector(c4, Prop_Send, "m_vecOrigin", plantedBombOrigin);

	for(new i = 1; i < MaxClients; i++) {
		if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_CT) {
			//Allow CT's to shoot as soon as the bomb is planted.
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", 0.0);

			// PrintHintText(i, "<font color='#ffff00'>You are now visible to the Terrorists and can attack!</font>!");

			if(c4 != -1)
				//Delay Beam otherwise game might crash because Source.
				CreateTimer(0.1, DelayedUserNotif, i);
		}
	}
}

public Action:DelayedUserNotif(Handle:timer, any:client) {
	if(IsValidClient(client)){
		decl Float:clientOrigin[3];
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

public OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast) {
	if(active || isWarmup) {
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		//Setting the collision mode to Pushaway. This allows for "bouncy" collisions,
		//as well as prevents people from boosting into difficult to reach spots
		SetEntProp(client, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PUSHAWAY);

		//Juuuust to be sure.
		new C4 = GetPlayerWeaponSlot(client, CS_SLOT_C4);
		if(C4 > MaxClients && IsValidEntity(C4)) {
			CS_DropWeapon(client, C4, false, true);
			AcceptEntityInput(C4, "kill");
		}
	}
}

/* Internal Functions */

public init() {
	if(inited) return;

	new ent = -1;
	//Kill all bomzones
	while((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
		AcceptEntityInput(ent, "Kill");

	//Create new, global bomb zone
	ent = CreateEntityByName("func_bomb_target");
	if(ent != -1){
		//TODO: Required?
		DispatchKeyValue(ent, "targetname", "A");

		DispatchSpawn(ent);
		ActivateEntity(ent);

		TeleportEntity(ent, Float:{0.0, 0.0, 0.0}, NULL_VECTOR, NULL_VECTOR);

		//I dont even know. Apparently its needed.
		SetEntityModel(ent, "models/props/cs_office/vending_machine.mdl");

		//-32k - 32k, Max. CS:GO Map size. Should be 'nuff
		new Float:minbounds[3] = {-32767.0, -32767.0, -32767.0};
		new Float:maxbounds[3] = {32767.0, 32767.0, 32767.0};
		SetEntPropVector(ent, Prop_Send, "m_vecMins", minbounds);
		SetEntPropVector(ent, Prop_Send, "m_vecMaxs", maxbounds);

		SetEntProp(ent, Prop_Send, "m_nSolidType", SOLID_BBOX);

		SetEntProp(ent, Prop_Send, "m_fEffects", GetEntProp(ent, Prop_Send, "m_fEffects") | EF_NODRAW);

		inited = true;

		ServerCommand("mp_give_player_c4 0");
		ServerCommand("mp_c4timer %i", c4TimerTarget);
		ServerCommand("mp_restartgame 1");

		LogMessage("Initialized on current Map");
	} else {
		LogError("Could not Init because spawning the global Bombzone failed!");
		active = false;
	}
}

public bool:IsValidClient(client){
	return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}