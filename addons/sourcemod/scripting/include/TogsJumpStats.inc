public SharedPlugin __pl_TogsJumpStats = 
{
    name = "TogsJumpStats",
    file = "TogsJumpStats.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
}

#if defined _TogsJumpStats_Included
	#endinput
#endif
#define _TogsJumpStats_Included

/**
 * Called when a client is detected for potential bunnyhop cheating.
 *
 * @param client    Client index of the detected player.
 * @param type      String describing the type of detection (e.g., "hacks", "hyperscroll", "pattern jumps", "fps_max-<value>").
 * @noreturn
 */

forward void TJS_ClientDetected(int client, const char[] type);

/**
 * Gets or sets the nerfed status of a client.
 * If setting, the plugin will reduce the client's movement speed.
 *
 * @param client    Client index.
 * @param set       Optional: True to nerf the client, false to un-nerf, omit to query status.
 * @return          True if the client is nerfed, false otherwise.
 */
native bool TJS_ClientNerfed(int client, bool set = false);

