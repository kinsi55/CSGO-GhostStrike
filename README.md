# GhostStrike
Simple concept for a custom [CS:GO](http://store.steampowered.com/app/730/?l=german) gamemode that turned out to be pretty fun!

It is tested, and meant to be played 5v5, so a normal "competitive" base.

##### Summary:

When the round starts Terrorists are unable to see, or hear Counterterrorists. On the other hand, Counterterrorists are unable to attack in any way. 40 seconds after the round has started a random Terrorist will be given a bomb, which he then can proceed to plant anywhere on the map. As soon as the bomb is planted Counterterrorists become visible to the Terrorists, and are able to Attack. After that its normal Counter-Strike with the aim to defuse the bomb.

##### Recommendations:

- **Friendlyfire** should be **on**		
- The **roundtime** should be **1min - 1:20**		
- You should allow **Max 8v8**, anything above that becomes an unplayable game (Because the gamemode is not designed for that much players).

##### Cvars:

- **ghoststrike_enable** - Enables/disables GhostStrike.
- **ghoststrike_autodisable** - Automatically disable the gamemode on Intermission (Game end)
- **ghoststrike_block_invisible_damage** - Block damage dealt to invisible counterterrorists
- **ghoststrike_allow_trolling** - Allow invisible Counter Terrorists to show themselves while holding R(Reload)
- **ghoststrike_block_all_invisible_sounds** - Block all Sounds created by invisible Countererrorists (Not just steps, but jumps etc as well)
- **ghoststrike_c4timer** - This value is piped into the mp_c4timer cvar when the gamemode is enabled
- **ghoststrike_show_bomb_guidelines** - Draw a Line from every Counterterrorist to the bomb when it is planted
- **ghoststrike_bomb_delay** - The delay in seconds after the roundstart when the bomb will be given out
- **ghoststrike_full_noblock** - If full noblock should be active instead of using bouncy collisions
- **ghoststrike_plant_block_radius** - Minimum spherical distance you need to have to previous plant-positions to be able to plant (0 = Off) to prevent re-use of plant spots.
- **ghoststrike_ct_hp_bonus** - Multiplicator for the HP bonus for CT's for each Terrorist after the fifth one (0 = off).
- **ghoststrike_timeover_forceplant** - Force the bomb plant when the time is about to hit 0 to prevent trolls.

##### Restrictions (Per concept):

- you are not (supposed to be) able to plant the bomb in locations where you are required to get boosted into. This is achieved by making collisions bouncy.
- While the steps of invisible Counterterrorists are inaudible, any other sound like jumping is not (Cvar changeable).
- Invisible Counterterrorists can still be hit by the Terrorists. This just adds more fun and thrill to the whole thing because it becomes a spamfest and you have to avoid getting killed before Terrorits plant the bomb (Cvar changeable).
- Terrorists are able to bounce into the invisible Counterterrorists, and see blood decals caused by damaging them. Again, this adds more fun and thrill to the game.

Post on the Alliedmods forum: https://forums.alliedmods.net/showthread.php?p=2462443
