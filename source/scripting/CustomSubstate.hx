package scripting;

import flixel.FlxG;

class CustomSubstate extends MusicBeatSubstate
{
	public static var name:String = 'unnamed';
	public static var instance:CustomSubstate;
	private var callOnLuas:(String, Array<Dynamic>, ?Bool, ?Array<String>, ?Array<Dynamic>) -> Dynamic;

	override function create()
	{
		instance = this;

		this.callOnLuas('onCustomSubstateCreate', [name]);
		super.create();
		this.callOnLuas('onCustomSubstateCreatePost', [name]);
	}

	public function new(name:String, callFunc:(String, Array<Dynamic>, ?Bool, ?Array<String>, ?Array<Dynamic>) -> Dynamic)
	{
		CustomSubstate.name = name;
		super();
        this.callOnLuas = callFunc;
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
	}

	override function update(elapsed:Float)
	{
		this.callOnLuas('onCustomSubstateUpdate', [name, elapsed]);
		super.update(elapsed);
		this.callOnLuas('onCustomSubstateUpdatePost', [name, elapsed]);
	}

	override function destroy()
	{
		this.callOnLuas('onCustomSubstateDestroy', [name]);
		super.destroy();
	}
}