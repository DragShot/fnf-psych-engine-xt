package scripting;

import flixel.FlxCamera;
import flixel.util.FlxColor;
import flixel.text.FlxText;

class ModchartText extends FlxText
{
	public var wasAdded:Bool = false;
	public function new(x:Float, y:Float, text:String, width:Float, ?camera:FlxCamera)
	{
		super(x, y, width, text, 16);
		setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		if (camera == null && PlayState.instance != null)
			camera = PlayState.instance.camHUD;
		if (camera != null)
			cameras = [camera];
		scrollFactor.set();
		borderSize = 2;
	}
}