package states;

import hrk.Eseq;
import options.OptimizeSettingsSubState;
import backend.StageData;
import haxe.ds.ArraySort;
import flixel.animation.FlxAnimation;
#if desktop import backend.FFMpeg; #end
import openfl.system.Capabilities;
import objects.Note.CastNote;
import objects.Note.SpamNoteData;
import flixel.math.FlxRandom;
import haxe.ds.IntMap;
import haxe.Timer;
import haxe.ds.Vector;
import mikolka.vslice.StickerSubState;
import states.FreeplayState;
import mikolka.vslice.freeplay.FreeplayState as NewFreeplayState;
import backend.PsychCamera;
import mikolka.compatibility.VsliceOptions;
import mikolka.stages.EventLoader;

import backend.Highscore;
import backend.WeekData;
import backend.Song;
import backend.Rating;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.util.FlxColor;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.input.keyboard.FlxKey;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;
import mikolka.stages.cutscenes.dialogueBox.DialogueBoxPsych;
import mikolka.vslice.ui.StoryMenuState;
import lime.math.Matrix3;
import mikolka.funkin.Scoring;
import mikolka.funkin.custom.FunkinTools;
import mikolka.vslice.results.Tallies;
import mikolka.vslice.results.ResultState;
import openfl.media.Sound;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;
import substates.PauseSubState;
import substates.GameOverSubstate;
#if !flash
import flixel.addons.display.FlxRuntimeShader;
import shaders.ErrorHandlerShader.ErrorHandledRuntimeShader;
import openfl.filters.ShaderFilter;
import shaders.WiggleEffect;
import shaders.PulseEffect;
#end
import objects.VideoSprite;
import objects.Note.EventNote;
import objects.*;

import mikolka.stages.erect.*;
import mikolka.stages.standard.*;
import states.stages.objects.*;
#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.LuaUtils;
#end
#if HSCRIPT_ALLOWED
import psychlua.HScript;
import psychlua.HScript.HScriptInfos;
import crowplexus.iris.Iris;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;
#end

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/
class PlayState extends MusicBeatState
{
        // --- BUG FIX: Added clearNoteBatches for Single Note To Note Group ---
        // Changed: PlayState now resets batch buffers when song starts
        public function clearNoteBatches() {
            // Called from create() to prevent leftover merged sprites
        }

        public static var STRUM_X = 42;
        public static var STRUM_X_MIDDLESCROLL = -278;

        private var strumAnim:Bool = ClientPrefs.data.strumAnim;

        public static var ratingStuff:Array<Dynamic> = [
                ["wh- really? are you sure???", 0.2], // From 0% to 19%
                ["If it's not overcharted, you're just bad.", 0.4], // From 20% to 39%
                ["Might you need a practice?", 0.5], // From 40% to 49%
                ["Not Bad", 0.6], // From 50% to 59%
                ["Ok?", 0.69], // From 60% to 68%
                ["Nice", 0.7], // 69%
                ["Good", 0.8], // From 70% to 79%
                ["Great!", 0.9], // From 80% to 89%
                ["Sick!!", 1], // From 90% to 99%
                ["ALL SICK?!?", 1] // The value on this one isn't used actually, since Perfect is always "1"
        ];
        public var ratingImage:String = "";
        var forceSick:Rating = new Rating('sick');

        // event variables
        private var isCameraOnForcedPos:Bool = false;

        public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
        public var dadMap:Map<String, Character> = new Map<String, Character>();
        public var gfMap:Map<String, Character> = new Map<String, Character>();

        #if HSCRIPT_ALLOWED
        public var hscriptArray:Array<HScript> = [];
        #end

        public var BF_X:Float = 770;
        public var BF_Y:Float = 100;
        public var DAD_X:Float = 100;
        public var DAD_Y:Float = 100;
        public var GF_X:Float = 400;
        public var GF_Y:Float = 130;

        public var songSpeedTween:FlxTween;
        public var songSpeed(default, set):Float = 1;
        public var songSpeedRate:Float = 1;
        public var songSpeedType:String = "multiplicative";
        public var lastSongSpeed:Float = 1;
        public final NoteKillTime:Float = 350;
        public var noteKillOffset:Float = 0;

        public var playbackRate(default, set):Float = 1;
        var normalRate:Float;
        var skipRate:Float;

        public var boyfriendGroup:FlxSpriteGroup;
        public var dadGroup:FlxSpriteGroup;
        public var gfGroup:FlxSpriteGroup;

        public static var curStage:String = '';
        public static var stageUI:String = "normal";
        public static var isPixelStage(get, never):Bool;
        public var antialias:Bool = true;

        @:noCompletion
        static function get_isPixelStage():Bool
                return stageUI == "pixel" || stageUI.endsWith("-pixel");

        public static var SONG:SwagSong = null;
        public static var inPlayState:Bool = false;
        public static var isStoryMode:Bool = false;
        public static var storyWeek:Int = 0;
        public static var storyPlaylist:Array<String> = [];
        public static var storyDifficulty:Int = 1;

        // ! new shit P-Slice
        public static var storyCampaignTitle = "";
        public static var altInstrumentals:String = null;
        public static var storyDifficultyColor = FlxColor.GRAY;

        public var spawnTime:Float = 1500;

        public var inst:FlxSound;
        public var vocals:FlxSound;
        public var opponentVocals:FlxSound;

        public var dad:Character = null;
        public var gf:Character = null;
        public var boyfriend:Character = null;

        public var notes:NoteGroup;
        public static var unspawnNotes:Array<CastNote> = [];
        public var unspawnSustainNotes:Array<CastNote> = [];
        public var eventNotes:Array<EventNote> = [];
        public var sustainAnim:Bool = ClientPrefs.data.holdAnim;
        private var skipNotes:NoteGroup;

        public static var spamNotes:Array<SpamNoteData> = [];

        public var skipGhostNotes:Bool = ClientPrefs.data.skipGhostNotes;
        public var ghostDensity:Bool = ClientPrefs.data.ghostDensity;
        public var ghostNotesCaught:Int = 0;

        // --- AndreJr HUD (Haxe, no Lua) ---
        public var andreHUDEnabled:Bool = false;
        public var andreCounterText:FlxText;
        public var andreCounterBox:FlxSprite;
        public var andreOppNpsText:FlxText;
        public var andreOppBox:FlxSprite;
        public var andrePlayerNpsText:FlxText;
        public var andrePlayerBox:FlxSprite;
        public var andreTopTimeText:FlxText;
        public var andreTopTimeBox:FlxSprite;
        public var andreStatsText:FlxText;
        public var andreStatsBox:FlxSprite;
        public var andrePlayerNotes:Int = 0;
        public var andreOppNotes:Int = 0;
        public var andrePlayerHits:Array<Float> = [];
        public var andreOppHits:Array<Float> = [];
        public var andreMaxPlayerNPS:Int = 0;
        public var lastComboNpsTime:Float = 0;
        public var lastPlayerCountForNps:Int = 0;
        public var lastOppCountForNps:Int = 0;
        public var andreMaxOppNPS:Int = 0;
        public var andreActualTotalNotes:Int = 0;
        public var andreVisibleTotalNotes:Int = 0;

        // --- Andre New HUD (Haxe, static cam) ---
        public var andreNewHUDEnabled:Bool = false;
        public var andreNewComboOpp:Int = 0;
        public var andreNewComboPlayer:Int = 0;
        public var andreNewComboTotal:Int = 0;
        public var andreNewOppHits:Array<Float> = [];
        public var andreNewPlayerHits:Array<Float> = [];
        public var andreNewMaxOppNPS:Int = 0;
        public var andreNewMaxPlayerNPS:Int = 0;
        public var andreNewBoxBgs:Array<FlxSprite> = [];
        public var andreNewBoxLines:Array<FlxSprite> = [];
        public var andreNewBoxTexts:Array<FlxText> = [];
        public var andreNewBoxBrackets:Array<Array<FlxSprite>> = [];
        public var andreNewBoxWidths:Array<Int> = [];
        public var andreNewBoxXs:Array<Int> = [];
        public var andreNoteTimes:Array<Float> = [];
        public var andreOppTimes:Array<Float> = [];
        public var andrePlayerTimes:Array<Float> = [];
        public var andreNpsHistory:Array<{t:Float, o:Int, p:Int}> = [];

        // --- Andre HUD (Lua Port) ---
        public var andreLuaHUDEnabled:Bool = false;
        public var andreLuaBoxBgs:Array<FlxSprite> = [];
        public var andreLuaBoxLines:Array<FlxSprite> = [];
        public var andreLuaBoxTexts:Array<FlxText> = [];
        public var andreLuaBoxBrackets:Array<Array<FlxSprite>> = [];
        public var andreLuaBoxWidths:Array<Int> = [];
        public var andreLuaBoxXs:Array<Int> = [];
        public var andreLuaComboOpp:Int = 0;
        public var andreLuaComboPlayer:Int = 0;
        public var andreLuaComboTotal:Int = 0;
        public var andreLuaPlayerHits:Array<Float> = [];
        public var andreLuaOppHits:Array<Float> = [];
        public var andreLuaMaxPlayerNPS:Int = 0;
        public var andreLuaMaxOppNPS:Int = 0;
        public var andreLuaPlayerBgColor:Int = 0xFF1A4D66;
        public var andreLuaPlayerBorderColor:Int = 0xFF33CCFF;
        public var andreLuaDefaultOppColor:Int = 0xFFA349A4;
        // Format numbers with commas: 1000 -> 1,000
        function andreFormat(num:Float):String {
                var n = Math.floor(num);
                var s = Std.string(n);
                var len = s.length;
                var result = "";
                var count = 0;
                for (i in 0...len) {
                        var c = s.charAt(len - 1 - i);
                        if (count == 3) {
                                result = "," + result;
                                count = 0;
                        }
                        result = c + result;
                        count++;
                }
                return result;
        }

        public var camFollow:FlxObject;

        private static var prevCamFollow:FlxObject;

        public var strumLineNotes:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
        public var opponentStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
        public var playerStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();

        public var grpNoteSplashes:FlxTypedGroup<NoteSplash> = new FlxTypedGroup<NoteSplash>();
        public var grpHoldSplashes:FlxTypedGroup<SustainSplash> = new FlxTypedGroup<SustainSplash>();

        public static var splashUsing:Array<Array<NoteSplash>>;
        public static var splashMoment:Vector<Int> = new Vector(8, 0);
        public static function resetLaneVectors():Void
        {
                var laneCount:Int = (Main.mania + 1) * 2;
                splashMoment = new Vector(laneCount, 0);
                susplashMap = new Vector(laneCount);
        }

        var splashCount:Int = ClientPrefs.data.splashCount != 0 ? ClientPrefs.data.splashCount : 2147483647;
        var splashOpponent:Bool = ClientPrefs.data.splashOpponent;
        var enableSplash:Bool = ClientPrefs.data.splashAlpha != 0 && ClientPrefs.data.splashSkin != "None";
        var enableHoldSplash:Bool = ClientPrefs.data.holdSplashAlpha != 0 && ClientPrefs.data.holdSkin != "None";

        public var camZooming:Bool = false;
        public var camZoomingMult:Float = 1;
        public var camZoomingFrequency:Float = 4;
        public var camZoomingDecay:Float = 1;

        private var curSong:String = "";

        public var gfSpeed:Int = 1;
        public var health(default, set):Float = 1;
        public var overHealth:Bool = ClientPrefs.data.overHealth;
        public var healthDrain:Bool = ClientPrefs.data.healthDrain;
        public var drainAccuracy:Int = ClientPrefs.data.drainAccuracy;

        private var healthLerp:Float = 1;

        public var combo:Float = 0;
        public var opCombo:Float = 0;
        public var maxCombo:Float = 0;

        public var healthBar:Bar;
        public var timeBar:Bar;
        public var desyncMusicBar:Array<FlxBar> = [];
        public var vsliceSmoothBar = ClientPrefs.data.vsliceSmoothBar;
        public var vsliceSmoothNess = ClientPrefs.data.vsliceSmoothNess;
        public var vsliceSongPosition = ClientPrefs.data.vsliceSongPosition;
        public var vsliceBotPlayPlace = ClientPrefs.data.vsliceBotPlayPlace;

        var songPercent:Float = 0;
        public var nanoPosition:Bool = ClientPrefs.data.nanoPosition;
        public var ratingsData:Array<Rating> = Rating.loadDefault();
        private var generatedMusic:Bool = false;

        public var endingSong:Bool = false;
        public var startingSong:Bool = false;
        public var leavePlayState:Bool = false;

        private var updateTime:Bool = true;

        public static var changedDifficulty:Bool = false;
        public static var chartingMode:Bool = false;

        // Recycling PopUps
        public var showPopups:Bool;
        public var showRating:Bool = ClientPrefs.data.showRating;
        public var showComboNum:Bool = ClientPrefs.data.showComboNum;
        public var showCombo:Bool = ClientPrefs.data.showCombo;
        public var changePopup:Bool = ClientPrefs.data.changeNotes;

        // Gameplay settings
        public var downScroll:Bool = ClientPrefs.data.downScroll;
        public var healthGain:Float = 1;
        public var healthLoss:Float = 1;

        public final guitarHeroSustains:Bool = false;
        public var instakillOnMiss:Bool = false;
        public var instacrashOnMiss:Bool = false;
        public var cpuControlled:Bool = false;
        public var practiceMode:Bool = false;
        public var pressMissDamage:Float = 0.05;

        public var botplaySine:Float = 0;
        public var botplaySineCnt:Int = 0;
        public var botplayTxt:FlxText;
        public var infoTxt:FlxText;

        public var iconP1:HealthIcon;
        public var iconP2:HealthIcon;
        public var iconBopType:String = ClientPrefs.data.iconBopType;
        public var iconStrength:Bool = ClientPrefs.data.iconStrength;
        public var camHUD:FlxCamera;
        public var camGame:FlxCamera;
        public var camOther:FlxCamera;
        public var luaTpadCam:FlxCamera;
        public var cameraSpeed:Float = 1;

        public var songScore:Float = 0;
        public var songHits:Float = 0;
        public var songMisses:Float = 0;
        public var scoreTxt:FlxText;

        var timeTxt:FlxText;
        var scoreTxtTween:FlxTween;

        public static var campaignScore:Float = 0;
        public static var campaignMisses:Float = 0;
        public static var seenCutscene:Bool = false;
        public static var deathCounter:Int = 0;

        public static var campaignSaveData:SaveScoreData = FunkinTools.newTali();

        public var defaultCamZoom:Float = 1.05;
        public var defaultStageZoom:Float = 1.05;
        private static var zoomTween:FlxTween;

        // how big to stretch the pixel art assets
        public static var daPixelZoom:Float = 6;

        private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

        public var inCutscene:Bool = false;
        public var skipCountdown:Bool = false;

        var songLength:Float = 0;

        public var boyfriendCameraOffset:Array<Float> = null;
        public var opponentCameraOffset:Array<Float> = null;
        public var girlfriendCameraOffset:Array<Float> = null;

        #if DISCORD_ALLOWED
        // Discord RPC variables
        var storyDifficultyText:String = "";
        var detailsText:String = "";
        var detailsPausedText:String = "";
        #end

        // Achievement shit
        var keysPressed:Array<Int> = [];
        var boyfriendIdleTime:Float = 0.0;
        var boyfriendIdled:Bool = false;

        // Lua shit
        public static var instance:PlayState;
        public var displaySizeX:Float = 0;
        public var displaySizeY:Float = 0;

        #if LUA_ALLOWED
        public var luaArray:Array<FunkinLua> = [];
        public var wiggleMap:Map<String, WiggleEffect> = new Map<String, WiggleEffect>();
        #end

        // Shaders
        public var shaderEnabled = ClientPrefs.data.shaders;
        public static var masterPulse:PulseEffect;
        var allowDisable:Bool = false;
        var allowDisableAt:Int = 0;

        #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
        private var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;
        #end

        public var introSoundsSuffix:String = '';

        // Less laggy controls
        private final keysArray:Array<Dynamic> = [

		['note_1a'],
		['note_2a', 'note_2b'],
		['note_3a', 'note_3b', 'note_3c'],
		['note_4a', 'note_4b', 'note_4c', 'note_4d'],
		['note_5a', 'note_5b', 'note_5c', 'note_5d', 'note_5e'],
		['note_6a', 'note_6b', 'note_6c', 'note_6d', 'note_6e', 'note_6f'],
		['note_7a', 'note_7b', 'note_7c', 'note_7d', 'note_7e', 'note_7f', 'note_7g'],
		['note_8a', 'note_8b', 'note_8c', 'note_8d', 'note_8e', 'note_8f', 'note_8g', 'note_8h'],
		['note_9a', 'note_9b', 'note_9c', 'note_9d', 'note_9e', 'note_9f', 'note_9g', 'note_9h', 'note_9i'],
		['note_10a', 'note_10b', 'note_10c', 'note_10d', 'note_10e', 'note_10f', 'note_10g', 'note_10h', 'note_10i', 'note_10j'],
		['note_11a', 'note_11b', 'note_11c', 'note_11d', 'note_11e', 'note_11f', 'note_11g', 'note_11h', 'note_11i', 'note_11j', 'note_11k'],
		['note_12a', 'note_12b', 'note_12c', 'note_12d', 'note_12e', 'note_12f', 'note_12g', 'note_12h', 'note_12i', 'note_12j', 'note_12k', 'note_12l'],
		['note_13a', 'note_13b', 'note_13c', 'note_13d', 'note_13e', 'note_13f', 'note_13g', 'note_13h', 'note_13i', 'note_13j', 'note_13k', 'note_13l', 'note_13m'],
		['note_14a', 'note_14b', 'note_14c', 'note_14d', 'note_14e', 'note_14f', 'note_14g', 'note_14h', 'note_14i', 'note_14j', 'note_14k', 'note_14l', 'note_14m', 'note_14n'],
		['note_15a', 'note_15b', 'note_15c', 'note_15d', 'note_15e', 'note_15f', 'note_15g', 'note_15h', 'note_15i', 'note_15j', 'note_15k', 'note_15l', 'note_15m', 'note_15n', 'note_15o'],
		['note_16a', 'note_16b', 'note_16c', 'note_16d', 'note_16e', 'note_16f', 'note_16g', 'note_16h', 'note_16i', 'note_16j', 'note_16k', 'note_16l', 'note_16m', 'note_16n', 'note_16o', 'note_16p'],
		['note_17a', 'note_17b', 'note_17c', 'note_17d', 'note_17e', 'note_17f', 'note_17g', 'note_17h', 'note_17i', 'note_17j', 'note_17k', 'note_17l', 'note_17m', 'note_17n', 'note_17o', 'note_17p', 'note_17q'],
		['note_18a', 'note_18b', 'note_18c', 'note_18d', 'note_18e', 'note_18f', 'note_18g', 'note_18h', 'note_18i', 'note_18j', 'note_18k', 'note_18l', 'note_18m', 'note_18n', 'note_18o', 'note_18p', 'note_18q', 'note_18r'],
		['note_19a', 'note_19b', 'note_19c', 'note_19d', 'note_19e', 'note_19f', 'note_19g', 'note_19h', 'note_19i', 'note_19j', 'note_19k', 'note_19l', 'note_19m', 'note_19n', 'note_19o', 'note_19p', 'note_19q', 'note_19r', 'note_19s'],
		['note_20a', 'note_20b', 'note_20c', 'note_20d', 'note_20e', 'note_20f', 'note_20g', 'note_20h', 'note_20i', 'note_20j', 'note_20k', 'note_20l', 'note_20m', 'note_20n', 'note_20o', 'note_20p', 'note_20q', 'note_20r', 'note_20s', 'note_20t'],
		['note_21a', 'note_21b', 'note_21c', 'note_21d', 'note_21e', 'note_21f', 'note_21g', 'note_21h', 'note_21i', 'note_21j', 'note_21k', 'note_21l', 'note_21m', 'note_21n', 'note_21o', 'note_21p', 'note_21q', 'note_21r', 'note_21s', 'note_21t', 'note_21u'],
		['note_22a', 'note_22b', 'note_22c', 'note_22d', 'note_22e', 'note_22f', 'note_22g', 'note_22h', 'note_22i', 'note_22j', 'note_22k', 'note_22l', 'note_22m', 'note_22n', 'note_22o', 'note_22p', 'note_22q', 'note_22r', 'note_22s', 'note_22t', 'note_22u', 'note_22v'],
		['note_23a', 'note_23b', 'note_23c', 'note_23d', 'note_23e', 'note_23f', 'note_23g', 'note_23h', 'note_23i', 'note_23j', 'note_23k', 'note_23l', 'note_23m', 'note_23n', 'note_23o', 'note_23p', 'note_23q', 'note_23r', 'note_23s', 'note_23t', 'note_23u', 'note_23v', 'note_23w'],
		['note_24a', 'note_24b', 'note_24c', 'note_24d', 'note_24e', 'note_24f', 'note_24g', 'note_24h', 'note_24i', 'note_24j', 'note_24k', 'note_24l', 'note_24m', 'note_24n', 'note_24o', 'note_24p', 'note_24q', 'note_24r', 'note_24s', 'note_24t', 'note_24u', 'note_24v', 'note_24w', 'note_24x'],
		['note_25a', 'note_25b', 'note_25c', 'note_25d', 'note_25e', 'note_25f', 'note_25g', 'note_25h', 'note_25i', 'note_25j', 'note_25k', 'note_25l', 'note_25m', 'note_25n', 'note_25o', 'note_25p', 'note_25q', 'note_25r', 'note_25s', 'note_25t', 'note_25u', 'note_25v', 'note_25w', 'note_25x', 'note_25y'],
		['note_26a', 'note_26b', 'note_26c', 'note_26d', 'note_26e', 'note_26f', 'note_26g', 'note_26h', 'note_26i', 'note_26j', 'note_26k', 'note_26l', 'note_26m', 'note_26n', 'note_26o', 'note_26p', 'note_26q', 'note_26r', 'note_26s', 'note_26t', 'note_26u', 'note_26v', 'note_26w', 'note_26x', 'note_26y', 'note_26z'],
		['note_27aa'],
		['note_28aa', 'note_28ab'],
		['note_29aa', 'note_29ab', 'note_29ac'],
		['note_30aa', 'note_30ab', 'note_30ac', 'note_30ad'],
		['note_31aa', 'note_31ab', 'note_31ac', 'note_31ad', 'note_31ae'],
		['note_32aa', 'note_32ab', 'note_32ac', 'note_32ad', 'note_32ae', 'note_32af'],
		['note_33aa', 'note_33ab', 'note_33ac', 'note_33ad', 'note_33ae', 'note_33af', 'note_33ag'],
		['note_34aa', 'note_34ab', 'note_34ac', 'note_34ad', 'note_34ae', 'note_34af', 'note_34ag', 'note_34ah'],
		['note_35aa', 'note_35ab', 'note_35ac', 'note_35ad', 'note_35ae', 'note_35af', 'note_35ag', 'note_35ah', 'note_35ai'],
		['note_36aa', 'note_36ab', 'note_36ac', 'note_36ad', 'note_36ae', 'note_36af', 'note_36ag', 'note_36ah', 'note_36ai', 'note_36aj'],
		['note_37aa', 'note_37ab', 'note_37ac', 'note_37ad', 'note_37ae', 'note_37af', 'note_37ag', 'note_37ah', 'note_37ai', 'note_37aj', 'note_37ak'],
		['note_38aa', 'note_38ab', 'note_38ac', 'note_38ad', 'note_38ae', 'note_38af', 'note_38ag', 'note_38ah', 'note_38ai', 'note_38aj', 'note_38ak', 'note_38al'],
		['note_39aa', 'note_39ab', 'note_39ac', 'note_39ad', 'note_39ae', 'note_39af', 'note_39ag', 'note_39ah', 'note_39ai', 'note_39aj', 'note_39ak', 'note_39al', 'note_39am'],
		['note_40aa', 'note_40ab', 'note_40ac', 'note_40ad', 'note_40ae', 'note_40af', 'note_40ag', 'note_40ah', 'note_40ai', 'note_40aj', 'note_40ak', 'note_40al', 'note_40am', 'note_40an'],
		['note_41aa', 'note_41ab', 'note_41ac', 'note_41ad', 'note_41ae', 'note_41af', 'note_41ag', 'note_41ah', 'note_41ai', 'note_41aj', 'note_41ak', 'note_41al', 'note_41am', 'note_41an', 'note_41ao'],
		['note_42aa', 'note_42ab', 'note_42ac', 'note_42ad', 'note_42ae', 'note_42af', 'note_42ag', 'note_42ah', 'note_42ai', 'note_42aj', 'note_42ak', 'note_42al', 'note_42am', 'note_42an', 'note_42ao', 'note_42ap'],
		['note_43aa', 'note_43ab', 'note_43ac', 'note_43ad', 'note_43ae', 'note_43af', 'note_43ag', 'note_43ah', 'note_43ai', 'note_43aj', 'note_43ak', 'note_43al', 'note_43am', 'note_43an', 'note_43ao', 'note_43ap', 'note_43aq'],
		['note_44aa', 'note_44ab', 'note_44ac', 'note_44ad', 'note_44ae', 'note_44af', 'note_44ag', 'note_44ah', 'note_44ai', 'note_44aj', 'note_44ak', 'note_44al', 'note_44am', 'note_44an', 'note_44ao', 'note_44ap', 'note_44aq', 'note_44ar'],
		['note_45aa', 'note_45ab', 'note_45ac', 'note_45ad', 'note_45ae', 'note_45af', 'note_45ag', 'note_45ah', 'note_45ai', 'note_45aj', 'note_45ak', 'note_45al', 'note_45am', 'note_45an', 'note_45ao', 'note_45ap', 'note_45aq', 'note_45ar', 'note_45as'],
		['note_46aa', 'note_46ab', 'note_46ac', 'note_46ad', 'note_46ae', 'note_46af', 'note_46ag', 'note_46ah', 'note_46ai', 'note_46aj', 'note_46ak', 'note_46al', 'note_46am', 'note_46an', 'note_46ao', 'note_46ap', 'note_46aq', 'note_46ar', 'note_46as', 'note_46at'],
		['note_47aa', 'note_47ab', 'note_47ac', 'note_47ad', 'note_47ae', 'note_47af', 'note_47ag', 'note_47ah', 'note_47ai', 'note_47aj', 'note_47ak', 'note_47al', 'note_47am', 'note_47an', 'note_47ao', 'note_47ap', 'note_47aq', 'note_47ar', 'note_47as', 'note_47at', 'note_47au'],
		['note_48aa', 'note_48ab', 'note_48ac', 'note_48ad', 'note_48ae', 'note_48af', 'note_48ag', 'note_48ah', 'note_48ai', 'note_48aj', 'note_48ak', 'note_48al', 'note_48am', 'note_48an', 'note_48ao', 'note_48ap', 'note_48aq', 'note_48ar', 'note_48as', 'note_48at', 'note_48au', 'note_48av'],
		['note_49aa', 'note_49ab', 'note_49ac', 'note_49ad', 'note_49ae', 'note_49af', 'note_49ag', 'note_49ah', 'note_49ai', 'note_49aj', 'note_49ak', 'note_49al', 'note_49am', 'note_49an', 'note_49ao', 'note_49ap', 'note_49aq', 'note_49ar', 'note_49as', 'note_49at', 'note_49au', 'note_49av', 'note_49aw'],
		['note_50aa', 'note_50ab', 'note_50ac', 'note_50ad', 'note_50ae', 'note_50af', 'note_50ag', 'note_50ah', 'note_50ai', 'note_50aj', 'note_50ak', 'note_50al', 'note_50am', 'note_50an', 'note_50ao', 'note_50ap', 'note_50aq', 'note_50ar', 'note_50as', 'note_50at', 'note_50au', 'note_50av', 'note_50aw', 'note_50ax'],
		['note_51aa', 'note_51ab', 'note_51ac', 'note_51ad', 'note_51ae', 'note_51af', 'note_51ag', 'note_51ah', 'note_51ai', 'note_51aj', 'note_51ak', 'note_51al', 'note_51am', 'note_51an', 'note_51ao', 'note_51ap', 'note_51aq', 'note_51ar', 'note_51as', 'note_51at', 'note_51au', 'note_51av', 'note_51aw', 'note_51ax', 'note_51ay'],
		['note_52aa', 'note_52ab', 'note_52ac', 'note_52ad', 'note_52ae', 'note_52af', 'note_52ag', 'note_52ah', 'note_52ai', 'note_52aj', 'note_52ak', 'note_52al', 'note_52am', 'note_52an', 'note_52ao', 'note_52ap', 'note_52aq', 'note_52ar', 'note_52as', 'note_52at', 'note_52au', 'note_52av', 'note_52aw', 'note_52ax', 'note_52ay', 'note_52az'],
		['note_53aa', 'note_53ab', 'note_53ac', 'note_53ad', 'note_53ae', 'note_53af', 'note_53ag', 'note_53ah', 'note_53ai', 'note_53aj', 'note_53ak', 'note_53al', 'note_53am', 'note_53an', 'note_53ao', 'note_53ap', 'note_53aq', 'note_53ar', 'note_53as', 'note_53at', 'note_53au', 'note_53av', 'note_53aw', 'note_53ax', 'note_53ay', 'note_53az', 'note_53ba'],
		['note_54aa', 'note_54ab', 'note_54ac', 'note_54ad', 'note_54ae', 'note_54af', 'note_54ag', 'note_54ah', 'note_54ai', 'note_54aj', 'note_54ak', 'note_54al', 'note_54am', 'note_54an', 'note_54ao', 'note_54ap', 'note_54aq', 'note_54ar', 'note_54as', 'note_54at', 'note_54au', 'note_54av', 'note_54aw', 'note_54ax', 'note_54ay', 'note_54az', 'note_54ba', 'note_54bb'],
		['note_55aa', 'note_55ab', 'note_55ac', 'note_55ad', 'note_55ae', 'note_55af', 'note_55ag', 'note_55ah', 'note_55ai', 'note_55aj', 'note_55ak', 'note_55al', 'note_55am', 'note_55an', 'note_55ao', 'note_55ap', 'note_55aq', 'note_55ar', 'note_55as', 'note_55at', 'note_55au', 'note_55av', 'note_55aw', 'note_55ax', 'note_55ay', 'note_55az', 'note_55ba', 'note_55bb', 'note_55bc'],
		['note_56aa', 'note_56ab', 'note_56ac', 'note_56ad', 'note_56ae', 'note_56af', 'note_56ag', 'note_56ah', 'note_56ai', 'note_56aj', 'note_56ak', 'note_56al', 'note_56am', 'note_56an', 'note_56ao', 'note_56ap', 'note_56aq', 'note_56ar', 'note_56as', 'note_56at', 'note_56au', 'note_56av', 'note_56aw', 'note_56ax', 'note_56ay', 'note_56az', 'note_56ba', 'note_56bb', 'note_56bc', 'note_56bd'],
		['note_57aa', 'note_57ab', 'note_57ac', 'note_57ad', 'note_57ae', 'note_57af', 'note_57ag', 'note_57ah', 'note_57ai', 'note_57aj', 'note_57ak', 'note_57al', 'note_57am', 'note_57an', 'note_57ao', 'note_57ap', 'note_57aq', 'note_57ar', 'note_57as', 'note_57at', 'note_57au', 'note_57av', 'note_57aw', 'note_57ax', 'note_57ay', 'note_57az', 'note_57ba', 'note_57bb', 'note_57bc', 'note_57bd', 'note_57be'],
		['note_58aa', 'note_58ab', 'note_58ac', 'note_58ad', 'note_58ae', 'note_58af', 'note_58ag', 'note_58ah', 'note_58ai', 'note_58aj', 'note_58ak', 'note_58al', 'note_58am', 'note_58an', 'note_58ao', 'note_58ap', 'note_58aq', 'note_58ar', 'note_58as', 'note_58at', 'note_58au', 'note_58av', 'note_58aw', 'note_58ax', 'note_58ay', 'note_58az', 'note_58ba', 'note_58bb', 'note_58bc', 'note_58bd', 'note_58be', 'note_58bf'],
		['note_59aa', 'note_59ab', 'note_59ac', 'note_59ad', 'note_59ae', 'note_59af', 'note_59ag', 'note_59ah', 'note_59ai', 'note_59aj', 'note_59ak', 'note_59al', 'note_59am', 'note_59an', 'note_59ao', 'note_59ap', 'note_59aq', 'note_59ar', 'note_59as', 'note_59at', 'note_59au', 'note_59av', 'note_59aw', 'note_59ax', 'note_59ay', 'note_59az', 'note_59ba', 'note_59bb', 'note_59bc', 'note_59bd', 'note_59be', 'note_59bf', 'note_59bg'],
		['note_60aa', 'note_60ab', 'note_60ac', 'note_60ad', 'note_60ae', 'note_60af', 'note_60ag', 'note_60ah', 'note_60ai', 'note_60aj', 'note_60ak', 'note_60al', 'note_60am', 'note_60an', 'note_60ao', 'note_60ap', 'note_60aq', 'note_60ar', 'note_60as', 'note_60at', 'note_60au', 'note_60av', 'note_60aw', 'note_60ax', 'note_60ay', 'note_60az', 'note_60ba', 'note_60bb', 'note_60bc', 'note_60bd', 'note_60be', 'note_60bf', 'note_60bg', 'note_60bh'],
		['note_61aa', 'note_61ab', 'note_61ac', 'note_61ad', 'note_61ae', 'note_61af', 'note_61ag', 'note_61ah', 'note_61ai', 'note_61aj', 'note_61ak', 'note_61al', 'note_61am', 'note_61an', 'note_61ao', 'note_61ap', 'note_61aq', 'note_61ar', 'note_61as', 'note_61at', 'note_61au', 'note_61av', 'note_61aw', 'note_61ax', 'note_61ay', 'note_61az', 'note_61ba', 'note_61bb', 'note_61bc', 'note_61bd', 'note_61be', 'note_61bf', 'note_61bg', 'note_61bh', 'note_61bi'],
		['note_62aa', 'note_62ab', 'note_62ac', 'note_62ad', 'note_62ae', 'note_62af', 'note_62ag', 'note_62ah', 'note_62ai', 'note_62aj', 'note_62ak', 'note_62al', 'note_62am', 'note_62an', 'note_62ao', 'note_62ap', 'note_62aq', 'note_62ar', 'note_62as', 'note_62at', 'note_62au', 'note_62av', 'note_62aw', 'note_62ax', 'note_62ay', 'note_62az', 'note_62ba', 'note_62bb', 'note_62bc', 'note_62bd', 'note_62be', 'note_62bf', 'note_62bg', 'note_62bh', 'note_62bi', 'note_62bj'],
		['note_63aa', 'note_63ab', 'note_63ac', 'note_63ad', 'note_63ae', 'note_63af', 'note_63ag', 'note_63ah', 'note_63ai', 'note_63aj', 'note_63ak', 'note_63al', 'note_63am', 'note_63an', 'note_63ao', 'note_63ap', 'note_63aq', 'note_63ar', 'note_63as', 'note_63at', 'note_63au', 'note_63av', 'note_63aw', 'note_63ax', 'note_63ay', 'note_63az', 'note_63ba', 'note_63bb', 'note_63bc', 'note_63bd', 'note_63be', 'note_63bf', 'note_63bg', 'note_63bh', 'note_63bi', 'note_63bj', 'note_63bk'],
		['note_64aa', 'note_64ab', 'note_64ac', 'note_64ad', 'note_64ae', 'note_64af', 'note_64ag', 'note_64ah', 'note_64ai', 'note_64aj', 'note_64ak', 'note_64al', 'note_64am', 'note_64an', 'note_64ao', 'note_64ap', 'note_64aq', 'note_64ar', 'note_64as', 'note_64at', 'note_64au', 'note_64av', 'note_64aw', 'note_64ax', 'note_64ay', 'note_64az', 'note_64ba', 'note_64bb', 'note_64bc', 'note_64bd', 'note_64be', 'note_64bf', 'note_64bg', 'note_64bh', 'note_64bi', 'note_64bj', 'note_64bk', 'note_64bl'],
		['note_65aa', 'note_65ab', 'note_65ac', 'note_65ad', 'note_65ae', 'note_65af', 'note_65ag', 'note_65ah', 'note_65ai', 'note_65aj', 'note_65ak', 'note_65al', 'note_65am', 'note_65an', 'note_65ao', 'note_65ap', 'note_65aq', 'note_65ar', 'note_65as', 'note_65at', 'note_65au', 'note_65av', 'note_65aw', 'note_65ax', 'note_65ay', 'note_65az', 'note_65ba', 'note_65bb', 'note_65bc', 'note_65bd', 'note_65be', 'note_65bf', 'note_65bg', 'note_65bh', 'note_65bi', 'note_65bj', 'note_65bk', 'note_65bl', 'note_65bm'],
		['note_66aa', 'note_66ab', 'note_66ac', 'note_66ad', 'note_66ae', 'note_66af', 'note_66ag', 'note_66ah', 'note_66ai', 'note_66aj', 'note_66ak', 'note_66al', 'note_66am', 'note_66an', 'note_66ao', 'note_66ap', 'note_66aq', 'note_66ar', 'note_66as', 'note_66at', 'note_66au', 'note_66av', 'note_66aw', 'note_66ax', 'note_66ay', 'note_66az', 'note_66ba', 'note_66bb', 'note_66bc', 'note_66bd', 'note_66be', 'note_66bf', 'note_66bg', 'note_66bh', 'note_66bi', 'note_66bj', 'note_66bk', 'note_66bl', 'note_66bm', 'note_66bn'],
		['note_67aa', 'note_67ab', 'note_67ac', 'note_67ad', 'note_67ae', 'note_67af', 'note_67ag', 'note_67ah', 'note_67ai', 'note_67aj', 'note_67ak', 'note_67al', 'note_67am', 'note_67an', 'note_67ao', 'note_67ap', 'note_67aq', 'note_67ar', 'note_67as', 'note_67at', 'note_67au', 'note_67av', 'note_67aw', 'note_67ax', 'note_67ay', 'note_67az', 'note_67ba', 'note_67bb', 'note_67bc', 'note_67bd', 'note_67be', 'note_67bf', 'note_67bg', 'note_67bh', 'note_67bi', 'note_67bj', 'note_67bk', 'note_67bl', 'note_67bm', 'note_67bn', 'note_67bo'],
		['note_68aa', 'note_68ab', 'note_68ac', 'note_68ad', 'note_68ae', 'note_68af', 'note_68ag', 'note_68ah', 'note_68ai', 'note_68aj', 'note_68ak', 'note_68al', 'note_68am', 'note_68an', 'note_68ao', 'note_68ap', 'note_68aq', 'note_68ar', 'note_68as', 'note_68at', 'note_68au', 'note_68av', 'note_68aw', 'note_68ax', 'note_68ay', 'note_68az', 'note_68ba', 'note_68bb', 'note_68bc', 'note_68bd', 'note_68be', 'note_68bf', 'note_68bg', 'note_68bh', 'note_68bi', 'note_68bj', 'note_68bk', 'note_68bl', 'note_68bm', 'note_68bn', 'note_68bo', 'note_68bp'],
		['note_69aa', 'note_69ab', 'note_69ac', 'note_69ad', 'note_69ae', 'note_69af', 'note_69ag', 'note_69ah', 'note_69ai', 'note_69aj', 'note_69ak', 'note_69al', 'note_69am', 'note_69an', 'note_69ao', 'note_69ap', 'note_69aq', 'note_69ar', 'note_69as', 'note_69at', 'note_69au', 'note_69av', 'note_69aw', 'note_69ax', 'note_69ay', 'note_69az', 'note_69ba', 'note_69bb', 'note_69bc', 'note_69bd', 'note_69be', 'note_69bf', 'note_69bg', 'note_69bh', 'note_69bi', 'note_69bj', 'note_69bk', 'note_69bl', 'note_69bm', 'note_69bn', 'note_69bo', 'note_69bp', 'note_69bq'],
		['note_70aa', 'note_70ab', 'note_70ac', 'note_70ad', 'note_70ae', 'note_70af', 'note_70ag', 'note_70ah', 'note_70ai', 'note_70aj', 'note_70ak', 'note_70al', 'note_70am', 'note_70an', 'note_70ao', 'note_70ap', 'note_70aq', 'note_70ar', 'note_70as', 'note_70at', 'note_70au', 'note_70av', 'note_70aw', 'note_70ax', 'note_70ay', 'note_70az', 'note_70ba', 'note_70bb', 'note_70bc', 'note_70bd', 'note_70be', 'note_70bf', 'note_70bg', 'note_70bh', 'note_70bi', 'note_70bj', 'note_70bk', 'note_70bl', 'note_70bm', 'note_70bn', 'note_70bo', 'note_70bp', 'note_70bq', 'note_70br'],
		['note_71aa', 'note_71ab', 'note_71ac', 'note_71ad', 'note_71ae', 'note_71af', 'note_71ag', 'note_71ah', 'note_71ai', 'note_71aj', 'note_71ak', 'note_71al', 'note_71am', 'note_71an', 'note_71ao', 'note_71ap', 'note_71aq', 'note_71ar', 'note_71as', 'note_71at', 'note_71au', 'note_71av', 'note_71aw', 'note_71ax', 'note_71ay', 'note_71az', 'note_71ba', 'note_71bb', 'note_71bc', 'note_71bd', 'note_71be', 'note_71bf', 'note_71bg', 'note_71bh', 'note_71bi', 'note_71bj', 'note_71bk', 'note_71bl', 'note_71bm', 'note_71bn', 'note_71bo', 'note_71bp', 'note_71bq', 'note_71br', 'note_71bs'],
		['note_72aa', 'note_72ab', 'note_72ac', 'note_72ad', 'note_72ae', 'note_72af', 'note_72ag', 'note_72ah', 'note_72ai', 'note_72aj', 'note_72ak', 'note_72al', 'note_72am', 'note_72an', 'note_72ao', 'note_72ap', 'note_72aq', 'note_72ar', 'note_72as', 'note_72at', 'note_72au', 'note_72av', 'note_72aw', 'note_72ax', 'note_72ay', 'note_72az', 'note_72ba', 'note_72bb', 'note_72bc', 'note_72bd', 'note_72be', 'note_72bf', 'note_72bg', 'note_72bh', 'note_72bi', 'note_72bj', 'note_72bk', 'note_72bl', 'note_72bm', 'note_72bn', 'note_72bo', 'note_72bp', 'note_72bq', 'note_72br', 'note_72bs', 'note_72bt'],
		['note_73aa', 'note_73ab', 'note_73ac', 'note_73ad', 'note_73ae', 'note_73af', 'note_73ag', 'note_73ah', 'note_73ai', 'note_73aj', 'note_73ak', 'note_73al', 'note_73am', 'note_73an', 'note_73ao', 'note_73ap', 'note_73aq', 'note_73ar', 'note_73as', 'note_73at', 'note_73au', 'note_73av', 'note_73aw', 'note_73ax', 'note_73ay', 'note_73az', 'note_73ba', 'note_73bb', 'note_73bc', 'note_73bd', 'note_73be', 'note_73bf', 'note_73bg', 'note_73bh', 'note_73bi', 'note_73bj', 'note_73bk', 'note_73bl', 'note_73bm', 'note_73bn', 'note_73bo', 'note_73bp', 'note_73bq', 'note_73br', 'note_73bs', 'note_73bt', 'note_73bu'],
		['note_74aa', 'note_74ab', 'note_74ac', 'note_74ad', 'note_74ae', 'note_74af', 'note_74ag', 'note_74ah', 'note_74ai', 'note_74aj', 'note_74ak', 'note_74al', 'note_74am', 'note_74an', 'note_74ao', 'note_74ap', 'note_74aq', 'note_74ar', 'note_74as', 'note_74at', 'note_74au', 'note_74av', 'note_74aw', 'note_74ax', 'note_74ay', 'note_74az', 'note_74ba', 'note_74bb', 'note_74bc', 'note_74bd', 'note_74be', 'note_74bf', 'note_74bg', 'note_74bh', 'note_74bi', 'note_74bj', 'note_74bk', 'note_74bl', 'note_74bm', 'note_74bn', 'note_74bo', 'note_74bp', 'note_74bq', 'note_74br', 'note_74bs', 'note_74bt', 'note_74bu', 'note_74bv'],
		['note_75aa', 'note_75ab', 'note_75ac', 'note_75ad', 'note_75ae', 'note_75af', 'note_75ag', 'note_75ah', 'note_75ai', 'note_75aj', 'note_75ak', 'note_75al', 'note_75am', 'note_75an', 'note_75ao', 'note_75ap', 'note_75aq', 'note_75ar', 'note_75as', 'note_75at', 'note_75au', 'note_75av', 'note_75aw', 'note_75ax', 'note_75ay', 'note_75az', 'note_75ba', 'note_75bb', 'note_75bc', 'note_75bd', 'note_75be', 'note_75bf', 'note_75bg', 'note_75bh', 'note_75bi', 'note_75bj', 'note_75bk', 'note_75bl', 'note_75bm', 'note_75bn', 'note_75bo', 'note_75bp', 'note_75bq', 'note_75br', 'note_75bs', 'note_75bt', 'note_75bu', 'note_75bv', 'note_75bw'],
		['note_76aa', 'note_76ab', 'note_76ac', 'note_76ad', 'note_76ae', 'note_76af', 'note_76ag', 'note_76ah', 'note_76ai', 'note_76aj', 'note_76ak', 'note_76al', 'note_76am', 'note_76an', 'note_76ao', 'note_76ap', 'note_76aq', 'note_76ar', 'note_76as', 'note_76at', 'note_76au', 'note_76av', 'note_76aw', 'note_76ax', 'note_76ay', 'note_76az', 'note_76ba', 'note_76bb', 'note_76bc', 'note_76bd', 'note_76be', 'note_76bf', 'note_76bg', 'note_76bh', 'note_76bi', 'note_76bj', 'note_76bk', 'note_76bl', 'note_76bm', 'note_76bn', 'note_76bo', 'note_76bp', 'note_76bq', 'note_76br', 'note_76bs', 'note_76bt', 'note_76bu', 'note_76bv', 'note_76bw', 'note_76bx'],
		['note_77aa', 'note_77ab', 'note_77ac', 'note_77ad', 'note_77ae', 'note_77af', 'note_77ag', 'note_77ah', 'note_77ai', 'note_77aj', 'note_77ak', 'note_77al', 'note_77am', 'note_77an', 'note_77ao', 'note_77ap', 'note_77aq', 'note_77ar', 'note_77as', 'note_77at', 'note_77au', 'note_77av', 'note_77aw', 'note_77ax', 'note_77ay', 'note_77az', 'note_77ba', 'note_77bb', 'note_77bc', 'note_77bd', 'note_77be', 'note_77bf', 'note_77bg', 'note_77bh', 'note_77bi', 'note_77bj', 'note_77bk', 'note_77bl', 'note_77bm', 'note_77bn', 'note_77bo', 'note_77bp', 'note_77bq', 'note_77br', 'note_77bs', 'note_77bt', 'note_77bu', 'note_77bv', 'note_77bw', 'note_77bx', 'note_77by'],
		['note_78aa', 'note_78ab', 'note_78ac', 'note_78ad', 'note_78ae', 'note_78af', 'note_78ag', 'note_78ah', 'note_78ai', 'note_78aj', 'note_78ak', 'note_78al', 'note_78am', 'note_78an', 'note_78ao', 'note_78ap', 'note_78aq', 'note_78ar', 'note_78as', 'note_78at', 'note_78au', 'note_78av', 'note_78aw', 'note_78ax', 'note_78ay', 'note_78az', 'note_78ba', 'note_78bb', 'note_78bc', 'note_78bd', 'note_78be', 'note_78bf', 'note_78bg', 'note_78bh', 'note_78bi', 'note_78bj', 'note_78bk', 'note_78bl', 'note_78bm', 'note_78bn', 'note_78bo', 'note_78bp', 'note_78bq', 'note_78br', 'note_78bs', 'note_78bt', 'note_78bu', 'note_78bv', 'note_78bw', 'note_78bx', 'note_78by', 'note_78bz'],
		['note_79aa', 'note_79ab', 'note_79ac', 'note_79ad', 'note_79ae', 'note_79af', 'note_79ag', 'note_79ah', 'note_79ai', 'note_79aj', 'note_79ak', 'note_79al', 'note_79am', 'note_79an', 'note_79ao', 'note_79ap', 'note_79aq', 'note_79ar', 'note_79as', 'note_79at', 'note_79au', 'note_79av', 'note_79aw', 'note_79ax', 'note_79ay', 'note_79az', 'note_79ba', 'note_79bb', 'note_79bc', 'note_79bd', 'note_79be', 'note_79bf', 'note_79bg', 'note_79bh', 'note_79bi', 'note_79bj', 'note_79bk', 'note_79bl', 'note_79bm', 'note_79bn', 'note_79bo', 'note_79bp', 'note_79bq', 'note_79br', 'note_79bs', 'note_79bt', 'note_79bu', 'note_79bv', 'note_79bw', 'note_79bx', 'note_79by', 'note_79bz', 'note_79ca'],
		['note_80aa', 'note_80ab', 'note_80ac', 'note_80ad', 'note_80ae', 'note_80af', 'note_80ag', 'note_80ah', 'note_80ai', 'note_80aj', 'note_80ak', 'note_80al', 'note_80am', 'note_80an', 'note_80ao', 'note_80ap', 'note_80aq', 'note_80ar', 'note_80as', 'note_80at', 'note_80au', 'note_80av', 'note_80aw', 'note_80ax', 'note_80ay', 'note_80az', 'note_80ba', 'note_80bb', 'note_80bc', 'note_80bd', 'note_80be', 'note_80bf', 'note_80bg', 'note_80bh', 'note_80bi', 'note_80bj', 'note_80bk', 'note_80bl', 'note_80bm', 'note_80bn', 'note_80bo', 'note_80bp', 'note_80bq', 'note_80br', 'note_80bs', 'note_80bt', 'note_80bu', 'note_80bv', 'note_80bw', 'note_80bx', 'note_80by', 'note_80bz', 'note_80ca', 'note_80cb'],
		['note_81aa', 'note_81ab', 'note_81ac', 'note_81ad', 'note_81ae', 'note_81af', 'note_81ag', 'note_81ah', 'note_81ai', 'note_81aj', 'note_81ak', 'note_81al', 'note_81am', 'note_81an', 'note_81ao', 'note_81ap', 'note_81aq', 'note_81ar', 'note_81as', 'note_81at', 'note_81au', 'note_81av', 'note_81aw', 'note_81ax', 'note_81ay', 'note_81az', 'note_81ba', 'note_81bb', 'note_81bc', 'note_81bd', 'note_81be', 'note_81bf', 'note_81bg', 'note_81bh', 'note_81bi', 'note_81bj', 'note_81bk', 'note_81bl', 'note_81bm', 'note_81bn', 'note_81bo', 'note_81bp', 'note_81bq', 'note_81br', 'note_81bs', 'note_81bt', 'note_81bu', 'note_81bv', 'note_81bw', 'note_81bx', 'note_81by', 'note_81bz', 'note_81ca', 'note_81cb', 'note_81cc'],
		['note_82aa', 'note_82ab', 'note_82ac', 'note_82ad', 'note_82ae', 'note_82af', 'note_82ag', 'note_82ah', 'note_82ai', 'note_82aj', 'note_82ak', 'note_82al', 'note_82am', 'note_82an', 'note_82ao', 'note_82ap', 'note_82aq', 'note_82ar', 'note_82as', 'note_82at', 'note_82au', 'note_82av', 'note_82aw', 'note_82ax', 'note_82ay', 'note_82az', 'note_82ba', 'note_82bb', 'note_82bc', 'note_82bd', 'note_82be', 'note_82bf', 'note_82bg', 'note_82bh', 'note_82bi', 'note_82bj', 'note_82bk', 'note_82bl', 'note_82bm', 'note_82bn', 'note_82bo', 'note_82bp', 'note_82bq', 'note_82br', 'note_82bs', 'note_82bt', 'note_82bu', 'note_82bv', 'note_82bw', 'note_82bx', 'note_82by', 'note_82bz', 'note_82ca', 'note_82cb', 'note_82cc', 'note_82cd'],
		['note_83aa', 'note_83ab', 'note_83ac', 'note_83ad', 'note_83ae', 'note_83af', 'note_83ag', 'note_83ah', 'note_83ai', 'note_83aj', 'note_83ak', 'note_83al', 'note_83am', 'note_83an', 'note_83ao', 'note_83ap', 'note_83aq', 'note_83ar', 'note_83as', 'note_83at', 'note_83au', 'note_83av', 'note_83aw', 'note_83ax', 'note_83ay', 'note_83az', 'note_83ba', 'note_83bb', 'note_83bc', 'note_83bd', 'note_83be', 'note_83bf', 'note_83bg', 'note_83bh', 'note_83bi', 'note_83bj', 'note_83bk', 'note_83bl', 'note_83bm', 'note_83bn', 'note_83bo', 'note_83bp', 'note_83bq', 'note_83br', 'note_83bs', 'note_83bt', 'note_83bu', 'note_83bv', 'note_83bw', 'note_83bx', 'note_83by', 'note_83bz', 'note_83ca', 'note_83cb', 'note_83cc', 'note_83cd', 'note_83ce'],
		['note_84aa', 'note_84ab', 'note_84ac', 'note_84ad', 'note_84ae', 'note_84af', 'note_84ag', 'note_84ah', 'note_84ai', 'note_84aj', 'note_84ak', 'note_84al', 'note_84am', 'note_84an', 'note_84ao', 'note_84ap', 'note_84aq', 'note_84ar', 'note_84as', 'note_84at', 'note_84au', 'note_84av', 'note_84aw', 'note_84ax', 'note_84ay', 'note_84az', 'note_84ba', 'note_84bb', 'note_84bc', 'note_84bd', 'note_84be', 'note_84bf', 'note_84bg', 'note_84bh', 'note_84bi', 'note_84bj', 'note_84bk', 'note_84bl', 'note_84bm', 'note_84bn', 'note_84bo', 'note_84bp', 'note_84bq', 'note_84br', 'note_84bs', 'note_84bt', 'note_84bu', 'note_84bv', 'note_84bw', 'note_84bx', 'note_84by', 'note_84bz', 'note_84ca', 'note_84cb', 'note_84cc', 'note_84cd', 'note_84ce', 'note_84cf'],
		['note_85aa', 'note_85ab', 'note_85ac', 'note_85ad', 'note_85ae', 'note_85af', 'note_85ag', 'note_85ah', 'note_85ai', 'note_85aj', 'note_85ak', 'note_85al', 'note_85am', 'note_85an', 'note_85ao', 'note_85ap', 'note_85aq', 'note_85ar', 'note_85as', 'note_85at', 'note_85au', 'note_85av', 'note_85aw', 'note_85ax', 'note_85ay', 'note_85az', 'note_85ba', 'note_85bb', 'note_85bc', 'note_85bd', 'note_85be', 'note_85bf', 'note_85bg', 'note_85bh', 'note_85bi', 'note_85bj', 'note_85bk', 'note_85bl', 'note_85bm', 'note_85bn', 'note_85bo', 'note_85bp', 'note_85bq', 'note_85br', 'note_85bs', 'note_85bt', 'note_85bu', 'note_85bv', 'note_85bw', 'note_85bx', 'note_85by', 'note_85bz', 'note_85ca', 'note_85cb', 'note_85cc', 'note_85cd', 'note_85ce', 'note_85cf', 'note_85cg'],
		['note_86aa', 'note_86ab', 'note_86ac', 'note_86ad', 'note_86ae', 'note_86af', 'note_86ag', 'note_86ah', 'note_86ai', 'note_86aj', 'note_86ak', 'note_86al', 'note_86am', 'note_86an', 'note_86ao', 'note_86ap', 'note_86aq', 'note_86ar', 'note_86as', 'note_86at', 'note_86au', 'note_86av', 'note_86aw', 'note_86ax', 'note_86ay', 'note_86az', 'note_86ba', 'note_86bb', 'note_86bc', 'note_86bd', 'note_86be', 'note_86bf', 'note_86bg', 'note_86bh', 'note_86bi', 'note_86bj', 'note_86bk', 'note_86bl', 'note_86bm', 'note_86bn', 'note_86bo', 'note_86bp', 'note_86bq', 'note_86br', 'note_86bs', 'note_86bt', 'note_86bu', 'note_86bv', 'note_86bw', 'note_86bx', 'note_86by', 'note_86bz', 'note_86ca', 'note_86cb', 'note_86cc', 'note_86cd', 'note_86ce', 'note_86cf', 'note_86cg', 'note_86ch'],
		['note_87aa', 'note_87ab', 'note_87ac', 'note_87ad', 'note_87ae', 'note_87af', 'note_87ag', 'note_87ah', 'note_87ai', 'note_87aj', 'note_87ak', 'note_87al', 'note_87am', 'note_87an', 'note_87ao', 'note_87ap', 'note_87aq', 'note_87ar', 'note_87as', 'note_87at', 'note_87au', 'note_87av', 'note_87aw', 'note_87ax', 'note_87ay', 'note_87az', 'note_87ba', 'note_87bb', 'note_87bc', 'note_87bd', 'note_87be', 'note_87bf', 'note_87bg', 'note_87bh', 'note_87bi', 'note_87bj', 'note_87bk', 'note_87bl', 'note_87bm', 'note_87bn', 'note_87bo', 'note_87bp', 'note_87bq', 'note_87br', 'note_87bs', 'note_87bt', 'note_87bu', 'note_87bv', 'note_87bw', 'note_87bx', 'note_87by', 'note_87bz', 'note_87ca', 'note_87cb', 'note_87cc', 'note_87cd', 'note_87ce', 'note_87cf', 'note_87cg', 'note_87ch', 'note_87ci'],
		['note_88aa', 'note_88ab', 'note_88ac', 'note_88ad', 'note_88ae', 'note_88af', 'note_88ag', 'note_88ah', 'note_88ai', 'note_88aj', 'note_88ak', 'note_88al', 'note_88am', 'note_88an', 'note_88ao', 'note_88ap', 'note_88aq', 'note_88ar', 'note_88as', 'note_88at', 'note_88au', 'note_88av', 'note_88aw', 'note_88ax', 'note_88ay', 'note_88az', 'note_88ba', 'note_88bb', 'note_88bc', 'note_88bd', 'note_88be', 'note_88bf', 'note_88bg', 'note_88bh', 'note_88bi', 'note_88bj', 'note_88bk', 'note_88bl', 'note_88bm', 'note_88bn', 'note_88bo', 'note_88bp', 'note_88bq', 'note_88br', 'note_88bs', 'note_88bt', 'note_88bu', 'note_88bv', 'note_88bw', 'note_88bx', 'note_88by', 'note_88bz', 'note_88ca', 'note_88cb', 'note_88cc', 'note_88cd', 'note_88ce', 'note_88cf', 'note_88cg', 'note_88ch', 'note_88ci', 'note_88cj'],
		['note_89aa', 'note_89ab', 'note_89ac', 'note_89ad', 'note_89ae', 'note_89af', 'note_89ag', 'note_89ah', 'note_89ai', 'note_89aj', 'note_89ak', 'note_89al', 'note_89am', 'note_89an', 'note_89ao', 'note_89ap', 'note_89aq', 'note_89ar', 'note_89as', 'note_89at', 'note_89au', 'note_89av', 'note_89aw', 'note_89ax', 'note_89ay', 'note_89az', 'note_89ba', 'note_89bb', 'note_89bc', 'note_89bd', 'note_89be', 'note_89bf', 'note_89bg', 'note_89bh', 'note_89bi', 'note_89bj', 'note_89bk', 'note_89bl', 'note_89bm', 'note_89bn', 'note_89bo', 'note_89bp', 'note_89bq', 'note_89br', 'note_89bs', 'note_89bt', 'note_89bu', 'note_89bv', 'note_89bw', 'note_89bx', 'note_89by', 'note_89bz', 'note_89ca', 'note_89cb', 'note_89cc', 'note_89cd', 'note_89ce', 'note_89cf', 'note_89cg', 'note_89ch', 'note_89ci', 'note_89cj', 'note_89ck'],
		['note_90aa', 'note_90ab', 'note_90ac', 'note_90ad', 'note_90ae', 'note_90af', 'note_90ag', 'note_90ah', 'note_90ai', 'note_90aj', 'note_90ak', 'note_90al', 'note_90am', 'note_90an', 'note_90ao', 'note_90ap', 'note_90aq', 'note_90ar', 'note_90as', 'note_90at', 'note_90au', 'note_90av', 'note_90aw', 'note_90ax', 'note_90ay', 'note_90az', 'note_90ba', 'note_90bb', 'note_90bc', 'note_90bd', 'note_90be', 'note_90bf', 'note_90bg', 'note_90bh', 'note_90bi', 'note_90bj', 'note_90bk', 'note_90bl', 'note_90bm', 'note_90bn', 'note_90bo', 'note_90bp', 'note_90bq', 'note_90br', 'note_90bs', 'note_90bt', 'note_90bu', 'note_90bv', 'note_90bw', 'note_90bx', 'note_90by', 'note_90bz', 'note_90ca', 'note_90cb', 'note_90cc', 'note_90cd', 'note_90ce', 'note_90cf', 'note_90cg', 'note_90ch', 'note_90ci', 'note_90cj', 'note_90ck', 'note_90cl'],
		['note_91aa', 'note_91ab', 'note_91ac', 'note_91ad', 'note_91ae', 'note_91af', 'note_91ag', 'note_91ah', 'note_91ai', 'note_91aj', 'note_91ak', 'note_91al', 'note_91am', 'note_91an', 'note_91ao', 'note_91ap', 'note_91aq', 'note_91ar', 'note_91as', 'note_91at', 'note_91au', 'note_91av', 'note_91aw', 'note_91ax', 'note_91ay', 'note_91az', 'note_91ba', 'note_91bb', 'note_91bc', 'note_91bd', 'note_91be', 'note_91bf', 'note_91bg', 'note_91bh', 'note_91bi', 'note_91bj', 'note_91bk', 'note_91bl', 'note_91bm', 'note_91bn', 'note_91bo', 'note_91bp', 'note_91bq', 'note_91br', 'note_91bs', 'note_91bt', 'note_91bu', 'note_91bv', 'note_91bw', 'note_91bx', 'note_91by', 'note_91bz', 'note_91ca', 'note_91cb', 'note_91cc', 'note_91cd', 'note_91ce', 'note_91cf', 'note_91cg', 'note_91ch', 'note_91ci', 'note_91cj', 'note_91ck', 'note_91cl', 'note_91cm'],
		['note_92aa', 'note_92ab', 'note_92ac', 'note_92ad', 'note_92ae', 'note_92af', 'note_92ag', 'note_92ah', 'note_92ai', 'note_92aj', 'note_92ak', 'note_92al', 'note_92am', 'note_92an', 'note_92ao', 'note_92ap', 'note_92aq', 'note_92ar', 'note_92as', 'note_92at', 'note_92au', 'note_92av', 'note_92aw', 'note_92ax', 'note_92ay', 'note_92az', 'note_92ba', 'note_92bb', 'note_92bc', 'note_92bd', 'note_92be', 'note_92bf', 'note_92bg', 'note_92bh', 'note_92bi', 'note_92bj', 'note_92bk', 'note_92bl', 'note_92bm', 'note_92bn', 'note_92bo', 'note_92bp', 'note_92bq', 'note_92br', 'note_92bs', 'note_92bt', 'note_92bu', 'note_92bv', 'note_92bw', 'note_92bx', 'note_92by', 'note_92bz', 'note_92ca', 'note_92cb', 'note_92cc', 'note_92cd', 'note_92ce', 'note_92cf', 'note_92cg', 'note_92ch', 'note_92ci', 'note_92cj', 'note_92ck', 'note_92cl', 'note_92cm', 'note_92cn'],
		['note_93aa', 'note_93ab', 'note_93ac', 'note_93ad', 'note_93ae', 'note_93af', 'note_93ag', 'note_93ah', 'note_93ai', 'note_93aj', 'note_93ak', 'note_93al', 'note_93am', 'note_93an', 'note_93ao', 'note_93ap', 'note_93aq', 'note_93ar', 'note_93as', 'note_93at', 'note_93au', 'note_93av', 'note_93aw', 'note_93ax', 'note_93ay', 'note_93az', 'note_93ba', 'note_93bb', 'note_93bc', 'note_93bd', 'note_93be', 'note_93bf', 'note_93bg', 'note_93bh', 'note_93bi', 'note_93bj', 'note_93bk', 'note_93bl', 'note_93bm', 'note_93bn', 'note_93bo', 'note_93bp', 'note_93bq', 'note_93br', 'note_93bs', 'note_93bt', 'note_93bu', 'note_93bv', 'note_93bw', 'note_93bx', 'note_93by', 'note_93bz', 'note_93ca', 'note_93cb', 'note_93cc', 'note_93cd', 'note_93ce', 'note_93cf', 'note_93cg', 'note_93ch', 'note_93ci', 'note_93cj', 'note_93ck', 'note_93cl', 'note_93cm', 'note_93cn', 'note_93co'],
		['note_94aa', 'note_94ab', 'note_94ac', 'note_94ad', 'note_94ae', 'note_94af', 'note_94ag', 'note_94ah', 'note_94ai', 'note_94aj', 'note_94ak', 'note_94al', 'note_94am', 'note_94an', 'note_94ao', 'note_94ap', 'note_94aq', 'note_94ar', 'note_94as', 'note_94at', 'note_94au', 'note_94av', 'note_94aw', 'note_94ax', 'note_94ay', 'note_94az', 'note_94ba', 'note_94bb', 'note_94bc', 'note_94bd', 'note_94be', 'note_94bf', 'note_94bg', 'note_94bh', 'note_94bi', 'note_94bj', 'note_94bk', 'note_94bl', 'note_94bm', 'note_94bn', 'note_94bo', 'note_94bp', 'note_94bq', 'note_94br', 'note_94bs', 'note_94bt', 'note_94bu', 'note_94bv', 'note_94bw', 'note_94bx', 'note_94by', 'note_94bz', 'note_94ca', 'note_94cb', 'note_94cc', 'note_94cd', 'note_94ce', 'note_94cf', 'note_94cg', 'note_94ch', 'note_94ci', 'note_94cj', 'note_94ck', 'note_94cl', 'note_94cm', 'note_94cn', 'note_94co', 'note_94cp'],
		['note_95aa', 'note_95ab', 'note_95ac', 'note_95ad', 'note_95ae', 'note_95af', 'note_95ag', 'note_95ah', 'note_95ai', 'note_95aj', 'note_95ak', 'note_95al', 'note_95am', 'note_95an', 'note_95ao', 'note_95ap', 'note_95aq', 'note_95ar', 'note_95as', 'note_95at', 'note_95au', 'note_95av', 'note_95aw', 'note_95ax', 'note_95ay', 'note_95az', 'note_95ba', 'note_95bb', 'note_95bc', 'note_95bd', 'note_95be', 'note_95bf', 'note_95bg', 'note_95bh', 'note_95bi', 'note_95bj', 'note_95bk', 'note_95bl', 'note_95bm', 'note_95bn', 'note_95bo', 'note_95bp', 'note_95bq', 'note_95br', 'note_95bs', 'note_95bt', 'note_95bu', 'note_95bv', 'note_95bw', 'note_95bx', 'note_95by', 'note_95bz', 'note_95ca', 'note_95cb', 'note_95cc', 'note_95cd', 'note_95ce', 'note_95cf', 'note_95cg', 'note_95ch', 'note_95ci', 'note_95cj', 'note_95ck', 'note_95cl', 'note_95cm', 'note_95cn', 'note_95co', 'note_95cp', 'note_95cq'],
		['note_96aa', 'note_96ab', 'note_96ac', 'note_96ad', 'note_96ae', 'note_96af', 'note_96ag', 'note_96ah', 'note_96ai', 'note_96aj', 'note_96ak', 'note_96al', 'note_96am', 'note_96an', 'note_96ao', 'note_96ap', 'note_96aq', 'note_96ar', 'note_96as', 'note_96at', 'note_96au', 'note_96av', 'note_96aw', 'note_96ax', 'note_96ay', 'note_96az', 'note_96ba', 'note_96bb', 'note_96bc', 'note_96bd', 'note_96be', 'note_96bf', 'note_96bg', 'note_96bh', 'note_96bi', 'note_96bj', 'note_96bk', 'note_96bl', 'note_96bm', 'note_96bn', 'note_96bo', 'note_96bp', 'note_96bq', 'note_96br', 'note_96bs', 'note_96bt', 'note_96bu', 'note_96bv', 'note_96bw', 'note_96bx', 'note_96by', 'note_96bz', 'note_96ca', 'note_96cb', 'note_96cc', 'note_96cd', 'note_96ce', 'note_96cf', 'note_96cg', 'note_96ch', 'note_96ci', 'note_96cj', 'note_96ck', 'note_96cl', 'note_96cm', 'note_96cn', 'note_96co', 'note_96cp', 'note_96cq', 'note_96cr'],
		['note_97aa', 'note_97ab', 'note_97ac', 'note_97ad', 'note_97ae', 'note_97af', 'note_97ag', 'note_97ah', 'note_97ai', 'note_97aj', 'note_97ak', 'note_97al', 'note_97am', 'note_97an', 'note_97ao', 'note_97ap', 'note_97aq', 'note_97ar', 'note_97as', 'note_97at', 'note_97au', 'note_97av', 'note_97aw', 'note_97ax', 'note_97ay', 'note_97az', 'note_97ba', 'note_97bb', 'note_97bc', 'note_97bd', 'note_97be', 'note_97bf', 'note_97bg', 'note_97bh', 'note_97bi', 'note_97bj', 'note_97bk', 'note_97bl', 'note_97bm', 'note_97bn', 'note_97bo', 'note_97bp', 'note_97bq', 'note_97br', 'note_97bs', 'note_97bt', 'note_97bu', 'note_97bv', 'note_97bw', 'note_97bx', 'note_97by', 'note_97bz', 'note_97ca', 'note_97cb', 'note_97cc', 'note_97cd', 'note_97ce', 'note_97cf', 'note_97cg', 'note_97ch', 'note_97ci', 'note_97cj', 'note_97ck', 'note_97cl', 'note_97cm', 'note_97cn', 'note_97co', 'note_97cp', 'note_97cq', 'note_97cr', 'note_97cs'],
		['note_98aa', 'note_98ab', 'note_98ac', 'note_98ad', 'note_98ae', 'note_98af', 'note_98ag', 'note_98ah', 'note_98ai', 'note_98aj', 'note_98ak', 'note_98al', 'note_98am', 'note_98an', 'note_98ao', 'note_98ap', 'note_98aq', 'note_98ar', 'note_98as', 'note_98at', 'note_98au', 'note_98av', 'note_98aw', 'note_98ax', 'note_98ay', 'note_98az', 'note_98ba', 'note_98bb', 'note_98bc', 'note_98bd', 'note_98be', 'note_98bf', 'note_98bg', 'note_98bh', 'note_98bi', 'note_98bj', 'note_98bk', 'note_98bl', 'note_98bm', 'note_98bn', 'note_98bo', 'note_98bp', 'note_98bq', 'note_98br', 'note_98bs', 'note_98bt', 'note_98bu', 'note_98bv', 'note_98bw', 'note_98bx', 'note_98by', 'note_98bz', 'note_98ca', 'note_98cb', 'note_98cc', 'note_98cd', 'note_98ce', 'note_98cf', 'note_98cg', 'note_98ch', 'note_98ci', 'note_98cj', 'note_98ck', 'note_98cl', 'note_98cm', 'note_98cn', 'note_98co', 'note_98cp', 'note_98cq', 'note_98cr', 'note_98cs', 'note_98ct'],
		['note_99aa', 'note_99ab', 'note_99ac', 'note_99ad', 'note_99ae', 'note_99af', 'note_99ag', 'note_99ah', 'note_99ai', 'note_99aj', 'note_99ak', 'note_99al', 'note_99am', 'note_99an', 'note_99ao', 'note_99ap', 'note_99aq', 'note_99ar', 'note_99as', 'note_99at', 'note_99au', 'note_99av', 'note_99aw', 'note_99ax', 'note_99ay', 'note_99az', 'note_99ba', 'note_99bb', 'note_99bc', 'note_99bd', 'note_99be', 'note_99bf', 'note_99bg', 'note_99bh', 'note_99bi', 'note_99bj', 'note_99bk', 'note_99bl', 'note_99bm', 'note_99bn', 'note_99bo', 'note_99bp', 'note_99bq', 'note_99br', 'note_99bs', 'note_99bt', 'note_99bu', 'note_99bv', 'note_99bw', 'note_99bx', 'note_99by', 'note_99bz', 'note_99ca', 'note_99cb', 'note_99cc', 'note_99cd', 'note_99ce', 'note_99cf', 'note_99cg', 'note_99ch', 'note_99ci', 'note_99cj', 'note_99ck', 'note_99cl', 'note_99cm', 'note_99cn', 'note_99co', 'note_99cp', 'note_99cq', 'note_99cr', 'note_99cs', 'note_99ct', 'note_99cu'],
		['note_100aa', 'note_100ab', 'note_100ac', 'note_100ad', 'note_100ae', 'note_100af', 'note_100ag', 'note_100ah', 'note_100ai', 'note_100aj', 'note_100ak', 'note_100al', 'note_100am', 'note_100an', 'note_100ao', 'note_100ap', 'note_100aq', 'note_100ar', 'note_100as', 'note_100at', 'note_100au', 'note_100av', 'note_100aw', 'note_100ax', 'note_100ay', 'note_100az', 'note_100ba', 'note_100bb', 'note_100bc', 'note_100bd', 'note_100be', 'note_100bf', 'note_100bg', 'note_100bh', 'note_100bi', 'note_100bj', 'note_100bk', 'note_100bl', 'note_100bm', 'note_100bn', 'note_100bo', 'note_100bp', 'note_100bq', 'note_100br', 'note_100bs', 'note_100bt', 'note_100bu', 'note_100bv', 'note_100bw', 'note_100bx', 'note_100by', 'note_100bz', 'note_100ca', 'note_100cb', 'note_100cc', 'note_100cd', 'note_100ce', 'note_100cf', 'note_100cg', 'note_100ch', 'note_100ci', 'note_100cj', 'note_100ck', 'note_100cl', 'note_100cm', 'note_100cn', 'note_100co', 'note_100cp', 'note_100cq', 'note_100cr', 'note_100cs', 'note_100ct', 'note_100cu', 'note_100cv'],
		['note_101aa', 'note_101ab', 'note_101ac', 'note_101ad', 'note_101ae', 'note_101af', 'note_101ag', 'note_101ah', 'note_101ai', 'note_101aj', 'note_101ak', 'note_101al', 'note_101am', 'note_101an', 'note_101ao', 'note_101ap', 'note_101aq', 'note_101ar', 'note_101as', 'note_101at', 'note_101au', 'note_101av', 'note_101aw', 'note_101ax', 'note_101ay', 'note_101az', 'note_101ba', 'note_101bb', 'note_101bc', 'note_101bd', 'note_101be', 'note_101bf', 'note_101bg', 'note_101bh', 'note_101bi', 'note_101bj', 'note_101bk', 'note_101bl', 'note_101bm', 'note_101bn', 'note_101bo', 'note_101bp', 'note_101bq', 'note_101br', 'note_101bs', 'note_101bt', 'note_101bu', 'note_101bv', 'note_101bw', 'note_101bx', 'note_101by', 'note_101bz', 'note_101ca', 'note_101cb', 'note_101cc', 'note_101cd', 'note_101ce', 'note_101cf', 'note_101cg', 'note_101ch', 'note_101ci', 'note_101cj', 'note_101ck', 'note_101cl', 'note_101cm', 'note_101cn', 'note_101co', 'note_101cp', 'note_101cq', 'note_101cr', 'note_101cs', 'note_101ct', 'note_101cu', 'note_101cv', 'note_101cw'],
		['note_102aa', 'note_102ab', 'note_102ac', 'note_102ad', 'note_102ae', 'note_102af', 'note_102ag', 'note_102ah', 'note_102ai', 'note_102aj', 'note_102ak', 'note_102al', 'note_102am', 'note_102an', 'note_102ao', 'note_102ap', 'note_102aq', 'note_102ar', 'note_102as', 'note_102at', 'note_102au', 'note_102av', 'note_102aw', 'note_102ax', 'note_102ay', 'note_102az', 'note_102ba', 'note_102bb', 'note_102bc', 'note_102bd', 'note_102be', 'note_102bf', 'note_102bg', 'note_102bh', 'note_102bi', 'note_102bj', 'note_102bk', 'note_102bl', 'note_102bm', 'note_102bn', 'note_102bo', 'note_102bp', 'note_102bq', 'note_102br', 'note_102bs', 'note_102bt', 'note_102bu', 'note_102bv', 'note_102bw', 'note_102bx', 'note_102by', 'note_102bz', 'note_102ca', 'note_102cb', 'note_102cc', 'note_102cd', 'note_102ce', 'note_102cf', 'note_102cg', 'note_102ch', 'note_102ci', 'note_102cj', 'note_102ck', 'note_102cl', 'note_102cm', 'note_102cn', 'note_102co', 'note_102cp', 'note_102cq', 'note_102cr', 'note_102cs', 'note_102ct', 'note_102cu', 'note_102cv', 'note_102cw', 'note_102cx'],
		['note_103aa', 'note_103ab', 'note_103ac', 'note_103ad', 'note_103ae', 'note_103af', 'note_103ag', 'note_103ah', 'note_103ai', 'note_103aj', 'note_103ak', 'note_103al', 'note_103am', 'note_103an', 'note_103ao', 'note_103ap', 'note_103aq', 'note_103ar', 'note_103as', 'note_103at', 'note_103au', 'note_103av', 'note_103aw', 'note_103ax', 'note_103ay', 'note_103az', 'note_103ba', 'note_103bb', 'note_103bc', 'note_103bd', 'note_103be', 'note_103bf', 'note_103bg', 'note_103bh', 'note_103bi', 'note_103bj', 'note_103bk', 'note_103bl', 'note_103bm', 'note_103bn', 'note_103bo', 'note_103bp', 'note_103bq', 'note_103br', 'note_103bs', 'note_103bt', 'note_103bu', 'note_103bv', 'note_103bw', 'note_103bx', 'note_103by', 'note_103bz', 'note_103ca', 'note_103cb', 'note_103cc', 'note_103cd', 'note_103ce', 'note_103cf', 'note_103cg', 'note_103ch', 'note_103ci', 'note_103cj', 'note_103ck', 'note_103cl', 'note_103cm', 'note_103cn', 'note_103co', 'note_103cp', 'note_103cq', 'note_103cr', 'note_103cs', 'note_103ct', 'note_103cu', 'note_103cv', 'note_103cw', 'note_103cx', 'note_103cy'],
		['note_104aa', 'note_104ab', 'note_104ac', 'note_104ad', 'note_104ae', 'note_104af', 'note_104ag', 'note_104ah', 'note_104ai', 'note_104aj', 'note_104ak', 'note_104al', 'note_104am', 'note_104an', 'note_104ao', 'note_104ap', 'note_104aq', 'note_104ar', 'note_104as', 'note_104at', 'note_104au', 'note_104av', 'note_104aw', 'note_104ax', 'note_104ay', 'note_104az', 'note_104ba', 'note_104bb', 'note_104bc', 'note_104bd', 'note_104be', 'note_104bf', 'note_104bg', 'note_104bh', 'note_104bi', 'note_104bj', 'note_104bk', 'note_104bl', 'note_104bm', 'note_104bn', 'note_104bo', 'note_104bp', 'note_104bq', 'note_104br', 'note_104bs', 'note_104bt', 'note_104bu', 'note_104bv', 'note_104bw', 'note_104bx', 'note_104by', 'note_104bz', 'note_104ca', 'note_104cb', 'note_104cc', 'note_104cd', 'note_104ce', 'note_104cf', 'note_104cg', 'note_104ch', 'note_104ci', 'note_104cj', 'note_104ck', 'note_104cl', 'note_104cm', 'note_104cn', 'note_104co', 'note_104cp', 'note_104cq', 'note_104cr', 'note_104cs', 'note_104ct', 'note_104cu', 'note_104cv', 'note_104cw', 'note_104cx', 'note_104cy', 'note_104cz'],
		['note_105aa', 'note_105ab', 'note_105ac', 'note_105ad', 'note_105ae', 'note_105af', 'note_105ag', 'note_105ah', 'note_105ai', 'note_105aj', 'note_105ak', 'note_105al', 'note_105am', 'note_105an', 'note_105ao', 'note_105ap', 'note_105aq', 'note_105ar', 'note_105as', 'note_105at', 'note_105au', 'note_105av', 'note_105aw', 'note_105ax', 'note_105ay', 'note_105az', 'note_105ba', 'note_105bb', 'note_105bc', 'note_105bd', 'note_105be', 'note_105bf', 'note_105bg', 'note_105bh', 'note_105bi', 'note_105bj', 'note_105bk', 'note_105bl', 'note_105bm', 'note_105bn', 'note_105bo', 'note_105bp', 'note_105bq', 'note_105br', 'note_105bs', 'note_105bt', 'note_105bu', 'note_105bv', 'note_105bw', 'note_105bx', 'note_105by', 'note_105bz', 'note_105ca', 'note_105cb', 'note_105cc', 'note_105cd', 'note_105ce', 'note_105cf', 'note_105cg', 'note_105ch', 'note_105ci', 'note_105cj', 'note_105ck', 'note_105cl', 'note_105cm', 'note_105cn', 'note_105co', 'note_105cp', 'note_105cq', 'note_105cr', 'note_105cs', 'note_105ct', 'note_105cu', 'note_105cv', 'note_105cw', 'note_105cx', 'note_105cy', 'note_105cz', 'note_105da']
        ];
        public var pressHit:Int = 0;

        public var songName:String;

        // Callbacks for stages
        public var startCallback:Void->Void = null;
        public var endCallback:Void->Void = null;
        
        // FFMpeg values >:(
        var ffmpegMode = ClientPrefs.data.ffmpegMode;
        var targetFPS = ClientPrefs.data.targetFPS;
        var unlockFPS = ClientPrefs.data.unlockFPS;
        var preshot = ClientPrefs.data.preshot;
        var previewRender = ClientPrefs.data.previewRender;
        var gcRate = ClientPrefs.data.gcRate;
        var gcMain = ClientPrefs.data.gcMain;
        #if desktop public static var video:FFMpeg = new FFMpeg(); #end

        // Optimizations
        var processFirst:Bool = ClientPrefs.data.processFirst;
        var showNotes:Bool = ClientPrefs.data.showNotes;
        var showAfter:Bool = ClientPrefs.data.showAfter;
        var keepNotes:Bool = ClientPrefs.data.keepNotes;
        var sortNotes:String = ClientPrefs.data.sortNotes;
        var noteHitPreEvent:Bool = ClientPrefs.data.noteHitPreEvent;
        var noteHitEvent:Bool = ClientPrefs.data.noteHitEvent;
        var skipNoteEvent:Bool = ClientPrefs.data.skipNoteEvent;
        var spawnNoteEvent:Bool = ClientPrefs.data.spawnNoteEvent;
        var noteHitStage:Bool = ClientPrefs.data.noteHitStage;
        var betterRecycle:Bool = ClientPrefs.data.betterRecycle;
        var limitNotes:Int = ClientPrefs.data.limitNotes;
        var hideOverlapped:Float = ClientPrefs.data.hideOverlapped;
        var skipSpawnNote:Bool = ClientPrefs.data.skipSpawnNote;
        var bulkSkip:Bool = ClientPrefs.data.bulkSkip;
        var breakTimeLimit:Bool = ClientPrefs.data.breakTimeLimit;
        var optimizeSpawnNote:Bool = ClientPrefs.data.optimizeSpawnNote;
        var uncappedFPS:Bool = ClientPrefs.data.uncappedFPS;
        var botplayOptimize:Bool = ClientPrefs.data.botplayOptimize;
        var smoothHighScroll:Bool = ClientPrefs.data.smoothHighScroll;
        var smoothHighScrollLimit:Int = 0;

        // CoolUtils Shortcut
        var toBool = CoolUtil.bool;
        var toInt = CoolUtil.int;
        var numFormat = CoolUtil.floatToStringPrecision;
        var fillNum = CoolUtil.fillNumber;
        var formatD = CoolUtil.formatMoney;
        var hex2bin = CoolUtil.hex2bin;
        var revStr = CoolUtil.reverseString;
        var numberDelimit = ClientPrefs.data.numberFormat;

        // Debug Informations
        var showInfoType = ClientPrefs.data.showInfoType;

        // songTime but it's based in nano second lmfao.
        public static var nanoTime:Float = 0;
        public static var elapsedNano:Float = 0;

        // for original A-Slice
        var worldRecordMode = ClientPrefs.data.worldRecordMode;
        
        private static var _lastLoadedModDirectory:String = '';
        public static var nextReloadAll:Bool = false;

        #if TOUCH_CONTROLS_ALLOWED
        public var luaTouchPad:TouchPad;
        #end

        var backupOffset = 0;
        var sortingWay = 0;
        var commaImg = false;

        var freeBotplayTxt:Array<String> = [
                "BOTPRAY",
                "Skill issue mode",
                "Ready or die",
                "Bambi black midis be like:",
                "You fish",
                "Pumpkin",
                "I hate garbage collector",
                "Someone calling 911",
                "Heaven or hell",
                "I'll give u the gift called empty",
                "Imagine 1 billion notes fnf chart",
                "Imagine 1 trillion notes fnf chart",
                "Run away or someone comes",
                "Disguised face",
                "Is rainbow eyesore a drug?",
                "Any number divided by 0 equals 42",
                "It's just a text",
                "Wait, who are you",
                "Hello, visitor!",
                "When botplay lags:",
                "Amogus",
                "Is it impossible?",
                "Testing... just testing...",
                "Gf neck is getting bonk",
                "It's a benchmark",
                "B0TPL4Y",
                "8 800 555 3535",
                "Never gonna give you up",
                "Spamming spamming spamming",
                "Beware memory leaks",
                "When would it can multi-threaded processing", // sadly opengl only supports single-threaded rendering... i'll wait haxeflixel can use vulkan
                "Help me, I have programming skill issue",
                "Demon is inside bot",
                "Don't worry, You can beat this",
                "It's not overcharted, You're just bad",
                ":)",
                ">:(",
                "+++++++++[>++++++++<-]>------.+++++++++++++.+++++.----.----.-----------.<+++++[>+++++<-]>-.",
                "TXkgZXZlcnkgdGVjaG5pcXVlIGhhdmUgc3RvbGVuIGJ5IG90aGVyIHByb2dyYW1tZXJz",
                "...---...",
                "Dark, Darker, Yet Darker",
                "Mesmerizing",
                "Your PC is screaming",
                "NOTPLAY",
                "Coming 2027",
                "Mango",
                "127.0.0.1:6000",
                "Break Infinity!",
                "Break Eternity!",
                "Break Unity/Reality!",
                "Recursion is Power",
                "YOUR TAKING TOO LONG",
                "YOUR LONG",
                "YOUR DONKEY KONG",
                "Dave and baldi are same game btw",
                "You felt deja vu",
                "No way...",
                "Amen break core",
        ];

        var rickRolled:Bool = false;
        final rickRollTxt:Array<String> = [
                "Never gonna give you up",
                "Never gonna let you down",
                "Never gonna run around",
                "and desert you",
                "Never gonna make you cry",
                "Never gonna say goodbye",
                "Never gonna tell a lie",
                "and hurt you"
        ];

        public static var canResync:Bool = false;
        public static var loaded:Bool = false;

        override public function create()
        {
                inPlayState = true;

                // Reset stale static note data from a previous PlayState. `loaded` and
                // `unspawnNotes` are static and survive across PlayState instances, which
                // otherwise makes generateSong() skip re-parsing the current chart and play
                // the previous song's notes (crashing on a mismatched lane count -> null strum).
                loaded = false;
                unspawnNotes = [];

                // trace('Playback Rate: ' + playbackRate);

                if (ffmpegMode) {
                        backupOffset = ClientPrefs.data.noteOffset;
                        ClientPrefs.data.noteOffset = 0;
                }

                //trace('Playback Rate: ' + playbackRate);
                _lastLoadedModDirectory = Mods.currentModDirectory;
                Paths.clearUnusedMemory();
                Paths.clearStoredMemory();
                if(nextReloadAll)
                {
                        Language.reloadPhrases();
                }
                nextReloadAll = false;
                noteKillOffset = NoteKillTime;
                if (smoothHighScroll) smoothHighScrollLimit = 50;

                startCallback = startCountdown;
                endCallback = endSong;

                // for lua
                instance = this;
                displaySizeX = Capabilities.screenResolutionX;
                displaySizeY = Capabilities.screenResolutionY;
                
                if (shaderEnabled) {
                        // Rainbow Eyesore Effect
                        masterPulse = new PulseEffect();
                        masterPulse.shader.uampmul.value[0] = 0;
                }

                if (SONG.mania == null || SONG.mania > Note.MAX_MANIA || SONG.mania < 0) SONG.mania = 3;
                Main.mania = SONG.mania;
                setOnScripts('mania', Main.mania);
                totalColumns = Main.mania + 1;
                resetLaneVectors();

                PauseSubState.songName = null; // Reset to default
                playbackRate = ClientPrefs.getGameplaySetting('songspeed');
                normalRate = playbackRate;
                skipRate = playbackRate * 8;

                if (FlxG.sound.music != null)
                        FlxG.sound.music.stop();

                // check available comma image
                commaImg = Paths.image('numComma') != null;

                // Gameplay settings
                healthGain = ClientPrefs.getGameplaySetting('healthgain');
                healthLoss = ClientPrefs.getGameplaySetting('healthloss');
                instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
                instacrashOnMiss = ClientPrefs.getGameplaySetting('instacrash');
                practiceMode = ClientPrefs.getGameplaySetting('practice');
                cpuControlled = ClientPrefs.getGameplaySetting('botplay') || ffmpegMode || !showNotes;

                // var gameCam:FlxCamera = FlxG.camera;
                camGame = initPsychCamera();
                camHUD = new PsychCamera();
                camOther = new PsychCamera();
                luaTpadCam = new FlxCamera();
                camHUD.bgColor.alpha = 0;
                camOther.bgColor.alpha = 0;
                luaTpadCam.bgColor.alpha = 0;

                FlxG.cameras.add(camHUD, false);
                FlxG.cameras.add(camOther, false);
                FlxG.cameras.add(luaTpadCam, false);

                grpNoteSplashes = new FlxTypedGroup<NoteSplash>();
                // var tmpNote:Note = new Note(0, 0, null);
                // tmpNote.strum = playerStrums.members[0];
                // spawnNoteSplash(tmpNote, -1);
                splashUsing = [for (i in 0...((Main.mania + 1) * 2)) []];

                persistentUpdate = true;
                persistentDraw = true;

                Conductor.mapBPMChanges(SONG);
                Conductor.bpm = SONG.bpm;

                #if DISCORD_ALLOWED
                // String that contains the mode defined here so it isn't necessary to call changePresence for each mode
                storyDifficultyText = Difficulty.getString();

                if (isStoryMode)
                        detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
                else
                        detailsText = "Freeplay";

                // String for when the game is paused
                detailsPausedText = "Paused - " + detailsText;
                #end

                GameOverSubstate.resetVariables();
                songName = Paths.formatToSongPath(SONG.song);
                if (SONG.stage == null || SONG.stage.length < 1)
                        SONG.stage = StageData.vanillaSongStage(Paths.formatToSongPath(Song.loadedSongName));

                curStage = SONG.stage;

                var stageData:StageFile = StageData.getStageFile(curStage);
                defaultCamZoom = stageData.defaultZoom;
                defaultStageZoom = defaultCamZoom;

                stageUI = "normal";
                if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
                        stageUI = stageData.stageUI;
                else if (stageData.isPixelStage == true) // Backward compatibility
                        stageUI = "pixel";

                antialias = ClientPrefs.data.antialiasing && !isPixelStage;

                BF_X = stageData.boyfriend[0];
                BF_Y = stageData.boyfriend[1];
                GF_X = stageData.girlfriend[0];
                GF_Y = stageData.girlfriend[1];
                DAD_X = stageData.opponent[0];
                DAD_Y = stageData.opponent[1];

                if (stageData.camera_speed != null)
                        cameraSpeed = stageData.camera_speed;

                boyfriendCameraOffset = stageData.camera_boyfriend;
                if (boyfriendCameraOffset == null) // Fucks sake should have done it since the start :rolling_eyes:
                        boyfriendCameraOffset = [0, 0];

                opponentCameraOffset = stageData.camera_opponent;
                if (opponentCameraOffset == null)
                        opponentCameraOffset = [0, 0];

                girlfriendCameraOffset = stageData.camera_girlfriend;
                if (girlfriendCameraOffset == null)
                        girlfriendCameraOffset = [0, 0];

                boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
                dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
                gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

                EventLoader.addstage(curStage);
                if(isPixelStage) introSoundsSuffix = '-pixel';

                #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
                luaDebugGroup.cameras = [camOther];
                add(luaDebugGroup);
                #end

                if (!stageData.hide_girlfriend)
                {
                        if (SONG.gfVersion == null || SONG.gfVersion.length < 1)
                                SONG.gfVersion = 'gf'; // Fix for the Chart Editor
                        gf = new Character(0, 0, SONG.gfVersion);
                        startCharacterPos(gf);
                        gfGroup.scrollFactor.set(1, 1);
                        gfGroup.add(gf);
                }

                dad = new Character(0, 0, SONG.player2);
                startCharacterPos(dad, true);
                dadGroup.add(dad);

                boyfriend = new Character(0, 0, SONG.player1, true);
                startCharacterPos(boyfriend);
                boyfriendGroup.add(boyfriend);

                if (stageData.objects != null && stageData.objects.length > 0)
                {
                        var list:Map<String, FlxSprite> = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? gfGroup : null, dadGroup,
                                boyfriendGroup, this);
                        for (key => spr in list)
                                if (!StageData.reservedNames.contains(key))
                                        variables.set(key, spr);
                }
                else
                {
                        add(gfGroup);
                        add(dadGroup);
                        add(boyfriendGroup);
                }

                #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                // "SCRIPTS FOLDER" SCRIPTS
                for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
                        #if linux
                        for (file in CoolUtil.sortAlphabetically(NativeFileSystem.readDirectory(folder)))
                        #else
                        for (file in NativeFileSystem.readDirectory(folder))
                        #end
                {
                        #if LUA_ALLOWED
                        if (file.toLowerCase().endsWith('.lua'))
                                new FunkinLua(folder + file);
                        #end

                        #if HSCRIPT_ALLOWED
                        if (file.toLowerCase().endsWith('.hx'))
                                initHScript(folder + file);
                        #end
                }
                #end

                var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
                if (gf != null)
                {
                        camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
                        camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
                }

                if (dad.curCharacter.startsWith('gf'))
                {
                        dad.setPosition(GF_X, GF_Y);
                        if (gf != null)
                                gf.visible = false;
                }

                #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                // STAGE SCRIPTS
                #if LUA_ALLOWED startLuasNamed('stages/' + curStage + '.lua'); #end
                #if HSCRIPT_ALLOWED startHScriptsNamed('stages/' + curStage + '.hx'); #end

                // CHARACTER SCRIPTS
                if (gf != null)
                        startCharacterScripts(gf.curCharacter);
                startCharacterScripts(dad.curCharacter);
                startCharacterScripts(boyfriend.curCharacter);
                #end

                notesGroup = new FlxTypedGroup<FlxBasic>();
                add(notesGroup);
                
                showPopups = showRating || showComboNum || showCombo;
                if (showPopups) {
                        popUpGroup = new PopupGroup();
                        add(popUpGroup);
                }

                uiGroup = new FlxSpriteGroup();
                add(uiGroup);

                Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
                var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');
                timeTxt = new FlxText(FlxG.width / 4, 19, FlxG.width / 2, "", 32);
                timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
                timeTxt.borderSize = 1;
                timeTxt.borderColor = FlxColor.BLACK;
                timeTxt.scrollFactor.set();
                timeTxt.alpha = 0;
                timeTxt.borderSize = 2;
                timeTxt.borderStyle = FlxTextBorderStyle.OUTLINE;
                timeTxt.antialiasing = ClientPrefs.data.antialiasing;
                timeTxt.visible = updateTime && showTime;
                if (downScroll)
                        timeTxt.y = FlxG.height - 44;
                if (ClientPrefs.data.timeBarType == 'Song Name')
                        timeTxt.text = SONG.song;

                timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
                timeBar.scrollFactor.set();
                timeBar.screenCenter(X);
                timeBar.alpha = 0;
                timeBar.visible = showTime;
                uiGroup.add(timeBar);
                uiGroup.add(timeTxt);

                notesGroup.add(strumLineNotes);

                if (ClientPrefs.data.timeBarType == 'Song Name')
                {
                        timeTxt.size = 24;
                        timeTxt.y += 3;
                }

                generateSong();
                canResync = true;

                notesGroup.add(grpNoteSplashes);
                notesGroup.add(grpHoldSplashes);

                camFollow = new FlxObject();
                camFollow.setPosition(camPos.x, camPos.y);
                camPos.put();

                if (prevCamFollow != null)
                {
                        camFollow = prevCamFollow;
                        prevCamFollow = null;
                }
                add(camFollow);

                FlxG.camera.follow(camFollow, LOCKON, 0);
                FlxG.camera.zoom = defaultCamZoom;
                FlxG.camera.snapToTarget();

                FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
                moveCameraSection();

                var barPlaceMultiplier = vsliceBotPlayPlace == 'Time Bar' ? 0.89 : 0.85;
                if (downScroll) barPlaceMultiplier = 1 - barPlaceMultiplier;
                
                healthBar = new Bar(0, FlxG.height * barPlaceMultiplier, 'healthBar', () -> return healthLerp, 0, 2);
                healthBar.screenCenter(X);
                healthBar.leftToRight = false;
                healthBar.scrollFactor.set();
                healthBar.visible = !ClientPrefs.data.hideHud;
                healthBar.alpha = ClientPrefs.data.healthBarAlpha;
                reloadHealthBarColors();
                uiGroup.add(healthBar);

                iconP1 = new HealthIcon(boyfriend.healthIcon, true, ClientPrefs.data.cacheOnGPU, boyfriend.healthIconDivider);
                iconP1.y = healthBar.y - 75;
                iconP1.visible = !ClientPrefs.data.hideHud;
                iconP1.alpha = ClientPrefs.data.healthBarAlpha;
                uiGroup.add(iconP1);

                iconP2 = new HealthIcon(dad.healthIcon, false, ClientPrefs.data.cacheOnGPU, dad.healthIconDivider);
                iconP2.y = healthBar.y - 75;
                iconP2.visible = !ClientPrefs.data.hideHud;
                iconP2.alpha = ClientPrefs.data.healthBarAlpha;
                uiGroup.add(iconP2);

                scoreTxt = new FlxText(0, healthBar.y + 30, FlxG.width, "", 20);
                scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER);
                scoreTxt.borderSize = 1;
                scoreTxt.borderColor = FlxColor.BLACK;
                scoreTxt.scrollFactor.set();
                scoreTxt.borderSize = 1.25;
                scoreTxt.borderStyle = FlxTextBorderStyle.OUTLINE;
                scoreTxt.visible = !ClientPrefs.data.hideHud;
                scoreTxt.antialiasing = ClientPrefs.data.antialiasing;
                updateScore();
                uiGroup.add(scoreTxt);
                
                infoTxt = new FlxText(0, downScroll ? healthBar.y + 64 : healthBar.y - 48, FlxG.width, "", 32);
                infoTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
                infoTxt.borderSize = 1;
                infoTxt.borderColor = FlxColor.BLACK;
                infoTxt.scrollFactor.set();
                infoTxt.borderSize = 1.25;
                infoTxt.borderStyle = FlxTextBorderStyle.OUTLINE;
                infoTxt.visible = true;
                infoTxt.antialiasing = ClientPrefs.data.antialiasing;

                uiGroup.add(infoTxt);

                // Default Value has inherited from HRK Engine
                var botplayTxtY:Float = timeBar.y + (downScroll ? -80 : 55);
                switch (vsliceBotPlayPlace) {
                        case "Health Bar":
                                botplayTxtY = healthBar.y + (downScroll ? -40 : 60);
                        case "Time Bar": // Omitted because nothing has changed.
                }

                botplayTxt = new FlxText(0, botplayTxtY, FlxG.width, Language.getPhrase("Botplay").toUpperCase(), 32);
                botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
                botplayTxt.borderSize = 1;
                botplayTxt.borderColor = FlxColor.BLACK;
                botplayTxt.scrollFactor.set();
                botplayTxt.borderSize = 1.25;
                botplayTxt.borderStyle = FlxTextBorderStyle.OUTLINE;
                botplayTxt.visible = cpuControlled;
                botplayTxt.antialiasing = ClientPrefs.data.antialiasing;
                uiGroup.add(botplayTxt);

                if (ClientPrefs.data.randomText && FlxG.random.bool(ClientPrefs.data.randomChance * 100) && !ffmpegMode){
                        botplayTxt.text = FlxG.random.getObject(freeBotplayTxt);
                }

                uiGroup.cameras = [camHUD];
                notesGroup.cameras = [camHUD];
                if (showPopups) {
                        popUpGroup.cameras = [camHUD];
                }

                startingSong = true;

                #if LUA_ALLOWED
                for (notetype in noteTypes)
                        startLuasNamed('custom_notetypes/' + notetype + '.lua');
                for (event in eventsPushed)
                        startLuasNamed('custom_events/' + event + '.lua');
                #end

                #if HSCRIPT_ALLOWED
                for (notetype in noteTypes)
                        startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
                for (event in eventsPushed)
                        startHScriptsNamed('custom_events/' + event + '.hx');
                #end
                noteTypes = null;
                eventsPushed = null;

                if (eventNotes.length > 1)
                {
                        for (event in eventNotes)
                                event.strumTime -= eventEarlyTrigger(event);
                        eventNotes.sort(sortByTime);
                }

                // SONG SPECIFIC SCRIPTS
                #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
                        #if linux
                        for (file in CoolUtil.sortAlphabetically(NativeFileSystem.readDirectory(folder)))
                        #else
                        for (file in NativeFileSystem.readDirectory(folder))
                        #end
                {
                        #if LUA_ALLOWED
                        if (file.toLowerCase().endsWith('.lua'))
                                new FunkinLua(folder + file);
                        #end

                        #if HSCRIPT_ALLOWED
                        if (file.toLowerCase().endsWith('.hx'))
                                initHScript(folder + file);
                        #end
                }
                #end

                #if TOUCH_CONTROLS_ALLOWED
                addHitbox();
                hitbox.visible = true;
                hitbox.onButtonDown.add(onHintPress);
                hitbox.onButtonUp.add(onHintRelease);
                #end

                startCallback();
                recalculateRating();
                if (cpuControlled) ratingImage = forceSick.name;

                FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
                FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

                // PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
                if (ClientPrefs.data.hitsoundVolume > 0)
                        Paths.sound('hitsound');
                if (!ClientPrefs.data.ghostTapping)
                        for (i in 1...4)
                                Paths.sound('missnote$i');
                Paths.image('alphabet');

                if (PauseSubState.songName != null)
                        Paths.music(PauseSubState.songName);
                else if (Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
                        Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

                resetRPC();

                stagesFunc(function(stage:BaseStage) stage.createPost());

                callOnScripts('onCreatePost');

                var splash:NoteSplash = new NoteSplash();
                grpNoteSplashes.add(splash);
                splash.alpha = 0.000001; // cant make it invisible or it won't allow precaching

                if (enableHoldSplash) {
                        for (i in 0...susplashMap.length) {
                                var holdSplash:SustainSplash = new SustainSplash();
                                holdSplash.alpha = 0.000001;
                                holdSplash.alive = false;
                                holdSplash.exists = false;
                                susplashMap[i] = holdSplash;
                        }
                }

                #if (TOUCH_CONTROLS_ALLOWED)
                addTouchPad('NONE', 'P');
                addTouchPadCamera();
                #end

                super.create();

                sortingWay = OptimizeSettingsSubState.SORT_PATTERN.indexOf(sortNotes);

                cacheCountdown();
                cachePopUpScore();

                if (eventNotes.length < 1)
                        checkEventNote();

                columns = showInfoType == "Debug Info" ? 7 : 2;

                changeInfo = switch (showInfoType) {
                        case "Debug Info", "Song Info": true;
                        default: false;
                }

                if (showInfoType == "Music Sync Info") {
                        var barCnt:Int = 1 + toInt(bfVocal) + toInt(opVocal);
                        
                        var colorArray:Array<Int> = [
                                0xffffffff, // Inst
                                boyfriend != null ? 0xff000000 | boyfriend.healthColorArray[0] << 16 | boyfriend.healthColorArray[1] << 8 | boyfriend.healthColorArray[2] : 0xff2080f0, // Bf
                                      dad != null ? 0xff000000 |       dad.healthColorArray[0] << 16 |       dad.healthColorArray[1] << 8 |       dad.healthColorArray[2] : 0xff9040b0 // Dad
                        ];

                        for (index in 0...barCnt) {
                                var bar = new FlxBar(
                                        0, 0,
                                        FlxBarFillDirection.LEFT_TO_RIGHT,
                                        Std.int(FlxG.width / 4), 24,
                                        null, 'Sync $index',
                                        -thresholdTime, thresholdTime
                                ).createFilledBar(
                                        FlxColor.fromInt(0x7f7f7f7f),
                                        FlxColor.fromInt(colorArray[index]),
                                        true, 0x7f000000, 4
                                );
                                bar.numDivisions = 1000;
                                bar.screenCenter(XY);
                                bar.y += 216 + (index - barCnt + 1) * 32;
                                desyncMusicBar.push(bar);
                                uiGroup.add(bar);
                        }
                }

                skipNoteSplash.active = false;
                skipNoteSplash.alpha = 0.00001;
                currSus.resize((Main.mania + 1) * 2); prevSus.resize((Main.mania + 1) * 2);

                if (limitNotes == 0) limitNotes = 2147483647;

                var diff = ClientPrefs.data.noteOffset;
                if (Conductor.songPosition - diff < startOnTime && startOnTime > 0) {
                        var left:Int = 0;
                        var right:Int = unspawnNotes.length;
                        var middle:Int = Std.int((left + right) / 2);
                        while (left < right) {
                                if (unspawnNotes[middle].strumTime - diff == startOnTime) break;
                                else {
                                        if (unspawnNotes[middle].strumTime - diff < startOnTime) {
                                                left = middle + 1;
                                        } else right = middle - 1;
                                        middle = Std.int((left + right) / 2);
                                }
                        };
                        currentId = middle;
                        trace('next index is ${numberDelimit ? formatD(currentId) : Std.string(currentId)}');
                }

                #if desktop
                if (ffmpegMode) {
                        FlxG.fixedTimestep = true;
                        FlxG.timeScale = ClientPrefs.data.framerate / targetFPS;
                        if (unlockFPS) {
                                FlxG.timeScale = 1000 / targetFPS;
                                FlxG.updateFramerate = 1000;
                                FlxG.drawFramerate = 1000;
                        }
                        // Cap catch-up so slow readPixels/ffmpeg I/O cannot advance multiple frames per tick.
                        FlxG.maxElapsed = 1.0 / targetFPS;
                        keepNotes = true;

                        if (ClientPrefs.data.vsync) FlxG.stage.application.window.vsync = false;

                        video.init();
                        video.setup();
                        previewRender = ClientPrefs.data.previewRender;
                }
                else if (uncappedFPS) {
                        FlxG.updateFramerate = 1000;
                        FlxG.drawFramerate = 1000;
                }
                #end

                if (ClientPrefs.data.disableGC) {
                        MemoryUtil.enable();
                        MemoryUtil.collect(true);
                        MemoryUtil.disable();
                }

                // --- AndreJr HUD Init ---
                andreHUDEnabled = ClientPrefs.data.useAndreHUD;
                // Calculate actual total notes for density display
                andreActualTotalNotes = 0;
                andreNoteTimes = [];
                andreOppTimes = [];
                andrePlayerTimes = [];
                if (SONG != null && SONG.notes != null) {
                        for (section in SONG.notes) {
                                if (section != null && section.sectionNotes != null) {
                                        var mustHit = section.mustHitSection;
                                        for (noteData in section.sectionNotes) {
                                                andreActualTotalNotes++;
                                                var t = noteData[0];
                                                andreNoteTimes.push(t);
                                                // simple side detection
                                                if (mustHit) andrePlayerTimes.push(t);
                                                else andreOppTimes.push(t);
                                        }
                                }
                        }
                }
                // sort just in case
                andreNoteTimes.sort(function(a,b) return a < b ? -1 : 1);
                andreOppTimes.sort(function(a,b) return a < b ? -1 : 1);
                andrePlayerTimes.sort(function(a,b) return a < b ? -1 : 1);
                if (andreHUDEnabled) {
                        // Hide default UI
                        if (healthBar != null) healthBar.visible = false;
                        if (iconP1 != null) iconP1.visible = false;
                        if (iconP2 != null) iconP2.visible = false;
                        if (scoreTxt != null) scoreTxt.visible = false;
                        if (timeBar != null) timeBar.visible = false;
                        if (timeTxt != null) timeTxt.visible = false;
                        if (botplayTxt != null) botplayTxt.visible = false;

                        var TEXT_SIZE = 28;
                        var NPS_SIZE = 22;
                        var TIME_SIZE = 20;
                        var PADDING_X = 20;
                        var PADDING_Y = 10;
                        var BOX_ALPHA = 0.5;

                        // counter (botplay)
                        andreCounterBox = new FlxSprite(0, 20).makeGraphic(10, 10, FlxColor.BLACK);
                        andreCounterBox.alpha = BOX_ALPHA;
                        andreCounterBox.cameras = [camOther];
                        andreCounterBox.scrollFactor.set();
                        add(andreCounterBox);

                        andreCounterText = new FlxText(0, 30, 0, "", TEXT_SIZE);
                        andreCounterText.setFormat(Paths.font("vcr.ttf"), TEXT_SIZE, FlxColor.WHITE, CENTER);
                        andreCounterText.borderSize = 1;
                        andreCounterText.borderColor = FlxColor.BLACK;
                        andreCounterText.borderStyle = FlxTextBorderStyle.OUTLINE;
                        andreCounterText.cameras = [camOther];
                        andreCounterText.scrollFactor.set();
                        add(andreCounterText);

                        // opp NPS left
                        andreOppBox = new FlxSprite(10, FlxG.height - 45).makeGraphic(10, 10, FlxColor.BLACK);
                        andreOppBox.alpha = BOX_ALPHA;
                        andreOppBox.cameras = [camOther];
                        andreOppBox.scrollFactor.set();
                        add(andreOppBox);

                        andreOppNpsText = new FlxText(20, FlxG.height - 40, 0, "", NPS_SIZE);
                        andreOppNpsText.setFormat(Paths.font("vcr.ttf"), NPS_SIZE, FlxColor.WHITE, LEFT);
                        andreOppNpsText.borderSize = 1;
                        andreOppNpsText.borderColor = FlxColor.BLACK;
                        andreOppNpsText.borderStyle = FlxTextBorderStyle.OUTLINE;
                        andreOppNpsText.cameras = [camOther];
                        andreOppNpsText.scrollFactor.set();
                        add(andreOppNpsText);

                        // player NPS right
                        andrePlayerBox = new FlxSprite(0, FlxG.height - 45).makeGraphic(10, 10, FlxColor.BLACK);
                        andrePlayerBox.alpha = BOX_ALPHA;
                        andrePlayerBox.cameras = [camOther];
                        andrePlayerBox.scrollFactor.set();
                        add(andrePlayerBox);

                        andrePlayerNpsText = new FlxText(0, FlxG.height - 40, 0, "", NPS_SIZE);
                        andrePlayerNpsText.setFormat(Paths.font("vcr.ttf"), NPS_SIZE, FlxColor.WHITE, RIGHT);
                        andrePlayerNpsText.borderSize = 1;
                        andrePlayerNpsText.borderColor = FlxColor.BLACK;
                        andrePlayerNpsText.borderStyle = FlxTextBorderStyle.OUTLINE;
                        andrePlayerNpsText.cameras = [camOther];
                        andrePlayerNpsText.scrollFactor.set();
                        add(andrePlayerNpsText);

                        // top time
                        andreTopTimeBox = new FlxSprite(0, 20).makeGraphic(10, 10, FlxColor.BLACK);
                        andreTopTimeBox.alpha = BOX_ALPHA;
                        andreTopTimeBox.cameras = [camOther];
                        andreTopTimeBox.scrollFactor.set();
                        add(andreTopTimeBox);

                        andreTopTimeText = new FlxText(0, 30, 0, "", TIME_SIZE);
                        andreTopTimeText.setFormat(Paths.font("vcr.ttf"), TIME_SIZE, FlxColor.WHITE, CENTER);
                        andreTopTimeText.borderSize = 1;
                        andreTopTimeText.borderColor = FlxColor.BLACK;
                        andreTopTimeText.borderStyle = FlxTextBorderStyle.OUTLINE;
                        andreTopTimeText.cameras = [camOther];
                        andreTopTimeText.scrollFactor.set();
                        add(andreTopTimeText);

                        // stats bottom
                        andreStatsBox = new FlxSprite(0, FlxG.height - 45).makeGraphic(10, 10, FlxColor.BLACK);
                        andreStatsBox.alpha = BOX_ALPHA;
                        andreStatsBox.cameras = [camOther];
                        andreStatsBox.scrollFactor.set();
                        add(andreStatsBox);

                        andreStatsText = new FlxText(0, FlxG.height - 40, FlxG.width, "", TEXT_SIZE);
                        andreStatsText.setFormat(Paths.font("vcr.ttf"), TEXT_SIZE, FlxColor.WHITE, CENTER);
                        andreStatsText.borderSize = 1;
                        andreStatsText.borderColor = FlxColor.BLACK;
                        andreStatsText.borderStyle = FlxTextBorderStyle.OUTLINE;
                        andreStatsText.cameras = [camOther];
                        andreStatsText.scrollFactor.set();
                        add(andreStatsText);
                        andreVisibleTotalNotes = andreActualTotalNotes - ghostNotesCaught;
                        if (andreVisibleTotalNotes < 1) andreVisibleTotalNotes = 1;
                }

                // --- Andre New HUD Init ---
                andreNewHUDEnabled = ClientPrefs.data.useAndreHUDNew;
                if (andreNewHUDEnabled) {
                        andreNewBoxBgs = [];
                        andreNewBoxLines = [];
                        andreNewBoxTexts = [];
                        andreNewBoxBrackets = [];
                        andreNewBoxWidths = [];
                        andreNewBoxXs = [];
                        
                        var BOX_HEIGHT = 35;
                        var BOX_ALPHA = 0.6;
                        var FONT_SIZE = 16;
                        var TOP_Y = 10;
                        var BRACKET_SIZE = 8;
                        var THICKNESS = 2;
                        var MAX_WIDTH = 500;
                        var labels = ["0 / 0", "0 / 0 / 0", "0 / 0"];
                        var bracketSizes = [BRACKET_SIZE, THICKNESS, BRACKET_SIZE, THICKNESS, BRACKET_SIZE, THICKNESS, BRACKET_SIZE, THICKNESS];
                        var bracketHeights = [THICKNESS, BRACKET_SIZE, THICKNESS, BRACKET_SIZE, THICKNESS, BRACKET_SIZE, THICKNESS, BRACKET_SIZE];
                        
                        for (i in 0...3) {
                                var bg = new FlxSprite(0, TOP_Y).makeGraphic(MAX_WIDTH, BOX_HEIGHT, FlxColor.BLACK);
                                bg.alpha = BOX_ALPHA;
                                bg.cameras = [camOther];
                                bg.scrollFactor.set();
                                add(bg);
                                andreNewBoxBgs.push(bg);
                                
                                var line = new FlxSprite(0, TOP_Y + BOX_HEIGHT - 8).makeGraphic(MAX_WIDTH, 2, FlxColor.WHITE);
                                line.cameras = [camOther];
                                line.scrollFactor.set();
                                add(line);
                                andreNewBoxLines.push(line);
                                
                                var brackets:Array<FlxSprite> = [];
                                for (j in 0...8) {
                                        var b = new FlxSprite(0, 0).makeGraphic(bracketSizes[j], bracketHeights[j], FlxColor.WHITE);
                                        b.cameras = [camOther];
                                        b.scrollFactor.set();
                                        add(b);
                                        brackets.push(b);
                                }
                                andreNewBoxBrackets.push(brackets);
                                
                                var text = new FlxText(0, TOP_Y + 5, 0, labels[i], FONT_SIZE);
                                text.setFormat(Paths.font("vcr.ttf"), FONT_SIZE, FlxColor.WHITE, CENTER);
                                text.borderSize = 1;
                                text.borderColor = FlxColor.BLACK;
                                text.borderStyle = FlxTextBorderStyle.OUTLINE;
                                text.cameras = [camOther];
                                text.scrollFactor.set();
                                add(text);
                                andreNewBoxTexts.push(text);
                                
                                andreNewBoxWidths.push(0);
                                andreNewBoxXs.push(0);
                        }

                        // Ghost density starts by clearing the history so the first 1s window doesn't start at 0.
                        andreNpsHistory = [];
                        andreNewMaxOppNPS = 0;
                        andreNewMaxPlayerNPS = 0;
                        andreNewComboOpp = andreNewComboPlayer = andreNewComboTotal = 0;
                }

                // --- Andre HUD (Lua Port) Init ---
                andreLuaHUDEnabled = ClientPrefs.data.useAndreHUDLua;
                if (andreLuaHUDEnabled) {
                        if (healthBar != null) healthBar.visible = false;
                        if (iconP1 != null) iconP1.visible = false;
                        if (iconP2 != null) iconP2.visible = false;
                        if (scoreTxt != null) scoreTxt.visible = false;
                        if (timeBar != null) timeBar.visible = false;
                        if (timeTxt != null) timeTxt.visible = false;
                        if (botplayTxt != null) botplayTxt.visible = false;

                        var LUABOX_HEIGHT = 35;
                        var LUABOX_ALPHA = 0.75;
                        var LUAFONT_SIZE = 16;
                        var LUABOX_Y = 10;
                        var LUABRACKET_SIZE = 8;
                        var LUATHICKNESS = 2;
                        var LUAMAX_WIDTH = 500;
                        var luaTags = ["boxLeft", "boxMidLeft", "boxMiddle", "boxMidRight", "boxRight"];

                        for (i in 0...5) {
                                var bg = new FlxSprite(0, LUABOX_Y).makeGraphic(LUAMAX_WIDTH, LUABOX_HEIGHT, FlxColor.WHITE);
                                bg.alpha = LUABOX_ALPHA;
                                bg.cameras = [camOther];
                                bg.scrollFactor.set();
                                add(bg);
                                andreLuaBoxBgs.push(bg);

                                var line = new FlxSprite(0, LUABOX_Y + LUABOX_HEIGHT - 8).makeGraphic(LUAMAX_WIDTH, 2, FlxColor.WHITE);
                                line.cameras = [camOther];
                                line.scrollFactor.set();
                                add(line);
                                andreLuaBoxLines.push(line);

                                var brackets:Array<FlxSprite> = [];
                                for (j in 0...8) {
                                        var b:FlxSprite = new FlxSprite(0, 0).makeGraphic((j % 2 == 0) ? LUABRACKET_SIZE : LUATHICKNESS, (j % 2 == 0) ? LUATHICKNESS : LUABRACKET_SIZE, FlxColor.WHITE);
                                        b.cameras = [camOther];
                                        b.scrollFactor.set();
                                        add(b);
                                        brackets.push(b);
                                }
                                andreLuaBoxBrackets.push(brackets);

                                var text = new FlxText(0, LUABOX_Y + 5, 0, (i == 0 || i == 4) ? "0 / 0" : "0", LUAFONT_SIZE);
                                text.setFormat(Paths.font("vcr.ttf"), LUAFONT_SIZE, FlxColor.WHITE, CENTER);
                                text.borderSize = 1;
                                text.borderColor = FlxColor.BLACK;
                                text.borderStyle = FlxTextBorderStyle.OUTLINE;
                                text.cameras = [camOther];
                                text.scrollFactor.set();
                                add(text);
                                andreLuaBoxTexts.push(text);

                                andreLuaBoxWidths.push(0);
                                andreLuaBoxXs.push(0);
                        }
                        andreLuaComboOpp = andreLuaComboPlayer = andreLuaComboTotal = 0;
                        andreLuaMaxOppNPS = andreLuaMaxPlayerNPS = 0;
                }
        }

        function set_songSpeed(value:Float):Float
        {
                if (generatedMusic)
                {
                        var ratio:Float = value / songSpeed; // funny word huh
                        if (ratio != 1)
                        {
                                for (note in notes.members)
                                        if (note.exists && note.visible) note.resizeByRatio(ratio);
                        }
                }
                songSpeed = value;
                noteKillOffset = Math.max(Conductor.stepCrochet, NoteKillTime / songSpeed);
                return value;
        }

        function set_playbackRate(value:Float):Float
        {
                #if FLX_PITCH
                if (generatedMusic)
                {
                        if (bfVocal) vocals.pitch = value;
                        if (opVocal) opponentVocals.pitch = value;
                        FlxG.sound.music.pitch = value;

                        var ratio:Float = playbackRate / value; // funny word huh
                        if (ratio != 1)
                        {
                                for (note in notes.members)
                                        note.resizeByRatio(ratio);
                        }
                }
                playbackRate = value;
                FlxG.animationTimeScale = 1 / value;
                Conductor.offset = Reflect.hasField(PlayState.SONG, 'offset') ? (PlayState.SONG.offset / value) : 0;
                Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
                #if VIDEOS_ALLOWED
                if(videoCutscene != null && videoCutscene.videoSprite != null) videoCutscene.videoSprite.bitmap.rate = value;
                #end
                setOnScripts('playbackRate', playbackRate);
                #else
                playbackRate = 1.0; // ensuring -Crow
                #end
                return playbackRate;
        }

        #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
        public function addTextToDebug(text:String, color:FlxColor)
        {
                var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
                newText.text = text;
                newText.color = color;
                newText.disableTime = 6;
                newText.alpha = 1;
                newText.setPosition(10, 8 - newText.height);

                luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText)
                {
                        spr.y += newText.height + 2;
                });
                luaDebugGroup.add(newText);

                trace(text);
        }
        #end

        public function reloadHealthBarColors() {
                if(ClientPrefs.data.vsliceLegacyBar) healthBar.setColors(FlxColor.RED,FlxColor.LIME);
                else healthBar.setColors(
                        FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
                        FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2])
                );
        }

        public function addCharacterToList(newCharacter:String, type:Int)
        {
                switch (type)
                {
                        case 0:
                                if (!boyfriendMap.exists(newCharacter))
                                {
                                        var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
                                        boyfriendMap.set(newCharacter, newBoyfriend);
                                        boyfriendGroup.add(newBoyfriend);
                                        startCharacterPos(newBoyfriend);
                                        newBoyfriend.alpha = 0.00001;
                                        startCharacterScripts(newBoyfriend.curCharacter);
                                }

                        case 1:
                                if (!dadMap.exists(newCharacter))
                                {
                                        var newDad:Character = new Character(0, 0, newCharacter);
                                        dadMap.set(newCharacter, newDad);
                                        dadGroup.add(newDad);
                                        startCharacterPos(newDad, true);
                                        newDad.alpha = 0.00001;
                                        startCharacterScripts(newDad.curCharacter);
                                }

                        case 2:
                                if (gf != null && !gfMap.exists(newCharacter))
                                {
                                        var newGf:Character = new Character(0, 0, newCharacter);
                                        newGf.scrollFactor.set(1, 1);
                                        gfMap.set(newCharacter, newGf);
                                        gfGroup.add(newGf);
                                        startCharacterPos(newGf);
                                        newGf.alpha = 0.00001;
                                        startCharacterScripts(newGf.curCharacter);
                                }
                }
        }

        function startCharacterScripts(name:String)
        {
                // Lua
                #if LUA_ALLOWED
                var doPush:Bool = false;
                var luaFile:String = 'characters/$name.lua';
                #if MODS_ALLOWED
                var replacePath:String = Paths.modFolders(luaFile);
                if(NativeFileSystem.exists(replacePath))
                {
                        luaFile = replacePath;
                        doPush = true;
                }
                else
                {
                        luaFile = Paths.getSharedPath(luaFile);
                        if(NativeFileSystem.exists(luaFile))
                                doPush = true;
                }
                #else
                luaFile = Paths.getSharedPath(luaFile);
                if (Assets.exists(luaFile))
                        doPush = true;
                #end

                if (doPush)
                {
                        for (script in luaArray)
                        {
                                if (script.scriptName == luaFile)
                                {
                                        doPush = false;
                                        break;
                                }
                        }
                        if (doPush)
                                new FunkinLua(luaFile);
                }
                #end

                // HScript
                #if HSCRIPT_ALLOWED
                var doPush:Bool = false;
                var scriptFile:String = 'characters/' + name + '.hx';
                #if MODS_ALLOWED
                var replacePath:String = Paths.modFolders(scriptFile);
                if(NativeFileSystem.exists(replacePath))
                {
                        scriptFile = replacePath;
                        doPush = true;
                }
                else
                #end
                {
                        scriptFile = Paths.getSharedPath(scriptFile);
                        if(NativeFileSystem.exists(scriptFile))
                                doPush = true;
                }

                if (doPush)
                {
                        if (Iris.instances.exists(scriptFile))
                                doPush = false;

                        if (doPush)
                                initHScript(scriptFile);
                }
                #end
        }

        public function getLuaObject(tag:String, text:Bool = true):FlxSprite
                return variables.get(tag);

        function startCharacterPos(char:Character, ?gfCheck:Bool = false)
        {
                if (gfCheck && char.curCharacter.startsWith('gf'))
                { // IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
                        char.setPosition(GF_X, GF_Y);
                        char.scrollFactor.set(1, 1);
                        char.danceEveryNumBeats = 2;
                }
                char.x += char.positionArray[0];
                char.y += char.positionArray[1];
        }

        public var videoCutscene:VideoSprite = null;

        public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true)
        {
                #if VIDEOS_ALLOWED
                inCutscene = !forMidSong;
                canPause = forMidSong;

                var foundFile:Bool = false;
                var fileName:String = Paths.video(name);

                #if sys
                if (NativeFileSystem.exists(fileName))
                #else
                if (OpenFlAssets.exists(fileName))
                #end
                foundFile = true;

                if (foundFile)
                {
                        videoCutscene = new VideoSprite(fileName, forMidSong, canSkip, loop);
                        if (forMidSong) videoCutscene.videoSprite.bitmap.rate = playbackRate;
                        else // Finish callback
                        {
                                function onVideoEnd()
                                {
                                        if (!isDead && generatedMusic && PlayState.SONG.notes[Std.int(curStep / 16)] != null && !endingSong && !isCameraOnForcedPos)
                                        {
                                                moveCameraSection();
                                                FlxG.camera.snapToTarget();
                                        }
                                        videoCutscene = null;
                                        canPause = true;
                                        inCutscene = false;
                                        startAndEnd();
                                }
                                videoCutscene.finishCallback = onVideoEnd;
                                videoCutscene.onSkip = onVideoEnd;
                        }
                        if (GameOverSubstate.instance != null && isDead) GameOverSubstate.instance.add(videoCutscene);
                        else add(videoCutscene);

                        if (playOnLoad)
                                videoCutscene.play();
                        return videoCutscene;
                }
                #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                else
                        addTextToDebug("Video not found: " + fileName, FlxColor.RED);
                #else
                else
                        FlxG.log.error("Video not found: " + fileName);
                #end
                #else
                FlxG.log.warn('Platform not supported!');
                startAndEnd();
                #end
                return null;
        }

        function startAndEnd()
        {
                if (endingSong)
                        endSong();
                else
                        startCountdown();
        }

        var dialogueCount:Int = 0;

        public var psychDialogue:DialogueBoxPsych;

        // You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
        public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
        {
                // TO DO: Make this more flexible, maybe?
                if (psychDialogue != null)
                        return;

                if (dialogueFile.dialogue.length > 0)
                {
                        inCutscene = true;
                        psychDialogue = new DialogueBoxPsych(dialogueFile, song);//TODO
                        psychDialogue.scrollFactor.set();
                        if (endingSong)
                        {
                                psychDialogue.finishThing = function()
                                {
                                        psychDialogue = null;
                                        endSong();
                                }
                        }
                        else
                        {
                                psychDialogue.finishThing = function()
                                {
                                        psychDialogue = null;
                                        startCountdown();
                                }
                        }
                        psychDialogue.nextDialogueThing = startNextDialogue;
                        psychDialogue.skipDialogueThing = skipDialogue;
                        psychDialogue.cameras = [camHUD];
                        add(psychDialogue);
                }
                else
                {
                        FlxG.log.warn('Your dialogue file is badly formatted!');
                        startAndEnd();
                }
        }

        // For being able to mess with the sprites on Lua
        public var countdownReady:FlxSprite;
        public var countdownSet:FlxSprite;
        public var countdownGo:FlxSprite;

        public static var startOnTime:Float = 0;

        function cacheCountdown()
        {
                var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
                var introImagesArray:Array<String> = switch (stageUI)
                {
                        case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
                        case "normal": ["ready", "set", "go"];
                        default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
                }
                introAssets.set(stageUI, introImagesArray);
                var introAlts:Array<String> = introAssets.get(stageUI);
                for (asset in introAlts)
                        Paths.image(asset);

                Paths.sound('intro3' + introSoundsSuffix);
                Paths.sound('intro2' + introSoundsSuffix);
                Paths.sound('intro1' + introSoundsSuffix);
                Paths.sound('introGo' + introSoundsSuffix);
        }

        var startTimer:FlxTimer = null;
        var finishTimer:FlxTimer = null;

        public function startCountdown()
        {
                if (startedCountdown)
                {
                        callOnScripts('onStartCountdown');
                        return false;
                }

                seenCutscene = true;
                inCutscene = false;
                var ret = callOnScripts('onStartCountdown', null, true);
                if (ret != LuaUtils.Function_Stop)
                {
                        if (skipCountdown || startOnTime > 0)
                                skipArrowStartTween = true;

                        canPause = true;
                        generateStaticArrows(0);
                        generateStaticArrows(1);
                        
                        for (i in 0...playerStrums.length) {
                                setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
                                setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
                        }
                        for (i in 0...opponentStrums.length) {
                                setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
                                setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
                        }

                        startedCountdown = true;
                        Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
                        botplaySine = Conductor.songPosition * 0.18;
                        setOnScripts('startedCountdown', true);
                        callOnScripts('onCountdownStarted');

                        var swagCounter:Int = 0;
                        if (startOnTime > 0)
                        {
                                setSongTime(startOnTime - noteKillOffset);
                                return true;
                        }
                        else if (skipCountdown)
                        {
                                setSongTime(0);
                                return true;
                        }
                        moveCameraSection();

                        for (i in 0...5)
                        {
                                startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate * (i+1), tmr -> 
                                {
                                        characterBopper(i);

                                        var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
                                        var introImagesArray:Array<String> = switch (stageUI)
                                        {
                                                case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
                                                case "normal": ["ready", "set", "go"];
                                                default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
                                        }
                                        introAssets.set(stageUI, introImagesArray);

                                        var introAlts:Array<String> = introAssets.get(stageUI);
                                        var tick:Countdown = THREE;
                                        var countVoice:FlxSound = null;

                                        switch (i)
                                        {
                                                case 0:
                                                        countVoice = FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6 * ClientPrefs.data.sfxVolume);
                                                        tick = THREE;
                                                case 1:
                                                        countdownReady = createCountdownSprite(introAlts[0], antialias);
                                                        countVoice = FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6 * ClientPrefs.data.sfxVolume);
                                                        tick = TWO;
                                                case 2:
                                                        countdownSet = createCountdownSprite(introAlts[1], antialias);
                                                        countVoice = FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6 * ClientPrefs.data.sfxVolume);
                                                        tick = ONE;
                                                case 3:
                                                        countdownGo = createCountdownSprite(introAlts[2], antialias);
                                                        countVoice = FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6 * ClientPrefs.data.sfxVolume);
                                                        tick = GO;
                                                case 4:
                                                        tick = START;
                                                        FlxG.maxElapsed = nanoPosition ? 1000000 : (ffmpegMode ? (1.0 / targetFPS) : 0.1);
                                        }

                                        #if FLX_PITCH if (countVoice != null) countVoice.pitch = playbackRate; #end

                                        if (!skipArrowStartTween)
                                        {
                                                notes.forEachAlive( note ->
                                                {
                                                        if (ClientPrefs.data.opponentStrums || note.mustPress)
                                                        {
                                                                note.copyAlpha = false;
                                                                note.alpha = note.multAlpha;
                                                                if (ClientPrefs.data.middleScroll && !note.mustPress)
                                                                        note.alpha *= 0.35;
                                                        }
                                                });
                                        }

                                        stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, i));
                                        callOnLuas('onCountdownTick', [i]);
                                        callOnHScript('onCountdownTick', [tick, i]);
                                });
                        }
                }
                return true;
        }

        inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
        {
                var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
                spr.cameras = [camHUD];
                spr.scrollFactor.set();
                spr.updateHitbox();

                if (PlayState.isPixelStage)
                        spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

                spr.screenCenter();
                spr.antialiasing = antialias;
                insert(members.indexOf(notesGroup), spr);
                FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000 / playbackRate, {
                        ease: FlxEase.cubeInOut,
                        onComplete: function(twn:FlxTween)
                        {
                                remove(spr);
                                spr.destroy();
                        }
                });
                return spr;
        }

        public function addBehindGF(obj:FlxBasic)
        {
                insert(members.indexOf(gfGroup), obj);
        }

        public function addBehindBF(obj:FlxBasic)
        {
                insert(members.indexOf(boyfriendGroup), obj);
        }

        public function addBehindDad(obj:FlxBasic)
        {
                insert(members.indexOf(dadGroup), obj);
        }

        public function clearNotesBefore(time:Float)
        {
                var i:Int = unspawnNotes.length - 1;
                var daCastNote:CastNote = unspawnNotes[i];
                while (daCastNote.strumTime - noteKillOffset < time)
                {
                        daCastNote = unspawnNotes[i--];
                }

                i = notes.length - 1;
                var daNote:Note = notes.members[i];
                while (daNote.strumTime - noteKillOffset < time)
                {
                        daNote.active = false;
                        daNote.visible = false;
                        daNote.ignoreNote = true;
                        invalidateNote(daNote);
                        daNote = notes.members[i--];
                }
        }

        // fun fact: Dynamic Functions can be overriden by just doing this
        // `updateScore = function(miss:Bool = false) { ... }
        // its like if it was a variable but its just a function!
        // cool right? -Crow
        public dynamic function updateScore(miss:Bool = false, scoreBop:Bool = true)
        {
                if(ClientPrefs.data.vsliceLegacyBar) scoreBop = false;
                var ret = callOnScripts('preUpdateScore', [miss], true);
                if (ret == LuaUtils.Function_Stop)
                        return;

                updateScoreText();
                if (!miss && !cpuControlled && scoreBop)
                        doScoreBop();

                callOnScripts('onUpdateScore', [miss]);
        }

        var targetHealth:Float;
        var updateScoreStr:String;
        var hpShowStr:String;
        var tempScoreStr:String;
        var opComboStr:String;
        var comboStr:String;
        var notesStr:String;
        var hpPrecision:Int;
        public dynamic function updateScoreText()
        {
                targetHealth = health * 50;
                if (!practiceMode) {
                        updateScoreStr = Language.getPhrase('rating_$ratingName', ratingName);
                        if (totalPlayed != 0)
                                updateScoreStr += ' (${CoolUtil.floorDecimal(ratingPercent * 100, 3)} %) - ${Language.getPhrase(ratingFC)}';
                }
                
                if (practiceMode) hpShowStr = '${numberDelimit ? formatD(targetHealth) : Std.string(targetHealth)} %';
                else {
                        hpPrecision = 4 - Std.string(Math.floor(targetHealth)).length;
                        if (hpPrecision > 0) {
                                hpShowStr = '${numberDelimit ? numFormat(targetHealth, hpPrecision, true) : Std.string(targetHealth)} ${targetHealth >= 0.001 ? '%' : ''}';
                        } else {
                                hpShowStr = '${numberDelimit ? formatD(targetHealth, hpPrecision, true) : Std.string(targetHealth)} %';
                        }
                }

                if (!cpuControlled) {
                        if (!instakillOnMiss && !instacrashOnMiss) {
                                if (!practiceMode) {
                                        tempScoreStr = Language.getPhrase(
                                                'score_text',
                                                'Score: {1} | Misses: {2} | Rating: {3} | HP: {4}',
                                                [songScore, songMisses, updateScoreStr, hpShowStr]
                                        );
                                } else {
                                        tempScoreStr = Language.getPhrase(
                                                'score_text',
                                                'Score: {1} | Misses: {2} | Practice Mode | HP: {3}',
                                                [songScore, songMisses, hpShowStr]
                                        );
                                }
                        } else
                                tempScoreStr = Language.getPhrase(
                                        'score_text_instakill',
                                        'Score: {1} | Instant ${instacrashOnMiss ? "Crash" : "Kill"} Mode - Good Luck! | Rating: {2}',
                                        [songScore, updateScoreStr]
                                );
                } else {
                        
                        if (numberDelimit) {
                                opComboStr = formatD(opCombo);
                                comboStr = formatD(combo);
                                notesStr = formatD(opCombo + combo);
                        } else {
                                opComboStr = Std.string(opCombo);
                                comboStr = Std.string(combo);
                                notesStr = Std.string(opCombo + combo);
                        }

                        tempScoreStr = Language.getPhrase(
                                'score_text_bot',
                                '{2} + {3} = {4}',
                                [ songScore, opComboStr, comboStr, notesStr ]
                        );
                        
                }
                scoreTxt.text = tempScoreStr;
                var scoreWidth:Int = Std.int(Math.max(180, scoreTxt.text.length * 12 + 24));
                scoreTxt.fieldWidth = scoreWidth;
                scoreTxt.screenCenter(X);
                scoreTxt.y = healthBar.y + 30;
        }

        public dynamic function fullComboFunction()
        {
                ratingFC = "";
                if (songMisses == 0)
                {
                        if (ratingsData[2].hits > 0 || ratingsData[3].hits > 0)
                                ratingFC = 'FC';
                        else if (ratingsData[1].hits > 0)
                                ratingFC = 'GFC';
                        else if (ratingsData[0].hits > 0)
                                ratingFC = 'SFC';
                }
                else
                {
                        if (songMisses < 10)
                                ratingFC = 'SDCB';
                        else
                                ratingFC = 'Clear';
                }
        }

        public function doScoreBop():Void
        {
                if (!ClientPrefs.data.scoreZoom)
                        return;

                if (scoreTxtTween != null)
                        scoreTxtTween.cancel();

                scoreTxt.scale.x = 1.075;
                scoreTxt.scale.y = 1.075;
                scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
                        onComplete: function(twn:FlxTween)
                        {
                                scoreTxtTween = null;
                        }
                });
        }

        public function setSongTime(time:Float)
        {
                if (!ffmpegMode) {
                        FlxG.sound.music.pause();
                        if (bfVocal) vocals.pause();
                        if (opVocal) opponentVocals.pause();

                        var mute:Bool = ffmpegMode || time > 0;

                        FlxG.sound.music.time = time - Conductor.offset;
                        #if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
                        // trace('songTime sets to $time');
                        FlxG.sound.music.play();
                        FlxG.sound.music.volume = mute ? 0 : ClientPrefs.data.bgmVolume;
                        FlxG.sound.music.onComplete = finishSong.bind();

                        if (bfVocal) {
                                if (Conductor.songPosition < vocals.length)
                                {
                                        vocals.time = time - Conductor.offset;
                                        #if FLX_PITCH vocals.pitch = playbackRate; #end
                                        vocals.play();
                                        vocals.volume = mute ? 0 : ClientPrefs.data.bgmVolume;
                                }
                                else vocals.pause();
                        }

                        if (opVocal) {
                                if (Conductor.songPosition < opponentVocals.length)
                                {
                                        opponentVocals.time = time - Conductor.offset;
                                        #if FLX_PITCH opponentVocals.pitch = playbackRate; #end
                                        opponentVocals.play();
                                        opponentVocals.volume = mute ? 0 : ClientPrefs.data.bgmVolume;
                                }
                                else opponentVocals.pause();
                        }
                }
                Conductor.songPosition = time;
        }

        public function startNextDialogue() {
                @:privateAccess
                dialogueCount = psychDialogue.currentText;
                callOnScripts('onNextDialogue', [dialogueCount]);
                stagesFunc(function(stage:BaseStage) stage.startNextDialogue(dialogueCount));
        }

        public function skipDialogue()
        {
                callOnScripts('onSkipDialogue', [dialogueCount]);
                stagesFunc(stage -> stage.onSkipDialogue(dialogueCount));
        }

        var started:Bool = false;
        var songText:String = "";
        function startSong():Void
        {
                startingSong = false;

                @:privateAccess
                if (!ffmpegMode) {
                        FlxG.sound.playMusic(inst._sound, ClientPrefs.data.bgmVolume, false);
                        #if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
                        FlxG.sound.music.onComplete = finishSong.bind();
                        if (bfVocal) {
                                vocals.play();
                                vocals.volume = ClientPrefs.data.bgmVolume;
                        }
                        if (opVocal) {
                                opponentVocals.play();
                                opponentVocals.volume = ClientPrefs.data.bgmVolume;
                        }
                } else {
                        FlxG.sound.playMusic(inst._sound, 0, false);
                        if (bfVocal) {vocals.play(); vocals.volume = 0;}
                        if (opVocal) {opponentVocals.play(); opponentVocals.volume = 0;}
                }

                if (startOnTime > 0) setSongTime(Math.max(0, startOnTime - 500) + Conductor.offset);
                startOnTime = 0;

                if (paused)
                {
                        // trace('Oopsie doopsie! Paused sound');
                        FlxG.sound.music.pause();
                        if (bfVocal) vocals.pause();
                        if (opVocal) opponentVocals.pause();
                }

                stagesFunc(stage -> stage.startSong());

                // Song duration in a float, useful for the time left feature
                songLength = FlxG.sound.music.length;
                FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
                FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

                #if DISCORD_ALLOWED
                // Updating Discord Rich Presence (with Time Left)
                if (autoUpdateRPC) {
                        songText = '${SONG.song} ($storyDifficultyText)';
                        DiscordClient.changePresence(detailsText, songText, iconP2.getCharacter(), true, songLength);
                }
                #end
                setOnScripts('songLength', songLength);
                callOnScripts('onSongStart');

                started = true;
        }

        private var noteTypes:Array<String> = [];
        private var eventsPushed:Array<String> = [];
        private var totalColumns:Int = 4;
        private var gfSide:Bool = false;

        public var bfVocal:Bool = false; // a.k.a. legacy voices
        public var opVocal:Bool = false;

        var loadTime:Float = CoolUtil.getNanoTime();
        var syncTime:Float = Timer.stamp();
        private function generateSong():Void
        {
                // FlxG.log.add(ChartParser.parse());
                songSpeed = PlayState.SONG.speed;
                songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
                switch (songSpeedType)
                {
                        case "multiplicative", "ignore changes":
                                songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
                        case "constant":
                                songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
                }

                Conductor.bpm = SONG.bpm;
                gfSide = !SONG.isOldVersion;

                curSong = SONG.song;
                bfVocal = opVocal = false;

                vocals = opponentVocals = null;
                try
                {
                        if (SONG.needsVoices)
                        {
                                var legacyVoices = Paths.voices(SONG.song);
                                if (legacyVoices == null)
                                {
                                        var playerVocals = Paths.voices(SONG.song,
                                                (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
                                        if (playerVocals != null && playerVocals.length > 0 && boyfriend != null && boyfriend.alive) {
                                                vocals = new FlxSound().loadEmbedded(playerVocals);
                                                bfVocal = true;
                                        }

                                        var oppVocals = Paths.voices(SONG.song, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
                                        if (oppVocals != null && oppVocals.length > 0 && dad != null && dad.alive) {
                                                opponentVocals = new FlxSound().loadEmbedded(oppVocals);
                                                opVocal = true;
                                        }
                                } else {
                                        vocals = new FlxSound().loadEmbedded(legacyVoices);
                                        bfVocal = vocals != null;
                                }
                        } 
                } catch (e:Dynamic) {}

                #if FLX_PITCH
                if (bfVocal) vocals.pitch = playbackRate;
                if (opVocal) opponentVocals.pitch = playbackRate;
                #end
                if (bfVocal) FlxG.sound.list.add(vocals);
                if (opVocal) FlxG.sound.list.add(opponentVocals);

                inst = new FlxSound(); trace('Alt inst: ${altInstrumentals ?? "None"}');
                try inst.loadEmbedded(Paths.inst(altInstrumentals ?? SONG.song)) catch (e:Dynamic) {}
                FlxG.sound.list.add(inst);

                notes = new NoteGroup();
                skipNotes = new NoteGroup();
                notesGroup.add(notes);

                // IT'S FOR OUTSIDE EVENTS.JSON
                try
                {
                        var eventsChart:SwagSong = Song.getChart('events', songName);
                        if (eventsChart != null)
                                for (event in eventsChart.events) // Event Notes
                                        for (i in 0...event[1].length)
                                                makeEvent(event, i);
                } catch (e:Dynamic) {}

                Note.chartArrowSkin = SONG.arrowSkin;

                if (!loaded) {
                        var sectionsData:Array<SwagSection> = SONG.notes;
                        var daBpm:Float = Conductor.bpm;

                        var secCnt:Int = 0;
                        var cnt:Int = 0;
                        var notes:Int = 0;

                        var sectionNoteCnt:Int = 0;
                        var shownProgress:Bool = false;
                        var sustainNoteCnt:Int = 0;
                        var sustainTotalCnt:Int = 0;

                        var songNotes:Array<Dynamic> = [];
                        var strumTime:Float;
                        var noteColumn:Int;
                        var holdLength:Float;
                        var noteType:String;

                        var gottaHitNote:Bool;

                        var swagNote:CastNote = { strumTime: 0, noteData: 0 };
                        var roundSus:Int;
                        var curStepCrochet:Float;
                        var sustainNote:CastNote;
                        var burst = null;

var chartNoteData:Int = 0;
			var strumTimeVector:Vector<Float> = new Vector(totalColumns * 2, 0.0);
			var lastNoteIndex:Vector<Int> = new Vector(totalColumns * 2, -1);

                        var updateElapse:Float = 0.01;
                        var syncTime:Float = Timer.stamp();
                        var removeTime:Float = ClientPrefs.data.ghostRange;

                        var loadNoteTime:Float = CoolUtil.getNanoTime();

                        Eseq.pln("Allocating castNote array");
                        var totalNoteCnt:Int = 0;
                        
                        for (section in sectionsData)
                        {
                                totalNoteCnt += section.sectionNotes.length;
                        }
                        unspawnNotes.resize(totalNoteCnt);

                        function showProgress(force:Bool = false) {
                                if (Timer.stamp() - syncTime > updateElapse || force)
                                {
                                        if (numberDelimit) 
                                                Eseq.p('Loading ${formatD(secCnt)}/${formatD(sectionsData.length)} (${formatD(notes + sectionNoteCnt)}/${formatD(totalNoteCnt)} notes)');
                                        else
                                                Eseq.p('Loading $secCnt/${sectionsData.length} (${notes + sectionNoteCnt}/$totalNoteCnt notes)');
                                        syncTime = Timer.stamp();
                                }
                        }
                        
                        // Do not declare inside loops. This causes memory leaks.
                        function extractSpamData(note:Array<Dynamic>):Array<Float> {
                                for (slot in [3, 4]) {
                                        var field = note[slot];
                                        if (Std.isOfType(field, Array)) {
                                                return cast field;
                                        } else if (field != null && field.cmpSpam != null) {
                                                var bd = field.cmpSpam;
                                                if (Std.isOfType(bd, Array)) return bd;
                                        }
                                }
                                return null;
                        }

                        for (section in sectionsData)
                        {
                                sectionNoteCnt = 0;
                                shownProgress = false;
                                if (section.changeBPM != null && section.changeBPM && section.bpm != null && daBpm != section.bpm)
                                        daBpm = section.bpm;

                                for (songNotes in section.sectionNotes)
                                {
                                        strumTime = songNotes[0];
                                        chartNoteData = songNotes[1];
                                        noteColumn = Std.int(chartNoteData % totalColumns);
                                        if (noteColumn < 0) noteColumn = 0; // negative data would break strum indexing
                                        gottaHitNote = (chartNoteData < totalColumns);

// CLEAR ANY POSSIBLE GHOST NOTES WHEN IF THE OPTION ENABLED
						if (skipGhostNotes && sectionNoteCnt != 0 && !worldRecordMode) {
								if (Math.abs(strumTimeVector[chartNoteData] - strumTime) <= removeTime) {
										ghostNotesCaught++;
										if (ghostDensity && !worldRecordMode) {
												var lastIdx = lastNoteIndex[chartNoteData];
												if (lastIdx >= 0 && lastIdx < cnt) {
														var lastNote = unspawnNotes[lastIdx];
														if (lastNote.density != null) lastNote.density++;
														else lastNote.density = 2;
												}
										}
										continue;
								} else {
										strumTimeVector[chartNoteData] = strumTime;
								}
						}
                                        
                                        swagNote = {
                                                strumTime: songNotes[0],
                                                noteData: noteColumn
                                        };
                                        if (skipGhostNotes && (swagNote.density == null || swagNote.density > 1)) swagNote.density = 1;

                                        if (Std.isOfType(songNotes[3], String))
                                                swagNote.noteType = songNotes[3];
                                        
                                        if (!worldRecordMode) {
                                                burst = extractSpamData(songNotes);
                                                if (burst != null) swagNote.cmpSpam = burst;
                                        }
                                        
swagNote.noteData |= gottaHitNote ? 1<<8 : 0; // mustHit
						swagNote.noteData |= (section.gfSection && (gfSide ? gottaHitNote : !gottaHitNote)) || songNotes[3] == 'GF Sing' || songNotes[3] == 4 ? 1<<11 : 0; // gfNote
						swagNote.noteData |= (section.altAnim || (songNotes[3] == 'Alt Animation' || songNotes[3] == 1)) ? 1<<12 : 0; // altAnim
						swagNote.noteData |= (songNotes[3] == 'No Animation' || songNotes[3] == 5) ? 1<<13 : 0; // noAnimation & noMissAnimaiton

						unspawnNotes[cnt] = swagNote;
						lastNoteIndex[chartNoteData] = cnt;

						if (songNotes[2] > 0.0)
						{
								swagNote.holdLength = songNotes[2];

								curStepCrochet = 15000 / daBpm;
								roundSus = Math.round(swagNote.holdLength / curStepCrochet);
								if (roundSus > 0)
								{
										for (susNote in 0...roundSus + 1)
										{
												sustainNote = {
														strumTime: swagNote.strumTime + curStepCrochet * susNote,
														noteData: swagNote.noteData,
														noteType: swagNote.noteType
												};
												if (!Math.isNaN(swagNote.density)) sustainNote.density = swagNote.density;

												sustainNote.noteData |= 1<<9; // isHold
												sustainNote.noteData |= susNote == roundSus ? 1<<10 : 0; // isHoldEnd

												unspawnSustainNotes.push(sustainNote);

												++sustainNoteCnt;
										}
										sustainTotalCnt += sustainNoteCnt;
								}
						}

						if (!noteTypes.contains(swagNote.noteType))
								noteTypes.push(swagNote.noteType);

						showProgress();
						++sectionNoteCnt; ++cnt;
                                }
                                notes += sectionNoteCnt;
                                ++secCnt;
                                showProgress();
                        }

                        showProgress(true);

                        Eseq.pln('\n[ --- "${SONG.song.toUpperCase()}" CHART INFO --- ]');
                        
                        var takenTime = CoolUtil.getNanoTime() - loadTime;
                        var takenNoteTime = CoolUtil.getNanoTime() - loadNoteTime;

                        Eseq.pln('Loaded ${numberDelimit ? formatD(notes) : Std.string(notes)} notes!\n' + 
                                        'Sustain notes amount: ${numberDelimit ? formatD(sustainTotalCnt) : Std.string(sustainTotalCnt)}\n' + 
                                        'Taken time: ${numberDelimit ? formatD(takenTime, 6) : Std.string(takenTime)} sec\n' + 
                                        'Average NPS in loading: ${numberDelimit ? formatD(notes / takenNoteTime, 3) : Std.string(notes / takenNoteTime)}'
                        );

                        if (skipGhostNotes) {
                                if (ghostNotesCaught > 0) {
                                        Eseq.pln('Overlapped Notes Cleared: $ghostNotesCaught');
                                        unspawnNotes.resize(notes);
                                }
                                else {
                                        Eseq.pln('WOW! There are no overlapped notes. Great charting!');
                                }
                        }
                
                        Eseq.pln('Merging Notes...');
                        for (usn in unspawnSustainNotes)
                                unspawnNotes.push(usn);
                        
                        unspawnSustainNotes.resize(0);

                        Eseq.pln('Sorting Notes...');
                        ArraySort.sort(unspawnNotes, sortByTime);
                } else {
                        trace("Chart loading has been skipped since unspawnNotes is already in the memory!");
                }

                // IT'S FOR INSIDE EVENTS ON CHART JSON
                for (event in SONG.events) //Event Notes
                        for (i in 0...event[1].length)
                                makeEvent(event, i);

                generatedMusic = loaded = true;
                Eseq.pln('Ready to PLAY!');
        }

        // called only once per different event (Used for precaching)
        function eventPushed(event:EventNote)
        {
                eventPushedUnique(event);
                if (eventsPushed.contains(event.event))
                {
                        return;
                }

                stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
                eventsPushed.push(event.event);
        }

        // called by every event with the same name
        function eventPushedUnique(event:EventNote)
        {
                switch (event.event)
                {
                        case "Change Character":
                                var charType:Int = 0;
                                switch (event.value1.toLowerCase())
                                {
                                        case 'gf' | 'girlfriend' | '1':
                                                charType = 2;
                                        case 'dad' | 'opponent' | '0':
                                                charType = 1;
                                        default:
                                                var val1:Int = Std.parseInt(event.value1);
                                                if (Math.isNaN(val1))
                                                        val1 = 0;
                                                charType = val1;
                                }

                                var newCharacter:String = event.value2;
                                addCharacterToList(newCharacter, charType);

                        case 'Play Sound':
                                Paths.sound(event.value1); // Precache sound
                }
                stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
        }

        function eventEarlyTrigger(event:EventNote):Float
        {
                var ret = Std.parseFloat(callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true));
                if (!Math.isNaN(ret) && ret != 0)
                {
                        return ret;
                }

                switch (event.event)
                {
                        case 'Kill Henchmen': // Better timing so that the kill sound matches the beat intended
                                return 280; // Plays 280ms before the actual position
                }
                return 0;
        }

        public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
                return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

        function makeEvent(event:Array<Dynamic>, i:Int)
        {
                var subEvent:EventNote = {
                        strumTime: event[0] + ClientPrefs.data.noteOffset,
                        event: event[1][i][0],
                        value1: event[1][i][1],
                        value2: event[1][i][2]
                };
                eventNotes.push(subEvent);
                eventPushed(subEvent);
                callOnScripts('onEventPushed', [
                        subEvent.event,
                        subEvent.value1 != null ? subEvent.value1 : '',
                        subEvent.value2 != null ? subEvent.value2 : '',
                        subEvent.strumTime
                ]);
        }

        public var skipArrowStartTween:Bool = false; // for lua

        private function generateStaticArrows(player:Int):Void
        {
                var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
                var strumLineY:Float = downScroll ? (FlxG.height - 150) : 50;
                var chochet:Float = Conductor.crochet;
                for (i in 0...(Main.mania + 1))
                {
                        // FlxG.log.add(i);
                        var targetAlpha:Float = 1;
                        if (player < 1)
                        {
                                if (!ClientPrefs.data.opponentStrums)
                                        targetAlpha = 0;
                                else if (ClientPrefs.data.middleScroll)
                                        targetAlpha = 0.35;
                        }

                        var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
                        babyArrow.downScroll = downScroll;
                        skipArrowStartTween = skipArrowStartTween || chochet <= ClientPrefs.data.framerate * 1000;
                        if (!isStoryMode && !skipArrowStartTween)
                        {
                                babyArrow.y -= 640 / (i+1);
                                babyArrow.alpha = 0;
                                babyArrow.angle = -2 * Math.PI;
                                FlxTween.tween(
                                        babyArrow, 
                                        {
                                                y: babyArrow.y + 640 / (i+1),
                                                alpha: targetAlpha,
                                                angle: 0
                                        },
                                        chochet * (Main.mania + 1 - i),
                                        {
                                                ease: FlxEase.circOut,
                                                startDelay: (chochet * (i+1))
                                        }
                                );
                        }
                        else
                                babyArrow.alpha = targetAlpha;

                        if (player == 1)
                                playerStrums.add(babyArrow);
                        else {
                                if (ClientPrefs.data.middleScroll)
                                {
                                        babyArrow.x += 310;
                                        if (i > Note.midArray[Main.mania])
                                        { // Up and Right
                                                babyArrow.x += FlxG.width / 2 + 25;
                                        }
                                }
                                opponentStrums.add(babyArrow);
                        }

                        strumLineNotes.add(babyArrow);
                        babyArrow.postAddedToGroup();
                }
        }

        override function openSubState(SubState:FlxSubState)
        {
                stagesFunc(stage -> stage.openSubState(SubState));
                if (paused)
                {
                        if (FlxG.sound.music != null)
                        {
                                FlxG.sound.music.pause();
                                if (bfVocal) vocals.pause();
                                if (opVocal) opponentVocals.pause();
                        }
                        FlxTimer.globalManager.forEach(tmr -> if (!tmr.finished) tmr.active = false);
                        FlxTween.globalManager.forEach(twn -> if (!twn.finished) twn.active = false);
                }

                super.openSubState(SubState);
        }

        override function closeSubState()
        {
                super.closeSubState();

                stagesFunc(stage -> stage.closeSubState());
                if (paused)
                {
                        // if (!ffmpegMode && FlxG.sound.music != null && !startingSong && !endingSong && canResync)
                        // {
                        //      resyncVocals();
                        // }
                        if (FlxG.sound.music != null)
                        {
                                FlxG.sound.music.resume();
                                if (bfVocal) vocals.resume();
                                if (opVocal) opponentVocals.resume();
                        }
                        FlxTimer.globalManager.forEach(tmr -> if (!tmr.finished) tmr.active = true);
                        FlxTween.globalManager.forEach(twn -> if (!twn.finished) twn.active = true);

                        paused = false;
                        callOnScripts('onResume');
                        resetRPC(startTimer != null && startTimer.finished);
                }
        }

        #if DISCORD_ALLOWED
        override public function onFocus():Void
        {
                if (health > 0 && !paused)
                        resetRPC(Conductor.songPosition > 0.0);
                if (FlxG.autoPause && nanoPosition) nanoTime = CoolUtil.getNanoTime();
                super.onFocus();
                if (!paused && health > 0)
                {
                        resetRPC(Conductor.songPosition > 0.0);
                }
        }

        override public function onFocusLost():Void
        {
                if (FlxG.autoPause && nanoPosition) nanoTime = CoolUtil.getNanoTime();
                // trace(nanoTime);

                super.onFocusLost();
                if (!paused && health > 0 && autoUpdateRPC)
                {
                        songText = '${SONG.song} ($storyDifficultyText)';
                        DiscordClient.changePresence(detailsPausedText, songText, iconP2.getCharacter());
                }
        }
        #end

        // Updating Discord Rich Presence.
        public var autoUpdateRPC:Bool = true; // performance setting for custom RPC things

        function resetRPC(?showTime:Bool = false)
        {
                #if DISCORD_ALLOWED
                if (!autoUpdateRPC) return;
                
                songText = '${SONG.song} ($storyDifficultyText)';
                // trace(songText);

                if (showTime) {
                        DiscordClient.changePresence(detailsText, songText, iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
                } else DiscordClient.changePresence(detailsText, songText, iconP2.getCharacter());
                #end
        }

        var thresholdTime:Float = ClientPrefs.data.syncThreshold;
        var desyncCount:Float = 0;
        var desyncTimes:Vector<Float> = new Vector(3, 0.0);
        function checkSync() {
                desyncTimes[0] = FlxG.sound.music.time - Conductor.songPosition;
                if (bfVocal) desyncTimes[1] = vocals.time - Conductor.songPosition;
                if (opVocal) desyncTimes[2] = opponentVocals.time - Conductor.songPosition;

                for (value in desyncTimes) if (Math.abs(value) > thresholdTime * playbackRate) resyncVocals();
        }

        function resyncVocals():Void
        {
                if (finishTimer != null)
                        return;

                desyncCount++;
                // trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

                FlxG.sound.music.play();
                if (!ffmpegMode && FlxG.sound.music.volume == 0) {
                        FlxG.sound.music.volume = ClientPrefs.data.bgmVolume;
                }
                #if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
                Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

                var checkVocals = [vocals, opponentVocals];
                for (voc in checkVocals)
                {
                        if (voc == null) continue;
                        if (FlxG.sound.music.time < voc.length)
                        {
                                voc.time = FlxG.sound.music.time;
                                #if FLX_PITCH voc.pitch = playbackRate; #end
                                voc.play();
                        } else voc.pause();
                }
        }

        public var paused:Bool = false;
        public var canReset:Bool = true;

        var startedCountdown:Bool = false;
        var canPause:Bool = true;
        var freezeCamera:Bool = false;
        var bfAnimName:String = "";

        // Time
        public var timeout:Float = ClientPrefs.data.nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp();
        var globalElapsed:Float = 0;
        var shownTime:Float = 0;
        var shownRealTime:Float = 0;
        var canBeHit:Bool = false;
        var tooLate:Bool = false;
        var noteSpawnJudge:Bool = false;
        var safeTime:Float = 0;
        var frameCount:Int = 0;
        var prevDecBeat:Float = 0;

        // Spawning
        var currentId:Int = 0;
        var targetNote:CastNote = null;
        var dunceNote:Note = null;
        var strumGroup:FlxTypedGroup<StrumNote>;
        final skipBuffer:Int = 1024;

        // Popup
        var popUpHitNote:Note = null;
        var popUpDebug:Vector<Int> = new Vector(4, 0);

        // Hit Management
        var hit:Array<Bool> = [];
        var skipHit:Array<Bool> = [];
        var globalNoteHit:Bool = false;
        var globalFrameHit:Bool = false;
        var opHit:Bool = false;
        var bfHit:Bool = false;
        var noteDataInfo:Int = 0;

        // Rendering Counter
        var shownCnt:Float = 0;
        public var shownMax:Float = 0;
        var skipCnt:Float = 0;
        var skipBf:Float = 0;
        var skipOp:Float = 0;
        var skipTimeOut:Float = 0;
        var skipTotalCnt:Float = 0;
        var skipMax:Float = 0;

        // Information
        var changeInfo:Bool = false;
        var debugInfos:Bool = false;
        var columnIndex:Int = 0;
        var columns:Int = 0;

        // NPS
        var npsTime = 0;
        var npsMod = false;
        var bothNpsAdd = false;
        var nps = new IntMap<Float>();
        var opNps = new IntMap<Float>();
        var bfNpsVal = 0.0;
        var opNpsVal = 0.0;
        var bfNpsMax = 0.0;
        var opNpsMax = 0.0;
        var totalNpsVal = 0.0;
        var totalNpsMax = 0.0;
        var npsControlled = 0;
        var bfNpsAdd = 0.0;
        var opNpsAdd = 0.0;
        var bfSideHit = 0.0;
        var opSideHit = 0.0;
        var npsHoldTime = 0.0;
        var npsHoldTimer = new FlxTimer();
        var npsHoldTimerWorked = false;

        var bfHitFrame:Float = 0;
        var bfHitSus:Float = 0;
        var opHitFrame:Float = 0;
        var opHitSus:Float = 0;

        var refBpm:Float = 0;
        var tweenBpm:Float = 1;

        override public function update(elapsed:Float)
        {

                // --- AndreJr HUD Update ---
                if (andreHUDEnabled) {
                        var curPos = Conductor.songPosition;
                        var isBot = cpuControlled;

                        // NPS calc
                        while (andrePlayerHits.length > 0 && curPos - andrePlayerHits[0] > 1000) andrePlayerHits.shift();
                        while (andreOppHits.length > 0 && curPos - andreOppHits[0] > 1000) andreOppHits.shift();
                        var playerNPS = andrePlayerHits.length;
                        var oppNPS = andreOppHits.length;
                        andreMaxPlayerNPS = Std.int(Math.max(andreMaxPlayerNPS, playerNPS));
                        andreMaxOppNPS = Std.int(Math.max(andreMaxOppNPS, oppNPS));

                        // visibility
                        andreCounterBox.visible = isBot;
                        andreCounterText.visible = isBot;
                        andreOppBox.visible = isBot;
                        andreOppNpsText.visible = isBot;
                        andrePlayerBox.visible = isBot;
                        andrePlayerNpsText.visible = isBot;
                        andreTopTimeBox.visible = !isBot;
                        andreTopTimeText.visible = !isBot;
                        andreStatsBox.visible = !isBot;
                        andreStatsText.visible = !isBot;

                        // Prevent camera beat bounce - force scale 1
                        var noBounce = [andreCounterBox, andreCounterText, andreOppBox, andreOppNpsText, andrePlayerBox, andrePlayerNpsText, andreTopTimeBox, andreTopTimeText, andreStatsBox, andreStatsText];
                        for (obj in noBounce) if (obj != null) obj.scale.set(1, 1);

                        if (isBot) {
                                // 0 + 0 = 0 format - THIS IS YOUR COMBO
                                var total = andreOppNotes + andrePlayerNotes;
                                if (ClientPrefs.data.ghostDensity) {
                                        var lo = 0;
                                        var hi = andreOppTimes.length - 1;
                                        var oppCount = 0;
                                        while (lo <= hi) {
                                                var m = (lo + hi) >> 1;
                                                if (andreOppTimes[m] <= curPos) {
                                                        oppCount = m + 1;
                                                        lo = m + 1;
                                                } else hi = m - 1;
                                        }

                                        lo = 0;
                                        hi = andrePlayerTimes.length - 1;
                                        var playerCount = 0;
                                        while (lo <= hi) {
                                                var m = (lo + hi) >> 1;
                                                if (andrePlayerTimes[m] <= curPos) {
                                                        playerCount = m + 1;
                                                        lo = m + 1;
                                                } else hi = m - 1;
                                        }

                                        var totalCount = oppCount + playerCount;
                                        var now = curPos;

                                        if (oppCount > lastOppCountForNps) {
                                                var diff = oppCount - lastOppCountForNps;
                                                for (i in 0...diff)
                                                        andreNpsHistory.push({t: now, o: lastOppCountForNps + i + 1, p: playerCount});
                                                lastOppCountForNps = oppCount;
                                        }

                                        if (playerCount > lastPlayerCountForNps) {
                                                var diff = playerCount - lastPlayerCountForNps;
                                                for (i in 0...diff)
                                                        andreNpsHistory.push({t: now, o: oppCount, p: lastPlayerCountForNps + i + 1});
                                                lastPlayerCountForNps = playerCount;
                                        }

                                        while (andreNpsHistory.length > 0 && now - andreNpsHistory[0].t > 1000)
                                                andreNpsHistory.shift();

                                        var first = andreNpsHistory.length > 0 ? andreNpsHistory[0] : {t: now, o: oppCount, p: playerCount};
                                        var oppNpsCombo = oppCount - first.o;
                                        var playerNpsCombo = playerCount - first.p;

                                        if (oppNpsCombo > andreMaxOppNPS) andreMaxOppNPS = oppNpsCombo;
                                        if (playerNpsCombo > andreMaxPlayerNPS) andreMaxPlayerNPS = playerNpsCombo;

                                        andreOppNpsText.text = andreFormat(oppNpsCombo) + " | " + andreFormat(andreMaxOppNPS);
                                        andrePlayerNpsText.text = andreFormat(playerNpsCombo) + " | " + andreFormat(andreMaxPlayerNPS);

                                        andreCounterText.text = andreFormat(oppCount) + " + " + andreFormat(playerCount) + " = " + andreFormat(totalCount) + " | " + andreFormat(andreActualTotalNotes);
                                } else {
                                        andreCounterText.text = andreFormat(andreOppNotes) + " + " + andreFormat(andrePlayerNotes) + " = " + andreFormat(andreOppNotes + andrePlayerNotes);

                                        andreOppNpsText.text = andreFormat(oppNPS) + " | " + andreFormat(andreMaxOppNPS);
                                        andrePlayerNpsText.text = andreFormat(playerNPS) + " | " + andreFormat(andreMaxPlayerNPS);
                                }
                                andreCounterText.x = (FlxG.width - andreCounterText.width) / 2;
                                andreCounterBox.setGraphicSize(Std.int(andreCounterText.width + 20), Std.int(andreCounterText.height + 10));
                                andreCounterBox.updateHitbox();
                                andreCounterBox.x = andreCounterText.x - 10;
                                andreCounterBox.y = andreCounterText.y - 5;

                                andreOppBox.setGraphicSize(Std.int(andreOppNpsText.width + 20), Std.int(andreOppNpsText.height + 10));
                                andreOppBox.updateHitbox();
                                andreOppBox.y = andreOppNpsText.y - 5;

                                andrePlayerNpsText.x = FlxG.width - andrePlayerNpsText.width - 20;
                                andrePlayerBox.setGraphicSize(Std.int(andrePlayerNpsText.width + 20), Std.int(andrePlayerNpsText.height + 10));
                                andrePlayerBox.updateHitbox();
                                andrePlayerBox.x = andrePlayerNpsText.x - 10;
                                andrePlayerBox.y = andrePlayerNpsText.y - 5;
                        } else {
                                // Player HUD - time and stats
                                var timeLeft = FlxG.sound.music.length - curPos;
                                if (timeLeft < 0) timeLeft = 0;
                                function fmt(ms:Float) {
                                        var s = Math.floor(ms / 1000);
                                        var m = Math.floor(s / 60);
                                        var sec = s % 60;
                                        var mil = Math.floor((ms % 1000) / 10);
                                        return (m < 10 ? "0"+m : ""+m) + ":" + (sec < 10 ? "0"+sec : ""+sec) + "." + (mil < 10 ? "0"+mil : ""+mil);
                                }
                                andreTopTimeText.text = fmt(timeLeft) + " | " + fmt(curPos);
                                andreTopTimeText.x = (FlxG.width - andreTopTimeText.width) / 2;
                                andreTopTimeBox.setGraphicSize(Std.int(andreTopTimeText.width + 20), Std.int(andreTopTimeText.height + 10));
                                andreTopTimeBox.updateHitbox();
                                andreTopTimeBox.x = andreTopTimeText.x - 10;
                                andreTopTimeBox.y = andreTopTimeText.y - 5;

                                var acc = Math.floor(ratingPercent * 100);
                                var hp = Math.floor(health * 50);
                                andreStatsText.text = "Score: " + andreFormat(songScore) + " | Misses: " + andreFormat(songMisses) + " | Accuracy: " + acc + "% | Health: " + hp + "%";
                                andreStatsText.screenCenter(X);
                                andreStatsBox.setGraphicSize(Std.int(andreStatsText.width + 20), Std.int(andreStatsText.height + 10));
                                andreStatsBox.updateHitbox();
                                andreStatsBox.x = andreStatsText.x - 10;
                                andreStatsBox.y = andreStatsText.y - 5;
                        }
                }

// --- Andre New HUD Update ---
                if (andreNewHUDEnabled) {
                        var noBounce:Array<Dynamic> = [];
                        for (i in 0...3) {
                                noBounce.push(andreNewBoxBgs[i]);
                                noBounce.push(andreNewBoxLines[i]);
                                for (b in andreNewBoxBrackets[i]) noBounce.push(b);
                                noBounce.push(andreNewBoxTexts[i]);
                        }
                        for (obj in noBounce) if (obj != null) obj.scale.set(1, 1);

                        var curPos = Conductor.songPosition;

                        // Ghost density combo/NPS (combo windows based on chart note density, like AndreJr)
                        if (ClientPrefs.data.ghostDensity) {
                                var lo = 0;
                                var hi = andreOppTimes.length - 1;
                                var oppCount = 0;
                                while (lo <= hi) {
                                        var m = (lo + hi) >> 1;
                                        if (andreOppTimes[m] <= curPos) {
                                                oppCount = m + 1;
                                                lo = m + 1;
                                        } else hi = m - 1;
                                }

                                lo = 0;
                                hi = andrePlayerTimes.length - 1;
                                var playerCount = 0;
                                while (lo <= hi) {
                                        var m = (lo + hi) >> 1;
                                        if (andrePlayerTimes[m] <= curPos) {
                                                playerCount = m + 1;
                                                lo = m + 1;
                                        } else hi = m - 1;
                                }

                                var now = curPos;

                                // track changing counts for a 1-second rolling window
                                if (oppCount > lastOppCountForNps) {
                                        var diff = oppCount - lastOppCountForNps;
                                        for (i in 0...diff)
                                                andreNpsHistory.push({t: now, o: lastOppCountForNps + i + 1, p: playerCount});
                                        lastOppCountForNps = oppCount;
                                }

                                if (playerCount > lastPlayerCountForNps) {
                                        var diff = playerCount - lastPlayerCountForNps;
                                        for (i in 0...diff)
                                                andreNpsHistory.push({t: now, o: oppCount, p: lastPlayerCountForNps + i + 1});
                                        lastPlayerCountForNps = playerCount;
                                }

                                while (andreNpsHistory.length > 0 && now - andreNpsHistory[0].t > 1000)
                                        andreNpsHistory.shift();

                                var first = andreNpsHistory.length > 0 ? andreNpsHistory[0] : {t: now, o: oppCount, p: playerCount};
                                var oppNpsCombo = oppCount - first.o;
                                var playerNpsCombo = playerCount - first.p;
                                var totalNpsCombo = (oppCount + playerCount) - (first.o + first.p);

                                if (oppNpsCombo > andreNewMaxOppNPS) andreNewMaxOppNPS = oppNpsCombo;
                                if (playerNpsCombo > andreNewMaxPlayerNPS) andreNewMaxPlayerNPS = playerNpsCombo;
                                if (totalNpsCombo > andreNewComboTotal) andreNewComboTotal = totalNpsCombo;

                                andreNewComboOpp = oppNpsCombo;
                                andreNewComboPlayer = playerNpsCombo;
                                // andreNewComboTotal is rolling max-like totalNpsCombo

                                andreNewBoxTexts[0].text = andreFormat(oppNpsCombo) + " / " + andreFormat(andreNewMaxOppNPS);
                                andreNewBoxTexts[1].text = andreFormat(andreNewComboOpp) + " / " + andreFormat(andreNewComboTotal) + " / " + andreFormat(andreNewComboPlayer);
                                andreNewBoxTexts[2].text = andreFormat(playerNpsCombo) + " / " + andreFormat(andreNewMaxPlayerNPS);
                        } else {
                                while (andreNewOppHits.length > 0 && curPos - andreNewOppHits[0] > 1000) andreNewOppHits.shift();
                                while (andreNewPlayerHits.length > 0 && curPos - andreNewPlayerHits[0] > 1000) andreNewPlayerHits.shift();
                                var oppNPS = andreNewOppHits.length;
                                var playerNPS = andreNewPlayerHits.length;
                                andreNewMaxOppNPS = Std.int(Math.max(andreNewMaxOppNPS, oppNPS));
                                andreNewMaxPlayerNPS = Std.int(Math.max(andreNewMaxPlayerNPS, playerNPS));

                                // combo values already computed elsewhere (existing logic)
                                andreNewBoxTexts[0].text = andreFormat(oppNPS) + " / " + andreFormat(andreNewMaxOppNPS);
                                andreNewBoxTexts[1].text = andreFormat(andreNewComboOpp) + " / " + andreFormat(andreNewComboTotal) + " / " + andreFormat(andreNewComboPlayer);
                                andreNewBoxTexts[2].text = andreFormat(playerNPS) + " / " + andreFormat(andreNewMaxPlayerNPS);
                        }

                        var padding = 28;
                        for (i in 0...3) {
                                andreNewBoxWidths[i] = Std.int(andreNewBoxTexts[i].width + padding);
                        }

                        var BOX_HEIGHT = 35;
                        var BRACKET_SIZE = 8;
                        var THICKNESS = 2;
                        var LINE_PADDING = 12;
                        var BOX_GAP = 8;
                        var TOP_Y = 10;

                        var midWidth = andreNewBoxWidths[1];
                        var midX = Std.int((FlxG.width / 2) - (midWidth / 2));
                        var leftX = midX - andreNewBoxWidths[0] - BOX_GAP;
                        var rightX = midX + midWidth + BOX_GAP;

                        andreNewBoxXs[0] = leftX;
                        andreNewBoxXs[1] = midX;
                        andreNewBoxXs[2] = rightX;

                        for (i in 0...3) {
                                var x = andreNewBoxXs[i];
                                var w = andreNewBoxWidths[i];
                                var bg = andreNewBoxBgs[i];
                                var line = andreNewBoxLines[i];
                                var brackets = andreNewBoxBrackets[i];
                                var text = andreNewBoxTexts[i];

                                bg.setGraphicSize(w, BOX_HEIGHT);
                                bg.updateHitbox();
                                bg.x = x;

                                var lineWidth = w - (LINE_PADDING * 2);
                                line.setGraphicSize(lineWidth, 2);
                                line.updateHitbox();
                                line.x = x + LINE_PADDING;
                                line.y = TOP_Y + BOX_HEIGHT - 8;

                                brackets[0].x = x; brackets[0].y = TOP_Y;
                                brackets[1].x = x; brackets[1].y = TOP_Y;
                                brackets[2].x = x + w - BRACKET_SIZE; brackets[2].y = TOP_Y;
                                brackets[3].x = x + w - THICKNESS; brackets[3].y = TOP_Y;
                                brackets[4].x = x; brackets[4].y = TOP_Y + BOX_HEIGHT - THICKNESS;
                                brackets[5].x = x; brackets[5].y = TOP_Y + BOX_HEIGHT - BRACKET_SIZE;
                                brackets[6].x = x + w - BRACKET_SIZE; brackets[6].y = TOP_Y + BOX_HEIGHT - THICKNESS;
                                brackets[7].x = x + w - THICKNESS; brackets[7].y = TOP_Y + BOX_HEIGHT - BRACKET_SIZE;

                                text.x = x + Std.int((w - text.width) / 2);
                        }
                }

                // --- Andre HUD (Lua Port) Update ---
                if (andreLuaHUDEnabled) {
                        var curPos = Conductor.songPosition;
                        var isBot = cpuControlled;
                        var curY = isBot ? 10 : 640;

                        // NPS calc
                        while (andreLuaPlayerHits.length > 0 && curPos - andreLuaPlayerHits[0] > 1000) andreLuaPlayerHits.shift();
                        while (andreLuaOppHits.length > 0 && curPos - andreLuaOppHits[0] > 1000) andreLuaOppHits.shift();
                        var playerNPS = andreLuaPlayerHits.length;
                        var oppNPS = andreLuaOppHits.length;
                        if (playerNPS > andreLuaMaxPlayerNPS) andreLuaMaxPlayerNPS = playerNPS;
                        if (oppNPS > andreLuaMaxOppNPS) andreLuaMaxOppNPS = oppNPS;

                        var noBounce2:Array<Array<Dynamic>> = [andreLuaBoxBgs, andreLuaBoxLines, andreLuaBoxTexts];
                        for (obj in noBounce2)
                                for (o in obj) if (o != null) o.scale.set(1, 1);
                        for (bb in andreLuaBoxBrackets)
                                for (o in bb) if (o != null) o.scale.set(1, 1);

                        if (isBot) {
                                andreLuaBoxTexts[0].text = andreFormat(oppNPS) + " / " + andreFormat(andreLuaMaxOppNPS);
                                andreLuaBoxTexts[1].text = andreFormat(andreLuaComboOpp);
                                andreLuaBoxTexts[2].text = andreFormat(andreLuaComboTotal);
                                andreLuaBoxTexts[3].text = andreFormat(andreLuaComboPlayer);
                                andreLuaBoxTexts[4].text = andreFormat(playerNPS) + " / " + andreFormat(andreLuaMaxPlayerNPS);
                        } else {
                                var score = songScore;
                                var misses = songMisses;
                                var acc = Math.floor(ratingPercent * 100 + 0.5);
                                andreLuaBoxTexts[0].text = "";
                                andreLuaBoxTexts[1].text = "";
                                andreLuaBoxTexts[2].text = "[Score: " + andreFormat(score) + "] [Misses: " + misses + "] [Accuracy: " + acc + "%]";
                                andreLuaBoxTexts[3].text = "";
                                andreLuaBoxTexts[4].text = "";
                        }

                        var padding = 28;
                        var leftWidth = ((isBot ? andreLuaBoxTexts[0].fieldWidth : 0) + padding);
                        var midLeftWidth = ((isBot ? andreLuaBoxTexts[1].fieldWidth : 0) + padding);
                        var midWidth = andreLuaBoxTexts[2].fieldWidth + padding;
                        var midRightWidth = ((isBot ? andreLuaBoxTexts[3].fieldWidth : 0) + padding);
                        var rightWidth = ((isBot ? andreLuaBoxTexts[4].fieldWidth : 0) + padding);

                        var midX = (FlxG.width / 2) - (midWidth / 2);
                        var midLeftX = midX - midLeftWidth - 8;
                        var leftX = midLeftX - leftWidth - 8;
                        var midRightX = midX + midWidth + 8;
                        var rightX = midRightX + midRightWidth + 8;

                        var oppColor:Array<Int> = [163, 73, 164];
                        var oppBorderColor:Int = andreLuaDefaultOppColor;
                        if (dad != null && dad.healthColorArray != null && dad.healthColorArray.length >= 3) {
                                oppBorderColor = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
                                oppColor = [dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]];
                        }
                        var oppBgColor = FlxColor.fromRGB(Std.int(oppColor[0] * 0.35), Std.int(oppColor[1] * 0.35), Std.int(oppColor[2] * 0.35));

                        var xs = [leftX, midLeftX, midX, midRightX, rightX];
                        var widths = [leftWidth, midLeftWidth, midWidth, midRightWidth, rightWidth];
                        var bgs = [oppBgColor, oppBgColor, FlxColor.BLACK, andreLuaPlayerBgColor, andreLuaPlayerBgColor];
                        var borders = [oppBorderColor, oppBorderColor, FlxColor.WHITE, andreLuaPlayerBorderColor, andreLuaPlayerBorderColor];
                        var alphas = [0.75, 0.75, 0.6, 0.75, 0.75];

                        for (i in 0...5) {
                                var x = xs[i];
                                var w = widths[i];
                                var isMiddle = (i == 2);
                                var visible = isBot || isMiddle;

                                var bg = andreLuaBoxBgs[i];
                                bg.visible = visible;
                                bg.color = bgs[i];
                                bg.alpha = alphas[i];
                                bg.setGraphicSize(w, 35);
                                bg.updateHitbox();
                                bg.x = x;
                                bg.y = curY;

                                var line = andreLuaBoxLines[i];
                                line.visible = visible;
                                line.color = borders[i];
                                line.setGraphicSize(w - 24, 2);
                                line.updateHitbox();
                                line.x = x + 12;
                                line.y = curY + 35 - 8;

                                var brackets = andreLuaBoxBrackets[i];
                                for (b in brackets) b.visible = visible;
                                var BS = 8;
                                var TH = 2;
                                brackets[0].color = borders[i]; brackets[0].x = x; brackets[0].y = curY;
                                brackets[1].color = borders[i]; brackets[1].x = x; brackets[1].y = curY;
                                brackets[2].color = borders[i]; brackets[2].x = x + w - BS; brackets[2].y = curY;
                                brackets[3].color = borders[i]; brackets[3].x = x + w - TH; brackets[3].y = curY;
                                brackets[4].color = borders[i]; brackets[4].x = x; brackets[4].y = curY + 35 - TH;
                                brackets[5].color = borders[i]; brackets[5].x = x; brackets[5].y = curY + 35 - BS;
                                brackets[6].color = borders[i]; brackets[6].x = x + w - BS; brackets[6].y = curY + 35 - TH;
                                brackets[7].color = borders[i]; brackets[7].x = x + w - TH; brackets[7].y = curY + 35 - BS;

                                var text = andreLuaBoxTexts[i];
                                text.visible = visible;
                                text.x = x + Std.int((w - text.width) / 2);
                                text.y = curY + 5;
                        }
                }
                // Pre Render Image
                if (preshot) renderFrame();

                if (!ffmpegMode && cpuControlled) {
                        if (FlxG.keys.justPressed.SPACE) playbackRate = skipRate;
                        if (FlxG.keys.released.SPACE) playbackRate = normalRate;
                }
                
                opHit = bfHit = showAgain = false; canAnim.fill(true);
                if (popUpHitNote != null) popUpHitNote = null;
                if (hit.length != totalColumns * 2) {
                        hit = [for (i in 0...(totalColumns * 2)) false];
                        skipHit = [for (i in 0...(totalColumns * 2)) false];
                        susEnds = [for (i in 0...(totalColumns * 2)) false];
                } else {
                        for (i in 0...hit.length) { hit[i] = false; skipHit[i] = false; susEnds[i] = false; }
                }
                shownCnt = skipBf = skipOp = 0;
                lastSongSpeed = songSpeed;

                if (refBpm != Conductor.bpm) {
                        refBpm = Conductor.bpm;
                        tweenBpm = Math.pow(refBpm / 120, 0.5);
                }

                splashMoment.fill(0);

                if (nanoPosition && !ffmpegMode) {
                        if (frameCount <= 2) elapsedNano = FlxG.elapsed; // Sync the timing
                        else elapsedNano = CoolUtil.getNanoTime() - nanoTime;
                        
                        globalElapsed = elapsedNano * playbackRate;
                        nanoTime = CoolUtil.getNanoTime();
                } else if (ffmpegMode) {
                        // Fixed step: output timing must not depend on compositor/frame pacing (Ubuntu GNOME).
                        globalElapsed = (1.0 / targetFPS) * playbackRate;
                } else {
                        globalElapsed = FlxG.elapsed * playbackRate;
                }
                
                if (startedCountdown && !paused) {
                        if (vsliceSongPosition && !ffmpegMode)
                        {
                                if (Conductor.songPosition >= Conductor.offset)
                                {
                                        Conductor.songPosition = FlxMath.lerp(FlxG.sound.music.time + Conductor.offset, Conductor.songPosition, Math.exp(-globalElapsed * 5));
                                        var timeDiff:Null<Float> = Math.abs((FlxG.sound.music.time + Conductor.offset) - Conductor.songPosition);
                                        if (timeDiff > 1000 * playbackRate)
                                                Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
                                        timeDiff = null;
                                }
                        }
                        Conductor.songPosition += globalElapsed * 1000;
                }
                
                if (!inCutscene && !paused && !freezeCamera)
                {
                        FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate * tweenBpm;
                        bfAnimName = boyfriend.getAnimationName();
                        if (!startingSong && !endingSong && (bfAnimName.startsWith('idle') || bfAnimName.startsWith('danceLeft') || bfAnimName.startsWith('danceRight')))
                        {
                                boyfriendIdleTime += globalElapsed;
                                if (boyfriendIdleTime >= 0.15)
                                { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
                                        boyfriendIdled = true;
                                }
                        }
                        else
                        {
                                boyfriendIdleTime = 0;
                        }
                } else FlxG.camera.followLerp = 0;
                callOnScripts('onUpdate', [globalElapsed]);

                prevDecBeat = curDecBeat;
                super.update(globalElapsed);

                setOnScripts('curDecStep', curDecStep);
                setOnScripts('curDecBeat', curDecBeat);

                if (botplayTxt != null && botplayTxt.visible && !botplayOptimize)
                {
                        botplaySine += 180 * globalElapsed;
                        botplayTxt.alpha = 1 - Math.sin(Math.PI * botplaySine / 180);
                        botplaySineCnt = Math.floor((botplaySine + 270) / 360);

                        if (botplayTxt.text == "Never gonna give you up" && !ffmpegMode) {
                                rickRolled = true;
                        }
                        
                        if (rickRolled) {
                                botplayTxt.text = rickRollTxt[botplaySineCnt & 7];
                        }
                        
                        #if desktop
                        if (ffmpegMode) {
                                if (video.wentPreview == null) {
                                        botplayTxt.text = botplaySineCnt % 2 == 0 ? "RENDERED" : "BY A-SLICE";
                                } else {
                                        botplayTxt.text = botplaySineCnt % 2 == 0 ? "Rendering was cancelled by: " : video.wentPreview;
                                }
                        }
                        #end
                }

                if ((controls.PAUSE #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonP.justPressed #end #if android || FlxG.android.justReleased.BACK #end) && startedCountdown && canPause)
                {
                        var ret = callOnScripts('onPause', null, true);
                        if (ret != LuaUtils.Function_Stop)
                        {
                                openPauseMenu();
                        }
                }

                if (!endingSong && !inCutscene)
                {
                        if (controls.justPressed('debug_1')) {
                                openChartEditor();
                        } else if (controls.justPressed('debug_2')) {
                                openCharacterEditor();
                        }
                }

                if (startingSong)
                {
                        if (startedCountdown && Conductor.songPosition >= Conductor.offset)
                                startSong();
                        else if (!startedCountdown)
                                Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
                }
                else if (!paused && updateTime)
                {
                        var curTime:Float;
                        var songCalc:Float;
                        var secondsTotal:Float;

                        curTime = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
                        songPercent = curTime / songLength;

                        songCalc = songLength - curTime;
                        if (ClientPrefs.data.timeBarType == 'Time Elapsed')
                                songCalc = curTime;

                        secondsTotal = songCalc / 1000;
                        if (secondsTotal < 0)
                                secondsTotal = 0;

                        if (ClientPrefs.data.timeBarType != 'Song Name')
                                timeTxt.text = CoolUtil.formatTime(secondsTotal, ClientPrefs.data.timePrec);

                        if (ffmpegMode && !endingSong && songCalc < 0) {
                                finishSong();
                        }
                }

                if (camZooming)
                {
                        var ratio = Math.exp(-globalElapsed * 3.125 * camZoomingDecay * tweenBpm);
                        FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, ratio);
                        camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, ratio);
                }

                FlxG.watch.addQuick("secShit", curSection);
                FlxG.watch.addQuick("beatShit", curBeat);
                FlxG.watch.addQuick("stepShit", curStep);

                // RESET = Quick Game Over Screen
                if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
                {
                        health = 0;
                        trace("RESET = True");
                }
                if (!practiceMode) doDeathCheck();

                if (!ffmpegMode && !startingSong && !endingSong && !paused && canResync)
                        checkSync();

                /* --- main process --- */
                if (!processFirst) {
                        noteSpawn();
                        noteUpdate();
                } else {
                        noteUpdate();
                        noteSpawn();
                }
                noteFinalize();
                /* --- main process --- */

                if (sortingWay >= 3) noteSort();
                
                if (overHealth) healthLerp = healthLerper();
                else {
                        if (healthBar.bounds.max != null) 
                                health = Math.max(healthBar.bounds.min, Math.min(health, healthBar.bounds.max));
                }

                updateIconsScale(globalElapsed);
                updateIconsPosition();

                // if (bfHitFrame > 0 || opHitFrame > 0 || health >= 2) {
                        updateScoreText();
                        bfHitFrame = opHitFrame = 0;
                // }
                
                if (!overHealth) healthLerp = healthLerper();
                else {
                        if (healthBar.bounds.max != null) 
                                health = Math.max(healthBar.bounds.min, Math.min(health, healthBar.bounds.max));
                }

                // Shader Update Zone
                if (shaderEnabled) {
                        for(wig in wiggleMap) {
                                wig.update(globalElapsed);
                        }

                        if (allowDisableAt == curStep || isDead)
                                allowDisable = true;

                        if (allowDisable)
                                masterPulse.shader.uampmul.value[0] -= (globalElapsed / 2);

                        if (masterPulse.shader.uampmul.value[0] > 0)
                                masterPulse.update(globalElapsed);
                }

                if (showPopups && popUpHitNote != null) {
                        popUpScore(popUpHitNote);
                }

                // NPS Zone
                if ((showInfoType == "Notes Per Second" || showInfoType == "NPS & Rendered") && !paused) {
                        npsMod = bfNpsAdd > 0 || opNpsAdd > 0;
                        bothNpsAdd = bfNpsAdd > 0 && opNpsAdd > 0;

                        if (npsMod) {
                                if (globalNoteHit) {
                                        if (opNpsAdd > 0) {
                                                doAnim(null, false);
                                                opSideHit -= bothNpsAdd ? opSideHit : Math.max(opSideHit, bfSideHit);
                                        }
                                        if (bfNpsAdd > 0) {
                                                doAnim(null, true);
                                                bfSideHit -= bothNpsAdd ? bfSideHit : Math.max(opSideHit, bfSideHit);
                                        }
                                        
                                        if (!npsHoldTimerWorked) {
                                                npsHoldTimer.start(FlxMath.bound(npsHoldTime, 0, 1), t -> bfNpsAdd = opNpsAdd = 0);
                                                npsHoldTimerWorked = true;
                                        }
                                }
                                opSideHit += opNpsAdd * globalElapsed;
                                bfSideHit += bfNpsAdd * globalElapsed;
                        }
                        npsTime = Math.round(Conductor.songPosition);

                        if (opSideHit > 0) opNps.set(npsTime, opSideHit);
                        if (bfSideHit > 0) nps.set(npsTime, bfSideHit);

                        for (key => value in opNps) {
                                if (key + 1000 > npsTime) {
                                        if (opSideHit > 0) {
                                                opNpsVal += opSideHit;
                                                opSideHit = 0;
                                        } else continue;
                                } else {
                                        opNpsVal -= value;
                                        opNps.remove(key);
                                }
                        }

                        for (key => value in nps) {
                                if (key + 1000 > npsTime) {
                                        if (bfSideHit > 0) {
                                                bfNpsVal += bfSideHit;
                                                bfSideHit = 0;
                                        } else continue;
                                } else {
                                        bfNpsVal -= value;
                                        nps.remove(key);
                                }
                        }

                        totalNpsVal = opNpsVal + bfNpsVal;

                        totalNpsMax = Math.max(totalNpsVal, totalNpsMax);
                        opNpsMax = Math.max(opNpsVal, opNpsMax);
                        bfNpsMax = Math.max(bfNpsVal, bfNpsMax);
                }

                if (changeInfo) {
                        if (FlxG.keys.justPressed.UP) --columnIndex;
                        if (FlxG.keys.justPressed.DOWN) ++columnIndex;

                        if (columnIndex >= columns) columnIndex = 0;
                        if (columnIndex < 0) columnIndex = FlxMath.maxInt(0, columns-1);

                        if (debugInfos) {
                                popUpDebug.fill(0); popUpAlive = 0;
                                if (showPopups) {
                                        popUpGroup.forEach(lmfao -> {
                                                switch (lmfao.type) {
                                                        case NONE: ++popUpDebug[0];
                                                        case RATING: ++popUpDebug[1];
                                                        case COMBO: ++popUpDebug[2];
                                                        case NUMBER: ++popUpDebug[3];
                                                }
                                        });
                                }

                                for (index in 0...popUpDebug.length) {
                                        if (index != 0)
                                                popUpAlive += popUpDebug[index];
                                }
                        }
                }

                if (showInfoType != "None") {
                        var info:String = '';
                        switch (showInfoType) {
                                case 'Notes Per Second', 'Rendered Notes', 'NPS & Rendered':
                                        var npsInfo:String = '', renderedInfo:String = '';
                                        var flag:Int = switch (showInfoType) {
                                                case 'NPS & Rendered': 3;
                                                case 'Rendered Notes': 2;
                                                case 'Notes Per Second': 1;
                                                case _: 0; // same as default
                                        }

                                        if (toBool(flag & 1)) {
                                                var nps:Array<Float> = [
                                                        Math.fround(opNpsVal),
                                                        Math.fround(bfNpsVal),
                                                        Math.fround(totalNpsVal),
                                                        Math.fround(opNpsMax),
                                                        Math.fround(bfNpsMax),
                                                        Math.fround(totalNpsMax),
                                                ];

                                                var lengths:Array<Int> = [Std.string(nps[3]).length, Std.string(nps[4]).length, Std.string(nps[5]).length];
                                                var len:Null<Int> = CoolUtil.integerArrayUtil(lengths, 0);
                                                var npsStr:Array<String> = [for (n in nps) fillNum(n, len, ' '.code, numberDelimit)];

                                                npsInfo = '${npsStr[0]}/${npsStr[3]}\n'
                                                        + '${npsStr[1]}/${npsStr[4]}\n'
                                                        + '${npsStr[2]}/${npsStr[5]}';

                                                npsStr.resize(0); nps.resize(0); len = null;
                                        }

                                        if (toBool(flag & 2)) {
                                                skipMax = Math.max(skipCnt, skipMax);

                                                if (numberDelimit)
                                                        renderedInfo = 'Rendered/Skipped: ${formatD(Math.max(notes.countLiving(), 0))}/${formatD(skipCnt)}/${formatD(notes.length)}/${formatD(skipMax)}';
                                                else
                                                        renderedInfo = 'Rendered/Skipped: ${Math.max(notes.countLiving(), 0)}/$skipCnt/${notes.length}/$skipMax';
                                        }

                                        info = npsInfo + (npsInfo != '' && renderedInfo != '' ? '\n' : '') + renderedInfo;
                                case 'Note Splash Counter':
                                        var buf:StringBuf = new StringBuf();
                                        buf.add("[");
                                        for (index => splash in splashUsing) {
                                                buf.add(splash.length.hex());
                                                if (index < splashUsing.length-1)
                                                        buf.add(",");
                                        } buf.add("]\n[");
                                        for (i in 0...splashMoment.length) {
                                                buf.add(splashMoment[i].hex());
                                                if (i < splashMoment.length-1)
                                                        buf.add(",");
                                        }
                                        if (enableHoldSplash) {
                                                buf.add("]\n[");
                                                for (i in 0...susplashMap.length) {
                                                        buf.add(susplashMap[i].holding ? 1 : 0);
                                                        if (i < susplashMap.length-1)
                                                                buf.add(",");
                                                }
                                        }
                                        buf.add("]");
                                        info = buf.toString();
                                        buf = null;
                                case 'Note Spawn Time':
                                        info = 'Speed: ${CoolUtil.decimal(songSpeed, 3)}'
                                                + ' / Time: ${CoolUtil.decimal(shownTime, 1)} ms'
                                                + ' / Capacity: ${numFormat(safeTime, 1)}'
                                                + ' % / Skip: $skipTimeOut/$skipTotalCnt';
                                #if desktop
                                case 'Video Info':
                                        info = numFormat(elapsedNano * 1000, 1) + " ms / " + (numberDelimit ? formatD(frameCount) : Std.string(frameCount));
                                #end
                                case 'Note Info':
                                        info = hex2bin(noteDataInfo.hex(4));
                                        if (dunceNote != null) info += '\nX:${fillNum(dunceNote.x, 5, 32)}, W:${fillNum(dunceNote.width, 5, 32)}, Offset:${fillNum(dunceNote.offset.x, 5, 32)}';
                                case 'Strums Info':
                                        var additional:Int = 0;
                                        for (strums in [opponentStrums, playerStrums]) {
                                                for (strum in strums) {
                                                        switch(strum.animation.curAnim.name) {
                                                                case "static": additional = 0;
                                                                case "press": additional = 1;
                                                                case "confirm": additional = 2;
                                                        }
                                                        info += ', $additional';
                                                }
                                        }
                                        info = info.substr(2);
                                case 'Song Info':
                                        switch (columnIndex) {
                                                case 0:
                                                        info = 'BPM: ${Conductor.bpm}, Sections: ${curSection+1}/${Math.max(curBeat+1,0)}/${Math.max(curStep+1,0)}, Update Cnt: ${updateMaxSteps}';
                                                        info += '\ncurDecBeat: ${numFormat(curDecBeat, 6)}, bopRatio: ${numFormat(bopRatio, 6)}';
                                                default:
                                                        var secBeat:Float = getBeatsOnSection();
                                                        info = 'BPM: ${Conductor.bpm}, Sections: ${curSection+1}/${Math.max(curBeat % secBeat + 1,0)}/${Math.max(curStep % secBeat + 1,0)}, Update Cnt: ${updateMaxSteps}';
                                                        info += '\ncurDecBeat: ${numFormat(curDecBeat, 6)}, bopRatio: ${numFormat(bopRatio, 6)}';
                                        }
                                case 'Music Sync Info':
                                        info = 'Desync (range of -${thresholdTime}ms ~ ${thresholdTime}ms)\n\n'
                                                 + (bfVocal ? "\n" : "") + (opVocal ? "\n" : "")
                                                 + 'Sync Count: $desyncCount';
                                        for (index => bar in desyncMusicBar) {
                                                bar.value = desyncTimes[index];
                                                bar.updateBar();
                                        }
                                case 'Debug Info':
                                        debugInfos = true;
                                        switch (columnIndex) {
                                                case 0:
                                                        if (betterRecycle) {
                                                                var f = notes.debugInfo();
                                                                info = '${f[0]} / ${f[1]}, ${numFormat(f[2], 3)}';
                                                                f = null;
                                                        } else {
                                                                info = 'Up/Down Key to change information';
                                                        }
                                                case 1:
                                                        info = '${numFormat(dad != null ? dad.holdTimer : Math.NaN, 3)}, '
                                                                 + '${numFormat(gf != null ? gf.holdTimer : Math.NaN, 3)}, '
                                                                 + '${numFormat(boyfriend != null ? boyfriend.holdTimer : Math.NaN, 3)}';
                                                case 2:
                                                        if (showPopups) {
                                                                info = '${popUpDebug[0]}, '
                                                                         + '${popUpDebug[1]}, '
                                                                         + '${popUpDebug[2]}, '
                                                                         + '${popUpDebug[3]}, '
                                                                         + '$popUpAlive / ${popUpGroup.length}';
                                                        } else {
                                                                info = 'No Popups';
                                                        }
                                                case 3:
                                                        info = 'Processed Real Notes: $processedReal / ${numFormat(processedRealElapsed * 1000, 3)} ms';
                                                case 4:
                                                        info = '${skipAnim[0]} / ${skipAnim[1]} / ${skipAnim[2]}\n${loopVector[0].strumTime} / ${loopVector[1].strumTime}';
                                                case 5:
                                                        info = '${revStr(hit.map(x -> x ? '1' : '0').join(''))}\n${revStr(skipHit.map(x -> x ? '1' : '0').join(''))}';
                                                case 6:
                                                        for (i in 0...8) {
                                                                info += '${numFormat(iDist[i], 1)}, ';
                                                        }
                                                        info = info.substring(0, info.length - 2) + "\n";
                                                        for (i in 0...8) {
                                                                info += '${toInt(currSus[i])}, ';
                                                        }
                                                        info = info.substring(0, info.length - 2) + "\n";
                                                        for (i in 0...8) {
                                                                info += '${toInt(prevSus[i])}, ';
                                                        }
                                                        info = info.substring(0, info.length - 2);
                                        }
                        }
                        infoTxt.text = info;
                } else {
                        if (infoTxt.text.length > 0) infoTxt.text = "";
                }
                
                // upScroll only
                if (!downScroll && infoTxt.text.length > 0) {
                        infoTxt.y = healthBar.y - 8 - infoTxt.height;
                }

                #if debug
                if (!endingSong && !startingSong)
                {
                        if (FlxG.keys.justPressed.ONE)
                        {
                                KillNotes();
                                FlxG.sound.music.onComplete();
                        }
                        if (FlxG.keys.justPressed.TWO)
                        { // Go 10 seconds into the future :O
                                setSongTime(Conductor.songPosition + 10000);
                                clearNotesBefore(Conductor.songPosition);
                        }
                }
                #end

                setOnScripts('botPlay', cpuControlled);
                callOnScripts('onUpdatePost', [globalElapsed]);

                #if debug
                if (FlxG.keys.justPressed.F1)
                {
                        KillNotes();
                        endSong();
                }
                #end

                // Post Render Image
                if (!preshot) renderFrame();
                
                ++frameCount;
        }

        function renderFrame() {
                #if desktop
                if (ffmpegMode && !previewRender)
                {
                        try {
                                video.pipeFrame();
                        } catch (e) {
                                video.wentPreview = e.message;
                                previewRender = true;
                                botplayTxt.size = Math.round(botplayTxt.size * 0.8);
                        }

                        if (gcRate != 0 && frameCount % gcRate == 0) {
                                if (ClientPrefs.data.disableGC) MemoryUtil.enable();
                                MemoryUtil.collect(gcMain);
                                if (gcMain) MemoryUtil.compact();
                                if (ClientPrefs.data.disableGC) MemoryUtil.disable();
                        }
                }
                #end
        }

        // Health icon updaters
        var iconBopTime:Float;
        var iconAngleTime:Float;
        var iconBopMultX:Float;
        var iconBopMultY:Float;
        var iconBopAngle:Float;
        public dynamic function updateIconsScale(time:Float)
        {
                if (iconBopType == "None") return;
                iconBopTime = Math.exp(-Conductor.bpm / 24 * time);
                iconAngleTime = Math.exp(-Conductor.bpm / 12 * time);

                for (icon in [iconP1, iconP2]) {
                        iconBopMultX = FlxMath.lerp(1, icon.scale.x, iconBopTime);
                        iconBopMultY = FlxMath.lerp(1, icon.scale.y, iconBopTime);
                        iconBopAngle = FlxMath.lerp(0, icon.angle, iconAngleTime);

                        icon.scale.set(iconBopMultX, iconBopMultY);
                        icon.angle = iconBopAngle;
                        icon.updateHitbox();
                }
        }

        public dynamic function updateIconsPosition()
        {
                var barPos = healthBar.x + healthBar.barWidth - healthLerp * .5 * healthBar.barWidth;

                iconP1.x = barPos + (iconP1.width - iconP1.iconW) * .5 - iconP1.iconW * .1733333333333333;
                iconP2.x = barPos - iconP2.width * .5 - iconP1.iconW * .3466666666666667;

                iconP1.y = healthBar.y - iconP1.height * .5;
                iconP2.y = healthBar.y - iconP2.height * .5;

                // Eseq.p('${iconP1.width}, ${iconP2.width}');
        }

        var limitCount = 0;
        var swapNote:Note;
        var skipOpCNote:CastNote;
        var skipBfCNote:CastNote;
        var skipNoteSplash:Note = new Note();
        var showAgain = false;
        var isCanPass = false;
        var isDisplay = false;
        var timeLimit = false;
        var noteJudge = false;

        var castHold = false;
        var castMust = false;
        var fixedPosition:Float = 0;
        var iDist:Array<Float> = [];
        var lDist:Array<Float> = [];
        var dist:Array<Float> = [];
        var availNoteData:Int = 0;

        var susEnds:Array<Bool> = [];

        inline function initSpawnInfo(casted:CastNote) {
                noteDataInfo = casted.noteData;
                castHold = toBool(noteDataInfo & (1<<9));
                castMust = toBool(noteDataInfo & (1<<8));
                availNoteData = (noteDataInfo & 0xFF) + (castMust ? totalColumns : 0);
                prevSus[availNoteData] = currSus[availNoteData];
                currSus[availNoteData] = castHold;
                
                shownTime = showNotes ? castHold ? Math.max(spawnTime / songSpeed, globalElapsed * 1000) : spawnTime / songSpeed : 0;
                shownRealTime = shownTime * 0.001;
        }
        var spawnBPM:Float = 100; //just because
        
        var currSus:Array<Bool> = [];
        var prevSus:Array<Bool> = [];

        var skipNoteFrom:CastNote;
        var skipNoteData:Int;
        var rangeCastHold:Bool;
        var rangeCastMust:Bool;
        var rangeLane:Int;
        inline function applySkipRange(from:Int, to:Int) {
                skipNoteFrom = unspawnNotes[from];
                skipNoteData = 0;

                while (from < to) {
                        skipNoteFrom = unspawnNotes[from];

                        if (skipNoteFrom.cmpSpam != null) {
                                spamNotes.push({
                                        remaining: (skipNoteFrom.cmpSpam[0]),
                                        density: skipNoteFrom.cmpSpam[1],
                                        seedNote: skipNoteFrom
                                });

                                skipNoteFrom.cmpSpam = null;
                                continue;
                        }
                        skipNoteData = skipNoteFrom.noteData;

                        rangeCastHold = (skipNoteData & (1 << 9)) != 0;
                        rangeCastMust = (skipNoteData & (1 << 8)) != 0;
                        rangeLane = (skipNoteData & 0xFF) + (rangeCastMust ? totalColumns : 0);

                        skipHit[rangeLane] = true;

                        if (cpuControlled) {
                                if (!rangeCastHold)
                                        rangeCastMust ? skipBf += skipNoteFrom.density ?? 1 : skipOp += skipNoteFrom.density ?? 1;
                        } else {
                                rangeCastMust ? noteMissCommon(rangeLane) : skipOp += skipNoteFrom.density ?? 1;
                        }

                        if (enableHoldSplash && rangeCastHold && (skipNoteData & (1 << 10)) != 0)
                                susEnds[rangeLane] = true;

                        if (enableSplash && !rangeCastHold &&
                                (cpuControlled || !rangeCastMust) &&
                                splashMoment[rangeLane] < splashCount)
                        {
                                if (splashUsing[rangeLane].length < splashCount) {
                                        skipNoteSplash.recycleNote(skipNoteFrom);
                                        spawnNoteSplashOnNote(skipNoteSplash);
                                }
                        }

                        if (rangeCastMust) skipBfCNote = skipNoteFrom; else skipOpCNote = skipNoteFrom;
                        ++from;
                }
        }

        var firstId:Int;
        var lastId:Int;
        var middleId:Int;
        var middleNote:CastNote;
        inline function findSkipBoundary(start:Int, fp:Float):Int {
                firstId = start;
                lastId = unspawnNotes.length;

                while (firstId < lastId) {
                        middleId = (firstId + lastId) >>> 1;
                        middleNote = unspawnNotes[middleId];

                        if (fp > middleNote.strumTime)
                                firstId = middleId + 1;
                        else
                                lastId = middleId;
                }

                return firstId;
        }

        inline function fastSkipRegularNotes(fp:Float):Bool {
                if ((!optimizeSpawnNote && !skipSpawnNote) || !bulkSkip)
                        return false;

                lastId = findSkipBoundary(currentId, fp);

                if (lastId > currentId) {
                        applySkipRange(currentId, lastId);
                        currentId = lastId;
                        return true;
                }

                return false;
        }
        
        // Do not declare inside loops. This causes memory leaks.
        var prevStrumTime:Float;
        var bulkSkipCount:Float;
        var noteInterval:Float;
        function spamSpawn() {
                for (spam in spamNotes) {
                        fixedPosition = Conductor.songPosition - ClientPrefs.data.noteOffset;
                        limitCount = notes.countLiving();

                        initSpawnInfo(spam.seedNote);
                        isDisplay = spam.seedNote.strumTime - fixedPosition < shownTime;

                        while (isDisplay && limitCount < limitNotes)
                        {
                                prevStrumTime = spam.seedNote.strumTime;
                                canBeHit = fixedPosition > spam.seedNote.strumTime; // false is before, true is after
                                timeLimit = (nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp()) - timeout < shownRealTime;

                                isCanPass = !skipSpawnNote || (keepNotes ? !canBeHit : timeLimit);
                                if (showAfter) {
                                        if (!showAgain && !canBeHit) {
                                                showAgain = true;
                                                lDist = []; dist = [];
                                                lDist.resize((Main.mania + 1) * 2); dist.resize((Main.mania + 1) * 2); iDist.resize((Main.mania + 1) * 2);
                                                timeout = nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp();
                                        }
                                }
                                if ((!canBeHit || !optimizeSpawnNote) && isCanPass) spawn(spam.seedNote);
                                else {
                                        bulkSkipCount = 0;
                                        noteInterval = (15000 / spawnBPM) / spam.density;
                                        if (spam.seedNote.strumTime < fixedPosition) {
                                                // Only skip notes that are fully in the past
                                                bulkSkipCount = Math.ffloor((fixedPosition - spam.seedNote.strumTime) / noteInterval) - 1;
                                                bulkSkipCount = Math.min(bulkSkipCount, spam.remaining);
                                        }
                                        if (bulkSkipCount > 0) {
                                                spam.seedNote.strumTime += bulkSkipCount * noteInterval;
                                                spam.remaining -= bulkSkipCount;
                                                // Update skip counters
                                                if (castMust) skipBf += bulkSkipCount;
                                                else skipOp += bulkSkipCount;
                                                skipCnt += bulkSkipCount;
                                                if (castMust) skipBfCNote = spam.seedNote; else skipOpCNote = spam.seedNote;

                                                if (spam.remaining <= 0) {
                                                        spamNotes.remove(spam);
                                                        break;
                                                }
                                        }
                                        skipNote(spam.seedNote);
                                }

                                if (spam.remaining > 0)
                                        spam.remaining--;
                                else { spamNotes.remove(spam); break; }
                                spam.seedNote.strumTime += (15000/spawnBPM)/spam.density;
                                spawnBPM = Conductor.getBPMFromSeconds(spam.seedNote.strumTime).bpm;

                                initSpawnInfo(spam.seedNote);
                                isDisplay = spam.seedNote.strumTime - fixedPosition < shownTime && spam.seedNote.strumTime != prevStrumTime;
                                timeLimit = (nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp()) - timeout < shownRealTime;
                        }
                }
        }

        public function noteSpawn()
        {
                timeout = nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp();

                lDist = []; dist = [];
                lDist.resize((Main.mania + 1) * 2); dist.resize((Main.mania + 1) * 2); iDist.resize((Main.mania + 1) * 2);
                
                fixedPosition = Conductor.songPosition - ClientPrefs.data.noteOffset;
                limitCount = notes.countLiving();

                fastSkipRegularNotes(fixedPosition);

                if (unspawnNotes.length > currentId)
                {
                        targetNote = unspawnNotes[currentId];
                        initSpawnInfo(targetNote);
                        isDisplay = targetNote.strumTime - fixedPosition < shownTime;
                        var notesProcessedThisFrame:Int = 0;

                        while (isDisplay && limitCount < limitNotes)
                        {
                                if (smoothHighScroll && songSpeed >= 2.5 && notesProcessedThisFrame >= smoothHighScrollLimit) break;
                                notesProcessedThisFrame++;
                                canBeHit = fixedPosition > targetNote.strumTime; // false is before, true is after
                                tooLate = fixedPosition > targetNote.strumTime + noteKillOffset;
                                noteJudge = castHold ? tooLate : canBeHit;
                                timeLimit = (nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp()) - timeout < shownRealTime;

                                isCanPass = !skipSpawnNote || (keepNotes ? !tooLate : timeLimit);

                                if (targetNote.cmpSpam != null) {
                                        spamNotes.push({
                                                remaining: (targetNote.cmpSpam[0]),
                                                density: targetNote.cmpSpam[1],
                                                seedNote: targetNote
                                        });

                                        targetNote.cmpSpam = null;
                                        spamSpawn();
                                } else {
                                        if (showAfter) {
                                                if (!showAgain && !canBeHit) {
                                                        showAgain = true;
                                                        lDist = []; dist = [];
                                                        lDist.resize((Main.mania + 1) * 2); dist.resize((Main.mania + 1) * 2); iDist.resize((Main.mania + 1) * 2);
                                                        timeout = nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp();
                                                }
                                        }

                                        if ((!noteJudge || !optimizeSpawnNote) && isCanPass) {
                                                spawn(targetNote);
                                        } else {
                                                skipNote(targetNote);
                                        }
                                }
                                
                                if (unspawnNotes.length > ++currentId) targetNote = unspawnNotes[currentId]; else break;

                                initSpawnInfo(targetNote);
                                isDisplay = targetNote.strumTime - fixedPosition < shownTime;
                        }
                }
                safeTime = ((nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp()) - timeout) / shownRealTime * 100;
                
                if (sortingWay == 1) {
                        if (ClientPrefs.data.fastSort)
                                notes.fasterSort();
                        else noteSortShortCut();
                }

                timeout = nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp();
                spamSpawn();
        }
        
        function spawn(targetNote:CastNote) {
                if (betterRecycle) {
                        dunceNote = notes.spawnNote(targetNote);
                } else dunceNote = notes.recycle(Note).recycleNote(targetNote);

                strumGroup = dunceNote.mustPress ? playerStrums : opponentStrums;
                dunceNote.strum = strumGroup.members[dunceNote.noteData];
                if (dunceNote.strum == null) dunceNote.visible = false; // safety: no matching lane
                
                dist[availNoteData] = 0.45 * (Conductor.songPosition - dunceNote.strumTime) * songSpeed;

                if (hideOverlapped > 0) {
                        iDist[availNoteData] = dist[availNoteData] - lDist[availNoteData];
                        dunceNote.visible = prevSus[availNoteData] != currSus[availNoteData] || Math.abs(iDist[availNoteData]) >= hideOverlapped;
                        // trace(availNoteData, prevSus[availNoteData], currSus[availNoteData], numFormat(dist[availNoteData], 3), numFormat(lDist[availNoteData], 3), dunceNote.visible ? "shown" : "hideeeeeeeeeeeeeeeeeeeee");
                        if (dunceNote.visible) {
                                lDist[availNoteData] = dist[availNoteData];
                                if (ClientPrefs.data.noteShaders) {
                                        dunceNote.rgbShader.enabled = true;
                                        dunceNote.defaultRGB();
                                        if (dunceNote.hitCausesMiss) {
                                                dunceNote.rgbShader.r = 0xFF101010;
                                                dunceNote.rgbShader.g = 0xFFFF0000;
                                                dunceNote.rgbShader.b = 0xFF990022;
                                        }
                                }
                        } else dunceNote.rgbShader.enabled = false;
                } else dunceNote.visible = true;

                if (spawnNoteEvent) {
                        callOnLuas('onSpawnNote', [
                                currentId,
                                dunceNote.noteData,
                                dunceNote.noteType,
                                dunceNote.isSustainNote,
                                dunceNote.strumTime
                        ]);
                        callOnHScript('onSpawnNote', [dunceNote]);
                }

                if (processFirst) {
                        if (dunceNote.visible && dunceNote.strum != null) {
                                dunceNote.followStrumNote(songSpeed, dist[availNoteData]);
                                if (canBeHit && dunceNote.isSustainNote && dunceNote.strum.sustainReduce) {
                                        dunceNote.clipToStrumNote();
                                }
                                ++shownCnt;
                        }
                } else ++shownCnt;
                ++limitCount;
        }

        function skipNote(targetNote:CastNote) {
                // Skip notes without spawning
                skipHit[availNoteData] = true;
                if (!timeLimit) ++skipTimeOut;

                if (cpuControlled) {
                        if (!castHold) castMust ? skipBf += targetNote.density ?? 1 : skipOp += targetNote.density ?? 1;
                } else castMust ? noteMissCommon(availNoteData) : skipOp += targetNote.density ?? 1;

                if (enableHoldSplash) susEnds[availNoteData] = (targetNote.noteData & 1<<10) > 0;
                
                if (enableSplash) {
                        if (!castHold && (cpuControlled || !castMust) &&
                                splashMoment[availNoteData] < splashCount && splashUsing[availNoteData].length < splashCount)
                        {
                                skipNoteSplash.recycleNote(targetNote);
                                spawnNoteSplashOnNote(skipNoteSplash);
                        }
                }

                if (castMust) skipBfCNote = targetNote; else skipOpCNote = targetNote;
        }

        var noteUpdateJudge:Bool = false;
        var processedReal:Int = 0;
        var processedRealTimer:Float = 0;
        var processedRealElapsed:Float = 0;
        public function noteUpdate()
        {
                if (generatedMusic)
                {
                        if (debugInfos) {
                                processedReal = 0;
                                processedRealTimer = nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp();
                        }

                        checkEventNote();

                        if (!inCutscene)
                        {
                                cpuControlled ? playerDance() : keysCheck();

                                if (notes.length > 0)
                                {
                                        if (lastSongSpeed != songSpeed) {
                                                lDist = []; dist = [];
                                                lDist.resize((Main.mania + 1) * 2); dist.resize((Main.mania + 1) * 2); iDist.resize((Main.mania + 1) * 2);
                                        }
                                        if (startedCountdown)
                                        {
                                                notes.forEachAlive(daNote -> {
                                                        ++processedReal;

                                                        canBeHit = Conductor.songPosition - daNote.strumTime > 0;
                                                        tooLate = Conductor.songPosition - daNote.strumTime > noteKillOffset;
                                                        
                                                        if (tooLate) {
                                                                // Kill extremely late notes and cause misses
                                                                if (daNote.mustPress)
                                                                {
                                                                        if (cpuControlled)
                                                                                goodNoteHit(daNote);
                                                                        else if (!daNote.ignoreNote && !endingSong && daNote.tooLate || !daNote.wasGoodHit) {
                                                                                // trace(noteKillOffset, Conductor.stepCrochet);
                                                                                noteMiss(daNote);
                                                                        }
                                                                } else if (!daNote.hitByOpponent)
                                                                        opponentNoteHit(daNote);

                                                                invalidateNote(daNote);
                                                                canBeHit = false;
                                                        } else if (hideOverlapped > 0) {
                                                                availNoteData = daNote.noteData + (daNote.mustPress ? totalColumns : 0);
                                                                dist[availNoteData] = 0.45 * (Conductor.songPosition - daNote.strumTime) * songSpeed;
                                                                
                                                                if (lastSongSpeed != songSpeed) {
                                                                        currSus[availNoteData] = daNote.isSustainNote;
                                                                        iDist[availNoteData] = dist[availNoteData] - lDist[availNoteData];

                                                                        daNote.visible = prevSus[availNoteData] != currSus[availNoteData] || Math.abs(iDist[availNoteData]) >= hideOverlapped;
                                                                        if (daNote.visible) {
                                                                                lDist[availNoteData] = dist[availNoteData];
                                                                                if (ClientPrefs.data.noteShaders) {
                                                                                        daNote.rgbShader.enabled = true;
                                                                                        daNote.defaultRGB();
                                                                                }
                                                                        } else daNote.rgbShader.enabled = false;

                                                                        prevSus[availNoteData] = currSus[availNoteData];
                                                                }

                                                                if (daNote.visible) daNote.followStrumNote(songSpeed, dist[availNoteData]);
                                                                ++shownCnt;
                                                        } else {
                                                                daNote.followStrumNote(songSpeed, 0.45 * (Conductor.songPosition - daNote.strumTime) * songSpeed); ++shownCnt;
                                                        }
                                                
                                                        if (canBeHit) {
                                                                if (daNote.mustPress) {
                                                                        if (!daNote.blockHit || daNote.isSustainNote) {
                                                                                if (cpuControlled) goodNoteHit(daNote);
                                                                                else if (!toBool(pressHit & 1<<daNote.noteData) && 
                                                                                        daNote.isSustainNote && !daNote.wasGoodHit && 
                                                                                Conductor.songPosition - daNote.strumTime > Conductor.stepCrochet) noteMiss(daNote);
                                                                        }
                                                                } else if (!daNote.hitByOpponent && !daNote.ignoreNote || daNote.isSustainNote)
                                                                        opponentNoteHit(daNote);

                                                                if (daNote.isSustainNote && daNote.strum.sustainReduce) {
                                                                        daNote.clipToStrumNote();
                                                                }
                                                        }
                                                });
                                        }
                                        else
                                        {
                                                notes.forEachAlive(daNote ->
                                                {
                                                        daNote.canBeHit = false;
                                                        daNote.wasGoodHit = false;
                                                });
                                        }
                                }
                        }
                        processedRealElapsed = (nanoPosition ? CoolUtil.getNanoTime() : Timer.stamp()) - processedRealTimer;
                }

                if (sortingWay == 2) {
                        if (ClientPrefs.data.fastSort)
                                notes.fasterSort();
                        else noteSortShortCut();
                }
        }

        var skipResult:Dynamic = null;
        var loopVector:Vector<Note> = new Vector(2, new Note());
        var skipArray:Array<Dynamic> = [];
        var skipAnim:Vector<Bool> = new Vector(3, false);
        var skipHitSearch:Int;
        public function noteFinalize() {
                skipAnim.fill(false);
                skipCnt = skipOp + skipBf;

                if (skipCnt > 0) {
                        if (!ClientPrefs.data.worldRecordModeFixed) {
                                opCombo += skipOp; opSideHit += skipOp;
                                combo += skipBf; bfSideHit += skipBf;
                        }
                        skipTotalCnt += skipCnt;

                        if (skipOp > 0 && !camZooming) camZooming = true;

                        skipHitSearch = totalColumns * 2 - 1;
                        while (skipHitSearch >= 0) {
                                if (skipHit[skipHitSearch])
                                        strumPlayAnim(skipHitSearch < totalColumns, skipHitSearch % totalColumns, false);
                                --skipHitSearch;
                        }
                        
                        if (enableHoldSplash) {
                                for (index in 0...susEnds.length) {
                                        if (susEnds[index]) susplashMap[index].showEndSplash();
                                        susEnds[index] = false;
                                }
                        }

                        skipAnim[0] = skipCnt > 0;
                        skipAnim[1] = skipOp > 0;
                        skipAnim[2] = skipBf > 0;

                        if (skipAnim[0]) {
                                if (skipAnim[1]) {
                                        if (betterRecycle) loopVector[0] = skipNotes.spawnNote(skipOpCNote);
                                        else loopVector[0] = skipNotes.recycle(Note).recycleNote(skipOpCNote);
                                        doAnim(loopVector[0]);
                                }
                                if (skipAnim[2] && cpuControlled) {
                                        if (betterRecycle) loopVector[1] = skipNotes.spawnNote(skipBfCNote);
                                        else loopVector[1] = skipNotes.recycle(Note).recycleNote(skipBfCNote);
                                        doAnim(loopVector[1]);
                                }

                                if (showPopups) {
                                        if (!changePopup && skipAnim[2]) popUpHitNote = loopVector[1];
                                        else if (changePopup && skipAnim[0]) {
                                                popUpHitNote = skipAnim[2] ? loopVector[1] : loopVector[0];
                                        }
                                }

                                if (skipNoteEvent) {
                                        var scriptTarget = [skipOp, skipBf];
                                        for (index => skippedAmount in scriptTarget) {
                                                if (skippedAmount == 0) continue;
                                                else if (index == 1 && !cpuControlled) break;

                                                var daNote = loopVector[index];
                                                skipArray = [0, Std.int(Math.abs(daNote.noteData)), daNote.noteType, daNote.isSustainNote];

                                                var targetStr = index == 0 ? 'opponent' : 'good';
                                                for (i in 0...Std.int(skippedAmount)) {
                                                        if (noteHitPreEvent) scriptCall(targetStr + 'NoteHitPre', [daNote]);
                                                        if (noteHitEvent) scriptCall(targetStr + 'NoteHit', [daNote]);
                                                }
                                        }
                                }
                        }
                }

                healthUpdate(bfHitFrame + skipBf + bfHitSus, opHitFrame + skipOp + opHitSus);
        }
        
        inline function scriptCall(funcName:String, hsArgs:Dynamic) {
                skipResult = callOnLuas(funcName, skipArray);
                if (skipResult != LuaUtils.Function_Stop)
                        if (skipResult != LuaUtils.Function_StopHScript)
                                if (skipResult != LuaUtils.Function_StopAll)
                                        skipResult = callOnHScript(funcName, hsArgs);
        }
        
        var sortOrder = false;
        inline function noteSortShortCut(reverse:Bool = false) {
                ArraySort.sort(notes.members, (note1, note2) -> reverse ? NoteGroup.noteSort(note2, note1) : NoteGroup.noteSort(note1, note2));
        }
        
        inline function noteSort() {
                switch (sortingWay) {
                        case 3, 4:
                                sortOrder = sortingWay == 4;
                                if (ClientPrefs.data.fastSort)
                                        notes.fasterSort(sortOrder);
                                else
                                        noteSortShortCut(sortOrder);
                        case 5:
                                noteSortShortCut(frameCount & 1 == 0);
                        case 6:
                                noteSortShortCut(FlxG.random.bool());
                        case 7:
                                FlxG.random.shuffle(notes.members);
                }
        }

        var altAnim:String;
        var curSec:SwagSection;
        var holdTime:Float = Conductor.stepCrochet / 1000;
        var canAnim:Vector<Bool> = new Vector(3, true);
        var animTarget:Int = 0;
        var isNullNote:Bool = false;

        /**
         * Force dance animation on the character.
         * if objectNote is null, It uses bf and daddy flag
         * for decide target to animation. that case, 
         * girlfriend will never dance.
         * 
         * @param objectNote 
         * @param bf 
         * @param daddy 
         */
        private function doAnim(objectNote:Note, mustHit:Bool = false) {
                isNullNote = objectNote == null;
                
                if (isNullNote) char = mustHit ? boyfriend : dad;
                else char = objectNote.gfNote ? gf : objectNote.mustPress ? boyfriend : dad;
                
                animTarget = if (char == dad) 0;
                                else if (char == boyfriend) 1;
                                else if (char == gf) 2;
                                else -1;

                if (animTarget == -1) return;
                
                if (char != null)
                {
                        if (canAnim[animTarget]) {
                                if (!isNullNote) {
                                        altAnim = objectNote.animSuffix;
                                        animCheck = objectNote.gfNote ? 'cheer' : 'hey';
                                        animToPlay = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, objectNote.noteData)))];
                                } else {
                                        animToPlay = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, FlxG.random.int(0, 4))))];
                                }

                                if (curSec != null) {
                                        if (curSec.altAnim && !curSec.gfSection)
                                                altAnim = '-alt';
                                } else if (altAnim != '') altAnim = '';

                                char.playAnim(animToPlay + altAnim, true);
                                char.holdTimer = 0;

                                if (!isNullNote && objectNote.noteType == 'Hey!') {
                                        if (char.animOffsets.exists(animCheck)) {
                                                char.playAnim(animCheck, true);
                                                char.specialAnim = true;
                                                char.heyTimer = 0.6;
                                        }
                                }

                                canAnim[animTarget] = false;
                        }
                }
        }

        var iconsAnimations:Bool = true;

        function set_health(value:Float):Float // You can alter how icon animations work here
        {
                // value = FlxMath.roundDecimal(value, 5); // Fix Float imprecision
                if (!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null)
                {
                        health = value;
                        return health;
                }

                // update health bar
                health = value;
                var newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max),
                        healthBar.bounds.min, healthBar.bounds.max, 0, 100);
                healthBar.percent = (newPercent != null ? newPercent : 0);

                if (healthBar.percent < 20) {
                        // If health is under 20%,
                        // change player icon to frame 1 (losing icon) and
                        // change opponent icon to frame 2 (winning icon if available)
                        iconP1.animation.curAnim.curFrame = 1;
                        iconP2.animation.curAnim.curFrame = iconP2.iconCnt > 2 ? 2 : 0;
                } else if (healthBar.percent > 80) {
                        // If health is over 80%,
                        // change opponent icon to frame 1 (losing icon) and
                        // change player icon to frame 2 (winning icon if available)
                        iconP1.animation.curAnim.curFrame = iconP1.iconCnt > 2 ? 2 : 0;
                        iconP2.animation.curAnim.curFrame = 1;
                } else {
                        // otherwise, frame 0 (normal)
                        iconP1.animation.curAnim.curFrame = 0;
                        iconP2.animation.curAnim.curFrame = 0;
                }

                return health;
        }
        
        inline function healthLerper():Float
        {
                return vsliceSmoothBar ? FlxMath.lerp(healthLerp, health, vsliceSmoothNess) : health;
        }

        var diffCnt:Float = 0;
        var diffMin:Float = 0;
        var loseHealth:Float = 0;
        function healthUpdate(bf:Float, op:Float) {
                loseHealth = 1.00 - 0.01 * healthLoss;
                if (healthDrain) {
                        if (practiceMode) {
                                health += bf * hitHealth * healthGain - op * 0.02 * healthLoss;
                        } else {
                                diffCnt = bf - op;
                                diffMin = Math.min(bf, op);
                                if (drainAccuracy > 0) diffMin = Math.min(diffMin, drainAccuracy);
                                
                                while (diffMin > 0) {
                                        health = (health + hitHealth) * loseHealth;
                                        --diffMin;
                                }

                                if (diffCnt < 0) // opponent has more notes than boyfriend
                                        health = Math.max(0.1e-320, health * Math.pow(loseHealth, -diffCnt));
                                else if (diffCnt > 0) // boyfriend has more notes than opponent
                                        health += hitHealth * diffCnt * healthGain;
                        }
                } else health += bf * hitHealth * healthGain;
        }

        var cancelCount:Int = 0;
        var pauseTimer:FlxTimer;
        function openPauseMenu()
        {
                if (ffmpegMode && !previewRender) {
                        if (cancelCount < 3) {
                                FlxG.sound.play(Paths.sound('cancelMenu'), ClientPrefs.data.sfxVolume).pitch = cancelCount * 0.2 + 1;
                                Eseq.pln(3 - cancelCount + " presses left to escape the rendering.");
                                ++cancelCount;
                        } else {
                                FlxG.fixedTimestep = false;
                                Eseq.pln("you escaped the rendering succesfully.");
                                finishSong();
                        }

                        if (pauseTimer != null) pauseTimer.cancel();
                        pauseTimer = new FlxTimer().start(3, _ -> {
                                cancelCount = 0;
                                FlxG.sound.play(Paths.sound('cancelMenu'), ClientPrefs.data.sfxVolume).pitch = 0.5;
                                Eseq.pln("Cancelled to escape rendering.\nWait build up for video.");
                        });
                        
                        return;
                }

                FlxG.camera.followLerp = 0;
                persistentUpdate = false;
                persistentDraw = true;
                paused = true;

                if (FlxG.sound.music != null)
                {
                        FlxG.sound.music.pause();
                        if (bfVocal) vocals.pause();
                        if (opVocal) opponentVocals.pause();
                }
                if (!cpuControlled)
                {
                        for (note in playerStrums)
                                if (note.animation.curAnim != null && note.animation.curAnim.name != 'static')
                                {
                                        note.playAnim('static');
                                        note.resetAnim = 0;
                                }
                }
                openSubState(new PauseSubState());

                #if DISCORD_ALLOWED
                if (autoUpdateRPC) {
                        songText = '${SONG.song} ($storyDifficultyText)';
                        DiscordClient.changePresence(detailsPausedText, songText, iconP2.getCharacter());
                }
                #end
        }

        public function openChartEditor()
        {
                canResync = false;
                FlxG.camera.followLerp = 0;
                persistentUpdate = false;
                paused = true;

                if (FlxG.sound.music != null)
                        FlxG.sound.music.stop();
                
                if (bfVocal) vocals.pause();
                if (opVocal) opponentVocals.pause();

                #if DISCORD_ALLOWED
                DiscordClient.changePresence("Chart Editor", null, null, true);
                DiscordClient.resetClientID();
                #end

                MusicBeatState.switchState(new ChartingState(!chartingMode));
                chartingMode = true;
        }

        function openCharacterEditor()
        {
                canResync = false;
                FlxG.camera.followLerp = 0;
                persistentUpdate = false;
                paused = true;

                if (FlxG.sound.music != null)
                        FlxG.sound.music.stop();
                if (bfVocal) vocals.pause();
                if (opVocal) opponentVocals.pause();

                #if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
                MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
        }

        public var isDead:Bool = false; // Don't mess with this on Lua!!!
        public var gameOverTimer:FlxTimer;
        function doDeathCheck(?skipHealthCheck:Bool = false)
        {
                if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !isDead && gameOverTimer == null)
                {
                        var ret = callOnScripts('onGameOver', null, true);
                        if (ret != LuaUtils.Function_Stop)
                        {
                                FlxG.animationTimeScale = 1;
                                boyfriend.stunned = true;
                                deathCounter++;

                                paused = true;
                                canResync = false;
                                canPause = false;
                                #if VIDEOS_ALLOWED
                                if(videoCutscene != null)
                                {
                                        videoCutscene.destroy();
                                        videoCutscene = null;
                                }
                                #end

                                persistentUpdate = false;
                                persistentDraw = false;
                                FlxTimer.globalManager.clear();
                                FlxTween.globalManager.clear();
                                FlxG.camera.filters = [];

                                if (GameOverSubstate.deathDelay > 0)
                                {
                                        gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_)
                                        {
                                                if (bfVocal) vocals.stop();
                                                if (opVocal) opponentVocals.stop();
                                                FlxG.sound.music.stop();
                                                openSubState(new GameOverSubstate(boyfriend));
                                                gameOverTimer = null;
                                        });
                                }
                                else
                                {
                                        if (bfVocal) vocals.stop();
                                        if (opVocal) opponentVocals.stop();
                                        FlxG.sound.music.stop();
                                        openSubState(new GameOverSubstate(boyfriend));
                                }

                                // MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

                                #if DISCORD_ALLOWED
                                // Game Over doesn't get his its variable because it's only used here
                                if (autoUpdateRPC) {
                                        songText = '${SONG.song} ($storyDifficultyText)';
                                        DiscordClient.changePresence("Game Over - " + detailsText, songText, iconP2.getCharacter());
                                }
                                #end
                                isDead = true;
                                return true;
                        }
                }
                return false;
        }

        public function checkEventNote()
        {
                while (eventNotes.length > 0)
                {
                        var leStrumTime:Float = eventNotes[0].strumTime;
                        if (Conductor.songPosition < leStrumTime)
                        {
                                return;
                        }

                        var value1:String = '';
                        if (eventNotes[0].value1 != null)
                                value1 = eventNotes[0].value1;

                        var value2:String = '';
                        if (eventNotes[0].value2 != null)
                                value2 = eventNotes[0].value2;

                        triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
                        eventNotes.shift();
                }
        }

        public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float)
        {
                var flValue1:Null<Float> = Std.parseFloat(value1);
                var flValue2:Null<Float> = Std.parseFloat(value2);
                if (Math.isNaN(flValue1))
                        flValue1 = null;
                if (Math.isNaN(flValue2))
                        flValue2 = null;

                switch (eventName)
                {
                        case 'Hey!':
                                var value:Int = 2;
                                switch (value1.toLowerCase().trim())
                                {
                                        case 'bf' | 'boyfriend' | '0':
                                                value = 0;
                                        case 'gf' | 'girlfriend' | '1':
                                                value = 1;
                                }

                                if (flValue2 == null || flValue2 <= 0)
                                        flValue2 = 0.6;

                                if (value != 0)
                                {
                                        if (dad.curCharacter.startsWith('gf'))
                                        { // Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
                                                dad.playAnim('cheer', true);
                                                dad.specialAnim = true;
                                                dad.heyTimer = flValue2;
                                        }
                                        else if (gf != null)
                                        {
                                                gf.playAnim('cheer', true);
                                                gf.specialAnim = true;
                                                gf.heyTimer = flValue2;
                                        }
                                }
                                if (value != 1)
                                {
                                        boyfriend.playAnim('hey', true);
                                        boyfriend.specialAnim = true;
                                        boyfriend.heyTimer = flValue2;
                                }

                        case 'Set GF Speed':
                                if (flValue1 == null || flValue1 < 1)
                                        flValue1 = 1;
                                gfSpeed = Math.round(flValue1);

                        case 'Add Camera Zoom':
                                if (ClientPrefs.data.camZooms && FlxG.camera.zoom < 10)
                                {
                                        if (flValue1 == null)
                                                flValue1 = 0.015;
                                        if (flValue2 == null)
                                                flValue2 = 0.03;

                                        FlxG.camera.zoom += flValue1;
                                        camHUD.zoom += flValue2;
                                }

                        case 'Play Animation':
                                // trace('Anim to play: ' + value1);
                                var char:Character = dad;
                                switch (value2.toLowerCase().trim())
                                {
                                        case 'bf' | 'boyfriend':
                                                char = boyfriend;
                                        case 'gf' | 'girlfriend':
                                                char = gf;
                                        default:
                                                if (flValue2 == null)
                                                        flValue2 = 0;
                                                switch (Math.round(flValue2))
                                                {
                                                        case 1: char = boyfriend;
                                                        case 2: char = gf;
                                                }
                                }

                                if (char != null)
                                {
                                        char.playAnim(value1, true);
                                        char.specialAnim = true;
                                }

                        case 'Camera Follow Pos':
                                if (camFollow != null)
                                {
                                        isCameraOnForcedPos = false;
                                        if (flValue1 != null || flValue2 != null)
                                        {
                                                isCameraOnForcedPos = true;
                                                if (flValue1 == null)
                                                        flValue1 = 0;
                                                if (flValue2 == null)
                                                        flValue2 = 0;
                                                camFollow.x = flValue1;
                                                camFollow.y = flValue2;
                                        }
                                }

                        case 'Alt Idle Animation':
                                var char:Character = dad;
                                switch (value1.toLowerCase().trim())
                                {
                                        case 'gf' | 'girlfriend':
                                                char = gf;
                                        case 'boyfriend' | 'bf':
                                                char = boyfriend;
                                        default:
                                                var val:Int = Std.parseInt(value1);
                                                if (Math.isNaN(val))
                                                        val = 0;

                                                switch (val)
                                                {
                                                        case 1: char = boyfriend;
                                                        case 2: char = gf;
                                                }
                                }

                                if (char != null)
                                {
                                        char.idleSuffix = value2;
                                        char.recalculateDanceIdle();
                                }

                        case 'Screen Shake':
                                var valuesArray:Array<String> = [value1, value2];
                                var targetsArray:Array<FlxCamera> = [camGame, camHUD];
                                for (i in 0...targetsArray.length)
                                {
                                        var split:Array<String> = valuesArray[i].split(',');
                                        var duration:Float = 0;
                                        var intensity:Float = 0;
                                        if (split[0] != null)
                                                duration = Std.parseFloat(split[0].trim());
                                        if (split[1] != null)
                                                intensity = Std.parseFloat(split[1].trim());
                                        if (Math.isNaN(duration))
                                                duration = 0;
                                        if (Math.isNaN(intensity))
                                                intensity = 0;

                                        if (duration > 0 && intensity != 0)
                                        {
                                                targetsArray[i].shake(intensity, duration);
                                        }
                                }

                        case 'Change Character':
                                var charType:Int = 0;
                                switch (value1.toLowerCase().trim())
                                {
                                        case 'gf' | 'girlfriend':
                                                charType = 2;
                                        case 'dad' | 'opponent':
                                                charType = 1;
                                        default:
                                                charType = Std.parseInt(value1);
                                                if (Math.isNaN(charType)) charType = 0;
                                }

                                switch (charType)
                                {
                                        case 0:
                                                if (boyfriend.curCharacter != value2)
                                                {
                                                        if (!boyfriendMap.exists(value2))
                                                        {
                                                                addCharacterToList(value2, charType);
                                                        }

                                                        var lastAlpha:Float = boyfriend.alpha;
                                                        boyfriend.shader = null; //? remove the shader
                                                        boyfriend.alpha = 0.00001;
                                                        boyfriend = boyfriendMap.get(value2);
                                                        boyfriend.alpha = lastAlpha;
                                                        iconP1.changeIcon(boyfriend.healthIcon, boyfriend.healthIconDivider);
                                                }
                                                setOnScripts('boyfriendName', boyfriend.curCharacter);

                                        case 1:
                                                if (dad.curCharacter != value2)
                                                {
                                                        if (!dadMap.exists(value2))
                                                        {
                                                                addCharacterToList(value2, charType);
                                                        }

                                                        var wasGf:Bool = dad.curCharacter.startsWith('gf-') || dad.curCharacter == 'gf';
                                                        var lastAlpha:Float = dad.alpha;
                                                        dad.shader = null; //? remove the shader
                                                        dad.alpha = 0.00001;
                                                        dad = dadMap.get(value2);
                                                        if (!dad.curCharacter.startsWith('gf-') && dad.curCharacter != 'gf')
                                                        {
                                                                if (wasGf && gf != null)
                                                                {
                                                                        gf.visible = true;
                                                                }
                                                        }
                                                        else if (gf != null)
                                                        {
                                                                gf.visible = false;
                                                        }
                                                        dad.alpha = lastAlpha;
                                                        iconP2.changeIcon(dad.healthIcon, dad.healthIconDivider);
                                                }
                                                setOnScripts('dadName', dad.curCharacter);

                                        case 2:
                                                if (gf != null)
                                                {
                                                        if (gf.curCharacter != value2)
                                                        {
                                                                if (!gfMap.exists(value2))
                                                                {
                                                                        addCharacterToList(value2, charType);
                                                                }

                                                                var lastAlpha:Float = gf.alpha;
                                                                gf.shader = null; //? remove the shader
                                                                gf.alpha = 0.00001;
                                                                gf = gfMap.get(value2);
                                                                gf.alpha = lastAlpha;
                                                        }
                                                        setOnScripts('gfName', gf.curCharacter);
                                                }
                                }
                                reloadHealthBarColors();

                        case 'Change Scroll Speed':
                                lastSongSpeed = songSpeed;
                                if (songSpeedType == "multiplicative")
                                {
                                        if (flValue1 == null) flValue1 = 1;
                                        if (flValue2 == null) flValue2 = 0;

                                        var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
                                        
                                        if (flValue2 <= 0) {
                                                songSpeed = newValue;
                                                songSpeedRate = flValue1;
                                        } else {
                                                songSpeedTween = FlxTween.tween(
                                                        this,
                                                        {
                                                                songSpeed: newValue,
                                                                songSpeedRate: flValue1
                                                        },
                                                        flValue2 / playbackRate,
                                                        {
                                                                ease: FlxEase.linear,
                                                                onComplete: function(twn:FlxTween)
                                                                {
                                                                        songSpeedTween = null;
                                                                }
                                                        }
                                                );
                                        }
                                }

                        case 'Vslice Scroll Speed':
                                if (songSpeedType == "multiplicative")
                                {
                                        if (flValue1 == null) flValue1 = 1;
                                        if (flValue2 == null) flValue2 = 0;

                                        var newValue:Float = ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
                                        if (flValue2 <= 0) {
                                                songSpeed = newValue;
                                                songSpeedRate = flValue1;
                                        } else {
                                                songSpeedTween = FlxTween.tween(
                                                        this, 
                                                        {
                                                                songSpeed: newValue,
                                                                songSpeedRate: flValue1
                                                        }, 
                                                        flValue2 / playbackRate, 
                                                        {
                                                                ease: FlxEase.quadInOut,
                                                                onComplete: function(twn:FlxTween)
                                                                {
                                                                        songSpeedTween = null;
                                                                }
                                                        }
                                                );
                                        }
                                }

                        case 'Set Property':
                                try
                                {
                                        var trueValue:Dynamic = value2.trim();
                                        if (trueValue == 'true' || trueValue == 'false')
                                                trueValue = trueValue == 'true';
                                        else if (flValue2 != null)
                                                trueValue = flValue2;
                                        else
                                                trueValue = value2;

                                        var split:Array<String> = value1.split('.');
                                        if (split.length > 1)
                                        {
                                                LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1], trueValue);
                                        }
                                        else
                                        {
                                                LuaUtils.setVarInArray(this, value1, trueValue);
                                        }
                                }
                                catch (e:Dynamic)
                                {
                                        var errorMsg = "";
                                        if(e.message != null){
                                                var len:Int = e.message.indexOf('\n') + 1;
                                                if(len <= 0) len = e.message.length;
                                                errorMsg = e.message.substr(0, len);
                                        }
                                        #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                                        addTextToDebug('ERROR ("Set Property" Event) - ' + errorMsg, FlxColor.RED);
                                        #else
                                        FlxG.log.warn('ERROR ("Set Property" Event) - ' + errorMsg);
                                        #end
                                }

                        case 'Rainbow Eyesore':
                                if (shaderEnabled && ClientPrefs.data.flashing && curStep < Std.parseInt(value1))
                                {
                                        allowDisable = false;
                                        allowDisableAt = Std.parseInt(value1);
                                        FlxG.camera.filters = [new ShaderFilter(masterPulse.shader)];
                                        
                                        masterPulse.waveAmplitude = 1;
                                        masterPulse.waveFrequency = 2;
                                        masterPulse.waveSpeed = Std.parseFloat(value2);
                                        masterPulse.shader.uTime.value[0] = FlxG.random.float(-1e3, 0);
                                        masterPulse.shader.uampmul.value[0] = 1;
                                        masterPulse.enabled = true;
                                }
                        
                        case 'Change Botplay Text':
                                if (!ffmpegMode) botplayTxt.text = value1;
                        
                        case 'Popup', 'Popup (No Pause)':
                                if (!ClientPrefs.data.worldRecordModeFixed)
                                {
                                        var doPause:Bool = !eventName.contains("Pause");
                                        if (doPause) {
                                                FlxG.sound.music.pause();
                                                if (bfVocal) vocals.pause();
                                                if (opVocal) opponentVocals.pause();
                                        }
                                        
                                        CoolUtil.showPopUp(value1, value2);

                                        if (doPause) {
                                                FlxG.sound.music.resume();
                                                if (bfVocal) vocals.resume();
                                                if (opVocal) opponentVocals.resume();
                                        }
                                }

                        case 'Play Sound':
                                if(flValue2 == null) flValue2 = 1;
                                FlxG.sound.play(Paths.sound(value1), flValue2);
                }

                stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
                callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
        }

        public function moveCameraSection(?sec:Null<Int>):Void
        {
                if (sec == null)
                        sec = curSection;
                if (sec < 0)
                        sec = 0;

                if (SONG.notes[sec] == null)
                        return;

                if (gf != null && SONG.notes[sec].gfSection)
                {
                        moveCameraToGirlfriend();
                        callOnScripts('onMoveCamera', ['gf']);
                        return;
                }

                var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
                moveCamera(isDad);
                if (isDad)
                        callOnScripts('onMoveCamera', ['dad']);
                else
                        callOnScripts('onMoveCamera', ['boyfriend']);
        }

        public function moveCameraToGirlfriend()
        {
                camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
                camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
                camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
                tweenCamIn();
        }

        var cameraTwn:FlxTween;

        public function moveCamera(isDad:Bool)
        {
                if (isDad)
                {
                        if (dad == null)
                                return;
                        camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
                        camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
                        camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
                        tweenCamIn();
                }
                else
                {
                        if (boyfriend == null)
                                return;
                        camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
                        camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
                        camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

                        if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
                        {
                                cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, 60 / Conductor.bpm, {
                                        ease: FlxEase.elasticInOut,
                                        onComplete: function(twn:FlxTween)
                                        {
                                                cameraTwn = null;
                                        }
                                });
                        }
                }
        }

        public function tweenCamIn()
        {
                if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3)
                {
                        cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, 60 / Conductor.bpm, {
                                ease: FlxEase.elasticInOut,
                                onComplete: function(twn:FlxTween)
                                {
                                        cameraTwn = null;
                                }
                        });
                }
        }

        public function finishSong(?ignoreNoteOffset:Bool = false):Void
        {
                updateTime = false;
                FlxG.sound.music.volume = 0;

                if (!ffmpegMode) {
                        if (bfVocal) {
                                vocals.volume = 0;
                                vocals.pause();
                        }
                        if (opVocal) {
                                opponentVocals.volume = 0;
                                opponentVocals.pause();
                        }

                        if (ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) 
                                endCallback();
                        else {
                                finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, tmr ->
                                {
                                        endCallback();
                                });
                        }
                } else endCallback();
        }

        public var transitioning = false;

        public function endSong()
        {
                #if TOUCH_CONTROLS_ALLOWED
                hitbox.visible = #if !android touchPad.visible = #end false;
                #end

                timeBar.visible = false;
                timeTxt.visible = false;
                canPause = false;
                endingSong = true;
                camZooming = false;
                inCutscene = false;
                updateTime = false;

                deathCounter = 0;
                seenCutscene = false;

                #if ACHIEVEMENTS_ALLOWED
                var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
                checkForAchievement([weekNoMiss, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger']);
                #end

                var ret = callOnScripts('onEndSong', null, true);
                var accPts = ratingPercent * totalPlayed;
                if (ret != LuaUtils.Function_Stop && !transitioning)
                {
                        var tempActiveTallises = {
                                score: songScore,
                                accPoints: accPts,

                                sick: ratingsData[0].hits,
                                good: ratingsData[1].hits,
                                bad: ratingsData[2].hits,
                                shit: ratingsData[3].hits,
                                missed: songMisses,
                                combo: combo,
                                maxCombo: maxCombo,
                                totalNotesHit: totalPlayed,
                                totalNotes: 69.0,
                        };

                        playbackRate = 1;

                        if (chartingMode)
                        {
                                openChartEditor();
                                return false;
                        }

                        if (isStoryMode)
                        {
                                campaignScore += songScore;
                                campaignMisses += songMisses;
                                campaignSaveData = FunkinTools.combineTallies(campaignSaveData, tempActiveTallises);

                                storyPlaylist.remove(storyPlaylist[0]);

                                #if !switch
                                        //!! We have to save the score for current song BEFORE loading the next one
                                        if(!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay')){
                                                var percent:Float = ratingPercent;
                                                if(Math.isNaN(percent)) percent = 0;
                                                Highscore.saveScore(SONG.song, songScore, storyDifficulty, percent,songMisses == 0);
                                        }
                                #end

                                if (storyPlaylist.length <= 0)
                                {
                                        var prevScore = Highscore.getWeekScore(WeekData.weeksList[storyWeek], storyDifficulty);
                                        var wasFC = Highscore.getWeekFC(WeekData.weeksList[storyWeek], storyDifficulty);
                                        var prevAcc = Highscore.getWeekAccuracy(WeekData.weeksList[storyWeek], storyDifficulty);

                                        var prevRank = Scoring.calculateRankFromData(prevScore, prevAcc, wasFC);
                                        // FlxG.sound.playMusic(Paths.music('freakyMenu'));
                                        #if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

                                        canResync = false;

                                        if (!practiceMode && !cpuControlled)
                                        {
                                                StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);

                                                var weekAccuracy = FlxMath.bound(campaignSaveData.accPoints / campaignSaveData.totalNotesHit, 0, 1);
                                                Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty, weekAccuracy, campaignMisses == 0);

                                                FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
                                                FlxG.save.flush();
                                        }
                                        zoomIntoResultsScreen(prevScore < campaignSaveData.score, campaignSaveData, prevRank);
                                        campaignSaveData = FunkinTools.newTali();

                                        changedDifficulty = false;
                                        leavePlayState = true;
                                }
                                else
                                {
                                        var difficulty:String = Difficulty.getFilePath();

                                        trace('LOADING NEXT SONG');
                                        var songLowercase:String = Paths.formatToSongPath(PlayState.storyPlaylist[0]);
                                        trace(songLowercase + difficulty);

                                        FlxTransitionableState.skipNextTransIn = true;
                                        FlxTransitionableState.skipNextTransOut = true;
                                        prevCamFollow = camFollow;

                                        Song.loadFromJson(songLowercase + difficulty, false, songLowercase);
                                        
                                        FlxG.sound.music.stop();

                                        canResync = false;
                                        LoadingState.prepareToSong();
                                        LoadingState.loadAndSwitchState(new PlayState(), false);
                                }
                        }
                        else
                        {
                                trace('WENT BACK TO FREEPLAY??');
                                var wasFC = Highscore.getFCState(curSong, PlayState.storyDifficulty);
                                var prevScore = Highscore.getScore(curSong, PlayState.storyDifficulty);
                                var prevAcc = Highscore.getRating(curSong, PlayState.storyDifficulty);

                                var prevRank = Scoring.calculateRankFromData(prevScore, prevAcc, wasFC);

                                #if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

                                canResync = false;
                                
                                zoomIntoResultsScreen(prevScore < tempActiveTallises.score, tempActiveTallises, prevRank);
                                changedDifficulty = false;

                                #if !switch
                                if (!practiceMode && !cpuControlled)
                                {
                                        var percent:Float = ratingPercent;
                                        if (Math.isNaN(percent))
                                                percent = 0;
                                        Highscore.saveScore(SONG.song, songScore, storyDifficulty, percent, songMisses == 0);
                                }
                                #end
                                leavePlayState = true;
                        }

                        transitioning = true;
                }
                
                unspawnNotes.resize(0);
                loaded = false;
                return true;
        }

        /**
         * Play the camera zoom animation and then move to the results screen once it's done.
         */
        function zoomIntoResultsScreen(isNewHighscore:Bool, scoreData:SaveScoreData, prevScoreRank:ScoringRank):Void
        {
                if (!ClientPrefs.data.vsliceResults || cpuControlled || practiceMode)
                {
                        var resultingAccuracy = Math.min(1, scoreData.accPoints / scoreData.totalNotesHit);
                        var fpRank = Scoring.calculateRankFromData(scoreData.score, resultingAccuracy, scoreData.missed == 0) ?? SHIT;
                        if (isNewHighscore && !isStoryMode)
                        {
                                camOther.fade(FlxColor.BLACK, 0.6, false, () ->
                                {
                                        if (ClientPrefs.data.vsliceFreeplay) {
                                                FlxTransitionableState.skipNextTransOut = true;
                                                FlxG.switchState(() -> NewFreeplayState.build({
                                                        {
                                                                fromResults: {
                                                                        oldRank: prevScoreRank,
                                                                        newRank: fpRank,
                                                                        songId: curSong,
                                                                        difficultyId: Difficulty.getString(),
                                                                        playRankAnim: !cpuControlled
                                                                }
                                                        }
                                                }));
                                        } else {
                                                MusicBeatState.switchState(new FreeplayState());
                                                FlxG.sound.playMusic(Paths.music('freakyMenu'), ClientPrefs.data.bgmVolume);
                                                changedDifficulty = false;
                                        }
                                });
                        }
                        else if (!isStoryMode)
                        {
                                if (ClientPrefs.data.vsliceFreeplay) {
                                        FlxTransitionableState.skipNextTransIn = true;
                                        FlxTransitionableState.skipNextTransOut = true;
                                        openSubState(new StickerSubState(null, (sticker) -> NewFreeplayState.build({
                                                {
                                                        fromResults: {
                                                                oldRank: null,
                                                                playRankAnim: false,
                                                                newRank: fpRank,
                                                                songId: curSong,
                                                                difficultyId: Difficulty.getString()
                                                        }
                                                }
                                        }, sticker)));
                                } else {
                                        FlxTransitionableState.skipNextTransIn = false;
                                        FlxTransitionableState.skipNextTransOut = false;
                                        MusicBeatState.switchState(new FreeplayState());
                                        FlxG.sound.playMusic(Paths.music('freakyMenu'), ClientPrefs.data.bgmVolume);
                                        changedDifficulty = false;
                                }
                        }
                        else
                        {
                                openSubState(new StickerSubState(null, (sticker) -> new StoryMenuState(sticker)));
                        }
                        return;
                }
                trace('WENT TO RESULTS SCREEN!');

                // If the opponent is GF, zoom in on the opponent.
                // Else, if there is no GF, zoom in on BF.
                // Else, zoom in on GF.
                var targetDad:Bool = dad != null && dad.curCharacter == 'gf';
                var targetBF:Bool = gf == null && !targetDad;

                if (targetBF)
                {
                        FlxG.camera.follow(boyfriend, null, 0.05);
                }
                else if (targetDad)
                {
                        FlxG.camera.follow(dad, null, 0.05);
                }
                else
                {
                        FlxG.camera.follow(gf, null, 0.05);
                }

                // TODO: Make target offset configurable.
                // In the meantime, we have to replace the zoom animation with a fade out.
                FlxG.camera.targetOffset.y -= 350;
                FlxG.camera.targetOffset.x += 20;

                // Replace zoom animation with a fade out for now.
                FlxG.camera.fade(FlxColor.BLACK, 0.6);

                FlxTween.tween(camHUD, {alpha: 0}, 0.6, {
                        onComplete: function(_)
                        {
                                moveToResultsScreen(isNewHighscore, scoreData, prevScoreRank);
                        }
                });

                // Zoom in on Girlfriend (or BF if no GF)
                new FlxTimer().start(0.8, function(_)
                {
                        if (targetBF)
                        {
                                boyfriend.animation.play('hey');
                        }
                        else if (targetDad)
                        {
                                dad.animation.play('cheer');
                        }
                        else
                        {
                                gf.animation.play('cheer');
                        }

                        // Zoom over to the Results screen.
                        // TODO: Re-enable this.
                        /*
                                                  FlxTween.tween(FlxG.camera, {zoom: 1200}, 1.1,
                                {
                                  ease: FlxEase.expoIn,
                                });
                         */
                });
        }

        /**
         * Move to the results screen right goddamn now.
         */
        function moveToResultsScreen(isNewHighscore:Bool, scoreData:SaveScoreData, prevScoreRank:ScoringRank):Void
        {
                persistentUpdate = false;

                var modManifest = Mods.getPack();
                var fpText = modManifest != null ? '${curSong} from ${modManifest.name}' : curSong;
                // Mods.loadTopMod();

                if (bfVocal) vocals.stop();
                camHUD.alpha = 1;

                var res:ResultState = new ResultState({
                        storyMode: isStoryMode,
                        songId: curSong,
                        difficultyId: Difficulty.getString(),
                        title: isStoryMode ? ('${storyCampaignTitle}') : fpText,
                        scoreData: scoreData,
                        prevScoreRank: prevScoreRank,
                        isNewHighscore: isNewHighscore,
                        characterId: SONG.player1
                });
                this.persistentDraw = false;
                openSubState(res);
        }

        public function KillNotes()
        {
                while (notes.length > 0)
                {
                        var daNote:Note = notes.members[0];
                        daNote.active = false;
                        daNote.visible = false;
                        invalidateNote(daNote);
                }
                unspawnNotes = [];
                eventNotes = [];
        }

        public var totalPlayed:Float = 0.0;
        public var totalNotesHit:Float = 0.0;
        
        // Stores Ratings and Combo Sprites in a group
        public var popUpGroup:PopupGroup;
        // Stores HUD Objects in a Group
        public var uiGroup:FlxSpriteGroup;
        // Stores Note Objects in a Group
        public var notesGroup:FlxTypedGroup<FlxBasic>;
        
        var uiPrefix:String = "";
        var uiPostfix:String = '';

        private function cachePopUpScore()
        {
                uiPrefix = '';
                uiPostfix = '';
                if (stageUI != "normal")
                {
                        uiPrefix = '${stageUI}UI/';
                        if (PlayState.isPixelStage)
                                uiPostfix = '-pixel';
                }

                if (showPopups)
                {
                        for (rating in ratingsData)
                                Paths.image(uiPrefix + rating.image + uiPostfix);
                        for (i in 0...10)
                                Paths.image(uiPrefix + 'num' + i + uiPostfix);
                }
        }
        
        var noteDiff:Float;
        var score:Float;
        var daRating:Rating;

        inline private function addScore(note:Note = null):Void
        {
                if (note == null) return;
                noteDiff = Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset);
                if (!cpuControlled && bfVocal) vocals.volume = ClientPrefs.data.bgmVolume;

                score = 350;

                //tryna do MS based judgment due to popular demand
                daRating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);

                totalNotesHit += daRating.ratingMod;
                note.ratingMod = daRating.ratingMod;
                if(!note.ratingDisabled) daRating.hits++;
                note.rating = daRating.name;
                score = daRating.score;

                if(!practiceMode) {
                        songScore += score;
                        if(!note.ratingDisabled)
                        {
                                songHits++;
                                totalPlayed++;
                                recalculateRating();
                        }
                }
        }

        var ratingPop:Popup = null;
        var comboPop:Popup = null;
        var numScore:Popup = null;
        var popUpAlive:Float = 0;
        private function popUpScore(note:Note = null):Void
        {
                var daloop:Null<Int> = 0;

                var seperatedScore:Array<Null<Float>> = [];
                var tempCombo:Null<Float> = changePopup ? combo + opCombo : combo;
                var tempNotes:Null<Float> = tempCombo;

                if (!ClientPrefs.data.comboStacking && popUpGroup.members.length > 0) {
                        for (spr in popUpGroup) {
                                if (spr.exists) spr.kill();
                        }
                }

                if (showRating && bfHit) {
                        ratingImage = cpuControlled ? forceSick.image : daRating.image;

                        ratingPop = popUpGroup.spawn();
                        ratingPop.setupRatingData(uiPrefix + ratingImage + uiPostfix);
                }

                if (showCombo && combo >= 10) {
                        comboPop = popUpGroup.spawn();
                        comboPop.setupComboData(uiPrefix + 'combo' + uiPostfix);
                }

                if (showComboNum) {
                        while(tempCombo >= 10) {
                                seperatedScore.unshift(Std.int(tempCombo / 10) % 10);
                                tempCombo /= 10;
                        }
                        seperatedScore.push(tempNotes % 10);

                        for (index => number in seperatedScore)
                        {       
                                var comboDigit = Std.string(tempNotes).length;
                                var delimiter = Std.int(index + 3 - comboDigit % 3);
                                var comma = numberDelimit && delimiter % 3 == 0;
                                if (changePopup || combo >= 10 || combo == 0) {
                                        numScore = popUpGroup.spawn();
                                        numScore.setupNumberData(uiPrefix + 'num' + Std.int(Math.abs(number)) + uiPostfix, index, comboDigit, numberDelimit);

                                        if (comma && index > 0 && commaImg) {
                                                numScore = popUpGroup.spawn();
                                                numScore.setupNumberData(uiPrefix + 'numComma' + uiPostfix, index, comboDigit, numberDelimit);
                                        }
                                }
                        }
                }

                popUpGroup.stableSort();

                for (i in seperatedScore) i = null;
                daloop = null; tempCombo = null;
        }

        public var strumsBlocked:Array<Bool> = [];

        private function onKeyPress(event:KeyboardEvent):Void
        {
                var eventKey:FlxKey = event.keyCode;
                var key:Int = getKeyFromEvent(keysArray[Main.mania], eventKey);

                if (!controls.controllerMode)
                {
                        #if debug
                        // Prevents crash specifically on debug without needing to try catch shit
                        @:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey))
                                return;
                        #end

                        if (FlxG.keys.checkStatus(eventKey, JUST_PRESSED))
                                keyPressed(key);
                }
        }

        private function keyPressed(key:Int)
        {
                if (cpuControlled || paused || inCutscene || key < 0 || key >= playerStrums.length || !generatedMusic || endingSong || boyfriend.stunned)
                        return;

                var ret = callOnScripts('onKeyPressPre', [key]);
                if (ret == LuaUtils.Function_Stop)
                        return;

                // more accurate hit time for the ratings?
                var lastTime:Float = Conductor.songPosition;
                if (Conductor.songPosition >= 0)
                        Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

                // obtain notes that the player can hit
                var plrInputNotes:Array<Note> = notes.members.filter(function(n:Note):Bool
                {
                        var canHit:Bool = n != null && !strumsBlocked[n.noteData] && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit;
                        return canHit && !n.isSustainNote && n.noteData == key;
                });
                plrInputNotes.sort(sortHitNotes);

                if (plrInputNotes.length != 0)
                { // slightly faster than doing `> 0` lol
                        var funnyNote:Note = plrInputNotes[0]; // front note

                        if (plrInputNotes.length > 1)
                        {
                                var doubleNote:Note = plrInputNotes[1];

                                if (doubleNote.noteData == funnyNote.noteData)
                                {
                                        // if the note has a 0ms distance (is on top of the current note), kill it
                                        if (Math.abs(doubleNote.strumTime - funnyNote.strumTime) < 1.0)
                                                invalidateNote(doubleNote);
                                        else if (doubleNote.strumTime < funnyNote.strumTime)
                                        {
                                                // replace the note if its ahead of time (or at least ensure "doubleNote" is ahead)
                                                funnyNote = doubleNote;
                                        }
                                }
                        }
                        goodNoteHit(funnyNote);
                        if (showPopups && popUpHitNote != null) popUpScore(funnyNote);
                }
                else
                {
                        if (ClientPrefs.data.ghostTapping)
                                callOnScripts('onGhostTap', [key]);
                        else
                                noteMissPress(key);
                }

                // Needed for the  "Just the Two of Us" achievement.
                //                                                                      - Shadow Mario
                if (!keysPressed.contains(key))
                        keysPressed.push(key);

                // more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
                Conductor.songPosition = lastTime;

                var spr:StrumNote = playerStrums.members[key];
                if (strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
                {
                        spr.playAnim('pressed');
                        spr.resetAnim = 0;
                }
                callOnScripts('onKeyPress', [key]);
        }

        public static function sortHitNotes(a:Note, b:Note):Int
        {
                if (a.lowPriority && !b.lowPriority)
                        return 1;
                else if (!a.lowPriority && b.lowPriority)
                        return -1;

                return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
        }

        private function onKeyRelease(event:KeyboardEvent):Void
        {
                var eventKey:FlxKey = event.keyCode;
                var key:Int = getKeyFromEvent(keysArray[Main.mania], eventKey);
                if (!controls.controllerMode && key > -1)
                        keyReleased(key);
        }

        private function keyReleased(key:Int)
        {
                if (cpuControlled || !startedCountdown || paused || key < 0 || key >= playerStrums.length)
                        return;

                var ret = callOnScripts('onKeyReleasePre', [key]);
                if (ret == LuaUtils.Function_Stop)
                        return;

                var spr:StrumNote = playerStrums.members[key];
                if (spr != null)
                {
                        spr.playAnim('static');
                        spr.resetAnim = 0;

                        if (enableHoldSplash) {
                                var susplash = grpHoldSplashes.members[key + totalColumns];
                                if (susplash != null && !susplash.ending) susplash.showEndSplash();
                        }
                }
                callOnScripts('onKeyRelease', [key]);
        }

        public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
        {
                if (key != NONE && Controls.instance != null)
                {
                        for (i in 0...arr.length)
                        {
                                var binds = Controls.instance.keyboardBinds[arr[i]];
                                if (binds == null) continue;
                                for (noteKey in binds)
                                        if (key == noteKey)
                                                return i;
                        }
                }
                return -1;
        }

        #if TOUCH_CONTROLS_ALLOWED
        private function onHintPress(button:TouchButton):Void
        {
                var buttonCode:Int = (button.IDs[0].toString().startsWith('HITBOX')) ? button.IDs[1] : button.IDs[0];
                callOnScripts('onHintPressPre', [buttonCode]);
                if (button.justPressed) keyPressed(buttonCode);
                callOnScripts('onHintPress', [buttonCode]);
        }

        private function onHintRelease(button:TouchButton):Void
        {
                var buttonCode:Int = (button.IDs[0].toString().startsWith('HITBOX')) ? button.IDs[1] : button.IDs[0];
                callOnScripts('onHintReleasePre', [buttonCode]);
                if(buttonCode > -1) keyReleased(buttonCode);
                callOnScripts('onHintRelease', [buttonCode]);
        }
        #end

        // Hold notes
        private function keysCheck():Void
        {
                var holdArray:Array<Bool> = [];
                var pressArray:Array<Bool> = [];
                var releaseArray:Array<Bool> = [];
                pressHit = 0;
                for (index => key in (keysArray[Main.mania]:Array<String>))
                {
                        holdArray.push(controls.pressed(key)); 
                        pressArray.push(controls.justPressed(key));
                        releaseArray.push(controls.justReleased(key));
                        pressHit |= holdArray[index] ? 1<<index : 0;
                }

                // TO DO: Find a better way to handle controller inputs, this should work for now
                if (controls.controllerMode && pressArray.contains(true))
                        for (i in 0...pressArray.length)
                                if (pressArray[i] && strumsBlocked[i] != true)
                                        keyPressed(i);

                if (startedCountdown && !inCutscene && !boyfriend.stunned && generatedMusic)
                {
                        if (notes.length > 0)
                        {
                                for (n in notes)
                                { // I can't do a filter here, that's kinda awesome
                                        var canHit:Bool = (n != null && !strumsBlocked[n.noteData] && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit);

                                        if (canHit && n.isSustainNote && n.strumTime < Conductor.songPosition)
                                        {
                                                // var released:Bool = !;

                                                if (holdArray[n.noteData]) {
                                                        goodNoteHit(n);
                                                }
                                        }
                                }
                        }

                        if (!holdArray.contains(true) || endingSong)
                                playerDance();

                        #if ACHIEVEMENTS_ALLOWED
                        else
                                checkForAchievement(['oversinging']);
                        #end
                }

                // TO DO: Find a better way to handle controller inputs, this should work for now
                if ((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
                        for (i in 0...releaseArray.length)
                                if (releaseArray[i] || strumsBlocked[i] == true)
                                        keyReleased(i);
        }

        function noteMiss(daNote:Note):Void
        { // You didn't hit the key and let it go offscreen, also used by Hurt Notes
                if (daNote.missed) return;
                if (andreNewHUDEnabled && daNote.mustPress && !daNote.isSustainNote) andreNewComboPlayer = 0;
                if (andreLuaHUDEnabled && daNote.mustPress && !daNote.isSustainNote) andreLuaComboPlayer = 0;
                // Dupe note remove
                notes.forEachAlive( note -> {
                        if (daNote != note
                                && daNote.mustPress
                                && daNote.noteData == note.noteData
                                && daNote.isSustainNote == note.isSustainNote
                                && Math.abs(daNote.strumTime - note.strumTime) < 1)
                                invalidateNote(note);
                });

                noteMissCommon(daNote.noteData, daNote);
                stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote));
                result = callOnLuas('noteMiss', [
                        notes.members.indexOf(daNote),
                        daNote.noteData,
                        daNote.noteType,
                        daNote.isSustainNote
                ]);
                if (result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll)
                        callOnHScript('noteMiss', [daNote]);
                result = null;
                // end = null;
        }
        
        // You pressed a key when there was no notes to press for this key
        // It's only works when ghost tapping disabled
        function noteMissPress(direction:Int = 1):Void 
        {
                if (ClientPrefs.data.ghostTapping) return; // fuck it

                noteMissCommon(direction);
                FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
                stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction));
                callOnScripts('noteMissPress', [direction]);
        }

        function noteMissCommon(direction:Int, note:Note = null)
        {
                // score and data
                var subtract:Float = pressMissDamage;
                if (note != null)
                        subtract = note.missHealth;

                if (instakillOnMiss)
                {
                        if (bfVocal) vocals.volume = 0;
                        if (opVocal) opponentVocals.volume = 0;
                        if (!practiceMode) doDeathCheck(true);
                }

                // please don't send issue about this lmao. i added it for fun.
                if (instacrashOnMiss) {
                        throw "You missed the NOTE! HAHAHA";
                }

                if (note != null) {
                        var index:Int = (note.mustPress ? totalColumns : 0) + direction;
                        if (enableHoldSplash && note.isSustainNote && susplashMap[index].holding) {
                                susplashMap[index].kill();
                        }
                }

                var lastCombo:Float = combo;
                combo = 0;

                health -= subtract * healthLoss;
                if (!practiceMode)
                        songScore -= 10;
                if (!endingSong)
                        songMisses++;
                totalPlayed++;
                // trace(health, subtract, healthLoss);
                recalculateRating(true);

                // play character anims
                var char:Character = boyfriend;
                if ((note != null && note.gfNote) || (curSec != null && curSec.gfSection))
                        char = gf;

                if (char != null && (note == null || !note.noMissAnimation) && char.hasMissAnimations)
                {
                        var postfix:String = '';
                        if (note != null)
                                postfix = note.animSuffix;

                        var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length - 1, direction)))] + 'miss' + postfix;
                        char.playAnim(animToPlay, true);

                        if (char != gf && lastCombo > 5 && gf != null && gf.hasAnimation('sad'))
                        {
                                gf.playAnim('sad');
                                gf.specialAnim = true;
                        }
                }

                if (bfVocal) vocals.volume = 0;
                if (note != null)note.missed = true;
        }

        var result:Dynamic;
        var char:Character;
        var animToPlay:String;
        var canPlay:Bool;
        var holdAnim:String;
        function opponentNoteHit(note:Note):Void
        {
                if (andreHUDEnabled && !note.isSustainNote) { if (ClientPrefs.data.andreGhostDensity) { andreOppNotes += Std.int(Math.max(1, note.density)); } else { andreOppNotes++; andreOppHits.push(Conductor.songPosition); } }
                if (andreLuaHUDEnabled && !note.isSustainNote) {
                        if (ClientPrefs.data.andreGhostDensity) {
                                andreLuaComboOpp += Std.int(Math.max(1, note.density));
                                andreLuaComboTotal += Std.int(Math.max(1, note.density));
                        } else {
                                andreLuaComboOpp++;
                                andreLuaComboTotal++;
                        }
                        andreLuaOppHits.push(Conductor.songPosition);
                }
                if (andreNewHUDEnabled && !note.isSustainNote) {
                        if (ClientPrefs.data.andreGhostDensity) {
                            andreNewComboOpp += Std.int(Math.max(1, note.density));
                            andreNewComboTotal += Std.int(Math.max(1, note.density));
                        } else {
                            andreNewComboOpp++;
                            andreNewComboTotal++;
                        }
                        andreNewOppHits.push(Conductor.songPosition);
                }
                if (note.hitByOpponent) return;

                if (noteHitPreEvent) {
                        result = callOnLuas('opponentNoteHitPre', [
                                notes.members.indexOf(note),
                                Math.abs(note.noteData),
                                note.noteType,
                                note.isSustainNote
                        ]);

                        if (result != LuaUtils.Function_Stop) {
                                if(result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll)
                                        result = callOnHScript('opponentNoteHitPre', [note]);
                        } else {
                                result = null;
                                return;
                        }
                        result = null;
                }

                if (songName != 'tutorial')
                        camZooming = true;
                globalNoteHit = true;

                if (opHit && note.sustainLength > 0) opHit = false;
                
                if (!opHit) {
                        if (note.noteType == 'Hey!' && dad.hasAnimation('hey'))
                        {
                                dad.playAnim('hey', true);
                                dad.specialAnim = true;
                                dad.heyTimer = 0.6;
                        }
                        else if (!note.noAnimation)
                        {
                                char = dad;
                                animToPlay = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length - 1, note.noteData)))] + note.animSuffix;
                                if (note.gfNote)
                                        char = gf;

                                if (char != null)
                                {
                                        canPlay = !note.isSustainNote || sustainAnim;
                                        if (note.isSustainNote)
                                        {
                                                holdAnim = animToPlay + '-hold';
                                                if (char.animation.exists(holdAnim))
                                                        animToPlay = holdAnim;
                                                if (char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop')
                                                        canPlay = false;
                                        }

                                        if (canPlay)
                                                char.playAnim(animToPlay, true);
                                        char.holdTimer = 0;
                                }
                        }
                        if (!ffmpegMode) {
                                if (opVocal) opponentVocals.volume = ClientPrefs.data.bgmVolume;
                                else if (bfVocal) vocals.volume = ClientPrefs.data.bgmVolume;
                        }
                }

                strumPlayAnim(true, note.noteData, note.isSustainNote && !note.isSustainEnds);
                note.hitByOpponent = true;

                if (noteHitStage) {
                        stagesFunc(stage -> stage.opponentNoteHit(note));
                }

                if (noteHitEvent) {
                        result = callOnLuas('opponentNoteHit', [
                                notes.members.indexOf(note),
                                Math.abs(note.noteData),
                                note.noteType,
                                note.isSustainNote
                        ]);
                        if (result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll)
                                callOnHScript('opponentNoteHit', [note]);
                        result = null;
                }

                if (splashOpponent && !note.noteSplashData.disabled) {
                        if (enableHoldSplash && note.isSustainNote) spawnHoldSplash(note);
                        if (enableSplash && !note.isSustainNote) spawnNoteSplashOnNote(note);
                }
        
                ++opHitFrame;
                if (!note.isSustainNote) {                      
                        opCombo += note.density; opSideHit += note.density; opHit = true;
                        if (showPopups && changePopup) popUpHitNote = note;
                        invalidateNote(note);
                }
        }

        var animCheck:String;
        var hitHealth:Float = 0.02;
        public function goodNoteHit(note:Note):Void
        {
                if (andreHUDEnabled && !note.isSustainNote) { if (ClientPrefs.data.andreGhostDensity) { andrePlayerNotes += Std.int(Math.max(1, note.density)); } else { andrePlayerNotes++; andrePlayerHits.push(Conductor.songPosition); } }
                if (andreLuaHUDEnabled && !note.isSustainNote) {
                        if (ClientPrefs.data.andreGhostDensity) {
                                andreLuaComboPlayer += Std.int(Math.max(1, note.density));
                                andreLuaComboTotal += Std.int(Math.max(1, note.density));
                        } else {
                                andreLuaComboPlayer++;
                                andreLuaComboTotal++;
                        }
                        andreLuaPlayerHits.push(Conductor.songPosition);
                }
                if (andreNewHUDEnabled && !note.isSustainNote) {
                        if (ClientPrefs.data.andreGhostDensity) {
                            andreNewComboPlayer += Std.int(Math.max(1, note.density));
                            andreNewComboTotal += Std.int(Math.max(1, note.density));
                        } else {
                            andreNewComboPlayer++;
                            andreNewComboTotal++;
                        }
                        andreNewPlayerHits.push(Conductor.songPosition);
                }
                if (note.wasGoodHit || cpuControlled && note.ignoreNote)
                        return;
                
                if (noteHitPreEvent) {
                        result = callOnLuas('goodNoteHitPre', [
                                notes.members.indexOf(note),
                                Math.round(Math.abs(note.noteData)),
                                note.noteType,
                                note.isSustainNote
                        ]);
                        
                        if (result != LuaUtils.Function_Stop) {
                                if(result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll)
                                        result = callOnHScript('opponentNoteHitPre', [note]);
                        } else {
                                result = null;
                                return;
                        }
                        result = null;
                }

                if (songName != 'tutorial')
                        camZooming = true;
                note.wasGoodHit = true;

                if (bfHit && note.sustainLength > 0) bfHit = false;
                
                if (!ffmpegMode && !bfHit && note.hitsoundVolume > 0 && !note.hitsoundDisabled)
                        FlxG.sound.play(Paths.sound(note.hitsound), note.hitsoundVolume);

                if (!note.hitCausesMiss) // Common notes
                {
                        if (!bfHit)
                        {
                                if (!note.noAnimation) {
                                        animToPlay = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length - 1, note.noteData)))] + note.animSuffix;

                                        char = boyfriend;
                                        animCheck = 'hey';
                                        if (note.gfNote)
                                        {
                                                char = gf;
                                                animCheck = 'cheer';
                                        }

                                        if (char != null)
                                        {
                                                canPlay = !note.isSustainNote || sustainAnim;
                                                if (note.isSustainNote)
                                                {
                                                        holdAnim = animToPlay + '-hold';
                                                        if (char.animation.exists(holdAnim))
                                                                animToPlay = holdAnim;
                                                        if (char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop')
                                                                canPlay = false;
                                                }

                                                if (canPlay) {
                                                        char.playAnim(animToPlay, true);
                                                }
                                                char.holdTimer = 0;

                                                if (note.noteType == 'Hey!')
                                                {
                                                        if (char.hasAnimation(animCheck))
                                                        {
                                                                char.playAnim(animCheck, true);
                                                                char.specialAnim = true;
                                                                char.heyTimer = 0.6;
                                                        }
                                                }
                                        }
                                }

                                if (!ffmpegMode && bfVocal) vocals.volume = ClientPrefs.data.bgmVolume;
                        }

                        if (!cpuControlled)
                        {
                                playerStrums.members[note.noteData].playAnim('confirm', true);
                        } else strumPlayAnim(false, note.noteData, note.isSustainNote && !note.isSustainEnds);
                        
                        ++bfHitFrame;
                        if (!note.isSustainNote)
                        {
                                var comboInc:Float = ClientPrefs.data.worldRecordModeFixed ? 1 : note.density;
                                combo += comboInc; bfSideHit += comboInc; globalNoteHit = true;
                                maxCombo = Math.max(maxCombo, combo);
                                if (showPopups) popUpHitNote = note;
                                if (!cpuControlled) addScore(note);
                        }

                        bfHit = true;
                        hitHealth = note.hitHealth;
                }
                else // Notes that count as a miss if you hit them (Hurt notes for example)
                {
                        if (!bfHit && !note.noMissAnimation)
                        {
                                switch (note.noteType)
                                {
                                        case 'Hurt Note':
                                                if (boyfriend.hasAnimation('hurt'))
                                                {
                                                        boyfriend.playAnim('hurt', true);
                                                        boyfriend.specialAnim = true;
                                                        bfHit = true;
                                                }
                                }
                        }

                        noteMiss(note);
                }

                if (!note.noteSplashData.disabled) {
                        if (enableHoldSplash && note.isSustainNote) spawnHoldSplash(note);
                        if (enableSplash && !note.isSustainNote) spawnNoteSplashOnNote(note);
                }

                if (noteHitStage) {
                        stagesFunc(stage -> stage.goodNoteHit(note));
                }

                if (noteHitEvent) {
                        result = callOnLuas('goodNoteHit', 
                                [
                                        notes.members.indexOf(note),
                                        Math.round(Math.abs(note.noteData)),
                                        note.noteType,
                                        note.isSustainNote
                                ]
                        );

                        if (result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll)
                                callOnHScript('goodNoteHit', [note]);
                        result = null;
                }

                if (!note.isSustainNote) invalidateNote(note);
        }

        public function invalidateNote(note:Note):Void {
                if (!note.exists) return;
                note.exists = note.visible = false;
                if (betterRecycle) notes.push(note);
        }

        public static var susplashMap:Vector<SustainSplash> = new Vector(8);

        public function spawnHoldSplash(note:Note) {
                if (note == null || note.strum == null) return;
                var susplashIndex = (note.mustPress ? totalColumns : 0) + note.noteData;
                var susplash = susplashMap[susplashIndex];
                var isUsedSplash = susplash.holding;

                if (!isUsedSplash || isUsedSplash && note.isSustainEnds) {
                        var holdSplashStrum = note.mustPress ? playerStrums.members[note.noteData] : opponentStrums.members[note.noteData];
                        if (note.strum != splashStrum) note.strum = holdSplashStrum;

                        susplash.setupSusSplash(note, playbackRate);
                        
                        if (!isUsedSplash) {
                                // trace("Index " + susplashIndex + " was added.");
                                grpHoldSplashes.add(susplash);
                        }
                }
        }
        
        var splashNoteData:Int = 0;
        var frames:Int = -1;
        var frameId:Int = -1;
        var targetSplash:NoteSplash = null;
        var splashStrum:StrumNote;

        public function spawnNoteSplashOnNote(note:Note)
        {
                if (!note.mustPress && !splashOpponent)
                        return;
                splashNoteData = note.noteData + (note.mustPress ? totalColumns : 0);
                if (splashMoment[splashNoteData] < splashCount)
                {
                        frameId = frames = -1;
                        splashStrum = note.mustPress ? playerStrums.members[note.noteData] : opponentStrums.members[note.noteData];
                        if (note.strum != splashStrum) note.strum = splashStrum;
                        
                        if (splashUsing[splashNoteData].length >= splashCount)
                        {
                                for (index => splash in splashUsing[splashNoteData])
                                {
                                        if (splash.alive && frames < splash.animation.curAnim.curFrame)
                                        {
                                                frames = splash.animation.curAnim.curFrame;
                                                frameId = index;
                                                targetSplash = splash;
                                        }
                                }
                                // trace(splashNoteData, splashUsing[splashNoteData].length, frameId);
                                if (frameId != -1) targetSplash.killLimit(frameId);
                        }
                        spawnNoteSplash(note, splashNoteData);
                        ++splashMoment[splashNoteData];
                }
        }

        var playerSplash:NoteSplash;

        public function spawnNoteSplash(note:Note, splashNoteData:Int = -1)
        {
                playerSplash = grpNoteSplashes.recycle(NoteSplash);
                if (note != null) {
                        playerSplash.babyArrow = note.strum;
                } else playerSplash.babyArrow = (splashNoteData < totalColumns ? opponentStrums.members[splashNoteData] : playerStrums.members[splashNoteData - totalColumns]);
                // trace(splashNoteData);
                playerSplash.spawnSplashNote(note, splashNoteData);
                if (splashNoteData >= 0) {
                        splashUsing[splashNoteData].push(playerSplash);
                }
                grpNoteSplashes.add(playerSplash);
        }

        override function destroy()
        {
                if (psychlua.CustomSubstate.instance != null)
                {
                        closeSubState();
                        resetSubState();
                }

                #if LUA_ALLOWED
                for (lua in luaArray)
                {
                        lua.call('onDestroy', []);
                        lua.stop();
                }
                luaArray = null;
                FunkinLua.customFunctions.clear();
                #end

                #if HSCRIPT_ALLOWED
                for (script in hscriptArray)
                        if (script != null)
                        {
                                script.call('onDestroy');
                                script.destroy();
                        }

                hscriptArray = null;
                #end
                stagesFunc(stage -> stage.destroy());

                FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
                FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

                FlxG.camera.filters = [];
                FlxG.maxElapsed = 0.1;

                #if FLX_PITCH FlxG.sound.music.pitch = 1; #end
                FlxG.animationTimeScale = 1;

                Note.globalRgbShaders = [];
                backend.NoteTypesConfig.clearNoteTypesData();
                NoteSplash.configs.clear();
                instance = null;
                
                Paths.noteSkinFramesMap.clear();
                Paths.noteSkinAnimsMap.clear();
                Paths.popUpFramesMap.clear();
                Note.chartArrowSkin = null;

                if (leavePlayState) SONG = null;
                notes.clear();
                spamNotes = [];
                
                #if desktop
                if (ffmpegMode) {
                        FlxG.fixedTimestep = false;
                        FlxG.timeScale = 1;
                        if (unlockFPS) {
                                FlxG.drawFramerate = ClientPrefs.data.framerate;
                                FlxG.updateFramerate = ClientPrefs.data.framerate;
                        }
                        if (!previewRender) video.destroy();

                        FlxG.stage.application.window.vsync = ClientPrefs.data.vsync;
                        ClientPrefs.data.noteOffset = backupOffset;

                        if (video.wentPreview != null) ClientPrefs.data.previewRender = false;
                }
                #end

                inPlayState = false;
                super.destroy();
        }

        var lastStepHit:Float = -1;

        override function stepHit()
        {
                super.stepHit();

                if (curStep == lastStepHit)
                {
                        return;
                }

                lastStepHit = curStep;
                setOnScripts('curStep', curStep);
                callOnScripts('onStepHit');
        }

        var lastBeatHit:Float = -1;
        var beatRatio:Float = 1;
        var bopRatio:Float = 1;
        var hpRatio:Float = 1;

        var multPlusX:Float = 0;
        var multPlusY:Float = 0;
        var angle:Float = 0;

        override function beatHit()
        {
                if (lastBeatHit > curBeat)
                {
                        // trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
                        return;
                }

                if (Math.abs(curDecBeat % 1) < Math.abs(prevDecBeat % 1 - 1))
                        beatRatio = curDecBeat % 1;
                else beatRatio = prevDecBeat % 1 - 1;
                bopRatio = 1 - beatRatio;

                if (iconBopType != "None") {
                        for (index => icon in [iconP2, iconP1]) {
                                angle = 0;
                                switch (iconBopType) {
                                        case 'Default':
                                                multPlusX = multPlusY = 0.2;
                                        case 'Horizontal':
                                                multPlusX = 0.2;
                                                multPlusY = -0.4;
                                        case 'Vertical':
                                                multPlusX = -0.4;
                                                multPlusY = 0.2;
                                        case 'Drill':
                                                multPlusX = 0.6;
                                                // multPlusY = 0.0;
                                                angle = (index == 0 ? 25 : -25);
                                        case 'HRK Style':
                                                if ((curBeat % 2 == 0) == (index == 0)) { // Simulate XNOR branch
                                                        multPlusX = 0.8;
                                                        multPlusY = 0.2;
                                                        angle = 30;
                                                } else {
                                                        multPlusX = 0.2;
                                                        multPlusY = 0.15;
                                                        angle = -20;
                                                }
                                }

                                // if (icon.flipX) angle = -angle;
                                
                                if (iconStrength) {
                                        hpRatio = Math.max(index == 0 ? 2 - healthLerp : healthLerp, 0);
                                        multPlusX = Math.pow(1 + multPlusX, hpRatio) - 1;
                                        multPlusY = Math.pow(1 + multPlusY, hpRatio) - 1;
                                        angle *= hpRatio;
                                }

                                icon.scale.set(1 + multPlusX * bopRatio, 1 + multPlusY * bopRatio);
                                icon.angle = angle * bopRatio;
                        }
                }

                iconP1.updateHitbox();
                iconP2.updateHitbox();

                if (curBeat > 0) characterBopper(curBeat);

                super.beatHit();
                lastBeatHit = curBeat;

                setOnScripts('curBeat', curBeat);
                callOnScripts('onBeatHit');
        }

        var sectionRatio:Float = 0;
        var zoomRatio:Float = 0;
        override function sectionHit()
        {
                sectionRatio = (curDecBeat / 4) % 1;
                zoomRatio = 1 - sectionRatio;

                curSec = SONG.notes[curSection];
                if (curSec != null)
                {
                        if (camZooming && ClientPrefs.data.camZooms)
                        {
                                FlxG.camera.zoom += 0.015 * camZoomingMult * zoomRatio;
                                camHUD.zoom += 0.03 * camZoomingMult * zoomRatio;
        
                                // if (FlxG.camera.zoom >= 1.35) FlxG.camera.zoom = 1.35;
                                // if (camHUD.zoom >= 1.7) camHUD.zoom = 1.7;
                        }
                        
                        if (generatedMusic && !endingSong && !isCameraOnForcedPos)
                                moveCameraSection();

                        if (curSec.changeBPM)
                        {
                                Conductor.bpm = curSec.bpm;
                                setOnScripts('curBpm', Conductor.bpm);
                                setOnScripts('crochet', Conductor.crochet);
                                setOnScripts('stepCrochet', Conductor.stepCrochet);
                        }
                        setOnScripts('mustHitSection', curSec.mustHitSection);
                        setOnScripts('altAnim', curSec.altAnim);
                        setOnScripts('gfSection', curSec.gfSection);
                }
                super.sectionHit();

                setOnScripts('curSection', curSection);
                callOnScripts('onSectionHit');
        }
        
        public function characterBopper(beat:Float):Void
        {
                if (gf != null
                        && beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0
                        && !gf.getAnimationName().startsWith('sing')
                        && !gf.stunned)
                        gf.dance();
                if (boyfriend != null
                        && beat % boyfriend.danceEveryNumBeats == 0
                        && !boyfriend.getAnimationName().startsWith('sing')
                        && !boyfriend.stunned)
                        boyfriend.dance();
                if (dad != null
                        && beat % dad.danceEveryNumBeats == 0
                        && !dad.getAnimationName().startsWith('sing')
                        && !dad.stunned)
                        dad.dance();
        }

        public function playerDance():Void
        {
                var anim:String = boyfriend.getAnimationName();
                if (boyfriend.holdTimer > boyfriend.charaCrochet * boyfriend.singDuration && anim.startsWith('sing') && !anim.endsWith('miss'))
                        boyfriend.dance();
        }

        #if LUA_ALLOWED
        var luaToLoad:String;
        public function startLuasNamed(luaFile:String)
        {
                #if MODS_ALLOWED
                luaToLoad = Paths.modFolders(luaFile);
                if(!NativeFileSystem.exists(luaToLoad))
                        luaToLoad = Paths.getSharedPath(luaFile);

                if(NativeFileSystem.exists(luaToLoad))
                #elseif sys
                luaToLoad = Paths.getSharedPath(luaFile);
                if (OpenFlAssets.exists(luaToLoad))
                #end
                {
                        for (script in luaArray)
                                if (script.scriptName == luaToLoad)
                                        return false;

                        new FunkinLua(luaToLoad);
                        return true;
                }
                return false;
        }
        #end

        #if HSCRIPT_ALLOWED
        var scriptToLoad:String;
        public function startHScriptsNamed(scriptFile:String)
        {
                #if MODS_ALLOWED
                scriptToLoad = Paths.modFolders(scriptFile);
                if(!NativeFileSystem.exists(scriptToLoad))
                        scriptToLoad = Paths.getSharedPath(scriptFile);
                #else
                scriptToLoad = Paths.getSharedPath(scriptFile);
                #end

                if(NativeFileSystem.exists(scriptToLoad))
                {
                        if (Iris.instances.exists(scriptToLoad))
                                return false;

                        initHScript(scriptToLoad);
                        return true;
                }
                return false;
        }

        var newScript:HScript;
        public function initHScript(file:String)
        {
                newScript = null;
                try
                {
                        newScript = new HScript(null, file);
                        newScript.call('onCreate');
                        trace('initialized hscript interp successfully: $file');
                        hscriptArray.push(newScript);
                }
                catch (e:Dynamic)
                {
                        addTextToDebug('ERROR ON LOADING ($file) - $e', FlxColor.RED);
                        newScript = cast(Iris.instances.get(file), HScript);
                        if (newScript != null)
                                newScript.destroy();
                }
        }
        #end

        var callResult:Dynamic;
        public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null,
                        excludeValues:Array<Dynamic> = null):Dynamic
        {
                // var returnVal:String = LuaUtils.Function_Continue;
                if (args == null)
                        args = [];
                if (exclusions == null)
                        exclusions = [];
                if (excludeValues == null)
                        excludeValues = [LuaUtils.Function_Continue];

                callResult = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
                if (callResult == null || excludeValues.contains(callResult))
                        callResult = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
                return callResult;
        }

        var arr:Array<FunkinLua> = [];
        var myValue:Dynamic;
        public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null,
                        excludeValues:Array<Dynamic> = null):Dynamic
        {
                var returnVal:String = LuaUtils.Function_Continue;
                #if LUA_ALLOWED
                if (args == null)
                        args = [];
                if (exclusions == null)
                        exclusions = [];
                if (excludeValues == null)
                        excludeValues = [LuaUtils.Function_Continue];

                arr.resize(0);
                for (script in luaArray)
                {
                        if (script.closed)
                        {
                                arr.push(script);
                                continue;
                        }

                        if (exclusions.contains(script.scriptName))
                                continue;

                        myValue = script.call(funcToCall, args);
                        if ((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll)
                                && !excludeValues.contains(myValue)
                                && !ignoreStops)
                        {
                                returnVal = myValue;
                                break;
                        }

                        if (myValue != null && !excludeValues.contains(myValue))
                                returnVal = myValue;

                        if (script.closed)
                                arr.push(script);
                }

                if (arr.length > 0)
                        for (script in arr)
                                luaArray.remove(script);
                #end
                return returnVal;
        }

        public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null,
                        excludeValues:Array<Dynamic> = null):Dynamic
        {
                var returnVal:String = LuaUtils.Function_Continue;

                #if HSCRIPT_ALLOWED
                if (exclusions == null)
                        exclusions = [];
                if (excludeValues == null)
                        excludeValues = [];
                excludeValues.push(LuaUtils.Function_Continue);

                if (hscriptArray.length < 1)
                        return returnVal;

                for (script in hscriptArray)
                {
                        @:privateAccess
                        if (script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
                                continue;

                        try
                        {
                                var callValue = script.call(funcToCall, args);
                                myValue = callValue.returnValue;

                                if ((myValue == LuaUtils.Function_StopHScript || myValue == LuaUtils.Function_StopAll)
                                        && !excludeValues.contains(myValue)
                                        && !ignoreStops)
                                {
                                        returnVal = myValue;
                                        break;
                                }

                                if (myValue != null && !excludeValues.contains(myValue))
                                        returnVal = myValue;
                        }
                        catch (e:Dynamic)
                        {
                                addTextToDebug('ERROR (${script.origin}: $funcToCall) - $e', FlxColor.RED);
                        }
                }
                #end

                return returnVal;
        }

        public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null)
        {
                if (exclusions == null)
                        exclusions = [];
                setOnLuas(variable, arg, exclusions);
                setOnHScript(variable, arg, exclusions);
        }

        public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null)
        {
                #if LUA_ALLOWED
                if (exclusions == null)
                        exclusions = [];
                for (script in luaArray)
                {
                        if (exclusions.contains(script.scriptName))
                                continue;

                        script.set(variable, arg);
                }
                #end
        }

        public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null)
        {
                #if HSCRIPT_ALLOWED
                if (exclusions == null)
                        exclusions = [];
                for (script in hscriptArray)
                {
                        if (exclusions.contains(script.origin))
                                continue;

                        script.set(variable, arg);
                }
                #end
        }

        var strumSpr:StrumNote = null;
        var strumHitId:Int = -1;
        var strumCurAnim:FlxAnimation = null;
        // var strumART:Float = 0;

        function strumPlayAnim(isDad:Bool, id:Int, inSustain:Bool)
        {
                if (!strumAnim) return;
                strumHitId = id + (isDad ? 0 : totalColumns);
                if (strumHitId >= hit.length) return;
                if (!hit[strumHitId])
                {
                        if (isDad)
                                strumSpr = opponentStrums.members[id];
                        else
                                strumSpr = playerStrums.members[id];

                        if (strumSpr != null)
                        {
                                strumSpr.playAnim('confirm', true);
                                strumCurAnim = strumSpr.animation.curAnim;
                                strumSpr.resetAnim = (1 / strumCurAnim.frameRate) * strumCurAnim.numFrames;
                        }
                        hit[strumHitId] = true;
                        if (!strumSpr.inSustain) strumSpr.inSustain = inSustain;
                }
        }

        public var ratingName:String = '?';
        public var ratingPercent:Float;
        public var ratingFC:String;
        
        var recalcRate:Dynamic;

        public function recalculateRating(badHit:Bool = false, scoreBop:Bool = true)
        {
                setOnScripts('score', songScore);
                setOnScripts('misses', songMisses);
                setOnScripts('hits', songHits);
                setOnScripts('combo', combo);

                if (!cpuControlled && !practiceMode) {
                        recalcRate = callOnScripts('onRecalculateRating', null, true);
                        if (recalcRate != LuaUtils.Function_Stop)
                        {
                                ratingName = '?';
                                if (totalPlayed != 0) // Prevent divide by 0
                                {
                                        // Rating Percent
                                        ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
                                        // trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

                                        // Rating Name
                                        ratingName = ratingStuff[ratingStuff.length - 1][0]; // Uses last string
                                        if (ratingPercent < 1)
                                                for (i in 0...ratingStuff.length - 1)
                                                        if (ratingPercent < ratingStuff[i][1])
                                                        {
                                                                ratingName = ratingStuff[i][0];
                                                                break;
                                                        }
                                }
                                fullComboFunction();
                        }
                }

                setOnScripts('rating', ratingPercent);
                setOnScripts('ratingName', ratingName);
                setOnScripts('ratingFC', ratingFC);
                setOnScripts('totalPlayed', totalPlayed);
                setOnScripts('totalNotesHit', totalNotesHit);
                updateScore(badHit, scoreBop); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
        }

        #if ACHIEVEMENTS_ALLOWED
        private function checkForAchievement(achievesToCheck:Array<String> = null)
        {
                if (chartingMode)
                        return;

                var usedPractice:Bool = (practiceMode || cpuControlled);
                if (cpuControlled)
                        return;

                for (name in achievesToCheck)
                {
                        if (!Achievements.exists(name))
                                continue;

                        var unlock:Bool = false;
                        if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
                        {
                                switch (name)
                                {
                                        case 'ur_bad':
                                                unlock = (ratingPercent < 0.2 && !practiceMode);

                                        case 'ur_good':
                                                unlock = (ratingPercent >= 1 && !usedPractice);

                                        case 'oversinging':
                                                unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

                                        case 'hype':
                                                unlock = (!boyfriendIdled && !usedPractice);

                                        case 'two_keys':
                                                unlock = (!usedPractice && keysPressed.length <= 2);

                                        case 'toastie':
                                                unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

                                        case 'debugger':
                                                unlock = (songName == 'test' && !usedPractice);
                                }
                        }
                        else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
                        {
                                if (isStoryMode
                                        && campaignMisses + songMisses < 1
                                        && Difficulty.getString().toUpperCase() == 'HARD'
                                        && storyPlaylist.length <= 1
                                        && !changedDifficulty
                                        && !usedPractice)
                                        unlock = true;
                        }

                        if (unlock)
                                Achievements.unlock(name);
                }
        }
        #end

        #if (!flash && sys)
        public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
        public function createRuntimeShader(shaderName:String):ErrorHandledRuntimeShader
        {
                if(!ClientPrefs.data.shaders) return new ErrorHandledRuntimeShader(shaderName);

                #if (!flash && MODS_ALLOWED && sys)
                if(!runtimeShaders.exists(shaderName) && !initLuaShader(shaderName))
                {
                        FlxG.log.warn('Shader $shaderName is missing!');
                        return new ErrorHandledRuntimeShader(shaderName);
                }

                var arr:Array<String> = runtimeShaders.get(shaderName);
                return new ErrorHandledRuntimeShader(shaderName, arr[0], arr[1]);
                #else
                FlxG.log.warn("Platform unsupported for Runtime Shaders!");
                return null;
                #end
        }

        public function initLuaShader(name:String, ?glslVersion:Int = 120)
        {
                if (!shaderEnabled)
                        return false;

                #if (MODS_ALLOWED && !flash && sys)
                if (runtimeShaders.exists(name))
                {
                        FlxG.log.warn('Shader $name was already initialized!');
                        return true;
                }

                for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/'))
                {
                        var frag:String = folder + name + '.frag';
                        var vert:String = folder + name + '.vert';
                        var found:Bool = false;
                        if(NativeFileSystem.exists(frag))
                        {
                                frag = NativeFileSystem.getContent(frag);
                                found = true;
                        }
                        else
                                frag = null;

                        if(NativeFileSystem.exists(vert))
                        {
                                vert = NativeFileSystem.getContent(vert);
                                found = true;
                        }
                        else
                                vert = null;

                        if (found)
                        {
                                runtimeShaders.set(name, [frag, vert]);
                                // trace('Found shader $name!');
                                return true;
                        }
                }
                #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
                #else
                FlxG.log.warn('Missing shader $name .frag AND .vert files!');
                #end
                #else
                FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
                #end
                return false;
        }
        #end

        #if TOUCH_CONTROLS_ALLOWED
        public function makeLuaTouchPad(DPadMode:String, ActionMode:String) {
                if(members.contains(luaTouchPad)) return;

                if(!variables.exists("luaTouchPad"))
                        variables.set("luaTouchPad", luaTouchPad);

                luaTouchPad = new TouchPad(DPadMode, ActionMode);
                luaTouchPad.alpha = ClientPrefs.data.controlsAlpha;
        }
        
        public function addLuaTouchPad() {
                if(luaTouchPad == null || members.contains(luaTouchPad)) return;

                var target = LuaUtils.getTargetInstance();
                target.insert(target.members.length + 1, luaTouchPad);
        }

        public function addLuaTouchPadCamera() {
                if(luaTouchPad != null)
                        luaTouchPad.cameras = [luaTpadCam];
        }

        public function removeLuaTouchPad() {
                if (luaTouchPad != null) {
                        luaTouchPad.kill();
                        luaTouchPad.destroy();
                        remove(luaTouchPad);
                        luaTouchPad = null;
                }
        }

        public function luaTouchPadPressed(button:Dynamic):Bool {
                if(luaTouchPad != null) {
                        if(Std.isOfType(button, String))
                                return luaTouchPad.buttonPressed(MobileInputID.fromString(button));
                        else if(Std.isOfType(button, Array)){
                                var FUCK:Array<String> = button; // haxe said "You Can't Iterate On A Dyanmic Value Please Specificy Iterator or Iterable *insert nerd emoji*" so that's the only i foud to fix
                                var idArray:Array<MobileInputID> = [];
                                for(strId in FUCK)
                                        idArray.push(MobileInputID.fromString(strId));
                                return luaTouchPad.anyPressed(idArray);
                        } else
                                return false;
                }
                return false;
        }

        public function luaTouchPadJustPressed(button:Dynamic):Bool {
                if(luaTouchPad != null) {
                        if(Std.isOfType(button, String))
                                return luaTouchPad.buttonJustPressed(MobileInputID.fromString(button));
                        else if(Std.isOfType(button, Array)){
                                var FUCK:Array<String> = button;
                                var idArray:Array<MobileInputID> = [];
                                for(strId in FUCK)
                                        idArray.push(MobileInputID.fromString(strId));
                                return luaTouchPad.anyJustPressed(idArray);
                        } else
                                return false;
                }
                return false;
        }
        
        public function luaTouchPadJustReleased(button:Dynamic):Bool {
                if(luaTouchPad != null) {
                        if(Std.isOfType(button, String))
                                return luaTouchPad.buttonJustReleased(MobileInputID.fromString(button));
                        else if(Std.isOfType(button, Array)){
                                var FUCK:Array<String> = button;
                                var idArray:Array<MobileInputID> = [];
                                for(strId in FUCK)
                                        idArray.push(MobileInputID.fromString(strId));
                                return luaTouchPad.anyJustReleased(idArray);
                        } else
                                return false;
                }
                return false;
        }

        public function luaTouchPadReleased(button:Dynamic):Bool {
                if(luaTouchPad != null) {
                        if(Std.isOfType(button, String))
                                return luaTouchPad.buttonJustReleased(MobileInputID.fromString(button));
                        else if(Std.isOfType(button, Array)){
                                var FUCK:Array<String> = button;
                                var idArray:Array<MobileInputID> = [];
                                for(strId in FUCK)
                                        idArray.push(MobileInputID.fromString(strId));
                                return luaTouchPad.anyReleased(idArray);
                        } else
                                return false;
                }
                return false;
        }
        #end
}

