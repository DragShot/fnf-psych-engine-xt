package scripting;

import llua.LuaCallback;
import flixel.util.FlxTimer;

class ModchartTimer extends FlxTimer {
    public var callback:LuaCallback;

    public function withCallback(callback:LuaCallback):ModchartTimer {
        this.callback = callback;
        return this;
    }

    override public function destroy() {
        super.destroy();
        if (callback != null) callback.dispose();
    }
}