package backend;

import haxe.ds.Vector;
import haxe.Json;
import backend.SongJson;
import lime.utils.Assets;

#if (NATIVE_LOOKUP || sys)
import mikolka.funkin.custom.NativeFileSystem;
#end

import objects.Note;

using StringTools;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Array<Dynamic>>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var offset:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	var format:String;

	@:optional var isOldVersion:Bool;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;
	
	@:optional var disableNoteRGB:Bool;
	@:optional var screwYou:String;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
}

typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var mustHitSection:Bool;
	@:optional var altAnim:Bool;
	@:optional var gfSection:Bool;
	@:optional var bpm:Float;
	@:optional var changeBPM:Bool;
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Array<Dynamic>>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'psych_v1';

	public static function convert(songJson:Dynamic) // Convert old charts to psych_v1 format
	{
		if(songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			if(Reflect.hasField(songJson, 'player3')) Reflect.deleteField(songJson, 'player3');
		}

		if(songJson.events == null)
		{
			songJson.events = [];
			for (secNum in 0...songJson.notes.length)
			{
				var sec:SwagSection = songJson.notes[secNum];

				var i:Int = 0;
				var notes:Array<Dynamic> = sec.sectionNotes;
				var len:Int = notes.length;
				while(i < len)
				{
					var note:Array<Dynamic> = notes[i];
					if(note[1] < 0)
					{
						songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						notes.remove(note);
						len = notes.length;
					}
					else i++;
				}
			}
		}

		var sectionsData:Array<SwagSection> = songJson.notes;
		if(sectionsData == null) return;

		for (section in sectionsData)
		{
			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats))
			{
				section.sectionBeats = 4;
				if(Reflect.hasField(section, 'lengthInSteps')) Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes)
			{
				var gottaHitNote:Bool = (note[1] < 4) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % 4) + (gottaHitNote ? 0 : 4);

				if(note[3] != null && !Std.isOfType(note[3], String) && !Std.isOfType(note[3], Array) && note[3].cmpSpam == null)
					note[3] = Note.DEFAULT_NOTE_TYPES[note[3]]; //compatibility with Week 7 and 0.1-0.3 psych charts
			}
		}
	}

	public static var chartPath:String;
	public static var loadedSongName:String;
	public static function loadFromJson(jsonInput:String, ?forPlay:Bool, ?folder:String):SwagSong
	{
		SongJson.skipChart = forPlay;
		folder = folder ?? jsonInput;
		PlayState.SONG = getChart(jsonInput, folder);

		loadedSongName = folder;
		chartPath = _lastPath;
		#if windows
		// prevent any saving errors by fixing the path on Windows (being the only OS to ever use backslashes instead of forward slashes for paths)
		chartPath = chartPath.replace('/', '\\');
		#end
		StageData.loadDirectory(PlayState.SONG);
		return PlayState.SONG;
	}

	static var _lastPath:String;
	public static function getChart(jsonInput:String, ?folder:String):SwagSong
	{
		if(folder == null) folder = jsonInput;
		var rawData:String = null;
		
		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);
		_lastPath = Paths.json('$formattedFolder/$formattedSong');
		
		trace('Looking for chart at: $_lastPath');
		
		if(NativeFileSystem.exists(_lastPath)) {
			rawData = NativeFileSystem.getContent(_lastPath);
			trace('Found chart, rawData length: ${rawData != null ? rawData.length : "null"}');
		} else {
			trace('Chart file not found at: $_lastPath');
		}

		if(rawData == null) {
			trace('Failed to load chart data');
			return null;
		}

		// Parse the base JSON file first (e.g., example.json)
		var baseSong:SwagSong = parseJSON(rawData, jsonInput);
		if(baseSong == null) {
			trace('Failed to parse chart JSON');
			return null;
		}

		// Loop to find and merge split parts automatically
		var partNum:Int = 2;
		while(true)
		{
			var partData:String = null;
			
			// Pattern A: example-2.json
			var pathPatternA:String = Paths.json('$formattedFolder/$formattedSong-$partNum');
			// Pattern B: example-part2.json
			var pathPatternB:String = Paths.json('$formattedFolder/$formattedSong-part$partNum');
			
			if(NativeFileSystem.exists(pathPatternA)) {
				partData = NativeFileSystem.getContent(pathPatternA);
			} else if(NativeFileSystem.exists(pathPatternB)) {
				partData = NativeFileSystem.getContent(pathPatternB);
			}

			// If a split file is found, parse it and append its contents
			if(partData != null) {
				var partSong:SwagSong = parseJSON(partData, jsonInput);
				if(partSong != null) {
					// Merge notes
					if(partSong.notes != null) {
						if(baseSong.notes == null) baseSong.notes = [];
						baseSong.notes = baseSong.notes.concat(partSong.notes);
					}
					// Merge events
					if(partSong.events != null) {
						if(baseSong.events == null) baseSong.events = [];
						baseSong.events = baseSong.events.concat(partSong.events);
					}
				}
				partNum++; // Move to the next part (e.g., -3 or -part3)
			} else {
				// No more sequential split parts found, stop looking
				break;
			}
		}

		return baseSong;
	}

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'psych_v1'):SwagSong
	{
		var isOldVer:Vector<Bool> = new Vector(2);
		var songJson:SwagSong = cast SongJson.parse(rawData);

		if(Reflect.hasField(songJson, 'song'))
		{
			isOldVer[0] = true;
			var subSong:SwagSong = Reflect.field(songJson, 'song');
			if(subSong != null && Type.typeof(subSong) == TObject)
				songJson = subSong;
		} else isOldVer[0] = false;

		if(convertTo != null && convertTo.length > 0)
		{
			var fmt:String = songJson.format;
			if(fmt == null)
			{
				fmt = songJson.format = 'unknown';
				isOldVer[1] = true;
				if (isOldVer[0] && isOldVer[1]) songJson.isOldVersion = true;
			}

			switch(convertTo)
			{
				case 'psych_v1':
					if(!fmt.startsWith('psych_v1')) //Convert to Psych 1.0 format
					{
						#if debug trace('converting chart $nameForError with format $fmt to psych_v1 format...'); #end
						songJson.format = 'psych_v1_convert';
						convert(songJson);
					}
			}
		}
		return songJson;
	}

	// Call this function from your ChartingState whenever you save a song
	public static function saveChart(songData:SwagSong, jsonInput:String, ?folder:String):Void
	{
		if(folder == null) folder = jsonInput;
		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);

		// 1.99 GB threshold in bytes. (Change this to something small like 2 * 1024 * 1024 for testing!)
		var maxBytes:Float = 1.99 * 1024 * 1024 * 1024; 

		// Create a dynamic template containing everything EXCEPT notes and events
		var template:Dynamic = {};
		for(field in Reflect.fields(songData)) {
			if(field != "notes" && field != "events") {
				Reflect.setField(template, field, Reflect.field(songData, field));
			}
		}

		var totalSections:Int = (songData.notes != null) ? songData.notes.length : 0;
		var totalEvents:Int = (songData.events != null) ? songData.events.length : 0;

		var currentPart:Int = 1;
		var sectionIndex:Int = 0;
		var eventIndex:Int = 0;

		// Keep filling up chunks until all data points are assigned to a file
		while(sectionIndex < totalSections || eventIndex < totalEvents)
		{
			var chunk:SwagSong = cast Reflect.copy(template);
			chunk.notes = [];
			chunk.events = [];

			var currentBytes:Int = 0;

			while(sectionIndex < totalSections || eventIndex < totalEvents)
			{
				if(sectionIndex < totalSections) {
					chunk.notes.push(songData.notes[sectionIndex]);
					sectionIndex++;
				}
				if(eventIndex < totalEvents) {
					chunk.events.push(songData.events[eventIndex]);
					eventIndex++;
				}

				// Generate test string wrapped under the standard "song" object layout
				var wrappedData:Dynamic = { song: chunk };
				var checkString:String = haxe.Json.stringify(wrappedData, null, "\t");
				
				currentBytes = haxe.io.Bytes.ofString(checkString).length;

				// If we step over the targeted boundary, halt this part and leave remaining elements for the next file
				if(currentBytes >= maxBytes && (sectionIndex < totalSections || eventIndex < totalEvents)) {
					break;
				}
			}

			// Format proper naming paths depending on file sequence
			var path:String = "";
			if(currentPart == 1) {
				path = Paths.json('$formattedFolder/$formattedSong');
			} else {
				path = Paths.json('$formattedFolder/$formattedSong-$currentPart');
			}

			#if windows
			path = path.replace('/', '\\');
			#end

			var finalWrapped:Dynamic = { song: chunk };
			var finalJsonStr:String = haxe.Json.stringify(finalWrapped, null, "\t");

			#if sys
			sys.io.File.saveContent(path, finalJsonStr);
			#else
			NativeFileSystem.saveContent(path, finalJsonStr); 
			#end

			currentPart++;
		}
		
		#if debug
		trace('Chart successfully split and saved across ' + (currentPart - 1) + ' files.');
		#end
	}
}
