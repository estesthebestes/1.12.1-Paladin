# 1.12.1-Paladin

This is a for fun project to see how far I can take scripting a lua based combat routine for private or local World of Warcraft 1.12.1 servers. Vanilla WoW is quite fun by itself, but it also comes with very little restriction on how LUA can interact with the game client without the need for a LUA unlocker. The routine now covers basic Retribution/support play and a first pass at Holy healing.

# Modes and commands

- `/ssa` — run the routine in your current mode
- `/ssa ret` — default Ret behavior
- `/ssa support` — swap to the support variant (Blessing of Wisdom focus)
- `/ssa healer` — enable Holy healer mode
- `/ssa assign <wisdom|might|salvation|kings>` — set which blessing you are assigned to keep up while healing

### Healer mode flow
- Keeps your assigned blessing active (default Wisdom; change with `/ssa assign ...`)
- Prefers Concentration Aura if known
- Chooses Seal of Wisdom while low on mana, Seal of Light when comfortable
- Healing priorities: Holy Shock in emergencies (if talented), Holy Light for big predictable damage, Flash of Light for steady spam
- Scans party/raid/target/self for the lowest health friendly and heals them without retargeting your hostile target

### Support mode
Ret baseline rotation but uses Blessing of Wisdom instead of Blessing of Might.
