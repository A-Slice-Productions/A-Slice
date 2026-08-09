
package debug;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.text.TextFieldAutoSize;

class FPSBg extends Sprite
{
	var bgCard:Sprite;

	public var offsetY:Float = 0;
	public var offsetX:Float = 0;

	private var lastWidth:Float = -1;
	private var lastHeight:Float = -1;

	private static inline var MIN_WIDTH:Float = 60;
	private static inline var MIN_HEIGHT:Float = 25;

	private static inline var PADDING_X:Float = 14;
	private static inline var PADDING_Y:Float = 8;

	public function new()
	{
		super();

		bgCard = new Sprite();
		addChild(bgCard);

		addEventListener(Event.ENTER_FRAME, onEnterFrame);

		updateSize();
	}

	private function onEnterFrame(e:Event):Void
	{
		updateSize();
	}

	public inline function updateSize():Void
	{
		if (bgCard == null)
			return;

		if (Main.fpsVar == null)
			return;

		var textField = Main.fpsVar;

		/*
		 * Make the TextField use its natural width.
		 * This prevents the background from being stuck
		 * at the TextField's original fixed width.
		 */
		textField.autoSize = TextFieldAutoSize.LEFT;

		/*
		 * Read the actual rendered dimensions.
		 */
		var textWidth:Float = textField.textWidth;
		var textHeight:Float = textField.textHeight;

		/*
		 * Safety values for empty text.
		 */
		if (textWidth < 1)
			textWidth = 1;

		if (textHeight < 1)
			textHeight = 17;

		/*
		 * Calculate the background size.
		 */
		var newWidth:Float = Math.ceil(textWidth + PADDING_X);
		var newHeight:Float = Math.ceil(textHeight + PADDING_Y);

		/*
		 * Don't allow the background to become too small.
		 */
		if (newWidth < MIN_WIDTH)
			newWidth = MIN_WIDTH;

		if (newHeight < MIN_HEIGHT)
			newHeight = MIN_HEIGHT;

		/*
		 * Only redraw when the dimensions actually change.
		 */
		if (newWidth == lastWidth && newHeight == lastHeight)
			return;

		lastWidth = newWidth;
		lastHeight = newHeight;

		bgCard.graphics.clear();
		bgCard.graphics.beginFill(0x000000, 0);
		bgCard.graphics.drawRect(
			0,
			0,
			newWidth,
			newHeight
		);
		bgCard.graphics.endFill();
	}

	public inline function relocate(X:Float, Y:Float, isWide:Bool = false):Void
	{
		Main.fpsBg.offsetY = 0;

		Main.fpsBg.offsetX =
			((ClientPrefs.data.worldRecordMode ||
			ClientPrefs.data.worldRecordModeFixed) &&
			ClientPrefs.data.ffmpegMode)
			? 0
			: -38;

		updateSize();

		if (isWide)
		{
			x = X + offsetX;
			y = Y + offsetY;
		}
		else
		{
			x = FlxG.game.x + X + offsetX;
			y = FlxG.game.y + Y + offsetY;
		}
	}
}

