package scripting;

import llua.LuaCallback;
import flixel.util.FlxTimer;
import flixel.util.FlxColor;
import flixel.util.FlxSave;
import flixel.math.FlxMath;
import flixel.system.FlxSound;
import flixel.FlxG;
import openfl.utils.Assets;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;

#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
#end

using StringTools;

class LuaUtils {
	public static inline var setupScript:String = "
do
	local path_bin, path_script, path_mod, path_relative, root;
	local source = ${scriptPath};

	--limit=2 -> Seach inside 'mods/modpack' folder
	--limit=1 -> Seach inside 'mods' folder
	function _pathSplice(limit)
		--Fetch the location of this script
		local path = string.sub(source, 2);
		local idx = 0;
		for i = 1, limit do
			idx, _ = string.find(path, '/', idx + 1, true);
		end
		path = string.sub(path, 1, idx);
		return path;
	end

	root = string.sub(source, 2):match('@?(.*/)');
	path_relative = root..'?.lua;'..root..'?/init.lua;';
	root = _pathSplice(2);
	path_mod = root..'libs/?.lua;'..root..'libs/?/init.lua;';
	root = _pathSplice(1);
	path_script = root..'libs/?.lua;'..root..'libs/?/init.lua;';
	path_bin = 'lua/?.lua;lua/?/init.lua;?.lua;?/init.lua;';

	package.path = path_relative .. path_mod .. path_script .. path_bin; --package.path .. 
end

local function _requireSetup()
	local luaRequire = _G.require; --OG require function
	local function _psychrequire(str) --A safer replacement
		local blacklist = {
			['ffi'] = true,
			--['bit'] = true,
			['jit'] = true,
			['io'] = true,
			['debug'] = true
		}
		if not blacklist[str] then
			return luaRequire(str);
		end
	end

	return _psychrequire; --Return the replacement function
end

_G.require = _requireSetup(); --_psychrequire
_requireSetup = nil;

--debug = nil
--io = nil
--dofile = nil
--load = nil
--loadfile = nil
os.execute = nil
--os.rename = nil
--os.remove = nil
os.tmpname = nil
os.setlocale = nil
os.getenv = nil
package.loadlib = nil
package.seeall = nil
package.preload.ffi = nil
package.preload['jit.profile'] = nil
package.preload['jit.util'] = nil
--package.loaded.debug = nil
--package.loaded.io = nil
package.loaded.jit = nil
package.loaded['jit.opt'] = nil
package.loaded.os.execute = nil
--package.loaded.os.rename = nil
--package.loaded.os.remove = nil
package.loaded.os.tmpname = nil
package.loaded.os.setlocale = nil
package.loaded.os.getenv = nil
package.loaded.process = nil
process = nil
	";

    #if LUA_ALLOWED
    public static function makeNewState(scriptPath:String):State {
        var lua:State = LuaL.newstate();
		LuaL.openlibs(lua);
		Lua.init_callbacks(lua);
        try {
            var initLua = StringTools.replace(setupScript, "${scriptPath}", "'@" + scriptPath + "'");
            LuaL.dostring(lua, initLua);
            var result:Dynamic = LuaL.dofile(lua, scriptPath);
            var resultStr:String = Lua.tostring(lua, result);
            if (resultStr != null && result != 0) {
				trace('Error on Lua script! ' + resultStr);
				#if windows
				lime.app.Application.current.window.alert(resultStr, 'Error on Lua script!');
				#end
				lua = null;
			}
        } catch (ex:Dynamic) {
			trace('Error on Lua script! ' + ex);
			lua = null;
		}
        return lua;
    }

    public static function defaultGlobals(lua:State, scriptPath:String) {
		if (lua == null) return;
        //Psych Engine
		set(lua, 'version', MainMenuState.psychEngineVersion.trim());
		set(lua, 'luaDebugMode', false);
		set(lua, 'luaDeprecatedWarnings', true);
        //Constants
		set(lua, 'Function_StopLua', FunkinLua.Function_StopLua);
		set(lua, 'Function_Stop', FunkinLua.Function_Stop);
		set(lua, 'Function_Continue', FunkinLua.Function_Continue);
        //Screen size
		set(lua, 'screenWidth', FlxG.width);
		set(lua, 'screenHeight', FlxG.height);
		//Script context
		set(lua, 'scriptName', scriptPath);
		set(lua, 'currentModDirectory', Paths.currentModDirectory);
        //Platform
		#if windows
		set(lua, 'buildTarget', 'windows');
		#elseif linux
		set(lua, 'buildTarget', 'linux');
		#elseif mac
		set(lua, 'buildTarget', 'mac');
		#elseif html5
		set(lua, 'buildTarget', 'browser');
		#elseif android
		set(lua, 'buildTarget', 'android');
		#else
		set(lua, 'buildTarget', 'unknown');
		#end
    }

	public static function bindSubstateFunctions(lua:State, state:MusicBeatState, callOnLuas:Dynamic) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "openCustomSubstate", function(name:String, pauseGame:Bool = false) {
			if (state is PlayState && pauseGame) {
				PlayState.instance.persistentUpdate = false;
				PlayState.instance.persistentDraw = true;
				PlayState.instance.paused = true;
				if (FlxG.sound.music != null) {
					FlxG.sound.music.pause();
					PlayState.instance.vocals.pause();
				}
			}
			state.openSubState(new CustomSubstate(name, callOnLuas));
		});
		Lua_helper.add_callback(lua, "closeCustomSubstate", function() {
			if (CustomSubstate.instance != null) {
				state.closeSubState();
				CustomSubstate.instance = null;
				return true;
			}
			return false;
		});
	}

    public static function bindFileAccessFunctions(lua:State, ?luaTrace:Dynamic) {
        if (lua == null) return;
		//Psych
		Lua_helper.add_callback(lua, "checkFileExists", function(filename:String, ?absolute:Bool = false) {
			#if MODS_ALLOWED
			if(absolute)
			{
				return FileSystem.exists(filename);
			}

			var path:String = Paths.modFolders(filename);
			if(FileSystem.exists(path))
			{
				return true;
			}
			return FileSystem.exists(Paths.getPath('assets/$filename', TEXT));
			#else
			if(absolute)
			{
				return Assets.exists(filename);
			}
			return Assets.exists(Paths.getPath('assets/$filename', TEXT));
			#end
		});
		Lua_helper.add_callback(lua, "saveFile", function(path:String, content:String, ?absolute:Bool = false)
		{
			try {
				if(!absolute)
					File.saveContent(Paths.mods(path), content);
				else
					File.saveContent(path, content);

				return true;
			} catch (e:Dynamic) {
				if (luaTrace != null) luaTrace("saveFile: Error trying to save " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		Lua_helper.add_callback(lua, "deleteFile", function(path:String, ?ignoreModFolders:Bool = false)
		{
			try {
				#if MODS_ALLOWED
				if(!ignoreModFolders)
				{
					var lePath:String = Paths.modFolders(path);
					if(FileSystem.exists(lePath))
					{
						FileSystem.deleteFile(lePath);
						return true;
					}
				}
				#end

				var lePath:String = Paths.getPath(path, TEXT);
				if(Assets.exists(lePath))
				{
					FileSystem.deleteFile(lePath);
					return true;
				}
			} catch (e:Dynamic) {
				if (luaTrace != null) luaTrace("deleteFile: Error trying to delete " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		Lua_helper.add_callback(lua, "getTextFromFile", function(path:String, ?ignoreModFolders:Bool = false) {
			return Paths.getTextFromFile(path, ignoreModFolders);
		});
		Lua_helper.add_callback(lua, "directoryFileList", function(folder:String) {
			var list:Array<String> = [];
			#if sys
			if(FileSystem.exists(folder)) {
				for (folder in FileSystem.readDirectory(folder)) {
					if (!list.contains(folder)) {
						list.push(folder);
					}
				}
			}
			#end
			return list;
		});
		//Filext4Psych
		Lua_helper.add_callback(lua, "folderExists", function(targetFolder:String = null, modOnly:Bool = false) {
			#if (MODS_ALLOWED && sys)
			return Paths.xtFindFolder(targetFolder, modOnly) != null;
			#else
			return false;
			#end
		});
		Lua_helper.add_callback(lua, "fileExists", function(targetFile:String = null, modOnly:Bool = false) {
			#if (MODS_ALLOWED && sys)
			return Paths.xtFindFile(targetFile, modOnly) != null;
			#else
			return false;
			#end
		});
		Lua_helper.add_callback(lua, "readFile", function(targetFile:String = null, modOnly:Bool = false) {
			#if (MODS_ALLOWED && sys)
			var path = Paths.xtFindFile(targetFile, modOnly);
			if (path != null) try {
				return File.getContent(path);
			} catch (ex:Dynamic) {
				trace('Error while reading from "$path": $ex');
			}
			#end
			return null;
		});
		Lua_helper.add_callback(lua, "readLines", function(targetFile:String = null, modOnly:Bool = false) {
			var text = Paths.getTextFromFile(targetFile, modOnly);
			return text == null ? null : CoolUtil.listFromString(text, false);
		});
		Lua_helper.add_callback(lua, "writeFile", function(targetFile:String = null, data:String = "", append:Bool = false) {
			#if (MODS_ALLOWED && sys)
			var path = Paths.xtFileWritePath(targetFile);
			if (path != null) try {
				var out:FileOutput = append ? File.append(path) : File.write(path);
				out.writeString(data, haxe.io.Encoding.UTF8);
				out.close();
				return true;
			} catch (ex:Dynamic) {
				trace('Error while writing into "$path": $ex');
			}
			#end
			return false;
		});
		Lua_helper.add_callback(lua, "makeFolder", function(targetFolder:String = null) {
			#if (MODS_ALLOWED && sys)
			var path = Paths.xtFolderCreatePath(targetFolder);
			if (path != null) try {
				FileSystem.createDirectory(path);
				return true;
			} catch (ex:Dynamic) {
				trace('Unable to create folder "$path": $ex');
			}
			#end
			return false;
		});
		Lua_helper.add_callback(lua, "removeFile", function(targetFile:String = null) {
			#if (MODS_ALLOWED && sys)
			if (Paths.currentModDirectory == '') return false;
			var path = Paths.xtFindFile(targetFile, true);
			if (path != null) try {
				FileSystem.deleteFile(path);
				return true;
			} catch (ex:Dynamic) {
				trace('Unable to delete file "$path": $ex');
			}
			#end
			return false;
		});
		Lua_helper.add_callback(lua, "removeFolder", function(targetFolder:String = null) {
			#if (MODS_ALLOWED && sys)
			if (Paths.currentModDirectory == '') return false;
			var path = Paths.xtFindFolder(targetFolder, true);
			if (path != null) try {
				FileSystem.deleteDirectory(path);
				return true;
			} catch (ex:Dynamic) {
				trace('Unable to delete folder "$path": $ex');
			}
			#end
			return false;
		});
    }

	public static function bindSaveDataFunctions(lua:State, state:MusicBeatState, ?luaTrace:Dynamic) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "initSaveData", function(name:String, ?folder:String = 'psychenginemods') {
			if (!state.modchartSaves.exists(name)) {
				var save:FlxSave = new FlxSave();
				// folder goes unused for flixel 5 users. @BeastlyGhost
				save.bind(name, CoolUtil.getSavePath(folder));
				state.modchartSaves.set(name, save);
				return;
			}
			if (luaTrace != null) luaTrace('initSaveData: Save file already initialized: ' + name);
		});
		Lua_helper.add_callback(lua, "flushSaveData", function(name:String) {
			if (state.modchartSaves.exists(name)) {
				state.modchartSaves.get(name).flush();
				return;
			}
			if (luaTrace != null) luaTrace('flushSaveData: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});
		Lua_helper.add_callback(lua, "getDataFromSave", function(name:String, field:String, ?defaultValue:Dynamic = null) {
			if (state.modchartSaves.exists(name)) {
				var retVal:Dynamic = Reflect.field(state.modchartSaves.get(name).data, field);
				return retVal;
			}
			if (luaTrace != null) luaTrace('getDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
			return defaultValue;
		});
		Lua_helper.add_callback(lua, "setDataFromSave", function(name:String, field:String, value:Dynamic) {
			if (state.modchartSaves.exists(name)) {
				Reflect.setField(state.modchartSaves.get(name).data, field, value);
				return;
			}
			if (luaTrace != null) luaTrace('setDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});
	}

    public static function bindInputFunctions(lua:State, state:MusicBeatState, ?luaTrace:Dynamic) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "mouseClicked", function(button:String) {
			var boobs = FlxG.mouse.justPressed;
			switch(button){
				case 'middle':
					boobs = FlxG.mouse.justPressedMiddle;
				case 'right':
					boobs = FlxG.mouse.justPressedRight;
			}
			return boobs;
		});
		Lua_helper.add_callback(lua, "mousePressed", function(button:String) {
			var boobs = FlxG.mouse.pressed;
			switch(button){
				case 'middle':
					boobs = FlxG.mouse.pressedMiddle;
				case 'right':
					boobs = FlxG.mouse.pressedRight;
			}
			return boobs;
		});
		Lua_helper.add_callback(lua, "mouseReleased", function(button:String) {
			var boobs = FlxG.mouse.justReleased;
			switch(button){
				case 'middle':
					boobs = FlxG.mouse.justReleasedMiddle;
				case 'right':
					boobs = FlxG.mouse.justReleasedRight;
			}
			return boobs;
		});
		Lua_helper.add_callback(lua, "keyboardJustPressed", function(name:String) {
			return Reflect.getProperty(FlxG.keys.justPressed, name);
		});
		Lua_helper.add_callback(lua, "keyboardPressed", function(name:String) {
			return Reflect.getProperty(FlxG.keys.pressed, name);
		});
		Lua_helper.add_callback(lua, "keyboardReleased", function(name:String) {
			return Reflect.getProperty(FlxG.keys.justReleased, name);
		});
		Lua_helper.add_callback(lua, "anyGamepadJustPressed", function(name:String) {
			return FlxG.gamepads.anyJustPressed(name);
		});
		Lua_helper.add_callback(lua, "anyGamepadPressed", function(name:String) {
			return FlxG.gamepads.anyPressed(name);
		});
		Lua_helper.add_callback(lua, "anyGamepadReleased", function(name:String) {
			return FlxG.gamepads.anyJustReleased(name);
		});
		Lua_helper.add_callback(lua, "gamepadAnalogX", function(id:Int, ?leftStick:Bool = true) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;
			return controller.getXAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		Lua_helper.add_callback(lua, "gamepadAnalogY", function(id:Int, ?leftStick:Bool = true) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;
			return controller.getYAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		Lua_helper.add_callback(lua, "gamepadJustPressed", function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;
			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		Lua_helper.add_callback(lua, "gamepadPressed", function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;
			return Reflect.getProperty(controller.pressed, name) == true;
		});
		Lua_helper.add_callback(lua, "gamepadReleased", function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;
			return Reflect.getProperty(controller.justReleased, name) == true;
		});
		Lua_helper.add_callback(lua, "keyJustPressed", function(name:String) {
			var key:Bool = false;
			switch(name) {
				case 'left': key = state.getControl('NOTE_LEFT_P');
				case 'down': key = state.getControl('NOTE_DOWN_P');
				case 'up': key = state.getControl('NOTE_UP_P');
				case 'right': key = state.getControl('NOTE_RIGHT_P');
				case 'accept': key = state.getControl('ACCEPT');
				case 'back': key = state.getControl('BACK');
				case 'pause': key = state.getControl('PAUSE');
				case 'reset': key = state.getControl('RESET');
				case 'space': key = FlxG.keys.justPressed.SPACE;//an extra key for convinience
				case 'ui_up': key = state.getControl('UI_UP');
				case 'ui_down': key = state.getControl('UI_DOWN');
				case 'ui_left': key = state.getControl('UI_LEFT');
				case 'ui_right': key = state.getControl('UI_RIGHT');
			}
			return key;
		});
		Lua_helper.add_callback(lua, "keyPressed", function(name:String) {
			var key:Bool = false;
			switch(name) {
				case 'left': key = state.getControl('NOTE_LEFT');
				case 'down': key = state.getControl('NOTE_DOWN');
				case 'up': key = state.getControl('NOTE_UP');
				case 'right': key = state.getControl('NOTE_RIGHT');
				case 'space': key = FlxG.keys.pressed.SPACE;//an extra key for convinience
			}
			return key;
		});
		Lua_helper.add_callback(lua, "keyReleased", function(name:String) {
			var key:Bool = false;
			switch(name) {
				case 'left': key = state.getControl('NOTE_LEFT_R');
				case 'down': key = state.getControl('NOTE_DOWN_R');
				case 'up': key = state.getControl('NOTE_UP_R');
				case 'right': key = state.getControl('NOTE_RIGHT_R');
				case 'space': key = FlxG.keys.justReleased.SPACE;//an extra key for convinience
			}
			return key;
		});
		//XT: Scripted states
		Lua_helper.add_callback(lua, "wasKeyJustPressed", function(key:String):Bool {
			key = key.toUpperCase();
			try {
				return Reflect.getProperty(FlxG.keys.justPressed, key);
			} catch (ex:Any) {
				return false;
			}
		});
		Lua_helper.add_callback(lua, "wasKeyJustReleased", function(key:String):Bool {
			key = key.toUpperCase();
			try {
				return Reflect.getProperty(FlxG.keys.justReleased, key);
			} catch (ex:Any) {
				return false;
			}
		});
		Lua_helper.add_callback(lua, "isKeyPressed", function(key:String):Bool {
			key = key.toUpperCase();
			try {
				return Reflect.getProperty(FlxG.keys.pressed, key);
			} catch (ex:Any) {
				return false;
			}
		});
	}

	public static function bindLocalizationFunctions(lua:State) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "getLangCode", function() {
			return LanguageSupport.currentLangCode();
		});
		Lua_helper.add_callback(lua, "getLangName", function() {
			return LanguageSupport.currentLangName();
		});
	}

	public static function bindAudioFunctions(lua:State, state:MusicBeatState, ?callOnLuas:Dynamic, ?luaTrace:Dynamic) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "luaSoundExists", function(tag:String) {
			return state.modchartSounds.exists(tag);
		});
		Lua_helper.add_callback(lua, "precacheSound", function(name:String) {
			CoolUtil.precacheSound(name);
		});
		Lua_helper.add_callback(lua, "precacheMusic", function(name:String) {
			CoolUtil.precacheMusic(name);
		});
        Lua_helper.add_callback(lua, "playMusic", function(sound:String, volume:Float = 1, loop:Bool = false) {
			FlxG.sound.playMusic(Paths.music(sound), volume, loop);
		});
		Lua_helper.add_callback(lua, "musicFadeIn", function(duration:Float, fromValue:Float = 0, toValue:Float = 1) {
			if (luaTrace != null) luaTrace('musicFadeIn is deprecated! Use soundFadeIn instead.', false, true);
			FlxG.sound.music.fadeIn(duration, fromValue, toValue);
		});
		Lua_helper.add_callback(lua, "musicFadeOut", function(duration:Float, toValue:Float = 0) {
			if (luaTrace != null) luaTrace('musicFadeOut is deprecated! Use soundFadeOut instead.', false, true);
			FlxG.sound.music.fadeOut(duration, toValue);
		});
		Lua_helper.add_callback(lua, "playSound", function(sound:String, volume:Float = 1, ?tag:String = null) {
			if(tag != null && tag.length > 0) {
				tag = tag.replace('.', '');
				if(state.modchartSounds.exists(tag)) {
					state.modchartSounds.get(tag).stop();
				}
				state.modchartSounds.set(tag, FlxG.sound.play(Paths.sound(sound), volume, false, function() {
					state.modchartSounds.remove(tag);
					if (callOnLuas != null) callOnLuas('onSoundFinished', [tag]);
				}));
				return;
			}
			FlxG.sound.play(Paths.sound(sound), volume);
		});
		Lua_helper.add_callback(lua, "stopSound", function(tag:String) {
			if(tag != null && tag.length > 1 && state.modchartSounds.exists(tag)) {
				state.modchartSounds.get(tag).stop();
				state.modchartSounds.remove(tag);
			}
		});
		Lua_helper.add_callback(lua, "pauseSound", function(tag:String) {
			if(tag != null && tag.length > 1 && state.modchartSounds.exists(tag)) {
				state.modchartSounds.get(tag).pause();
			}
		});
		Lua_helper.add_callback(lua, "resumeSound", function(tag:String) {
			if(tag != null && tag.length > 1 && state.modchartSounds.exists(tag)) {
				state.modchartSounds.get(tag).play();
			}
		});
		Lua_helper.add_callback(lua, "soundFadeIn", function(tag:String, duration:Float, fromValue:Float = 0, toValue:Float = 1) {
			if(tag == null || tag.length < 1) {
				FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			} else if(state.modchartSounds.exists(tag)) {
				state.modchartSounds.get(tag).fadeIn(duration, fromValue, toValue);
			}
		});
		Lua_helper.add_callback(lua, "soundFadeOut", function(tag:String, duration:Float, toValue:Float = 0) {
			if(tag == null || tag.length < 1) {
				FlxG.sound.music.fadeOut(duration, toValue);
			} else if(state.modchartSounds.exists(tag)) {
				state.modchartSounds.get(tag).fadeOut(duration, toValue);
			}
		});
		Lua_helper.add_callback(lua, "soundFadeCancel", function(tag:String) {
			if(tag == null || tag.length < 1) {
				if(FlxG.sound.music.fadeTween != null) {
					FlxG.sound.music.fadeTween.cancel();
				}
			} else if(state.modchartSounds.exists(tag)) {
				var theSound:FlxSound = state.modchartSounds.get(tag);
				if(theSound.fadeTween != null) {
					theSound.fadeTween.cancel();
					state.modchartSounds.remove(tag);
				}
			}
		});
		Lua_helper.add_callback(lua, "getSoundVolume", function(tag:String) {
			if(tag == null || tag.length < 1) {
				if(FlxG.sound.music != null) {
					return FlxG.sound.music.volume;
				}
			} else if(state.modchartSounds.exists(tag)) {
				return state.modchartSounds.get(tag).volume;
			}
			return 0;
		});
		Lua_helper.add_callback(lua, "setSoundVolume", function(tag:String, value:Float) {
			if(tag == null || tag.length < 1) {
				if(FlxG.sound.music != null) {
					FlxG.sound.music.volume = value;
				}
			} else if(state.modchartSounds.exists(tag)) {
				state.modchartSounds.get(tag).volume = value;
			}
		});
		Lua_helper.add_callback(lua, "getSoundTime", function(tag:String) {
			if(tag != null && tag.length > 0 && state.modchartSounds.exists(tag)) {
				return state.modchartSounds.get(tag).time;
			}
			return 0;
		});
		Lua_helper.add_callback(lua, "setSoundTime", function(tag:String, value:Float) {
			if(tag != null && tag.length > 0 && state.modchartSounds.exists(tag)) {
				var theSound:FlxSound = state.modchartSounds.get(tag);
				if(theSound != null) {
					var wasResumed:Bool = theSound.playing;
					theSound.pause();
					theSound.time = value;
					if(wasResumed) theSound.play();
				}
			}
		});
	}

	public static function bindTimerFunctions(lua:State, state:MusicBeatState, ?callOnLuas:Dynamic) {
		var cancelTimer = function (tag:String) {
			if (state.modchartTimers.exists(tag)) {
				var timer:FlxTimer = state.modchartTimers.get(tag);
				timer.cancel();
				timer.destroy();
				state.modchartTimers.remove(tag);
			}
		};
		Lua_helper.add_callback(lua, "runTimer", function(tag:String, time:Float = 1, loops:Int = 1, ?onComplete:LuaCallback) {
			cancelTimer(tag);
			state.modchartTimers.set(tag, new ModchartTimer().withCallback(onComplete)
					.start(time, function(tmr:FlxTimer) {
				if (tmr.finished)
					state.modchartTimers.remove(tag);
				if (onComplete != null) {
					onComplete.call([tag, tmr.loops, tmr.loopsLeft]);
					//Once we're done using the callback, we must dealocate its pointer off heap
					if (tmr.finished) onComplete.dispose();
				}
				if (callOnLuas != null) {
					var args:Dynamic = [tag, tmr.loops, tmr.loopsLeft];
					callOnLuas('onTimerCompleted', args);
				}
			}, loops));
		});
		Lua_helper.add_callback(lua, "cancelTimer", function(tag:String) {
			cancelTimer(tag);
		});
	}

	public static function bindRandomizerFunctions(lua:State) {
		Lua_helper.add_callback(lua, "getRandomInt", function(min:Int, max:Int = FlxMath.MAX_VALUE_INT, exclude:String = '') {
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Int> = [];
			for (i in 0...excludeArray.length) {
				toExclude.push(Std.parseInt(excludeArray[i].trim()));
			}
			return FlxG.random.int(min, max, toExclude);
		});
		Lua_helper.add_callback(lua, "getRandomFloat", function(min:Float, max:Float = 1, exclude:String = '') {
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Float> = [];
			for (i in 0...excludeArray.length) {
				toExclude.push(Std.parseFloat(excludeArray[i].trim()));
			}
			return FlxG.random.float(min, max, toExclude);
		});
		Lua_helper.add_callback(lua, "getRandomBool", function(chance:Float = 50) {
			return FlxG.random.bool(chance);
		});
	}

	public static function bindStringFunctions(lua:State) {
		Lua_helper.add_callback(lua, "stringStartsWith", function(str:String, start:String) {
			return str.startsWith(start);
		});
		Lua_helper.add_callback(lua, "stringEndsWith", function(str:String, end:String) {
			return str.endsWith(end);
		});
		Lua_helper.add_callback(lua, "stringSplit", function(str:String, split:String) {
			return str.split(split);
		});
		Lua_helper.add_callback(lua, "stringTrim", function(str:String) {
			return str.trim();
		});
	}

	public static function getBool(lua:State, variable:String):Bool {
		if (lua == null) return false;
		Lua.getglobal(lua, variable);
		var result:String = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);
		return result != null && result == 'true';
	}

	public static function set(lua:State, variable:String, data:Dynamic) {
		if (lua == null) return;
		Convert.toLua(lua, data);
		Lua.setglobal(lua, variable);
	}

    public static function call(lua:State, func:String, args:Array<Dynamic>):Dynamic {
		if (lua == null) return null;
		try {
            //Fetch function
			Lua.getglobal(lua, func);
			var type:Int = Lua.type(lua, -1);
            //Drop on nil or wrong type
			if (type != Lua.LUA_TFUNCTION) {
				if (type > Lua.LUA_TNIL)
					trace("ERROR (" + func + "): attempt to call a " + typeToString(type) + " value");
				Lua.pop(lua, 1);
				return null;
			}
            //Call the function
			for (arg in args) Convert.toLua(lua, arg);
			var status:Int = Lua.pcall(lua, args.length, 1, 0);
			//Handle response
			if (status != Lua.LUA_OK) {
				var error:String = getErrorMessage(lua, status);
				trace("ERROR (" + func + "): " + error);
				return null;
			}
			//Convert and return the result
			var result:Dynamic = cast Convert.fromLua(lua, -1);
			Lua.pop(lua, 1);
			return result;
		}
		catch (e:Dynamic) {
			trace(e);
		}
		return null;
	}
    #end

	public static function typeToString(type:Int):String {
		#if LUA_ALLOWED
		switch(type) {
			case Lua.LUA_TBOOLEAN: return "boolean";
			case Lua.LUA_TNUMBER: return "number";
			case Lua.LUA_TSTRING: return "string";
			case Lua.LUA_TTABLE: return "table";
			case Lua.LUA_TFUNCTION: return "function";
		}
		if (type <= Lua.LUA_TNIL) return "nil";
		#end
		return "unknown";
	}

	public static function getErrorMessage(lua:State, status:Int):String {
		#if LUA_ALLOWED
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);
		if (v != null) v = v.trim();
		if (v == null || v == "") {
			switch(status) {
				case Lua.LUA_ERRRUN: return "Runtime Error";
				case Lua.LUA_ERRMEM: return "Memory Allocation Error";
				case Lua.LUA_ERRERR: return "Critical Error";
			}
			return "Unknown Error";
		}
		return v;
		#end
		return null;
	}
}