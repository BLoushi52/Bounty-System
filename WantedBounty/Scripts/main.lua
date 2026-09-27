-- ============================================================
--  WantedBounty v1.0 — server-side UE4SS Lua mod for Palworld
--
--  Kill a player LevelGap+ levels below you -> you are WANTED for
--  WantedMinutes. While wanted, a marker follows you live on EVERY
--  player's world map (Steam, Xbox, PS5, Mac — nothing to install
--  client-side), plus chat announcements.
--
--  How the map marker works: the server writes a guild marker into
--  every online guild through the game's own guild-marker functions
--  and moves it to the wanted player every few seconds. Vanilla
--  clients already know how to draw guild markers, so consoles see it.
-- ============================================================

local Config = require("config")

local MOD = "[WantedBounty]"
local SIG = 0x0B0A7700 -- first 32 bits of every marker ID this mod creates

local function log(msg) print(string.format("%s %s\n", MOD, tostring(msg))) end
local function dbg(msg) if Config.Debug then log(msg) end end

-- ------------------------------------------------------------
-- Small helpers
-- ------------------------------------------------------------
local function valid(o)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end

local PalUtilityCDO, PlayerCharClass
local function Util()
    if not valid(PalUtilityCDO) then
        PalUtilityCDO = StaticFindObject("/Script/Pal.Default__PalUtility")
    end
    return PalUtilityCDO
end
local function PlayerClass()
    if not valid(PlayerCharClass) then
        PlayerCharClass = StaticFindObject("/Script/Pal.PalPlayerCharacter")
    end
    return PlayerCharClass
end

local function u32(n) return (n or 0) & 0xFFFFFFFF end
local function gkey(g)
    return string.format("%08x%08x%08x%08x", u32(g.A), u32(g.B), u32(g.C), u32(g.D))
end
local function gcopy(g) return { A = g.A, B = g.B, C = g.C, D = g.D } end
local function gzero(g) return g.A == 0 and g.B == 0 and g.C == 0 and g.D == 0 end

local function fmt(template, vars)
    return (template:gsub("{(%w+)}", function(k)
        local v = vars[k]
        if v == nil then return "{" .. k .. "}" end
        return tostring(v)
    end))
end

local function fmtTime(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    return string.format("%d:%02d", secs // 60, secs % 60)
end

local function mapCoords(l)
    if not l then return "?", "?" end
    local x = (l.Y - Config.MapOffsetY) / Config.MapScale
    local y = (l.X + Config.MapOffsetX) / Config.MapScale
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

local function announce(msg)
    log("ANNOUNCE: " .. msg)
    local ok, err = pcall(function()
        local ctx = FindFirstOf("PalGameStateInGame")
        Util():SendSystemAnnounce(ctx, msg)
    end)
    if not ok then log("SendSystemAnnounce failed: " .. tostring(err)) end
end

-- ------------------------------------------------------------
-- Player lookups
-- ------------------------------------------------------------
local function isPlayerChar(a)
    local ok, r = pcall(function() return a:IsA(PlayerClass()) end)
    return ok and r == true
end

-- Attacker can be the player, their Pal, or the Pal they ride -> resolve to the player.
local function resolvePlayer(actor)
    if not valid(actor) then return nil end
    if isPlayerChar(actor) then return actor end
    local ok, trainer = pcall(function() return Util():GetTrainerPlayer(actor) end)
    if ok and valid(trainer) then return trainer end
    return nil
end

local function charPlayerState(ch)
    local ok, ps = pcall(function() return ch.PlayerState end)
    if ok and valid(ps) then return ps end
    ok, ps = pcall(function() return Util():GetPlayerStateByPlayer(ch) end)
    if ok and valid(ps) then return ps end
    return nil
end

local function playerName(ps)
    local ok, n = pcall(function() return ps:GetPlayerName():ToString() end)
    if ok and n and n ~= "" then return n end
    return "Unknown"
end

local function charLevel(ch)
    local ok, lvl = pcall(function() return ch.CharacterParameterComponent:GetLevel() end)
    if ok and type(lvl) == "number" then return lvl end
    return nil
end

local function playerInfo(ch)
    if not valid(ch) then return nil end
    local ps = charPlayerState(ch)
    if not ps then return nil end
    local uid = ps.PlayerUId
    if gzero(uid) then return nil end
    return { char = ch, ps = ps, uid = gcopy(uid), key = gkey(uid), name = playerName(ps), level = charLevel(ch) }
end

local function actorLocation(actor)
    local ok, v = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and v then return { X = v.X, Y = v.Y, Z = v.Z } end
    return nil
end

-- Every online player with controller, guild and pawn.
local function collectOnline()
    local byKey, guilds = {}, {}
    local ctrls = FindAllOf("PalPlayerController") or {}
    for _, c in ipairs(ctrls) do
        pcall(function()
            if not valid(c) then return end
            local ps = c.PlayerState
            if not valid(ps) then return end
            local uid = ps.PlayerUId
            if gzero(uid) then return end
            local pawn = c.Pawn
            local p = {
                ctrl = c, ps = ps, uid = gcopy(uid), key = gkey(uid),
                pawn = valid(pawn) and pawn or nil, name = playerName(ps),
            }
            local g = ps.GuildBelongTo
            if valid(g) then
                p.gkey = g:GetAddress()
                local ge = guilds[p.gkey]
                if not ge then
                    ge = { guild = g, gkey = p.gkey, members = {} }
                    guilds[p.gkey] = ge
                end
                table.insert(ge.members, p)
            end
            byKey[p.key] = p
        end)
    end
    return byKey, guilds
end

-- ------------------------------------------------------------
-- State
-- ------------------------------------------------------------
local Wanted = {}      -- playerKey -> { uid, name, remaining, sinceAnnounce, lastLoc }
local LastHit = {}     -- victimKey -> { attackerKey -> os.time() }
local RecentDeath = {} -- victimKey -> os.time()  (de-dupe double death events)
local AddFails = {}    -- guild..wanted -> count  (detect rejected marker adds)

local function makeWanted(info, seconds, extendMsgVars)
    local w = Wanted[info.key]
    if w then
        w.remaining = Config.StackTime and (w.remaining + seconds) or seconds
        w.name = info.name
        if extendMsgVars then
            extendMsgVars.time = fmtTime(w.remaining)
            announce(fmt(Config.Messages.Extended, extendMsgVars))
        end
        return w, true
    end
    w = { uid = info.uid, name = info.name, remaining = seconds, sinceAnnounce = 0 }
    Wanted[info.key] = w
    return w, false
end

-- ------------------------------------------------------------
-- Combat events
-- ------------------------------------------------------------
local function onPlayerDamaged(victimChar, damageResult)
    local atk = resolvePlayer(damageResult.Attacker)
    if not atk then return end
    local vi, ai = playerInfo(victimChar), playerInfo(atk)
    if not vi or not ai or vi.key == ai.key then return end
    LastHit[vi.key] = LastHit[vi.key] or {}
    LastHit[vi.key][ai.key] = os.time()
end

local function onPlayerDeath(vi, ki)
    local now = os.time()
    if RecentDeath[vi.key] and now - RecentDeath[vi.key] < 5 then return end
    RecentDeath[vi.key] = now

    local victimWanted = Wanted[vi.key]

    -- Not killed by another player
    if not ki or ki.key == vi.key then
        dbg(string.format("%s died (no player killer)", vi.name))
        if victimWanted and Config.ClearOnNonPlayerDeath then
            Wanted[vi.key] = nil
            announce(fmt(Config.Messages.Expired, { name = vi.name }))
        end
        return
    end

    dbg(string.format("PvP kill: %s (Lv%s) -> %s (Lv%s)", ki.name, tostring(ki.level), vi.name, tostring(vi.level)))

    -- Killing a wanted player claims the bounty and is always free.
    if victimWanted then
        Wanted[vi.key] = nil
        announce(fmt(Config.Messages.Claimed, { killer = ki.name, victim = vi.name }))
        return
    end

    if not ki.level or not vi.level then
        log("Could not read levels for this kill - no bounty applied.")
        return
    end

    local gap = ki.level - vi.level
    if gap < Config.LevelGap then return end

    -- Self-defence: the victim hit the killer recently -> no bounty.
    local victimHitKillerAt = LastHit[ki.key] and LastHit[ki.key][vi.key]
    if victimHitKillerAt and (now - victimHitKillerAt) <= Config.SelfDefenseSeconds then
        dbg(string.format("No bounty: %s attacked %s first (self-defence)", vi.name, ki.name))
        return
    end

    local secs = Config.WantedMinutes * 60
    local vars = { killer = ki.name, victim = vi.name, gap = gap }
    local _, existed = makeWanted(ki, secs, vars)
    if not existed then
        vars.time = fmtTime(secs)
        announce(fmt(Config.Messages.Wanted, vars))
    end
end

-- ------------------------------------------------------------
-- Map markers (guild markers written into every online guild)
-- ------------------------------------------------------------
local function markerIdFor(w) return { A = SIG, B = w.uid.B, C = w.uid.C, D = w.uid.D } end

local function wantedKeyForMarker(id)
    for k, w in pairs(Wanted) do
        if w.uid.B == id.B and w.uid.C == id.C and w.uid.D == id.D then return k end
    end
    return nil
end

local function markerData(id, loc, ownerUid)
    return {
        MarkerID = id,
        IconLocation = { X = loc.X, Y = loc.Y, Z = loc.Z },
        IconType = Config.MarkerIconType,
        OwnerPlayerUId = ownerUid,
    }
end

local function readOurMarkers(guild)
    local out = {}
    pcall(function()
        guild.GuildMarkers:ForEach(function(_, elem)
            local m = elem:get()
            local id = m.MarkerID
            if id.A == SIG then
                table.insert(out, {
                    id = gcopy(id),
                    ownerKey = gkey(m.OwnerPlayerUId),
                    wkey = wantedKeyForMarker(id),
                })
            end
        end)
    end)
    return out
end

local function callSafe(ctrl, fnName, ...)
    local args = { ... }
    local ok, err = pcall(function() ctrl[fnName](ctrl, table.unpack(args)) end)
    if not ok then log(fnName .. " failed: " .. tostring(err)) end
    return ok
end

local function pickCaller(ge, preferKey, byKey)
    local p = preferKey and byKey[preferKey]
    if p and p.gkey == ge.gkey then return p end
    return ge.members[1]
end

local function syncGuild(ge, targets, byKey)
    local present = readOurMarkers(ge.guild)
    local have = {}

    -- Remove markers that are stale, duplicated or no longer wanted.
    for _, m in ipairs(present) do
        local t = m.wkey and targets[m.wkey]
        local wanted = t and (Config.ShowToOwnGuild or t.gkey ~= ge.gkey)
        if wanted and not have[m.wkey] then
            have[m.wkey] = m
        else
            local caller = pickCaller(ge, m.ownerKey, byKey)
            if caller then
                dbg("Removing marker from guild " .. tostring(ge.gkey))
                callSafe(caller.ctrl, "RequestRemoveGuildMarker_ToServer", m.id)
            end
        end
    end

    -- Add or move a marker for every active wanted player.
    for wkey, t in pairs(targets) do
        if Config.ShowToOwnGuild or t.gkey ~= ge.gkey then
            local m = have[wkey]
            local owner = m and byKey[m.ownerKey]
            if m and owner and owner.gkey == ge.gkey then
                callSafe(owner.ctrl, "RequestChangeGuildMarker_ToServer", m.id, markerData(m.id, t.loc, owner.uid))
                AddFails[ge.gkey .. wkey] = nil
            else
                local caller = ge.members[1]
                if m and caller then
                    callSafe(caller.ctrl, "RequestRemoveGuildMarker_ToServer", m.id)
                end
                if caller then
                    local fk = ge.gkey .. wkey
                    local fails = AddFails[fk] or 0
                    -- after 3 failed adds, only retry every ~5th tick to avoid spam
                    if fails < 3 or fails % 5 == 0 then
                        local id = markerIdFor(t.w)
                        callSafe(caller.ctrl, "RequestAddGuildMarker_ToServer", id, markerData(id, t.loc, caller.uid))
                    end
                    AddFails[fk] = fails + 1
                    if fails == 3 then
                        log("WARNING: guild marker for " .. t.w.name .. " is not sticking in guild of " .. caller.name ..
                            " (server rejected the add?). Try another MarkerIconType or check the guild marker limit.")
                    end
                end
            end
        end
    end
end

-- ------------------------------------------------------------
-- Main tick
-- ------------------------------------------------------------
local function tick(dt)
    local byKey, guilds = collectOnline()
    local targets = {}
    local now = os.time()

    for key, w in pairs(Wanted) do
        local p = byKey[key]
        local online = p and p.pawn
        if online or not Config.PauseWhileOffline then
            w.remaining = w.remaining - dt
        end
        if w.remaining <= 0 then
            Wanted[key] = nil
            announce(fmt(Config.Messages.Expired, { name = w.name }))
        elseif online then
            local l = actorLocation(p.pawn)
            if l then
                w.lastLoc = l
                targets[key] = { loc = l, gkey = p.gkey, w = w }
            end
            if Config.AnnounceEverySeconds and Config.AnnounceEverySeconds > 0 then
                w.sinceAnnounce = (w.sinceAnnounce or 0) + dt
                if w.sinceAnnounce >= Config.AnnounceEverySeconds then
                    w.sinceAnnounce = 0
                    local x, y = mapCoords(w.lastLoc)
                    announce(fmt(Config.Messages.Reminder, { name = w.name, x = x, y = y, time = fmtTime(w.remaining) }))
                end
            end
        end
    end

    for _, ge in pairs(guilds) do
        if #ge.members > 0 then
            local ok, err = pcall(syncGuild, ge, targets, byKey)
            if not ok then log("syncGuild error: " .. tostring(err)) end
        end
    end

    -- prune old hit records
    for vk, hits in pairs(LastHit) do
        for ak, t in pairs(hits) do
            if now - t > Config.SelfDefenseSeconds then hits[ak] = nil end
        end
        if next(hits) == nil then LastHit[vk] = nil end
    end
    for k, t in pairs(RecentDeath) do
        if now - t > 30 then RecentDeath[k] = nil end
    end
end

-- ------------------------------------------------------------
-- Chat commands
--   !wanted              -> list wanted players (anyone)
--   !bountytest          -> make yourself wanted for TestMinutes (admin)
--   !bountyclear <name>  -> clear a bounty (admin)  / "all" clears everyone
--   !bountyicon <n>      -> change marker icon live (admin)
-- ------------------------------------------------------------
local function handleCommand(text, senderKey)
    local byKey = collectOnline()
    local sender = byKey[senderKey]
    local isAdmin = false
    if sender then
        local ok, a = pcall(function() return sender.ctrl.bAdmin end)
        isAdmin = ok and a == true
    end

    local cmd, arg = text:match("^!(%S+)%s*(.-)%s*$")
    cmd = cmd and cmd:lower()

    if cmd == "wanted" then
        local any = false
        for _, w in pairs(Wanted) do
            any = true
            local x, y = mapCoords(w.lastLoc)
            announce(fmt(Config.Messages.Reminder, { name = w.name, x = x, y = y, time = fmtTime(w.remaining) }))
        end
        if not any then announce(Config.Messages.None) end
    elseif cmd == "bountytest" and isAdmin then
        local w = makeWanted({ uid = sender.uid, key = sender.key, name = sender.name }, Config.TestMinutes * 60)
        w.remaining = Config.TestMinutes * 60
        announce(fmt(Config.Messages.Wanted, { killer = sender.name, victim = "a test dummy", gap = Config.LevelGap, time = fmtTime(w.remaining) }))
    elseif cmd == "bountyclear" and isAdmin then
        local needle = (arg or ""):lower()
        for k, w in pairs(Wanted) do
            if needle == "all" or w.name:lower() == needle then
                Wanted[k] = nil
                announce(fmt(Config.Messages.Cleared, { name = w.name }))
            end
        end
    elseif cmd == "bountyicon" and isAdmin then
        local n = tonumber(arg)
        if n then
            Config.MarkerIconType = math.floor(n)
            announce("[BOUNTY] Marker icon set to " .. Config.MarkerIconType)
        end
    end
end

-- ------------------------------------------------------------
-- Hooks
-- ------------------------------------------------------------
local function tryHook(path, fn)
    local ok, err = pcall(RegisterHook, path, fn)
    if ok then log("Hooked " .. path) else log("FAILED to hook " .. path .. ": " .. tostring(err)) end
end

tryHook("/Script/Pal.PalPlayerCharacter:OnDamagePlayer_Server", function(self, DamageResult)
    local ok, err = pcall(function() onPlayerDamaged(self:get(), DamageResult:get()) end)
    if not ok then dbg("damage hook error: " .. tostring(err)) end
end)

tryHook("/Script/Pal.PalPlayerCharacter:OnDeadPlayer_Server", function(self, DeadInfo)
    local ok, err = pcall(function()
        local info = DeadInfo:get()
        local vi = playerInfo(self:get())
        if not vi then return end
        local killer = resolvePlayer(info.LastAttacker)
        local ki = killer and playerInfo(killer) or nil
        onPlayerDeath(vi, ki)
    end)
    if not ok then log("death hook error: " .. tostring(err)) end
end)

tryHook("/Script/Pal.PalGameStateInGame:BroadcastChatMessage", function(self, ChatMessage)
    local text, senderKey
    pcall(function()
        local m = ChatMessage:get()
        text = m.Message:ToString()
        senderKey = gkey(m.SenderPlayerUId)
    end)
    if not text or text:sub(1, 1) ~= "!" then return end
    -- run after the chat message finishes processing (avoids re-entering this hook)
    ExecuteWithDelay(100, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(handleCommand, text, senderKey)
            if not ok then log("command error: " .. tostring(err)) end
        end)
    end)
end)

-- ------------------------------------------------------------
-- Loop
-- ------------------------------------------------------------
local interval = math.max(1, Config.MarkerUpdateSeconds or 2)
LoopAsync(interval * 1000, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(tick, interval)
        if not ok then log("tick error: " .. tostring(err)) end
    end)
    return false -- keep looping
end)

log(string.format("Loaded. Gap=%d levels, bounty=%d min, marker every %ds, icon=%d",
    Config.LevelGap, Config.WantedMinutes, interval, Config.MarkerIconType))
