package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isPlayer:Bool = false;
	private var char:String = '';

	public var iconW:Int;
	public var iconH:Int;
	public var iconCnt:Int;

	public function new(char:String = 'face', isPlayer:Bool = false, ?allowGPU:Bool = true, iconSet = 0)
	{
		super();
		this.isPlayer = isPlayer;
		changeIcon(char, allowGPU, iconSet);
		scrollFactor.set();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y + 45 - iconH * 0.5);
	}

	private var iconOffsets:Array<Float> = [0, 0];
	public function changeIcon(char:String, ?allowGPU:Bool = true, iconSet:Int = 0) {
		if(this.char != char) {
			var name:String = 'icons/' + char;
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon
			
			var graphic = Paths.image(name, allowGPU);
			var iSize:Float = FlxMath.maxInt(iconSet == 0 ? FlxMath.minInt(Math.round(graphic.width / graphic.height), 3) : iconSet, 1);
			iconCnt = Std.int(iSize);
			
			iconW = Math.round(graphic.width / iSize);
			iconH = Math.round(graphic.height);

			loadGraphic(graphic, true, iconW, iconH);
			
			iconOffsets[0] = (width - iconW) / iSize;
			iconOffsets[1] = (height - iconH) / iSize;
			updateHitbox();

			animation.add(char, [for (i in 0...iconCnt) i], 0, false, isPlayer);
			animation.play(char);
			this.char = char;

			if(char.endsWith('-pixel'))
				antialiasing = false;
			else
				antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	public var autoAdjustOffset:Bool = true;
	override function updateHitbox()
	{
		super.updateHitbox();
		if(autoAdjustOffset)
		{
			offset.x = iconOffsets[0];
			offset.y = iconOffsets[1];
		}
	}

	public function getCharacter():String {
		return char;
	}
}
