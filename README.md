# Palworld WantedBounty

Server-side UE4SS Lua mod for Palworld dedicated servers (Windows). Crossplay-safe: Steam, Xbox, PS5 and Mac players install nothing.

- Kill a player **20+ levels** below you → you're **WANTED** for 10 minutes, announced server-wide.
- While wanted, a marker follows you live on **every player's world map** (server-placed guild marker, updated every 2 s).
- Fighting back never makes you wanted (45 s self-defence window).
- Killing a wanted player claims the bounty.
- Chat commands: `!wanted`, and for admins `!bountytest`, `!bountyclear <name|all>`, `!bountyicon <n>`.

Install and test steps: see [`WantedBounty/README.txt`](WantedBounty/README.txt). Settings: [`WantedBounty/Scripts/config.lua`](WantedBounty/Scripts/config.lua).

Drop the `WantedBounty` folder into `PalServer\Pal\Binaries\Win64\ue4ss\Mods\`.
