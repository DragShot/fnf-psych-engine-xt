package scripting;

import flixel.input.keyboard.FlxKey;
import openfl.events.KeyboardEvent;
import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.system.FlxSound;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSave;
import flixel.util.FlxTimer;
import sys.FileSystem;
import haxe.Exception;

class ScriptedState extends MusicBeatState {
    public var name:String;
    public var script:StateLua;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	private var luaDebugGroup:FlxTypedGroup<DebugLuaText>;

    public function new(name:String) {
        super();
        #if (!MODS_ALLOWED || !LUA_ALLOWED)
        throw new Exception("Scripted states are not available with mods or Lua disabled!");
        #end
        this.name = name;
        #if (MODS_ALLOWED && LUA_ALLOWED && sys)
        var scriptPath = Paths.modsStates(name);
        if (!FileSystem.exists(scriptPath))
            throw new Exception('Could not find any script for the state "$name". Make sure you\'re storing it in the "states/" folder.');
        this.script = new StateLua(scriptPath, this);
        #end
    }

    override function create() {
		#if MODS_ALLOWED
		Paths.pushGlobalMods();
		#end
		WeekData.loadTheFirstEnabledMod();
        super.create();
		camGame = new FlxCamera();
		camOther = new FlxCamera();
		camOther.bgColor.alpha = 0;
		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camOther, false);
		FlxG.cameras.setDefaultDrawTarget(camGame, true);
		CustomFadeTransition.nextCamera = camOther;
		transIn = FlxTransitionableState.defaultTransIn;
		transOut = FlxTransitionableState.defaultTransOut;
		persistentUpdate = persistentDraw = true;
		luaDebugGroup = new FlxTypedGroup<DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
        script.call('onCreate');
    }

	override public function stepHit():Void {
		super.stepHit();
        script.set('curStep', curStep);
        script.set('curBpm', Conductor.bpm);
        script.set('crochet', Conductor.crochet);
        script.set('stepCrochet', Conductor.stepCrochet);
        script.call('onStepHit');
	}

	override public function beatHit():Void {
		super.beatHit();
        script.set('curBeat', curBeat);
        script.call('onBeatHit');
	}

	function onKeyPress(event:KeyboardEvent):Void {
		var key:FlxKey = event.keyCode;
		script.call('onKeyPress', [key]);
	}

	function onKeyRelease(event:KeyboardEvent):Void {
		var key:FlxKey = event.keyCode;
		script.call('onKeyRelease', [key]);
	}

    override function update(elapsed:Float) {
        if (FlxG.sound.music != null) {
			Conductor.songPosition = FlxG.sound.music.time;
        }
        super.update(elapsed);
        script.set('curDecBeat', curDecBeat);
        script.set('curDecStep', curDecStep);
        script.call('onUpdate', [elapsed]);
    }

    override function destroy() {
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
        script.dispose();
		/*for (lua in luaArray) {
			lua.call('onDestroy', []);
			lua.stop();
		}*/
		super.destroy();
	}

    public function callOnLuas(event:String, args:Array<Dynamic>, ignoreStops = true, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
        return script.call(event, args);
    }

	public function addTextToDebug(text:String, color:FlxColor) {
		luaDebugGroup.forEachAlive(function(spr:DebugLuaText) {
			spr.y += 20;
		});
		if(luaDebugGroup.members.length > 34) {
			var blah = luaDebugGroup.members[34];
			luaDebugGroup.remove(blah);
			blah.destroy();
		}
		luaDebugGroup.insert(0, new DebugLuaText(text, luaDebugGroup, color));
	}
}