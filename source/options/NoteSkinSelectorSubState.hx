package options;

import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.group.FlxSpriteGroup;
import flixel.FlxSprite;
import backend.ClientPrefs;
import backend.Paths;
import objects.StrumNote;
import flixel.math.FlxMath;

class NoteSkinSelectorSubState extends MusicBeatSubstate
{
	var noteSkins:Array<String> = [];
	var curSelected:Int = 0;
	
	var grpOptions:FlxSpriteGroup;
	var selectorLeft:FlxText;
	var selectorRight:FlxText;
	
	var previewNotes:FlxSpriteGroup;
	
	public function new()
	{
		super();
		noteSkins = Mods.mergeAllTextsNamed('images/noteSkins/list.txt');
		if(noteSkins.length > 0)
		{
			if(!noteSkins.contains(ClientPrefs.data.noteSkin))
				ClientPrefs.data.noteSkin = ClientPrefs.defaultData.noteSkin;
			noteSkins.insert(0, ClientPrefs.defaultData.noteSkin);
		}
		else
		{
			noteSkins = [ClientPrefs.defaultData.noteSkin];
		}
	}

	override function create()
	{
		super.create();
		
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = 0xFFea71fd;
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);
		
		grpOptions = new FlxSpriteGroup();
		add(grpOptions);
		
		for (i in 0...noteSkins.length)
		{
			var optionText:FlxText = new FlxText(0, 0, FlxG.width, noteSkins[i], 32);
			optionText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
			optionText.borderSize = 1;
			optionText.borderColor = FlxColor.BLACK;
			optionText.screenCenter();
			optionText.y += (60 * (i - (noteSkins.length / 2))) + 30;
			grpOptions.add(optionText);
		}
		
		selectorLeft = new FlxText(0, 0, 0, '>>>', 32);
		selectorLeft.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
		selectorLeft.borderSize = 1;
		selectorLeft.borderColor = FlxColor.BLACK;
		add(selectorLeft);
		
		selectorRight = new FlxText(0, 0, 0, '<<<', 32);
		selectorRight.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
		selectorRight.borderSize = 1;
		selectorRight.borderColor = FlxColor.BLACK;
		add(selectorRight);
		
		previewNotes = new FlxSpriteGroup();
		add(previewNotes);
		
		changeSelection();
		
		#if TOUCH_CONTROLS_ALLOWED
		addTouchPad('UP_DOWN', 'A_B');
		#end
	}
	
	override function update(elapsed:Float)
	{
		var choice:Bool = FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE
			#if TOUCH_CONTROLS_ALLOWED
			|| touchPad.buttonA.justPressed
			#end;
		
		if (choice)
		{
			ClientPrefs.data.noteSkin = noteSkins[curSelected];
			ClientPrefs.saveSettings();
			closeSubState();
			return;
		}
		
		if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.BACKSPACE
			#if TOUCH_CONTROLS_ALLOWED
			|| touchPad.buttonB.justPressed
			#end)
		{
			closeSubState();
			return;
		}
		
		var up = FlxG.keys.justPressed.UP || FlxG.keys.justPressed.W
			#if TOUCH_CONTROLS_ALLOWED
			|| touchPad.buttonUp.justPressed
			#end;
		var down = FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S
			#if TOUCH_CONTROLS_ALLOWED
			|| touchPad.buttonDown.justPressed
			#end;
			
		if (up) changeSelection(-1);
		if (down) changeSelection(1);
		
		super.update(elapsed);
	}
	
	function changeSelection(change:Int = 0)
	{
		curSelected += change;
		if (curSelected < 0) curSelected = noteSkins.length - 1;
		if (curSelected >= noteSkins.length) curSelected = 0;
		
		for (i in 0...grpOptions.length)
		{
			grpOptions.members[i].color = (i == curSelected) ? FlxColor.YELLOW : FlxColor.WHITE;
		}
		
		selectorLeft.visible = selectorRight.visible = false;
		if (curSelected > 0) selectorLeft.visible = true;
		if (curSelected < noteSkins.length - 1) selectorRight.visible = true;
		
		selectorLeft.screenCenter();
		selectorLeft.x -= FlxG.width / 2 - 80;
		selectorLeft.y = grpOptions.members[curSelected].y;
		
		selectorRight.screenCenter();
		selectorRight.x += FlxG.width / 2 - 80;
		selectorRight.y = grpOptions.members[curSelected].y;
		
		updatePreview();
	}
	
	function updatePreview()
	{
		previewNotes.clear();
		var oldSkin = ClientPrefs.data.noteSkin;
		ClientPrefs.data.noteSkin = noteSkins[curSelected];
		for (i in 0...Main.mania + 1)
		{
			var note:StrumNote = new StrumNote(100 + (i * 100), FlxG.height / 2 - 50, i, 0);
			note.alpha = 0.8;
			previewNotes.add(note);
		}
		ClientPrefs.data.noteSkin = oldSkin;
	}
	
	override function closeSubState()
	{
		#if TOUCH_CONTROLS_ALLOWED
		removeTouchPad();
		#end
		super.closeSubState();
	}
}
