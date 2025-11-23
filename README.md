# 1.12.1-Paladin

This is a for fun project to see how far I can take scripting a lua based combat routine for private or local World of Warcraft 1.12.1 servers. Vanilla WoW is quite fun by itself, but it also comes with very little restriction on how LUA can interact with the game client without the need for a LUA unlocker. So far, this project only covers the beginning aspects of playing retribution paladin, but I plan to update this as I level to include both logic and support for holy and prot paladin.

# Support Mode 

/ssa support on

This command currently changes your Blessing to Wisdom rather than the current placeholder Blessing of Might. Eventually, this setting will be used for a different behavior for general group support in the open world or in dungeon environment. This will mean that under certain health percentages, the routine will start using flash of light to heal a party member below a health threshold, but this is currently not implemented. For now, this setting only changes the blessing to Wisdom.
