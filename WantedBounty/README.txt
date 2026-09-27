WantedBounty - server-side Palworld mod (UE4SS Lua)
=====================================================
Kill a player 20+ levels below you -> you are WANTED for 10 minutes.
While wanted, a marker follows you live on every player's world map
(Steam, Xbox, PS5, Mac - players install nothing), with chat announcements.
Killing a wanted player claims the bounty. Fighting back never makes you wanted.

INSTALL
1. Back up Pal\Saved first (your server is no-wipe).
2. Stop the server.
3. Copy the whole "WantedBounty" folder into your UE4SS Mods folder:
     PalServer\Pal\Binaries\Win64\ue4ss\Mods\WantedBounty\
   (older UE4SS layouts use  PalServer\Pal\Binaries\Win64\Mods\ )
   It must look like:  ...\Mods\WantedBounty\Scripts\main.lua
                       ...\Mods\WantedBounty\enabled.txt
4. Start the server. In UE4SS.log you should see:
     [WantedBounty] Hooked ... (3 lines)
     [WantedBounty] Loaded. Gap=20 levels ...

FIRST TEST (takes 2 minutes)
1. Join, log in as admin (/AdminPassword <yourpassword> in chat).
2. Type  !bountytest   -> you become wanted for 2 minutes.
3. Have a friend in ANOTHER guild open their map: a marker should sit on you
   and follow you as you move (updates every 2 seconds).
4. Don't like the icon? Type  !bountyicon 1 , !bountyicon 2 ... until it looks
   right (red if available), then put that number in config.lua -> MarkerIconType.
5. !bountyclear all  to end the test.

COMMANDS
  !wanted               anyone - lists wanted players, rough map coords, time left
  !bountytest           admin  - make yourself wanted (TestMinutes)
  !bountyclear <name>   admin  - clear a bounty ("all" clears every bounty)
  !bountyicon <number>  admin  - change the marker icon live

SETTINGS  (Scripts\config.lua)
  LevelGap, WantedMinutes, SelfDefenseSeconds, PauseWhileOffline,
  MarkerUpdateSeconds, MarkerIconType, AnnounceEverySeconds, all messages.

GOOD TO KNOW
- The marker is a guild marker the server places in every online guild and
  moves; it's removed automatically when the bounty ends. Players in a guild
  with nobody else online still see it (each player has their own guild).
- Bounties live in memory: a server restart clears them.
- Set Debug = false in config.lua once everything works.
