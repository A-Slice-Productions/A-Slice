package backend.ui;

import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;

class PsychUIEventHandler
{
	// Applies the standard UI text stroke (outline) so all PsychUI labels
	// look consistent with the rest of the game's menu text.
	// NOTE: PsychUI text uses the tiny default 8px font, so a thick border
	// (like the 2px one used on the big menu fonts) makes it look like a blob.
	public static function applyTextStroke(text:FlxText, ?color:FlxColor = FlxColor.BLACK, size:Float = 0.5)
	{
		if (text == null) return;
		text.borderStyle = FlxTextBorderStyle.OUTLINE;
		text.borderSize = size;
		text.borderColor = color;
	}

	public static function event(id:String, sender:Dynamic)
	{
		var state:Dynamic = cast FlxG.state;
		if(state == null) return;

		while(state.subState != null)
			state = cast state.subState;

		if(state != null && state.UIEvent != null)
			state.UIEvent(id, sender);
	}
}

interface PsychUIEvent {
	public function UIEvent(id:String, sender:Dynamic):Void;
}