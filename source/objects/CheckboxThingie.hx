package objects;

import flixel.graphics.frames.FlxAtlasFrames;

class CheckboxThingie extends FlxSprite
{
	static var _cachedFrames:FlxAtlasFrames = null;

	public var sprTracker:FlxSprite;
	public var daValue(default, set):Bool;
	public var copyAlpha:Bool = true;
	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public function new(x:Float = 0, y:Float = 0, ?checked = false) {
		super(x, y);

		if(_cachedFrames == null || _cachedFrames.parent == null || _cachedFrames.parent.bitmap == null || _cachedFrames.parent.isDestroyed || _cachedFrames.parent.shader == null)
			_cachedFrames = Paths.getSparrowAtlas('checkboxanim');
		frames = _cachedFrames;
		animation.addByPrefix("unchecked", "checkbox0", 24, false);
		animation.addByPrefix("unchecking", "checkbox anim reverse", 24, false);
		animation.addByPrefix("checking", "checkbox anim0", 24, false);
		animation.addByPrefix("checked", "checkbox finish", 24, false);

		antialiasing = ClientPrefs.data.antialiasing;
		setGraphicSize(Std.int(0.9 * width));
		updateHitbox();

		animationFinished(checked ? 'checking' : 'unchecking');
		animation.finishCallback = animationFinished;
		daValue = checked;
	}

	override function update(elapsed:Float) {
		if (sprTracker != null) {
			setPosition(sprTracker.x - 130 + offsetX, sprTracker.y + 30 + offsetY);
			if(copyAlpha) {
				alpha = sprTracker.alpha;
			}
		}
		super.update(elapsed);
	}

	private function set_daValue(check:Bool):Bool {
		var curAnimName:String = (animation.curAnim != null) ? animation.curAnim.name : null;
		if(check) {
			if(curAnimName != 'checked' && curAnimName != 'checking') {
				animation.play('checking', true);
				offset.set(34, 25);
			}
		} else if(curAnimName != 'unchecked' && curAnimName != 'unchecking') {
			animation.play("unchecking", true);
			offset.set(25, 28);
		}
		return check;
	}

	private function animationFinished(name:String)
	{
		switch(name)
		{
			case 'checking':
				animation.play('checked', true);
				offset.set(3, 12);

			case 'unchecking':
				animation.play('unchecked', true);
				offset.set(0, 2);
		}
	}
}