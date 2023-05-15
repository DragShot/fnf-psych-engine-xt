package scripting;

import FreeplayState.SongMetadata;
import haxe.ds.StringMap;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxTimer;
import flixel.util.FlxColor;
import flixel.FlxG;
import haxe.Exception;

#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
import llua.LuaCallback;
#end

using StringTools;

class StateLua {
	private var state:ScriptedState;
	public var scriptPath:String;
	#if LUA_ALLOWED
	public var lua(default,null):State; //public read, private write
	#end
	var weeks:Array<WeekData> = null;
	var weeksLua:Array<StringMap<Dynamic>> = null;
	var songs:Array<SongMetadata> = null;
	var songsLua:Array<StringMap<Dynamic>> = null;

	public function new (scriptPath:String, state:ScriptedState) {
		this.state = state;
		this.scriptPath = scriptPath;
		#if LUA_ALLOWED
		this.lua = LuaUtils.makeNewState(scriptPath);
		#end
		if (this.lua == null)
			throw new Exception("There was a Lua error while loading the script");
		trace('Lua script loaded: ' + scriptPath);
		#if LUA_ALLOWED
		deployGlobals();
		deployFunctions();
		#end
		this.call('onLoad');
	}

	private function deployGlobals() {
		LuaUtils.defaultGlobals(this.lua, this.scriptPath);
		//User settings
		set('downscroll', ClientPrefs.downScroll);
		set('middlescroll', ClientPrefs.middleScroll);
		set('framerate', ClientPrefs.framerate);
		set('ghostTapping', ClientPrefs.ghostTapping);
		set('hideHud', ClientPrefs.hideHud);
		set('timeBarType', ClientPrefs.timeBarType);
		set('scoreZoom', ClientPrefs.scoreZoom);
		set('cameraZoomOnBeat', ClientPrefs.camZooms);
		set('flashingLights', ClientPrefs.flashing);
		set('noteOffset', ClientPrefs.noteOffset);
		set('healthBarAlpha', ClientPrefs.healthBarAlpha);
		set('noResetButton', ClientPrefs.noReset);
		set('lowQuality', ClientPrefs.lowQuality);
		set('shadersEnabled', ClientPrefs.shaders);
		//Soundtrack
		set('curBeat', 0);
		set('curDecBeat', 0);
		set('curStep', 0);
		set('curDecStep', 0);
		set('curBpm', Conductor.bpm);
		set('crochet', Conductor.crochet);
		set('stepCrochet', Conductor.stepCrochet);
	}

	private function deployFunctions() {
		LuaUtils.bindSubstateFunctions(lua, state, state.callOnLuas);
		LuaUtils.bindFileAccessFunctions(lua, luaTrace);
		LuaUtils.bindSaveDataFunctions(lua, state, luaTrace);
		LuaUtils.bindLocalizationFunctions(lua);
		LuaUtils.bindAudioFunctions(lua, state, luaTrace);
		LuaUtils.bindRandomizerFunctions(lua);
		LuaUtils.bindStringFunctions(lua);
		LuaUtils.bindTimerFunctions(lua, state, state.callOnLuas);

		/*addCallback("debugPrint", function(...text:Dynamic) {
			luaTrace(text.toArray().join(""), true, false);
		});*/
		addCallback("debugPrint", function(text1:Dynamic = '', ?text2:Dynamic, ?text3:Dynamic, ?text4:Dynamic, ?text5:Dynamic) {
			luaTrace(Std.string(nvl(text1, '')) + Std.string(nvl(text2, ''))
				+ Std.string(nvl(text3, '')) + Std.string(nvl(text4, ''))
				+ Std.string(nvl(text5, '')), true, false);
		});

		//XT: Scripted states
		addCallback("switchState", function(target:String = null, skipTransition:Bool = false) {
			if (target == null) return;
			if (skipTransition) {
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
				CustomFadeTransition.nextCamera = null;
			}
			MusicBeatState.switchState(target);
		});

		addCallback("startFreeplay", function(songName:String, difficulty:Int) {
			//Check availability
			this.getLuaWeeks();
			var chosenWeek:WeekData = null;
			for (i in 0...this.weeks.length) {
				for (songData in this.weeks[i].songs) {
					if (songName == songData[0]) {
						chosenWeek = this.weeks[i];
						PlayState.storyWeek = i;
						break;
					}
				}
			}
			if (chosenWeek == null) return false;
			//Load week
			WeekData.setDirectoryFromWeek(chosenWeek);
			CoolUtil.difficulties = this.weeksLua[PlayState.storyWeek].get('difficulties');
			//Load song
			//state.persistentUpdate = false;
			var songLowercase:String = Paths.formatToSongPath(songName);
			var jsonPath:String = Highscore.formatSong(songLowercase, difficulty);
			PlayState.curFolder = songLowercase; //XT: Data folder
			PlayState.SONG = Song.loadFromJson(jsonPath, songLowercase);
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = difficulty;
			trace('Loading chart: $jsonPath - Week: ${WeekData.getWeekFileName()}');
			LoadingState.loadAndSwitchState(new PlayState());
			return true;
		});

		addCallback("startStoryMode", function(weekName:String, difficulty:Int) {
			//Check availability and load week
			this.getLuaWeeks();
			var chosenWeek:WeekData = null;
			for (i in 0...this.weeks.length) {
				if (weekName == this.weeks[i].fileName) {
					chosenWeek = this.weeks[i];
					PlayState.storyWeek = i;
					break;
				}
			}
			if (chosenWeek == null) return false;
			//Load week
			var luaWeek = this.weeksLua[PlayState.storyWeek];
			WeekData.setDirectoryFromWeek(chosenWeek);
			PlayState.storyPlaylist = luaWeek.get('playlist');
			CoolUtil.difficulties = luaWeek.get('difficulties');
			//Load first song
			var suffix = nvl(CoolUtil.getDifficultyFilePath(difficulty), '');
			PlayState.storyDifficulty = difficulty;
			PlayState.curFolder = Paths.formatToSongPath(PlayState.storyPlaylist[0]); //XT: Data folder
			PlayState.SONG = Song.loadFromJson(PlayState.storyPlaylist[0].toLowerCase() + suffix, PlayState.storyPlaylist[0].toLowerCase());
			PlayState.isStoryMode = true;
			PlayState.campaignScore = 0;
			PlayState.campaignMisses = 0;
			LoadingState.loadAndSwitchState(new PlayState(), true);
			return true;
		});

		addCallback("getWeekData", function(weekName:String = null) {
			return this.getLuaWeeks(weekName);
		});

		addCallback("getSongData", function(songName:String = null) {
			return this.getLuaSongs(songName);
		});
	}

	function getPlaylist(week:WeekData) {
		var playlist:Array<String> = [];
		var songsData:Array<Dynamic> = week.songs;
		for (i in 0...songsData.length) {
			playlist.push(songsData[i][0]);
		}
		return playlist;
	}

	function getDifficulties(week:WeekData) {
		var difficulties = CoolUtil.defaultDifficulties.copy();
		var declrDiffStr:String = Std.string(nvl(week.difficulties, '')).trim();
		var declrDiff:Array<String> = declrDiffStr.split(',');
		if (declrDiffStr.length > 0 && declrDiff.length > 0) {
			var newDiffs = new Array<String>();
			for (diff in declrDiff) {
				diff = diff.trim();
				if (diff.length > 0)
					newDiffs.push(diff);
			}
			if (newDiffs.length > 0)
				difficulties = newDiffs;
		}
		return difficulties;
	}

	function isWeekLocked(week:WeekData) {
		return (!week.startUnlocked && week.weekBefore.length > 0 && (!StoryMenuState.weekCompleted.exists(week.weekBefore) || !StoryMenuState.weekCompleted.get(week.weekBefore)));
	}

	public function getSongs() {
		if (this.songs == null) {
			this.songs = new Array<SongMetadata>();
			var weeks:Array<WeekData> = this.getWeeks();
			for (i in 0...weeks.length) {
				//if (weekIsLocked(weeks[i])) continue;
				WeekData.setDirectoryFromWeek(weeks[i]);
				for (song in weeks[i].songs) {
					var colors:Array<Int> = song[2];
					if (colors == null || colors.length < 3)
						colors = [146, 113, 253];
					songs.push(new SongMetadata(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2])));
				}
			}
		}
		return this.songs;
	}

	public function getLuaSongs(songName:String = null) {
		if (this.songsLua == null) {
			this.songsLua = new Array<StringMap<Dynamic>>();
			var songs:Array<SongMetadata> = this.getSongs();
			for (song in songs) {
				var week = this.weeks[song.week];
				var songData:StringMap<Dynamic> = new StringMap<Dynamic>();
				songData.set('name', song.songName);
				songData.set('character', song.songCharacter);
				songData.set('locked', this.isWeekLocked(week));
				songData.set('difficulties', this.getDifficulties(week));
				songData.set('hideFreeplay', week.hideFreeplay);
				songData.set('week', song.week);
				songData.set('folder', song.folder);
				this.songsLua.push(songData);
			}
		}
		//Return all songs in a list
		if (songName == null) return this.songsLua;
		//Return only the song requested, if it exists
		for (song in this.songsLua)
			if (songName == song.get('name')) return [song];
		//Songs not found, return an empty list
		return [];
	}

	public function getWeeks() {
		if (this.weeks == null) {
			this.weeks = new Array<WeekData>();
			WeekData.reloadWeekFiles(null);
			for (i in 0...WeekData.weeksList.length) {
				var weekFile:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
				WeekData.setDirectoryFromWeek(weekFile);
				this.weeks.push(weekFile);
			}
		}
		return this.weeks;
	}

	public function getLuaWeeks(weekName:String = null) {
		if (this.weeksLua == null) {
			this.weeksLua = new Array<StringMap<Dynamic>>();
			var weeks:Array<WeekData> = this.getWeeks();
			for (week in weeks) {
				var weekData:StringMap<Dynamic> = new StringMap<Dynamic>();
				weekData.set('songs', week.songs);
				weekData.set('playlist', this.getPlaylist(week));
				weekData.set('weekCharacters', week.weekCharacters);
				weekData.set('weekBackground', week.weekBackground);
				weekData.set('weekBefore', week.weekBefore);
				weekData.set('storyName', week.storyName);
				weekData.set('weekName', week.weekName);
				weekData.set('freeplayColor', week.freeplayColor);
				weekData.set('startUnlocked', week.startUnlocked);
				weekData.set('hiddenUntilUnlocked', week.hiddenUntilUnlocked);
				weekData.set('hideStoryMode', week.hideStoryMode);
				weekData.set('hideFreeplay', week.hideFreeplay);
				weekData.set('difficulties', this.getDifficulties(week));
				weekData.set('difficultyString', week.difficulties);
				weekData.set('locked', this.isWeekLocked(week));
				weekData.set('fileName', week.fileName);
				weekData.set('folder', week.folder);
				this.weeksLua.push(weekData);
			}
		}
		//Return all weeks in a list
		if (weekName == null) return this.weeksLua;
		//Return only the week requested, if it exists
		for (week in this.weeksLua)
			if (weekName == week.get('fileName')) return [week];
		//Week not found, return an empty list
		return [];
	}

	public function set(variable:String, data:Dynamic) {
		#if LUA_ALLOWED
		LuaUtils.set(lua, variable, data);
		#end
	}

	public function addCallback(name:String, func:Dynamic) {
		#if LUA_ALLOWED
		Lua_helper.add_callback(lua, name, func);
		#end
	}

	public function removeCallback(name:String) {
		#if LUA_ALLOWED
		Lua_helper.remove_callback(lua, name);
		#end
	}

	public function call(func:String, ?args:Array<Dynamic>):Dynamic {
		if (args == null) args = [];
		#if LUA_ALLOWED
		return LuaUtils.call(lua, func, args);
		#end
	}

	public function dispose() {
		#if LUA_ALLOWED
		if (lua != null) {
			this.call('onDestroy', []);
			Lua.close(lua);
			lua = null;
		}
		#end
	}

	public function luaTrace(text:String, ignoreCheck:Bool = false, deprecated:Bool = false, color:FlxColor = FlxColor.WHITE) {
		#if LUA_ALLOWED
		if (!ignoreCheck && !LuaUtils.getBool(lua, 'luaDebugMode'))
			return;
		if (deprecated && !LuaUtils.getBool(lua, 'luaDeprecatedWarnings'))
			return;
		state.addTextToDebug(text, color);
		trace(text);
		#end
	}

	public function nvl(value:Any, ifNull:Any):Any {
		return value == null ? ifNull : value;
	}
}