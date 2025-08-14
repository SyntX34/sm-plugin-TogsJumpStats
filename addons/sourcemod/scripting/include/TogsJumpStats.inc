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


/**
 * Checks whether the client is permanently capped.
 *
 * This usually indicates a long-term restriction on the client's movement speed or jump behavior.
 *
 * @param client    Client index.
 *
 * @return          True if the client has a permanent cap, false otherwise.
 */
native bool TJS_ClientIsPermanentCapped(int client);

/**
 * Checks whether the client is whitelisted.
 *
 * Whitelisted clients are excluded from jump stat detection and nerfing.
 *
 * @param client    Client index.
 *
 * @return          True if the client is whitelisted, false otherwise.
 */
native bool TJS_ClientIsWhitelisted(int client);

/**
 * Sets whether the client should be ignored by jump stat detection.
 *
 * When set to true, the client will not be monitored or penalized.
 *
 * @param client    Client index.
 * @param ignore    True to ignore the client, false to resume monitoring.
 *
 * @noreturn
 */
native void TJS_IgnoreClient(int client, bool ignore);
