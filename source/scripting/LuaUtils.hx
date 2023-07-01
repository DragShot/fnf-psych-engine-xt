package scripting;

import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.text.FlxText;
import openfl.display.BlendMode;
import flixel.FlxObject;
import flixel.FlxCamera;
import animateatlas.AtlasFrameMaker;
import flixel.FlxBasic;
import flixel.FlxSprite;
import Type.ValueType;
import flixel.group.FlxGroup.FlxTypedGroup;
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

#if desktop
import Discord.DiscordClient;
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

    public static function bindDynamicAccessFunctions(lua:State, getInstance: () -> MusicBeatState, ?luaTrace:Dynamic) {
		Lua_helper.add_callback(lua, "getProperty", function(variable:String) {
			return DynamicAccess.getField(getInstance(), variable);
		});
		Lua_helper.add_callback(lua, "setProperty", function(variable:String, value:Dynamic) {
			return DynamicAccess.setField(getInstance(), variable, value);
		});
		Lua_helper.add_callback(lua, "getPropertyFromClass", function(classVar:String, variable:String) {
			@:privateAccess
			return DynamicAccess.getStatic(classVar, variable);
		});
		Lua_helper.add_callback(lua, "setPropertyFromClass", function(classVar:String, variable:String, value:Dynamic) {
			@:privateAccess
			return DynamicAccess.setStatic(classVar, variable, value);
		});
		Lua_helper.add_callback(lua, "getPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic):Dynamic {
			var prop = propertyFromGroup(obj, index, variable, getInstance(), luaTrace);
			return prop == null ? null : prop.getValue();
		});
		Lua_helper.add_callback(lua, "setPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic, value:Dynamic) {
			var prop = propertyFromGroup(obj, index, variable, getInstance(), luaTrace);
			return prop == null ? null : prop.setValue(value);
		});
		Lua_helper.add_callback(lua, "removeFromGroup", function(obj:String, index:Int, dontDestroy:Bool = false) {
			var group:Dynamic = Reflect.getProperty(getInstance(), obj);
			if (Std.isOfType(group, FlxTypedGroup)) {
				var item = group.members[index];
				if (!dontDestroy) item.kill();
				group.remove(item, true);
				if (!dontDestroy) item.destroy();
			} else {
				group.remove(group[index]);
			}
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

    public static function bindSpriteFunctions(lua:State, getInstance: () -> MusicBeatState, ?luaTrace:Dynamic) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "precacheImage", function(name:String) {
			Paths.returnGraphic(name);
		});
		Lua_helper.add_callback(lua, "loadGraphic", function(tag:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0) {
			var spr:FlxSprite = getSprite(getInstance(), tag, false);
			var animated = gridX != 0 || gridY != 0;
			if (spr != null && spr is FlxSprite && image != null && image.length > 0) {
				spr.loadGraphic(Paths.image(image), animated, gridX, gridY);
			}
		});
		Lua_helper.add_callback(lua, "loadFrames", function(tag:String, image:String, spriteType:String = "sparrow") {
			var spr:FlxSprite = getSprite(getInstance(), tag, false);
			if (spr != null && spr is FlxSprite && image != null && image.length > 0) {
				loadFrames(spr, image, spriteType);
			}
		});
		Lua_helper.add_callback(lua, "makeLuaSprite", function(tag:String, image:String, x:Float, y:Float) {
			var instance = getInstance();
			tag = tag.replace('.', '');
			resetSpriteTag(instance, tag);
			var sprite:ModchartSprite = new ModchartSprite(x, y);
			if (image != null && image.length > 0)
				sprite.loadGraphic(Paths.image(image));
			sprite.antialiasing = ClientPrefs.globalAntialiasing;
			instance.modchartSprites.set(tag, sprite);
			sprite.active = true;
		});
		Lua_helper.add_callback(lua, "makeAnimatedLuaSprite", function(tag:String, image:String, x:Float, y:Float, ?spriteType:String = "sparrow") {
			var instance = getInstance();
			tag = tag.replace('.', '');
			resetSpriteTag(instance, tag);
			var sprite:ModchartSprite = new ModchartSprite(x, y);
			loadFrames(sprite, image, spriteType);
			sprite.antialiasing = ClientPrefs.globalAntialiasing;
			instance.modchartSprites.set(tag, sprite);
		});
		Lua_helper.add_callback(lua, "makeGraphic", function(tag:String, width:Int, height:Int, colorHex:String) {
			var color = getColorFromHex(colorHex);
			var sprite:FlxSprite = getSprite(getInstance(), tag, false);
			if (sprite != null)
				sprite.makeGraphic(width, height, color);
		});
		Lua_helper.add_callback(lua, "addAnimationByPrefix", function(tag:String, name:String, prefix:String, framerate:Int = 24, loop:Bool = true) {
			var sprite:FlxSprite = getSprite(getInstance(), tag, false);
			if (sprite != null) {
				sprite.animation.addByPrefix(name, prefix, framerate, loop);
				if (sprite.animation.curAnim == null)
					sprite.animation.play(name, true);
			}
		});
		Lua_helper.add_callback(lua, "addAnimation", function(tag:String, name:String, frames:Array<Int>, framerate:Int = 24, loop:Bool = true) {
			var sprite:FlxSprite = getSprite(getInstance(), tag, false);
			if (sprite != null) {
				sprite.animation.add(name, frames, framerate, loop);
				if (sprite.animation.curAnim == null)
					sprite.animation.play(name, true);
			}
		});
		Lua_helper.add_callback(lua, "addAnimationByIndices", function(tag:String, name:String, prefix:String, indices:String, framerate:Int = 24, loop:Bool = false): Bool {
			return addAnimByIndices(getSprite(getInstance(), tag, false), name, prefix, indices, framerate, loop);
		});
		Lua_helper.add_callback(lua, "addAnimationByIndicesLoop", function(tag:String, name:String, prefix:String, indices:String, framerate:Int = 24): Bool {
			return addAnimByIndices(getSprite(getInstance(), tag, false), name, prefix, indices, framerate, true);
		});
		Lua_helper.add_callback(lua, "playAnim", function(tag:String, name:String, forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0): Bool {
			var instance = getInstance();
			//Try with mod sprites
			var sprite:FlxSprite = instance.getLuaObject(tag, false);
			if (sprite != null) {
				if (sprite.animation.getByName(name) != null) {
					sprite.animation.play(name, forced, reverse, startFrame);
					if (Std.isOfType(sprite, ModchartSprite)) {
						var modspr = cast(sprite, ModchartSprite);
						var offset = modspr.animOffsets.get(name);
						if (offset != null) {
							modspr.offset.set(offset[0], offset[1]);
						}
					}
				}
				return true;
			}
			//Try with source sprites and characters
			sprite = Reflect.getProperty(instance, tag);
			if (sprite != null && sprite is FlxSprite) {
				if (sprite.animation.getByName(name) != null) {
					if (Std.isOfType(sprite, Character)) {
						var char = cast(sprite, Character);
						char.playAnim(name, forced, reverse, startFrame);
					} else
						sprite.animation.play(name, forced, reverse, startFrame);
				}
				return true;
			}
			return false;
		});
		Lua_helper.add_callback(lua, "addOffset", function(tag:String, anim:String, x:Float, y:Float): Bool {
			var instance = getInstance();
			tag = tag.replace('.', '');
			//Try with mod sprites
			var sprite:Any = instance.getLuaObject(tag, false);
			if (sprite != null && sprite is ModchartSprite) {
				cast(sprite, ModchartSprite).animOffsets.set(anim, [x, y]);
				return true;
			}
			//Try with source sprites and characters
			sprite = Reflect.getProperty(instance, tag);
			if (sprite != null && sprite is Character) {
				cast(sprite, Character).addOffset(anim, x, y);
				return true;
			}
			return false;
		});
		Lua_helper.add_callback(lua, "addLuaSprite", function(tag:String, front:Bool = false) {
			var instance = getInstance();
			var sprite:ModchartSprite = instance.modchartSprites.get(tag);
			if (sprite != null && !sprite.wasAdded) {
				if (front || !Std.isOfType(instance, PlayState)) {
					instance.add(sprite);
				} else if (instance is PlayState) {
					var playState = cast(instance, PlayState);
					if (playState.isDead) {
						GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), sprite);
					} else {
						var position:Int = lowestIndexOf(playState, playState.gfGroup, playState.boyfriendGroup, playState.dadGroup);
						playState.insert(position, sprite);
					}
				}
				sprite.wasAdded = true;
			}
		});
		Lua_helper.add_callback(lua, "setGraphicSize", function(tag:String, x:Int, y:Int = 0, updateHitbox:Bool = true) {
			var sprite:FlxSprite = getSprite(getInstance(), tag, false);
			if (sprite != null) {
				sprite.setGraphicSize(x, y);
				if (updateHitbox) sprite.updateHitbox();
			} else
				luaTrace('setGraphicSize: Couldnt find object: ' + tag, false, false, FlxColor.RED);
		});
		Lua_helper.add_callback(lua, "removeLuaSprite", function(tag:String, destroy:Bool = true) {
			var instance = getInstance();
			var sprite:ModchartSprite = instance.modchartSprites.get(tag);
			if (sprite == null) return;
			if (destroy) {
				sprite.kill();
			} if (sprite.wasAdded) {
				instance.remove(sprite, true);
				sprite.wasAdded = false;
			} if (destroy) {
				sprite.destroy();
				instance.modchartSprites.remove(tag);
			}
		});
		Lua_helper.add_callback(lua, "luaSpriteExists", function(tag:String) {
			return getInstance().modchartSprites.exists(tag);
		});
	}

    public static function bindTextFunctions(lua:State, getInstance: () -> MusicBeatState, cameraFromString:Dynamic, ?luaTrace:Dynamic) {
		Lua_helper.add_callback(lua, "makeLuaText", function(tag:String, text:String, width:Int, x:Float, y:Float) {
			var instance = getInstance();
			tag = tag.replace('.', '');
			resetTextTag(instance, tag);
			var cam = cameraFromString == null ? null : cameraFromString('');
			var obj:ModchartText = new ModchartText(x, y, text, width, cam);
			instance.modchartTexts.set(tag, obj);
		});
		Lua_helper.add_callback(lua, "setTextString", function(tag:String, text:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				obj.text = text;
				return true;
			}
			luaTrace("setTextString: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "setTextSize", function(tag:String, size:Int) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				obj.size = size;
				return true;
			}
			luaTrace("setTextSize: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "setTextWidth", function(tag:String, width:Float) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				obj.fieldWidth = width;
				return true;
			}
			luaTrace("setTextWidth: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "setTextBorder", function(tag:String, size:Int, color:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				obj.borderSize = size;
				obj.borderColor = getColorFromHex(color);
				return true;
			}
			luaTrace("setTextBorder: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "setTextColor", function(tag:String, color:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				obj.color = getColorFromHex(color);
				return true;
			}
			luaTrace("setTextColor: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "setTextFont", function(tag:String, newFont:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				obj.font = Paths.font(newFont);
				return true;
			}
			luaTrace("setTextFont: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "setTextItalic", function(tag:String, italic:Bool) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				obj.italic = italic;
				return true;
			}
			luaTrace("setTextItalic: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "setTextAlignment", function(tag:String, alignment:String = 'left') {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				switch(alignment.trim().toLowerCase()) {
					case 'right':
						obj.alignment = RIGHT;
					case 'center':
						obj.alignment = CENTER;
					default:
						obj.alignment = LEFT;
				}
				return true;
			}
			luaTrace("setTextAlignment: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "getTextString", function(tag:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null && obj.text != null) {
				return obj.text;
			}
			luaTrace("getTextString: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return null;
		});
		Lua_helper.add_callback(lua, "getTextSize", function(tag:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				return obj.size;
			}
			luaTrace("getTextSize: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return -1;
		});
		Lua_helper.add_callback(lua, "getTextFont", function(tag:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				return obj.font;
			}
			luaTrace("getTextFont: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return null;
		});
		Lua_helper.add_callback(lua, "getTextWidth", function(tag:String) {
			var obj:FlxText = getTextObject(getInstance(), tag);
			if (obj != null) {
				return obj.fieldWidth;
			}
			luaTrace("getTextWidth: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return 0;
		});
		Lua_helper.add_callback(lua, "addLuaText", function(tag:String) {
			var instance = getInstance();
			if (instance.modchartTexts.exists(tag)) {
				var text:ModchartText = instance.modchartTexts.get(tag);
				if (!text.wasAdded) {
					getInstance().add(text);
					text.wasAdded = true;
				}
			}
		});
		Lua_helper.add_callback(lua, "removeLuaText", function(tag:String, destroy:Bool = true) {
			var instance = getInstance();
			var sprite:ModchartText = instance.modchartTexts.get(tag);
			if (sprite == null) return;
			if (destroy) {
				sprite.kill();
			} if (sprite.wasAdded) {
				instance.remove(sprite, true);
				sprite.wasAdded = false;
			} if (destroy) {
				sprite.destroy();
				instance.modchartTexts.remove(tag);
			}
		});
		Lua_helper.add_callback(lua, "luaTextExists", function(tag:String) {
			return getInstance().modchartTexts.exists(tag);
		});
	}

    public static function bindObjectFunctions(lua:State, getInstance: () -> MusicBeatState, cameraFromString: (String) -> FlxCamera, ?luaTrace:Dynamic) {
		Lua_helper.add_callback(lua, "getObjectOrder", function(obj:String) {
			var instance = getInstance();
			var sprite:FlxBasic = getSprite(instance, obj);
			if (sprite != null)
				return instance.members.indexOf(sprite);
			else
				luaTrace("getObjectOrder: Object \"" + obj + "\" doesn't exist!", false, false, FlxColor.RED);
			return -1;
		});
		Lua_helper.add_callback(lua, "setObjectOrder", function(obj:String, position:Int) {
			var instance = getInstance();
			var sprite:FlxBasic = getSprite(instance, obj);
			if (sprite != null) {
				instance.remove(sprite, true);
				instance.insert(position, sprite);
			} else{
				luaTrace("setObjectOrder: Object \"" + obj + "\" doesn't exist!", false, false, FlxColor.RED);
			}
		});
		Lua_helper.add_callback(lua, "setObjectCamera", function(obj:String, camera:String = ''): Bool {
			var sprite:FlxSprite = getSprite(getInstance(), obj);
			if (sprite != null) {
				sprite.cameras = [cameraFromString(camera)];
				return true;
			}
			luaTrace("setObjectCamera: Object \"" + obj + "\" doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "getMidpointX", function(obj:String): Float {
			var spr:FlxSprite = getSprite(getInstance(), obj);
			if (spr != null) return spr.getMidpoint().x;
			return 0;
		});
		Lua_helper.add_callback(lua, "getMidpointY", function(obj:String): Float {
			var spr:FlxSprite = getSprite(getInstance(), obj);
			if (spr != null) return spr.getMidpoint().y;
			return 0;
		});
		Lua_helper.add_callback(lua, "getGraphicMidpointX", function(obj:String): Float {
			var spr:FlxSprite = getSprite(getInstance(), obj);
			if (spr != null) return spr.getGraphicMidpoint().x;
			return 0;
		});
		Lua_helper.add_callback(lua, "getGraphicMidpointY", function(obj:String): Float {
			var spr:FlxSprite = getSprite(getInstance(), obj);
			if (spr != null) return spr.getGraphicMidpoint().y;
			return 0;
		});
		Lua_helper.add_callback(lua, "getScreenPositionX", function(obj:String): Float {
			var spr:FlxSprite = getSprite(getInstance(), obj);
			if (spr != null) return spr.getScreenPosition().x;
			return 0;
		});
		Lua_helper.add_callback(lua, "getScreenPositionY", function(obj:String): Float {
			var spr:FlxSprite = getSprite(getInstance(), obj);
			if (spr != null) return spr.getScreenPosition().y;
			return 0;
		});
		Lua_helper.add_callback(lua, "setScrollFactor", function(obj:String, scrollX:Float, scrollY:Float) {
			var sprite:FlxSprite = getSprite(getInstance(), obj);
			if (sprite != null)
				sprite.scrollFactor.set(scrollX, scrollY);
		});
		Lua_helper.add_callback(lua, "scaleObject", function(obj:String, x:Float, y:Float, updateHitbox:Bool = true) {
			var sprite:FlxSprite = getSprite(getInstance(), obj);
			if (sprite != null) {
				sprite.scale.set(x, y);
				if (updateHitbox) sprite.updateHitbox();
			} else
				luaTrace('scaleObject: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		Lua_helper.add_callback(lua, "updateHitbox", function(obj:String) {
			var sprite:FlxSprite = getSprite(getInstance(), obj);
			if (sprite != null)
				sprite.updateHitbox();
			else
				luaTrace('updateHitbox: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		Lua_helper.add_callback(lua, "updateHitboxFromGroup", function(group:String, index:Int) {
			var obj:Dynamic = DynamicAccess.getField(getInstance(), group);
			if (obj == null)
				luaTrace('updateHitboxFromGroup: Couldnt find object: ' + group, false, false, FlxColor.RED);
			else if (obj is FlxTypedGroup)
				obj.members[index].updateHitbox();
			else
				obj[index].updateHitbox();
		});
		Lua_helper.add_callback(lua, "setBlendMode", function(obj:String, blend:String = ''): Bool {
			var sprite:FlxSprite = getSprite(getInstance(), obj, true);
			if (sprite != null) {
				sprite.blend = blendModeFromString(blend);
				return true;
			}
			luaTrace("setBlendMode: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "screenCenter", function(obj:String, pos:String = 'xy') {
			var sprite:FlxSprite = getSprite(getInstance(), obj, true);
			if (sprite != null) {
				switch (pos.trim().toLowerCase()) {
					case 'x': sprite.screenCenter(X);
					case 'y': sprite.screenCenter(Y);
					default: sprite.screenCenter(XY);
				}
				return;
			}
			luaTrace("screenCenter: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
		});
		Lua_helper.add_callback(lua, "objectsOverlap", function(obj1:String, obj2:String) {
			var instance = getInstance();
			var sprites:Array<FlxSprite> = [
				getSprite(instance, obj1, true),
				getSprite(instance, obj2, true)
			];
			return !sprites.contains(null) && FlxG.overlap(sprites[0], sprites[1]);
		});
		Lua_helper.add_callback(lua, "getPixelColor", function(obj:String, x:Int, y:Int) {
			var sprite:FlxSprite = getSprite(getInstance(), obj, true);
			if (sprite != null) {
				if (sprite.framePixels != null) sprite.framePixels.getPixel32(x, y);
				return sprite.pixels.getPixel32(x, y);
			}
			return 0;
		});
		Lua_helper.add_callback(lua, "getColorFromHex", function(color:String): Int {
			return getColorFromHex(color);
		});
	}

    public static function bindCameraFunctions(lua:State, cameraFromString: (String) -> FlxCamera, ?luaTrace:Dynamic) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "cameraShake", function(camera:String, intensity:Float, duration:Float) {
			cameraFromString(camera).shake(intensity, duration);
		});
		Lua_helper.add_callback(lua, "cameraFlash", function(camera:String, color:String, duration:Float,forced:Bool) {
			cameraFromString(camera).flash(getColorFromHex(color), duration,null,forced);
		});
		Lua_helper.add_callback(lua, "cameraFade", function(camera:String, color:String, duration:Float,forced:Bool) {
			cameraFromString(camera).fade(getColorFromHex(color), duration,false,null,forced);
		});
		Lua_helper.add_callback(lua, "getMouseX", function(camera:String): Float {
			return FlxG.mouse.getScreenPosition(cameraFromString(camera)).x;
		});
		Lua_helper.add_callback(lua, "getMouseY", function(camera:String): Float {
			return FlxG.mouse.getScreenPosition(cameraFromString(camera)).y;
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
		Lua_helper.add_callback(lua, "getSongPosition", function() {
			return Conductor.songPosition;
		});
	}

	public static function bindTweenFunctions(lua:State, state:MusicBeatState, ?callOnLuas:Dynamic, ?luaTrace:Dynamic) {
		if (lua == null) return;
		var cancelTween = function(tag:String) {
			var tween:ModchartTween = state.modchartTweens.get(tag);
			if (tween != null) {
				tween.cancel();
				tween.destroy();
				state.modchartTweens.remove(tag);
			}
		}
		var fetchForTween = function(tag:String, vars:String) {
			cancelTween(tag);
			return getSprite(state, vars);
		}
		Lua_helper.add_callback(lua, "doTweenX", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String, ?callback:LuaCallback) {
			var obj:Dynamic = fetchForTween(tag, vars);
			if (obj != null) {
				state.modchartTweens.set(tag, ModchartTween.tween(obj, {x: value}, duration, {ease: easeFromString(ease),
					onComplete: function(twn:FlxTween) {
						if (callOnLuas != null) callOnLuas('onTweenCompleted', [tag]);
						state.modchartTweens.remove(tag);
						if (callback != null) {
							callback.call([tag]);
							callback.dispose();
						}
					}
				}).withCallback(callback));
			} else {
				luaTrace('doTweenX: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		Lua_helper.add_callback(lua, "doTweenY", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String, ?callback:LuaCallback) {
			var obj:Dynamic = fetchForTween(tag, vars);
			if (obj != null) {
				state.modchartTweens.set(tag, ModchartTween.tween(obj, {y: value}, duration, {ease: easeFromString(ease),
					onComplete: function(twn:FlxTween) {
						if (callOnLuas != null) callOnLuas('onTweenCompleted', [tag]);
						state.modchartTweens.remove(tag);
						if (callback != null) {
							callback.call([tag]);
							callback.dispose();
						}
					}
				}).withCallback(callback));
			} else {
				luaTrace('doTweenY: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		Lua_helper.add_callback(lua, "doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String, ?callback:LuaCallback) {
			var obj:Dynamic = fetchForTween(tag, vars);
			if (obj != null) {
				state.modchartTweens.set(tag, ModchartTween.tween(obj, {angle: value}, duration, {ease: easeFromString(ease),
					onComplete: function(twn:FlxTween) {
						if (callOnLuas != null) callOnLuas('onTweenCompleted', [tag]);
						state.modchartTweens.remove(tag);
						if (callback != null) {
							callback.call([tag]);
							callback.dispose();
						}
					}
				}).withCallback(callback));
			} else {
				luaTrace('doTweenAngle: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		Lua_helper.add_callback(lua, "doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String, ?callback:LuaCallback) {
			var obj:Dynamic = fetchForTween(tag, vars);
			if (obj != null) {
				state.modchartTweens.set(tag, ModchartTween.tween(obj, {alpha: value}, duration, {ease: easeFromString(ease),
					onComplete: function(twn:FlxTween) {
						if (callOnLuas != null) callOnLuas('onTweenCompleted', [tag]);
						state.modchartTweens.remove(tag);
						if (callback != null) {
							callback.call([tag]);
							callback.dispose();
						}
					}
				}).withCallback(callback));
			} else {
				luaTrace('doTweenAlpha: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		Lua_helper.add_callback(lua, "doTweenZoom", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String, ?callback:LuaCallback) {
			var obj:Dynamic = fetchForTween(tag, vars);
			if (obj != null) {
				state.modchartTweens.set(tag, ModchartTween.tween(obj, {zoom: value}, duration, {ease: easeFromString(ease),
					onComplete: function(twn:FlxTween) {
						if (callOnLuas != null) callOnLuas('onTweenCompleted', [tag]);
						state.modchartTweens.remove(tag);
						if (callback != null) {
							callback.call([tag]);
							callback.dispose();
						}
					}
				}).withCallback(callback));
			} else {
				luaTrace('doTweenZoom: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		Lua_helper.add_callback(lua, "doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ease:String, ?callback:LuaCallback) {
			var obj:Dynamic = fetchForTween(tag, vars);
			if (obj != null) {
				var color:Int = getColorFromHex(targetColor);
				var curColor:FlxColor = obj.color;
				curColor.alphaFloat = obj.alpha;
				state.modchartTweens.set(tag, ModchartTween.color(obj, duration, curColor, color, {ease: easeFromString(ease),
					onComplete: function(twn:FlxTween) {
						if (callOnLuas != null) callOnLuas('onTweenCompleted', [tag]);
						state.modchartTweens.remove(tag);
						if (callback != null) {
							callback.call([tag]);
							callback.dispose();
						}
					}
				}).withCallback(callback));
			} else {
				luaTrace('doTweenColor: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		Lua_helper.add_callback(lua, "cancelTween", function(tag:String) {
			cancelTween(tag);
		});
	}

	public static function bindTimerFunctions(lua:State, state:MusicBeatState, ?callOnLuas:Dynamic) {
		if (lua == null) return;
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
		if (lua == null) return;
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
		if (lua == null) return;
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

	public static function bindPresenceFunctions(lua:State) {
		if (lua == null) return;
		Lua_helper.add_callback(lua, "changePresence", function(details:String, state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float) {
			#if desktop
			DiscordClient.changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp);
			#end
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

	static function lowestIndexOf(instance: MusicBeatState, ...objects: FlxObject) {
		var min = -1, idx;
		for (obj in objects) {
			idx = instance.members.indexOf(obj);
			if (idx != -1 && (idx != -1 && idx < min))
				min = idx;
		}
		return min;
	}

	static function resetTextTag(instance: MusicBeatState, tag: String) {
		var obj:ModchartText = instance.modchartTexts.get(tag);
		if (obj == null) return;
		obj.kill();
		if (obj.wasAdded) instance.remove(obj, true);
		obj.destroy();
		instance.modchartTexts.remove(tag);
	}

	static function resetSpriteTag(instance: MusicBeatState, tag:String) {
		var obj:ModchartText = instance.modchartTexts.get(tag);
		if (obj == null) return;
		obj.kill();
		if (obj.wasAdded) instance.remove(obj, true);
		obj.destroy();
		instance.modchartSprites.remove(tag);
	}
	
	static function addAnimByIndices(sprite:FlxSprite, name:String, prefix:String, indexes:String, framerate:Int = 24, loop:Bool = false) {
		if (sprite == null) return false;
		var indexSplit:Array<String> = indexes.trim().split(',');
		var indexArray:Array<Int> = [];
		for (i in 0...indexSplit.length) {
			indexArray.push(Std.parseInt(indexSplit[i]));
		}
		sprite.animation.addByIndices(name, prefix, indexArray, '', framerate, loop);
		if (sprite.animation.curAnim == null)
			sprite.animation.play(name, true);
		return true;
	}

	static function blendModeFromString(blend: String): BlendMode {
		switch(blend.toLowerCase().trim()) {
			case 'add': return ADD;
			case 'alpha': return ALPHA;
			case 'darken': return DARKEN;
			case 'difference': return DIFFERENCE;
			case 'erase': return ERASE;
			case 'hardlight': return HARDLIGHT;
			case 'invert': return INVERT;
			case 'layer': return LAYER;
			case 'lighten': return LIGHTEN;
			case 'multiply': return MULTIPLY;
			case 'overlay': return OVERLAY;
			case 'screen': return SCREEN;
			case 'shader': return SHADER;
			case 'subtract': return SUBTRACT;
		}
		return NORMAL;
	}

	static function easeFromString(?ease:String = '') {
		switch(ease.toLowerCase().trim()) {
			case 'backin': return FlxEase.backIn;
			case 'backinout': return FlxEase.backInOut;
			case 'backout': return FlxEase.backOut;
			case 'bouncein': return FlxEase.bounceIn;
			case 'bounceinout': return FlxEase.bounceInOut;
			case 'bounceout': return FlxEase.bounceOut;
			case 'circin': return FlxEase.circIn;
			case 'circinout': return FlxEase.circInOut;
			case 'circout': return FlxEase.circOut;
			case 'cubein': return FlxEase.cubeIn;
			case 'cubeinout': return FlxEase.cubeInOut;
			case 'cubeout': return FlxEase.cubeOut;
			case 'elasticin': return FlxEase.elasticIn;
			case 'elasticinout': return FlxEase.elasticInOut;
			case 'elasticout': return FlxEase.elasticOut;
			case 'expoin': return FlxEase.expoIn;
			case 'expoinout': return FlxEase.expoInOut;
			case 'expoout': return FlxEase.expoOut;
			case 'quadin': return FlxEase.quadIn;
			case 'quadinout': return FlxEase.quadInOut;
			case 'quadout': return FlxEase.quadOut;
			case 'quartin': return FlxEase.quartIn;
			case 'quartinout': return FlxEase.quartInOut;
			case 'quartout': return FlxEase.quartOut;
			case 'quintin': return FlxEase.quintIn;
			case 'quintinout': return FlxEase.quintInOut;
			case 'quintout': return FlxEase.quintOut;
			case 'sinein': return FlxEase.sineIn;
			case 'sineinout': return FlxEase.sineInOut;
			case 'sineout': return FlxEase.sineOut;
			case 'smoothstepin': return FlxEase.smoothStepIn;
			case 'smoothstepinout': return FlxEase.smoothStepInOut;
			case 'smoothstepout': return FlxEase.smoothStepInOut;
			case 'smootherstepin': return FlxEase.smootherStepIn;
			case 'smootherstepinout': return FlxEase.smootherStepInOut;
			case 'smootherstepout': return FlxEase.smootherStepOut;
		}
		return FlxEase.linear;
	}

	static function propertyFromGroup(obj:String, index:Int, variable:Dynamic, instance:MusicBeatState, ?luaTrace:Dynamic):DynamicAccesor {
		var group:Dynamic = DynamicAccess.getField(instance, obj);
		if (group == null) {
			if (luaTrace != null)
				luaTrace("propertyFromGroup: Group \"" + obj + "\" doesn't exist!", false, false, FlxColor.RED);
			return null;
		}
		var item:Dynamic = null;
		if (group is FlxTypedGroup) {
			item = group.members[index];
		} else {
			item = group[index];
		}
		if (item == null) {
			if (luaTrace != null)
				luaTrace("propertyFromGroup: Object #" + index + " from group \"" + obj + "\" doesn't exist!", false, false, FlxColor.RED);
			return null;
		}
		var prop:DynamicAccesor = null;
		if (Type.typeof(variable) == ValueType.TInt) {
			prop = new DynamicAccesor().target(item, null, variable);
		} else {
			prop = DynamicAccess.forField(item, variable);
		}
		return prop;
	}

	public static function getSprite(instance: MusicBeatState, tag: String, includeTexts: Bool = true): FlxSprite {
		var sprite:FlxSprite = null;
		if (tag.contains('.')) {
			var paths = tag.split('.');
			sprite = instance.getLuaObject(paths[0], includeTexts);
			if (sprite != null) {
				sprite = DynamicAccess.getField(sprite, tag.substring(paths[0].length + 1));
			}
		} else {
			sprite = instance.getLuaObject(tag, includeTexts);
		}
		if (sprite == null) sprite = DynamicAccess.getField(instance, tag);
		return sprite;
	}

	public static function getTextObject(instance: MusicBeatState, name: String): FlxText {
		var obj = instance.modchartTexts.get(name);
		if (obj == null) obj = DynamicAccess.getField(instance, name);
		return obj is FlxText ? obj : null;
	}

	public static function loadFrames(spr:FlxSprite, image:String, spriteType:String) {
		switch (spriteType.toLowerCase().trim()) {
			case "texture" | "textureatlas" | "tex":
				spr.frames = AtlasFrameMaker.construct(image);
			case "texture_noaa" | "textureatlas_noaa" | "tex_noaa":
				spr.frames = AtlasFrameMaker.construct(image, null, true);
			case "packer" | "packeratlas" | "pac":
				spr.frames = Paths.getPackerAtlas(image);
			default:
				spr.frames = Paths.getSparrowAtlas(image);
		}
	}

	public static function getColorFromHex(hex: String) {
		if (!hex.startsWith('0x')) {
			if (hex.length == 3) {
				hex = '0xff' + hex.charAt(0) + hex.charAt(0)
				+ hex.charAt(1) + hex.charAt(1)
				+ hex.charAt(2) + hex.charAt(2);
			} else if (hex.length == 6) {
				hex = '0xff' + hex;
			} else {
				hex = '0x' + hex;
			}
		}
		return Std.parseInt(hex);
	}

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