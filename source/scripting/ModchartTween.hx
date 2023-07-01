package scripting;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import llua.LuaCallback;
import flixel.tweens.FlxTween;

class ModchartTween {
    var tweenObj:FlxTween;
    public var callback:LuaCallback;

    public function new(tween:FlxTween){
        this.tweenObj = tween;
    }

    public static function tween(object:Dynamic, values:Dynamic, duration:Float = 1, ?options:TweenOptions):ModchartTween {
        return new ModchartTween(FlxTween.tween(object, values, duration, options));
    }
	public static function color(?sprite:FlxSprite, duration:Float = 1, fromColor:FlxColor, toColor:FlxColor, ?options:TweenOptions):ModchartTween {
        return new ModchartTween(FlxTween.color(sprite, duration, fromColor, toColor, options));
    }

    public function withCallback(callback:LuaCallback):ModchartTween {
        this.callback = callback;
        return this;
    }

    public function unwrap():FlxTween {
        return this.tweenObj;
    }

    public function cancel() {
        this.tweenObj.cancel();
    }

    public function destroy() {
        this.tweenObj.destroy();
        if (callback != null) callback.dispose();
    }
}