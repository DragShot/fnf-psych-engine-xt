package;

import editors.MasterEditorMenu;
import scripting.ModchartTween;
import Conductor.BPMChangeEvent;
import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.addons.ui.FlxUIState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxRect;
import flixel.system.FlxSound;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxGradient;
import flixel.util.FlxSave;
import flixel.util.FlxTimer;
//XT: Scripted states
import scripting.DebugLuaText;
import scripting.ModchartSprite;
import scripting.ModchartText;
//

using StringTools;

class MusicBeatState extends FlxUIState
{
	//XT: Scripted states
	public static inline var TITLE_STATE:String = 'title';
	public static inline var MAINMENU_STATE:String = 'main_menu';
	public static inline var STORYMODE_STATE:String = 'story_mode';
	public static inline var FREEPLAY_STATE:String = 'freeplay';
	public static inline var AWARDS_STATE:String = 'awards';
	public static inline var CREDITS_STATE:String = 'credits';
	public static inline var OPTIONS_STATE:String = 'options';
	public static inline var MODEDITOR_STATE:String = 'mod_editor';
	//

	#if (haxe >= "4.0.0")
	public var modchartTweens:Map<String, ModchartTween> = new Map<String, ModchartTween>();
	public var modchartSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartTexts:Map<String, ModchartText> = new Map<String, ModchartText>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();
	#else
	public var modchartTweens:Map<String, ModchartTween> = new Map();
	public var modchartSprites:Map<String, ModchartSprite> = new Map();
	public var modchartTimers:Map<String, FlxTimer> = new Map();
	public var modchartSounds:Map<String, FlxSound> = new Map();
	public var modchartTexts:Map<String, ModchartText> = new Map();
	public var modchartSaves:Map<String, FlxSave> = new Map();
	#end

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	private var prevModDir:String; //XT: Scripted states

	public static var camBeat:FlxCamera;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	override function create() {
		camBeat = FlxG.camera;
		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		super.create();

		if(!skip) {
			openSubState(new CustomFadeTransition(0.7, true));
		}
		FlxTransitionableState.skipNextTransOut = false;
	}

	override function update(elapsed:Float)
	{
		//everyStep();
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep)
		{
			if(curStep > 0)
				stepHit();

			if(PlayState.SONG != null)
			{
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		if(FlxG.save.data != null) FlxG.save.data.fullscreen = FlxG.fullscreen;

		super.update(elapsed);
	}

	private function updateSection():Void
	{
		if(stepsToDo < 1) stepsToDo = Math.round(getBeatsOnSection() * 4);
		while(curStep >= stepsToDo)
		{
			curSection++;
			var beats:Float = getBeatsOnSection();
			stepsToDo += Math.round(beats * 4);
			sectionHit();
		}
	}

	private function rollbackSection():Void
	{
		if(curStep < 0) return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			if (PlayState.SONG.notes[i] != null)
			{
				stepsToDo += Math.round(getBeatsOnSection() * 4);
				if(stepsToDo > curStep) break;
				
				curSection++;
			}
		}

		if(curSection > lastSection) sectionHit();
	}

	private function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
		curDecBeat = curDecStep/4;
	}

	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
		//trace('step = $curStep');
	}

	//XT: Scripted states
	public static function switchState(nextState:Dynamic) { //FlxState|String
		if (nextState == null) {
			MusicBeatState._switchState(FlxG.state);
		} else if (nextState is FlxState) {
			MusicBeatState._switchState(nextState);
		} else if (nextState is String) {
			var state: String = nextState;
			if (state.startsWith('#')) { //Custom state class, because the game has many and mods would rarely ever use them
				state = state.substring(1);
				var clazz = Type.resolveClass(state);
				if (clazz != null && Type.createEmptyInstance(clazz) is FlxState)
					MusicBeatState._switchState(Type.createInstance(clazz, []));
				return;
			}
			switch (nextState) {
				case TITLE_STATE:
					if (!loadCustomState(TITLE_STATE))
						MusicBeatState._switchState(new TitleState());
				case MAINMENU_STATE:
					if (!loadCustomState(MAINMENU_STATE))
						MusicBeatState._switchState(new MainMenuState());
				case STORYMODE_STATE:
					if (!loadCustomState(STORYMODE_STATE))
						MusicBeatState._switchState(new StoryMenuState());
				case FREEPLAY_STATE:
					if (!loadCustomState(FREEPLAY_STATE))
						MusicBeatState._switchState(new FreeplayState());
				case AWARDS_STATE:
					if (!loadCustomState(AWARDS_STATE))
						MusicBeatState._switchState(new AchievementsMenuState());
				case CREDITS_STATE:
					if (!loadCustomState(CREDITS_STATE))
						MusicBeatState._switchState(new CreditsState());
				case OPTIONS_STATE:
					if (!loadCustomState(OPTIONS_STATE))
						LoadingState.loadAndSwitchState(new options.OptionsState());
				case MODEDITOR_STATE:
					MusicBeatState._switchState(new editors.MasterEditorMenu());
				default:
					#if MODS_ALLOWED
					try {
						MusicBeatState._switchState(new scripting.ScriptedState(nextState));
					} catch (ex:Dynamic) {
						trace('Could not load custom state "$nextState". Reason: $ex');
					}
					#else
						trace('Custom states are not supported with mods disabled!');
					#end
			}
		} else {
			trace('Unsupported call to switchState("$nextState")');
		}
	}

	private static function loadCustomState(name:String):Bool {
		#if MODS_ALLOWED
		try {
			MusicBeatState.switchState(new scripting.ScriptedState(name));
			return true;
		} catch (ex:Dynamic) {
			var msg = '$ex';
			if (!(ex is haxe.Exception && msg.startsWith("Could not find any script")))
				trace('Could not load state "$name". Reason: $ex');
		}
		#end
		return false;
	}
	//

	private static function _switchState(nextState:FlxState) { //XT
		// Custom made Trans in
		var curState:Dynamic = FlxG.state;
		var leState:MusicBeatState = curState;
		if(!FlxTransitionableState.skipNextTransIn) {
			leState.openSubState(new CustomFadeTransition(0.6, false));
			if(nextState == FlxG.state) {
				CustomFadeTransition.finishCallback = function() {
					FlxG.resetState();
				};
				//trace('resetted');
			} else {
				CustomFadeTransition.finishCallback = function() {
					FlxG.switchState(nextState);
				};
				//trace('changed state');
			}
			return;
		}
		FlxTransitionableState.skipNextTransIn = false;
		FlxG.switchState(nextState);
	}

	public static function resetState() {
		MusicBeatState._switchState(FlxG.state); //XT
	}

	public static function getState():MusicBeatState {
		var curState:Dynamic = FlxG.state;
		var leState:MusicBeatState = curState;
		return leState;
	}

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		//trace('Beat: ' + curBeat);
	}

	public function sectionHit():Void
	{
		//trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
	}

	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}

	public function getControl(key:String) {
		var pressed:Bool = Reflect.getProperty(controls, key);
		//trace('Control result: ' + pressed);
		return pressed;
	}

	public function getLuaObject(tag:String, text:Bool = true):FlxSprite {
		if (modchartSprites.exists(tag))
			return modchartSprites.get(tag);
		if (text && modchartTexts.exists(tag))
			return modchartTexts.get(tag);
		return null;
	}

	public function hasLuaObject(tag:String, text:Bool = true):Bool {
		return modchartSprites.exists(tag) || (text && modchartTexts.exists(tag));
	}
}
