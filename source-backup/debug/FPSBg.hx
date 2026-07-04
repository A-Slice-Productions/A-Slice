package debug;

import openfl.display.Sprite;

class FPSBg extends Sprite
{
	var bgCard:Sprite;
    var isShow:Bool = false;
	public var offsetY:Float = 0;
	public var offsetX:Float = 0;

    public function new()
    {
        super();

		bgCard = new Sprite();
		bgCard.graphics.beginFill(0x000000, 0.5);
		bgCard.graphics.drawRect(0, 0, 320, 55);
		bgCard.graphics.endFill();
		addChild(bgCard);
    }

	public inline function relocate(X:Float, Y:Float, isWide:Bool = false)
	{
		var lineHeight:Float = 16;
		// XOR - !A != !B
		if (!ClientPrefs.data.showMemory != !ClientPrefs.data.showOS) Main.fpsBg.offsetY = -lineHeight;
		else if (ClientPrefs.data.showMemory && ClientPrefs.data.showOS) Main.fpsBg.offsetY = 0;
		else Main.fpsBg.offsetY = -lineHeight * 2;

		Main.fpsBg.offsetX = (ClientPrefs.data.worldRecordMode && ClientPrefs.data.ffmpegMode) ? 0 : -38;

		if (isWide) {
			x = X + offsetX; y = Y + offsetY;
		} else {
			x = FlxG.game.x + X + offsetX;
			y = FlxG.game.y + Y + offsetY;
		}
	}
}