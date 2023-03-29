# Psych Engine XTended
This is a fork of [Psych Engine 0.6.3](https://github.com/ShadowMario/FNF-PsychEngine) made for its use in the creation of games/mods based on Friday Night Funkin'. It includes all of the features of Psych Engine, plus the additions featured in [Vs Selever 2.0](https://github.com/DragShot/fnf-vs-selever-mod) and new ones on their way; basically becoming the next step from the later project.

This engine is being prepared to be the foundation of upcoming games like **Funk Guys** and **Friday Night Godness**, as well as other mods I might get involved later on; so this repository will not hold files related to specific FNF mods.

## Planned Features
### From Psych 0.5.2-xt:
* Automatic loading of dialogues in Story Mode
* Localization support for in-game dialogues
* Tweaks in the Lua scripting API

### New in 0.6.3-xt:
* Lua scripting support for custom game states.
* Some helper Lua utility scripts might come bundled with the stock files

## Building
If you want to build a copy of this engine by yourself, here's what you need:

* Windows 10 or some compatible system. Virtual machines work well enough.
* [Haxe 4.2.5](https://haxe.org/download/version/4.2.5/)
* [HaxeFlixel](https://haxeflixel.com/documentation/install-haxeflixel/)
* [Visual Studio Code](https://code.visualstudio.com)
* [Visual Code Build Tools 2019](https://visualstudio.microsoft.com/vs/older-downloads/): Install modules `MSVC v142 - VS 2019 C++ x64/x86 build tools` and `Windows SDK (10.0.17763.0)` only.

Once you've installed all of the mentioned tools, checkout a copy of these files, open a terminal inside the project folder, then execute the following commands:
```
haxelib --global install hmm
haxelib --global install hxCodec 2.5.1
haxelib run hmm install
```
Once the setup process is complete, you should be able to build this program. Run the command `lime build windows` to do it.

## Licensing
Any additional code featured in this repository, and not present in Psych Engine, is licensed under the **GNU General Public License 3.0**. This means you can make use of the released executables for your FNF mod, free of any charges and compromises.

However, if you wish to incorporate any functionality from this project into your own engine, or make a fork of it for customization, you will be required to post your project's sources publicly under the GPL or a license compatible with it. This is for the sake of keeping things free and open.
