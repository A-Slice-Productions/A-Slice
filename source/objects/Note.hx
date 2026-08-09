package objects;

import flixel.math.FlxAngle;
import haxe.ds.Vector;
import flixel.animation.FlxAnimationController;
import flixel.graphics.frames.FlxFramesCollection;
import flixel.graphics.FlxGraphic;
import backend.animation.PsychAnimationController;
import backend.NoteTypesConfig;

import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

import objects.StrumNote;

import flixel.math.FlxRect;

using StringTools;

typedef EventNote = {
	strumTime:Float,
	event:String,
	value1:String,
	value2:String
}

typedef NoteSplashData = {
	disabled:Bool,
	texture:String,
	useGlobalShader:Bool, //breaks r/g/b but makes it copy default colors for your custom note
	useRGBShader:Bool,
	antialiasing:Bool,
	r:FlxColor,
	g:FlxColor,
	b:FlxColor,
	a:Float
}

typedef CastNote = {
	var strumTime:Float;
	// noteData and flags
	// 1st-8th bits are for noteData (256keys)
	// 9th bit is for mustHit
	// 10th bit is for isHold
	// 11th bit is for isHoldEnd
	// 12th bit is for gfNote
	// 13th bit is for altAnim
	// 14th bit is for noAnim & noMissAnim
	// 15th bit is for blockHit
	// 16th bit is for ignoreNote
	var noteData:Int;
	@:optional var density:Null<Float>;
	@:optional var holdLength:Null<Float>;
	@:optional var noteType:String;
	@:optional var cmpSpam:Array<Dynamic>;
}

typedef SpamNoteData = {
    var remaining:Float;
    var density:Float;
    var seedNote:CastNote;  // reference to original note
};

var toBool = CoolUtil.bool;
var toInt = CoolUtil.int;

/**
 * The note object used as a data structure to spawn and manage notes during gameplay.
 * 
 * If you want to make a custom note type, you should search for: "function set_noteType"
**/
class Note extends FlxSprite
{
	//This is needed for the hardcoded note types to appear on the Chart Editor,
	//It's also used for backwards compatibility with 0.1 - 0.3.2 charts.
	public static final DEFAULT_NOTE_TYPES:Array<String> = [
		'', //Always leave this one empty pls
		'Alt Animation',
		'Hey!',
		'Hurt Note',
		'GF Sing',
		'No Animation'
	];

	public static final DEFAULT_CAST:CastNote = {
		strumTime: 0,
		noteData: 0,
		density: 1,
		noteType: "",
		holdLength: 0
	};

	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public var strumTime:Float = 0;
	public var noteData:Int = 0;
	public var density:Float = 1;
	public var strum:StrumNote = null;
	public var spawned:Bool = false;
	public var multSpeed:Float = 1;

	public var mustPress:Bool = false;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;

	public var wasGoodHit:Bool = false;
	public var missed:Bool = false;

	public var ignoreNote:Bool = false;
	public var hitByOpponent:Bool = false;
	public var noteWasHit:Bool = false;

	public var tail:Array<Note> = []; // for sustains
	public var parent:Note;

	public var prevNote:Note;
	public var nextNote:Note;
	
	public var blockHit:Bool = false; // only works for player

	public var sustainLength:Float = 0;
	public var sustainScale:Float = 1.0;
	public var isSustainNote:Bool = false;
	public var isSustainEnds:Bool = false;
	public var noteType(default, set):String = null;

	public var eventName:String = '';
	public var eventLength:Int = 0;
	public var eventVal1:String = '';
	public var eventVal2:String = '';

	public var rgbShader:RGBShaderReference;
	public static var globalRgbShaders:Array<RGBPalette> = [];
	public var inEditor:Bool = false;

	public var animSuffix:String = '';
	public var gfNote:Bool = false;
	public var earlyHitMult:Float = 1;
	public var lateHitMult:Float = 1;
	public var lowPriority:Bool = false;

	public static var isBotplay:Bool = false;

	public static final SUSTAIN_SIZE:Int = 44;
	public static final DEFAULT_NOTE_SKIN:String = 'noteSkins/NOTE_assets';
	public static var swagWidth:Float = 160 * 0.7;
	public static var originalWidth:Float = swagWidth;
	public static var originalHeight:Float = swagWidth;
	public static var chartArrowSkin:String = null;
	public static var pixelWidth:Vector<Int> = new Vector(2, 0);
	public static var pixelHeight:Vector<Int> = new Vector(2, 0);

	// Mania arrays (1K - 26K)
	public static var colArray:Array<String> = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];
	public static var colArrayAlt:Array<String> = ['purple', 'blue', 'green', 'red', 'white', 'yellow', 'violet', 'black', 'dark', 'pink', 'orange', 'cyan', 'magenta', 'lime', 'indigo', 'maroon', 'navy', 'teal', 'coral', 'gold', 'silver', 'crimson', 'olive', 'turquoise', 'plum', 'sienna'];
	public static var pressArrayAlt:Array<String> = ['left', 'down', 'up', 'right', 'white', 'yellow', 'violet', 'black', 'dark', 'left', 'down', 'up', 'right', 'white', 'yellow', 'violet', 'black', 'dark', 'left', 'down', 'up', 'right', 'white', 'yellow', 'violet', 'black'];

	public static var scales:Array<Float> = [0.7, 0.7, 0.7, 0.7, 0.65, 0.6, 0.55, 0.5, 0.46, 0.42, 0.38, 0.35, 0.32, 0.30, 0.28, 0.26, 0.24, 0.22, 0.21, 0.20, 0.19, 0.18, 0.17, 0.16, 0.15, 0.14];
	public static var scalesPixel:Array<Float> = [1, 1, 1, 1, 0.93, 0.86, 0.79, 0.71, 0.66, 0.61, 0.56, 0.52, 0.48, 0.44, 0.41, 0.38, 0.35, 0.33, 0.31, 0.29, 0.27, 0.25, 0.24, 0.23, 0.22, 0.21];
	public static var splashOffsetScale:Array<Float> = [1, 1, 1, 1, 1.08, 1.17, 1.27, 1.4, 1.52, 1.64, 1.77, 1.91, 2.06, 2.22, 2.40, 2.59, 2.80, 3.02, 3.26, 3.52, 3.80, 4.10, 4.43, 4.78, 5.16, 5.57];
	public static var swidths:Array<Float> = [112, 112, 112, 112, 98, 84, 77, 70, 63, 57, 52, 48, 44, 40, 37, 34, 32, 30, 28, 26, 25, 24, 23, 22, 21, 20];
	public static var posRest:Array<Int> = [-168, -112, -56, 0, 15, 35, 45, 55, 60, 65, 70, 75, 78, 81, 84, 87, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108];
	public static var midArray:Array<Int> = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12];
	public static var gfxIndex:Array<Dynamic> = [
		[4],
		[0, 3],
		[0, 4, 3],
		[0, 1, 2, 3],
		[0, 1, 4, 2, 3],
		[0, 2, 3, 5, 1, 8],
		[0, 2, 3, 4, 5, 1, 8],
		[0, 1, 2, 3, 5, 6, 7, 8],
		[0, 1, 2, 3, 4, 5, 6, 7, 8],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7]
	];
	public static var gfxHud:Array<Dynamic> = [
		[4],
		[0, 3],
		[0, 4, 3],
		[0, 1, 2, 3],
		[0, 1, 4, 2, 3],
		[0, 2, 3, 0, 1, 3],
		[0, 2, 3, 4, 0, 1, 3],
		[0, 1, 2, 3, 0, 1, 2, 3],
		[0, 1, 2, 3, 4, 0, 1, 2, 3],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4],
		[0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0]
	];
	public static var gfxDir:Array<String> = ['LEFT', 'DOWN', 'UP', 'RIGHT', 'SPACE'];
	public static var dataNum:Int;

	public var correctionOffset:Float = 55; //dont mess with this, it makes the hold notes look better

	public var noteSplashData:NoteSplashData = {
		disabled: false,
		texture: null,
		antialiasing: !PlayState.isPixelStage,
		useGlobalShader: false,
		useRGBShader: PlayState.SONG != null && !PlayState.SONG.disableNoteRGB && ClientPrefs.data.noteShaders,
		r: -1,
		g: -1,
		b: -1,
		a: ClientPrefs.data.splashAlpha
	};
	public var noteHoldSplash:SustainSplash;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var multAlpha:Float = 1;
	// public var multSpeed(default, set):Float = 1;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;
	// public var copyScale:Bool = true;

	public var hitHealth:Float = 0.02;
	public var missHealth:Float = 0.1;
	public var rating:String = 'unknown';
	public var ratingMod:Float = 0; //9 = unknown, 0.25 = shit, 0.5 = bad, 0.75 = good, 1 = sick
	public var ratingDisabled:Bool = false;

	public var texture(default, set):String = null;
	// public var prevDownScr:Bool = false;

	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var hitCausesMiss:Bool = false;
	public var distance:Float = 2000; //plan on doing scroll directions soon -bb

	public var hitsoundDisabled:Bool = false;
	public var hitsoundChartEditor:Bool = true;
	/**
	 * Forces the hitsound to be played even if the user's hitsound volume is set to 0
	**/
	public var hitsoundForce:Bool = false;
	public var hitsoundVolume(get, default):Float = 1.0;
	function get_hitsoundVolume():Float {
		if(ClientPrefs.data.hitsoundVolume > 0)
			return ClientPrefs.data.hitsoundVolume;
		return hitsoundForce ? hitsoundVolume : 0.0;
	}
	public var hitsound:String = 'hitsound';

	inline public function resizeByRatio(ratio:Float) //haha funny twitter shit
	{
		if(isSustainNote && animation != null && animation.curAnim != null && !animation.curAnim.name.endsWith('end'))
		{
			scale.y *= ratio;
			updateHitbox();
		}
	}

	static var noteFramesCollection:FlxFramesCollection;
	static var noteFramesAnimation:FlxAnimationController;
	
	// It's only used newing instances
	private function set_texture(value:String):String {
		if (value == null || value.length == 0) {
			value = DEFAULT_NOTE_SKIN + getNoteSkinPostfix();
		}
		// if (!PlayState.isPixelStage) {
		if(texture != value) {
			if (!Paths.noteSkinFramesMap.exists(value)) inline Paths.initNote(value);

			noteFramesCollection = Paths.noteSkinFramesMap.get(value);
			noteFramesAnimation = Paths.noteSkinAnimsMap.get(value);
			if (frames != noteFramesCollection) frames = noteFramesCollection;
			if (animation != noteFramesAnimation) animation.copyFrom(noteFramesAnimation);
			
			antialiasing = ClientPrefs.data.antialiasing;
			if (originalWidth != width || originalHeight != height) {
				setGraphicSize(Std.int(width * scales[Main.mania]));
				updateHitbox();
				originalWidth = width;
				originalHeight = height;
			}
		} else return value;
		texture = value;
		return value;
	}

	static var colArr:Array<FlxColor>;
	public function defaultRGB()
	{
		colArr = PlayState.isPixelStage ? ClientPrefs.data.arrowRGBPixelExtra[gfxIndex[Main.mania][noteData]] : ClientPrefs.data.arrowRGBExtra[gfxIndex[Main.mania][noteData]];

		if (colArr != null && noteData > -1 && noteData <= Main.mania)
		{
			rgbShader.r = colArr[0];
			rgbShader.g = colArr[1];
			rgbShader.b = colArr[2];
		}
		else
		{
			rgbShader.r = 0xFFFF0000;
			rgbShader.g = 0xFF00FF00;
			rgbShader.b = 0xFF0000FF;
		}
	}

	private function set_noteType(value:String):String {
		noteSplashData.texture = PlayState.SONG != null ? PlayState.SONG.splashSkin : 'noteSplashes/noteSplashes';
		if (rgbShader != null && rgbShader.enabled) defaultRGB();

		if (noteData > -1) {
			if (value == 'Hurt Note') {
				ignoreNote = mustPress && isBotplay;
				//this used to change the note texture to HURTNOTE_assets.png,
				//but i've changed it to something more optimized with the implementation of RGBPalette:

				// note colors
				if (rgbShader != null && rgbShader.enabled) {
					rgbShader.r = 0xFF101010;
					rgbShader.g = 0xFFFF0000;
					rgbShader.b = 0xFF990022;
				} else {
					try {
						reloadNote('HURTNOTE_assets');
					} catch (e) {alpha = 0.5; }
				}

				// splash data and colors
				noteSplashData.r = 0xFFFF0000;
				noteSplashData.g = 0xFF101010;
				noteSplashData.texture = 'noteSplashes/noteSplashes-electric';

				// gameplay data
				lowPriority = true;
				missHealth = isSustainNote ? 0.25 : 0.1;
				hitCausesMiss = true;
				hitsound = 'cancelMenu';
				hitsoundChartEditor = false;
			}
			if (value != null && value.length > 1) NoteTypesConfig.applyNoteTypeData(this, value);
			if (hitsound != 'hitsound' && hitsoundVolume > 0) Paths.sound(hitsound); //precache new sound for being idiot-proof
			noteType = value;
		}
		return value;
	}

	public function new(strumTime:Float = 0, noteData:Int = -1, ?prevNote:Note = null, sustainNote:Bool = false, inEditor:Bool = false, createdFrom:Dynamic = null)
	{
		super();

		antialiasing = ClientPrefs.data.antialiasing;
		if(createdFrom == null) createdFrom = PlayState.instance;

		if (prevNote == null)
			prevNote = this;

		this.prevNote = prevNote;
		isSustainNote = sustainNote;
		this.inEditor = inEditor;
		this.moves = false;

		x += (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50 - posRest[Main.mania];
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;
		this.strumTime = strumTime;
		if(!inEditor) this.strumTime += ClientPrefs.data.noteOffset;

		this.noteData = noteData;

		if(noteData > -1) {
			texture = '';
			rgbShader = new RGBShaderReference(this, initializeGlobalRGBShader(noteData));
			if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB) rgbShader.enabled = false;
			if(!ClientPrefs.data.noteShaders) rgbShader.enabled = false;

			if (Main.mania != 0) x += Note.swidths[Main.mania] * (noteData % (Main.mania+1));
			if(!isSustainNote && noteData < Main.mania+1) { //Doing this 'if' check to fix the warnings on Senpai songs
				animation.play(colArray[gfxIndex[Main.mania][noteData]] + 'Scroll');
			}
		} else {
			try {
				rgbShader = new RGBShaderReference(this, new RGBPalette());
				if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB) rgbShader.enabled = false;
				if(!ClientPrefs.data.noteShaders) rgbShader.enabled = false;
			} catch (e) { rgbShader = null; }
		}

		if(prevNote != null)
			prevNote.nextNote = this;

		if (isSustainNote && prevNote != null)
		{
			alpha = 0.6;
			multAlpha = 0.6;
			hitsoundDisabled = true;
			if(ClientPrefs.data.downScroll) flipY = true;

			offsetX += width / 2;
			copyAngle = false;

			animation.play(colArray[gfxIndex[Main.mania][noteData]] + 'holdend');

			updateHitbox();

			offsetX -= width / 2;

			if (PlayState.isPixelStage)
				offsetX += 30 * scalesPixel[Main.mania];

			if (prevNote.isSustainNote)
			{
				prevNote.animation.play(colArray[gfxIndex[Main.mania][prevNote.noteData]] + 'hold');

				prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.05;
				if(createdFrom != null && createdFrom.songSpeed != null) prevNote.scale.y *= createdFrom.songSpeed;

				if(PlayState.isPixelStage) {
					prevNote.scale.y *= 1.19;
					prevNote.scale.y *= (6 / height); //Auto adjust note size
				}
				prevNote.updateHitbox();
			}

			if(PlayState.isPixelStage)
			{
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}
			earlyHitMult = 0;
		}
		else if(!isSustainNote)
		{
			centerOffsets();
			centerOrigin();
		}
		x += offsetX;
	}

	public static function initializeGlobalRGBShader(noteData:Int)
	{
		var dataNum = gfxIndex[Main.mania][noteData];
		if(globalRgbShaders[dataNum] == null)
		{
			var newRGB = new RGBPalette();
			globalRgbShaders[dataNum] = newRGB;

			colArr = PlayState.isPixelStage ? ClientPrefs.data.arrowRGBPixelExtra[dataNum] : ClientPrefs.data.arrowRGBExtra[dataNum];
			
			if (colArr != null && noteData > -1 && noteData <= Main.mania)
			{
				newRGB.r = colArr[0];
				newRGB.g = colArr[1];
				newRGB.b = colArr[2];
			}
			else
			{
				newRGB.r = 0xFFFF0000;
				newRGB.g = 0xFF00FF00;
				newRGB.b = 0xFF0000FF;
			}
		}
		return globalRgbShaders[dataNum];
	}

	var rSkin:String;
	var rAnimName:String;

	var rSkinPixel:String;
	var rLastScaleY:Float;
	var rSkinPostfix:String;
	var rCustomSkin:String;
	var rPath:String;

	var rGraphic:FlxGraphic;

	static var _lastValidChecked:String; //optimization
	public function reloadNote(texture:String = '', postfix:String = '') {
		if(texture == null) texture = '';
		if(postfix == null) postfix = '';

		rSkin = texture + postfix;
		if(texture.length < 1)
		{
			rSkin = PlayState.SONG != null ? PlayState.SONG.arrowSkin : null;
			if(rSkin == null || rSkin.length < 1)
				rSkin = DEFAULT_NOTE_SKIN + postfix;
		}
		else rgbShader.enabled = false;

		rAnimName = null;
		if(animation.curAnim != null) {
			rAnimName = animation.curAnim.name;
		}

		rPath = PlayState.isPixelStage ? 'pixelUI/' : '';
		rSkinPixel = rPath + rSkin;
		rLastScaleY = scale.y;
		rSkinPostfix = getNoteSkinPostfix();
		rCustomSkin = rSkin + rSkinPostfix;

		if (rCustomSkin == _lastValidChecked || Paths.fileExists('images/' + rPath + rCustomSkin + '.png', IMAGE))
		{
			rSkin = rCustomSkin;
			_lastValidChecked = rCustomSkin;
		}
		else rSkinPostfix = '';

		if (PlayState.isPixelStage) {
			rGraphic = Paths.image(rSkinPixel + (isSustainNote ? 'ENDS' : '') + rSkinPostfix);
			loadGraphic(rGraphic, true, Math.floor(rGraphic.width / 9), Math.floor(rGraphic.height / (isSustainNote ? 2 : 5)));
			
			setGraphicSize(Std.int(width * PlayState.daPixelZoom * scalesPixel[Main.mania]));
			loadPixelNoteAnims();
			antialiasing = false;
			
			pixelWidth[isSustainNote ? 1:0] = frameWidth;
			pixelHeight[isSustainNote ? 1:0] = frameHeight;
		} else {
			frames = Paths.getSparrowAtlas(rSkin);
			loadNoteAnims();
			if(!isSustainNote)
			{
				centerOffsets();
				centerOrigin();
			}
		}

		if(isSustainNote) {
			scale.y = rLastScaleY;
		}
		updateHitbox();

		if(rAnimName != null)
			animation.play(rAnimName, true);
	}

	static var skin:String = '';
	public static function getNoteSkinPostfix()
	{
		skin = '';
		if(ClientPrefs.data.noteSkin != ClientPrefs.defaultData.noteSkin)
			skin = '-' + ClientPrefs.data.noteSkin.trim().toLowerCase().replace(' ', '_');
		return skin;
	}

	function loadNoteAnims() {
		if (noteData < 0)
			return;

		var playAnim:String = colArray[gfxIndex[Main.mania][noteData]];
		var playAnimAlt:String = colArrayAlt[gfxIndex[Main.mania][noteData]];

		if (isSustainNote)
		{
			attemptToAddAnimationByPrefix('purpleholdend', 'pruple end hold', 24, true); // this fixes some retarded typo from the original note .FLA
			attemptToAddAnimationByPrefix(playAnim + 'holdend', playAnim + ' tail0', 24, true);
			attemptToAddAnimationByPrefix(playAnim + 'hold', playAnim + ' hold0', 24, true);
			attemptToAddAnimationByPrefix(playAnim + 'holdend', playAnimAlt + ' hold end', 24, true);
			attemptToAddAnimationByPrefix(playAnim + 'hold', playAnimAlt + ' hold piece', 24, true);
			attemptToAddAnimationByPrefix(playAnim + 'holdend', playAnim + ' hold end', 24, true);
			attemptToAddAnimationByPrefix(playAnim + 'hold', playAnim + ' hold piece', 24, true);
		}
		else
		{
			attemptToAddAnimationByPrefix(playAnim + 'Scroll', playAnimAlt + '0');
			attemptToAddAnimationByPrefix(playAnim + 'Scroll', playAnim + '0');
		}

		setGraphicSize(Std.int(width * scales[Main.mania]));
		updateHitbox();
	}

	function loadPixelNoteAnims() {
		if (noteData < 0)
			return;

		var playAnim:String = colArray[gfxIndex[Main.mania][noteData]];
		var noteIndex:Int = gfxIndex[Main.mania][noteData];

		if(isSustainNote)
		{
			animation.add(playAnim + 'holdend', [noteIndex + 9], 24, true);
			animation.add(playAnim + 'hold', [noteIndex], 24, true);
		} else animation.add(playAnim + 'Scroll', [noteIndex + 9], 24, true);
	}

	
	function attemptToAddAnimationByPrefix(name:String, prefix:String, framerate:Float = 24, doLoop:Bool = true)
	{
		var animFrames = [];
		@:privateAccess
		animation.findByPrefix(animFrames, prefix); // adds valid frames to animFrames
		if(animFrames.length < 1) return;

		animation.addByPrefix(name, prefix, framerate, doLoop);
	}

	var songTime:Float = 0;
	var safeZone:Float = 0;
	override function update(elapsed:Float)
	{
		if (isBotplay) return;
		super.update(elapsed);

		songTime = Conductor.songPosition;
		safeZone = Conductor.safeZoneOffset;

		if (mustPress)
		{
			canBeHit = (strumTime > songTime - (safeZone * lateHitMult) &&
						strumTime < songTime + (safeZone * earlyHitMult));

			if (strumTime < songTime - safeZone && !wasGoodHit)
				tooLate = true;
		}
		else
		{
			canBeHit = false;

			if (!wasGoodHit && strumTime <= songTime)
			{
				if(!isSustainNote || !ignoreNote)
					wasGoodHit = true;
			}
		}

		if (tooLate && !inEditor)
		{
			if (alpha > 0.3)
				alpha = 0.3;
		}
	}

	override public function destroy()
	{
		super.destroy();
		_lastValidChecked = '';
	}
	
	var angleDir:Float;
	var angleRad:Float;
	public function followStrumNote(songSpeed:Float = 1, distance:Float = 0)
	{
		if (isSustainNote)
		{
			scale.set(scales[Main.mania], animation != null && animation.curAnim != null && animation.curAnim.name.endsWith('end') ? scales[Main.mania] : Conductor.stepCrochet * 0.0105 * songSpeed * sustainScale);
			if (PlayState.isPixelStage)
			{
				scale.x = PlayState.daPixelZoom * scalesPixel[Main.mania];
				scale.y *= PlayState.daPixelZoom * 1.19;
			}

			updateHitbox();
		}

		this.distance = -distance;
		
		angleDir = strum.direction + (strum.downScroll ? 180 : 0); // convert direction to degrees
		angleRad = angleDir * Math.PI / 180;
		if (copyAngle)
			angle = isSustainNote ? strum.direction - 90 : strum.angle;

		if (copyAlpha)
			alpha = strum.alpha * multAlpha;

		if (copyX)
		{
			x = strum.x + offsetX + Math.cos(angleRad) * this.distance;
			if (isSustainNote)
			{
				// x -= frameWidth * scale.x - Note.swagWidth * (Math.cos(angleRad) * 0.25 - 0.5);
				x += height * Math.cos(angleRad) * 0.5;
			}
		}

		if (copyY)
		{
			y = strum.y + offsetY + Math.sin(angleRad) * this.distance;
			if (isSustainNote)
			{
				if(PlayState.isPixelStage)
				{
					y -= PlayState.daPixelZoom * scalesPixel[Main.mania] * 9.5;
				}
				y += correctionOffset * Math.sin(angleRad) + (originalHeight - height) * (-Math.sin(angleRad) + 1) * 0.5;
			}
		}

		// wtf is this
		// if (copyScale) {
		// 	scale.x = strum.scale.x;
		// 	if(!isSustainNote) scale.y = strum.scale.y;
		// 	updateHitbox();
		// }
	}

	var swagRect:FlxRect;
	public function clipToStrumNote()
	{
		if((mustPress || !ignoreNote) && (wasGoodHit || hitByOpponent || !canBeHit))
		{
			if (swagRect == null) {
				swagRect = new FlxRect(0, 0, frameWidth, frameHeight);
			} else {
				swagRect.setPosition(0, 0);
				swagRect.setSize(frameWidth, frameHeight);
			}
			swagRect.y = -distance / scale.y;
			swagRect.height = frameHeight - swagRect.y;

			clipRect = swagRect;
		}
	}

	override function kill() {
		active = visible = false;
		super.kill();
	}
	
	var initSkin:String = Note.DEFAULT_NOTE_SKIN + getNoteSkinPostfix();
	var playbackRate:Float;
	var correctWidth:Float;

	public function recycleNote(target:CastNote) {
		wasGoodHit = hitByOpponent = tooLate = false;
		canBeHit = missed = flipY = false; // Don't make an update call of this for the note group
		exists = true;

		isBotplay = PlayState.instance != null ? PlayState.instance.cpuControlled : false;

		strumTime = target.strumTime;
		if (!inEditor) strumTime += ClientPrefs.data.noteOffset;

		mustPress = toBool(target.noteData & (1<<8));						 // mustHit
		isSustainNote = toBool(target.noteData & (1<<9));					 // isHold
		isSustainEnds = toBool(target.noteData & (1<<10));					 // isHoldEnd
		gfNote = toBool(target.noteData & (1<<11));							 // gfNote
		animSuffix = toBool(target.noteData & (1<<12)) ? "-alt" : "";		 // altAnim
		noAnimation = noMissAnimation = toBool(target.noteData & (1<<13));	 // noAnim
		blockHit = toBool(target.noteData & (1<<14));				 		 // blockHit
		ignoreNote = toBool(target.noteData & (1<<15));				 		 // ignoreNote
		noteData = target.noteData & 0xFF;
		density = target.density ?? 1;

		hitsoundDisabled = isSustainNote;

		// Absoluty should be here, or messing pixel texture glitches...
		if (!PlayState.isPixelStage) {
			if (!CoolUtil.notBlank(chartArrowSkin)) texture = chartArrowSkin = initSkin;
			else if (chartArrowSkin != texture) texture = chartArrowSkin;
		} else reloadNote(texture);

		try {
			if (target.noteType is String) noteType = target.noteType; // applying note color on damage notes
			else noteType = DEFAULT_NOTE_TYPES[Std.parseInt(target.noteType)];
		} catch (e:Dynamic) {}

		sustainLength = target.holdLength ?? 0;

		// this.parent = parent;
		// if (this.parent != null) parent.tail = [];

		// copyAngle = !isSustainNote;

		// Juuuust in case we recycle a sustain note to a regular note
		if (PlayState.isPixelStage || !isSustainNote){
			animation.play(colArray[gfxIndex[Main.mania][noteData]] + 'Scroll', true);
			offsetX = 0;
		}

		if (isSustainNote)
		{
			flipY = ClientPrefs.data.downScroll;
			alpha = multAlpha = 0.6;

			if (PlayState.isPixelStage) {
				offsetX += pixelWidth[0] * 0.5 * PlayState.daPixelZoom;
				animation.play(colArray[gfxIndex[Main.mania][noteData]] + (isSustainEnds ? 'holdend' : 'hold'));  // isHoldEnd
				offsetX -= pixelWidth[1] * 0.5 * PlayState.daPixelZoom;

				if(!isSustainEnds) {
					// trace(pixelHeight[0], pixelHeight[1]);
					sustainScale = (PlayState.daPixelZoom / pixelHeight[1]); //Auto adjust note size
				}
			} else {
				offsetX += width * 0.5;
				animation.play(colArray[gfxIndex[Main.mania][noteData]] + (isSustainEnds ? 'holdend' : 'hold'));  // isHoldEnd
				updateHitbox();
				offsetX -= width * 0.5;

				if (!isSustainEnds) sustainScale = Note.SUSTAIN_SIZE / frameHeight;
			}
			
			// correctionOffset = 55;
		} else {
			alpha = multAlpha = sustainScale = 1;

			if (!PlayState.isPixelStage) 
			{
				scale.set(scales[Main.mania], scales[Main.mania]);
				width = originalWidth;
				height = originalHeight;

				centerOffsets(true);
				centerOrigin();
			} else scale.set(PlayState.daPixelZoom * scalesPixel[Main.mania], PlayState.daPixelZoom * scalesPixel[Main.mania]);
		}

		if (sustainScale != 1 && !isSustainEnds)
			resizeByRatio(sustainScale);
		clipRect = null;
		x += offsetX;
		return this;
	}

	// it used on spawning hold splashes
	public function toCastNote():CastNote {
		var lmfao:Int = 
			this.noteData & 255 |
			toInt(mustPress) << 8 |
			toInt(isSustainNote) << 9 |
			toInt(isSustainEnds) << 10 |
			toInt(gfNote) << 11 |
			toInt(animSuffix != "")	<< 12 |
			toInt(noAnimation) << 13 |
			toInt(blockHit) << 14 |
			toInt(ignoreNote) << 15;
		
		var converted:CastNote = {
			strumTime: this.strumTime,
			noteData: lmfao,
			density: 1,
			noteType: this.noteType,
			holdLength: this.sustainLength
		};

		return converted;
	}
}
