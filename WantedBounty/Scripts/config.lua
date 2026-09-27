-- ============================================================
--  WantedBounty — settings
--  Edit, save, then restart the server (or reload UE4SS mods).
-- ============================================================
return {
    -- Killer must be at least this many levels above the victim to become WANTED.
    LevelGap = 20,

    -- How long a bounty lasts, in minutes.
    WantedMinutes = 10,

    -- Another gank while already wanted: true = add another full timer on top,
    -- false = reset the timer back to WantedMinutes.
    StackTime = false,

    -- Self-defence: if the (lower-level) victim hit the killer within this many
    -- seconds before dying, the level gap is ignored and no bounty is set.
    SelfDefenseSeconds = 45,

    -- Timer only counts down while the wanted player is online
    -- (so logging out doesn't burn the bounty off).
    PauseWhileOffline = true,

    -- If a wanted player dies to something that isn't a player (fall, wild Pal,
    -- suicide), should the bounty end? false = the bounty keeps running after respawn.
    ClearOnNonPlayerDeath = false,

    -- ---------------- Map marker ----------------
    -- How often the red marker follows the wanted player (seconds). 2 is a good balance.
    MarkerUpdateSeconds = 2,

    -- Which map pin icon to use. This is the same icon set players pick from when
    -- placing a guild marker on the world map (0 = first icon in that picker).
    -- Change live in-game as admin with:  !bountyicon <number>
    -- then put the number that looks right here.
    MarkerIconType = 0,

    -- Also show the marker to the wanted player's own guild.
    ShowToOwnGuild = true,

    -- ---------------- Chat ----------------
    -- Repeat "X is still wanted near (x, y), mm:ss left" every N seconds. 0 = off.
    AnnounceEverySeconds = 60,

    -- World -> map coordinate conversion used in chat messages (approximate).
    MapOffsetX = 123467.1611767,
    MapOffsetY = 157664.55791065,
    MapScale   = 462.962962963,

    -- Admin-only test command duration (!bountytest makes YOU wanted), minutes.
    TestMinutes = 2,

    -- Placeholders: {killer} {victim} {gap} {time} {x} {y} {name}
    Messages = {
        Wanted   = "[WANTED] {killer} killed {victim} ({gap} levels lower) and is WANTED for {time}! Hunt them down - their location is marked on the map.",
        Extended = "[WANTED] {killer} ganked {victim} ({gap} levels lower) again! Bounty now {time}.",
        Reminder = "[WANTED] {name} is still wanted near ({x}, {y}) - {time} left.",
        Claimed  = "[BOUNTY] {killer} claimed the bounty on {victim}!",
        Expired  = "[BOUNTY] The bounty on {name} has expired.",
        Cleared  = "[BOUNTY] An admin cleared the bounty on {name}.",
        None     = "[BOUNTY] Nobody is wanted right now.",
    },

    -- Extra logging in UE4SS.log (turn on while testing).
    Debug = true,
}
