package backend;

import haxe.ds.Vector;
import haxe.Json;
import haxe.io.Bytes;
import haxe.zip.Entry;
import haxe.zip.Reader;
import haxe.zip.Uncompress;
import haxe.io.BytesInput;
import sys.FileSystem;
import sys.io.Process;
import backend.SongJson;
import lime.utils.Assets;

import backend.ClientPrefs;


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
	@:optional var mania:Null<Int>;
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
	/**
	 * Recursively deletes a directory and all its contents
	 */
	static function deleteDirectoryRecursive(path:String):Void
	{
		#if !web
		if (!FileSystem.exists(path)) return;
		
		for (file in FileSystem.readDirectory(path))
		{
			var fullPath = '$path/$file';
			if (FileSystem.isDirectory(fullPath))
			{
				deleteDirectoryRecursive(fullPath);
			}
			else
			{
				FileSystem.deleteFile(fullPath);
			}
		}
		FileSystem.deleteDirectory(path);
		#end
	}

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

		trace('[Song] Looking for chart at: $_lastPath');
		trace('[Song] Formatted folder: $formattedFolder, song: $formattedSong');

		if(NativeFileSystem.exists(_lastPath))
		{
			rawData = NativeFileSystem.getContent(_lastPath);
			trace('[Song] Found raw JSON, length: ${rawData != null ? rawData.length : 0}');
		}
		else
		{
			trace('[Song] Raw JSON not found at $_lastPath');
		}

		// Json Zip Reader: try loading from compressed archive if enabled and raw JSON not found
		if(rawData == null && ClientPrefs.data.jsonZipReader)
		{
			trace('[Song] jsonZipReader enabled, trying archives...');
			var archiveExtensions:Array<String> = ['.zip', '.7z', '.tar.xz', '.tar.gz', '.tar.zx', '.tgz'];
			// `_lastPath` points at `song.json`; also try the plain `song` archive name
			// (e.g. both `tutorial.json.zip` and `tutorial.zip`).
			var archiveBase:String = _lastPath;
			if (archiveBase.endsWith('.json'))
				archiveBase = archiveBase.substring(0, archiveBase.length - 5);
			var archiveNames:Array<String> = [_lastPath, archiveBase];
			for (name in archiveNames)
			{
				for (ext in archiveExtensions)
				{
					var archivePath:String = name + ext;
					trace('[Song] Checking archive: $archivePath exists=${NativeFileSystem.existsAnywhere(archivePath)}');
					if(NativeFileSystem.existsAnywhere(archivePath))
					{
						rawData = readJsonFromArchive(archivePath, formattedSong + '.json');
						trace(rawData != null ? '[Song] readJsonFromArchive result: SUCCESS (${rawData.length} chars)' : '[Song] readJsonFromArchive result: FAILED');
						if (rawData != null) break;
					}
				}
				if (rawData != null) break;
			}
		}

		if(rawData == null) return null;

		// Parse the base JSON file first (e.g., example.json)
		var baseSong:SwagSong = parseJSON(rawData, jsonInput);

		// Merge streaming split chart parts automatically (opt-in via ClientPrefs)
		// Supports sequential numeric suffix files:
		//  - song-2.json, song-3.json...
		//  - song-part2.json, song-part3.json...
		if(ClientPrefs.data.mergeStreaming)
		{
			var partNum:Int = 2;
			while(true)
			{
				var partData:String = null;
				var pathPatternA:String = Paths.json('$formattedFolder/$formattedSong-$partNum');
				var pathPatternB:String = Paths.json('$formattedFolder/$formattedSong-part$partNum');

				if(NativeFileSystem.exists(pathPatternA)) {
					partData = NativeFileSystem.getContent(pathPatternA);
				} else if(NativeFileSystem.exists(pathPatternB)) {
					partData = NativeFileSystem.getContent(pathPatternB);
				}

			if(partData != null) {
				var partSong:SwagSong = parseJSON(partData, jsonInput, null);
				if(partSong != null) {
						if(partSong.notes != null) {
							if(baseSong.notes == null) baseSong.notes = [];
							baseSong.notes = baseSong.notes.concat(partSong.notes);
						}
						if(partSong.events != null) {
							if(baseSong.events == null) baseSong.events = [];
							baseSong.events = baseSong.events.concat(partSong.events);
						}
					}
					partNum++;
				}
				else {
					break;
				}
			}
		}


		return baseSong;
	}

	/**
	 * Reads a JSON file from a compressed archive.
	 * Supports: .zip, .7z, .tar.xz, .tar.gz, .tar.zx, and nested archives.
	 * @param archivePath Path to the archive file
	 * @param fileName Name of the JSON file inside the archive
	 * @return The decompressed JSON string, or null if not found
	 */
	static function readJsonFromArchive(archivePath:String, fileName:String):Null<String>
	{
		// Try native ZIP reading first
		var result = readJsonFromZip(archivePath, fileName);
		if (result != null) return result;

		// Try system decompression tools for other formats
		result = readJsonFromArchiveSystem(archivePath, fileName);
		if (result != null) return result;

		// Try nested archive extraction
		return readJsonFromNestedArchive(archivePath, fileName);
	}

	/**
	 * Native ZIP reading using haxe.zip
	 */
	static function readJsonFromZip(zipPath:String, fileName:String):Null<String>
	{
		trace('[Song] readJsonFromZip: path=$zipPath, file=$fileName');
		var zipBytes:Bytes = NativeFileSystem.getBytesAnywhere(zipPath);
		trace(zipBytes != null ? '[Song] getBytes result: ${zipBytes.length} bytes' : '[Song] getBytes result: null');
		if (zipBytes == null) return null;

		try
		{
			var input = new haxe.io.BytesInput(zipBytes);
			var entries = Reader.readZip(input);
			
			for (entry in entries)
			{
				if (entry.fileName == fileName || entry.fileName.endsWith('/' + fileName))
				{
					// ZIP entries are raw DEFLATE (no zlib header), so we must inflate
					// with a negative window size. Uncompress.run expects a zlib header
					// and fails with "incorrect header check" on most real-world zips.
					var data:Bytes = entry.compressed ? inflateRaw(entry.data) : entry.data;
					return data.toString();
				}
			}

			// No direct JSON match: accept a single *.json entry as a fallback
			// (covers zips where the chart json is named differently).
			var jsonFallback:String = null;
			for (entry in entries)
			{
				if (entry.fileName.endsWith('.json'))
				{
					if (jsonFallback != null) { jsonFallback = null; break; }
					jsonFallback = entry.fileName;
				}
			}
			if (jsonFallback != null)
			{
				for (entry in entries)
				{
					if (entry.fileName == jsonFallback)
					{
						var data:Bytes = entry.compressed ? inflateRaw(entry.data) : entry.data;
						return data.toString();
					}
				}
			}

			// No JSON found — the zip may contain nested archives (zip -> 7z -> tar.xz -> json).
			return readNestedFromZipEntries(entries, zipPath, fileName);
		}
		catch (e:Dynamic)
		{
			trace('Failed to read JSON from zip: $zipPath - $e');
		}
		return null;
	}

	/**
	 * Extracts archive entries from a zip to a temp dir and recursively reads
	 * the target JSON from the nested archive (e.g. zip -> 7z -> tar.xz -> json).
	 */
	static function readNestedFromZipEntries(entries:List<Entry>, zipPath:String, fileName:String):Null<String>
	{
		#if !web
		var tempDir:String = 'temp_zip_nested_' + Math.round(Math.random() * 10000);
		FileSystem.createDirectory(tempDir);
		try
		{
			for (entry in entries)
			{
				if (entry.fileName.endsWith('.zip') || entry.fileName.endsWith('.7z') || entry.fileName.endsWith('.tar.xz')
					|| entry.fileName.endsWith('.tar.gz') || entry.fileName.endsWith('.tar.zx') || entry.fileName.endsWith('.tgz')
					|| entry.fileName.endsWith('.tar'))
				{
					var data:Bytes = entry.compressed ? inflateRaw(entry.data) : entry.data;
					var name:String = entry.fileName.split('/').pop();
					var fullPath:String = '$tempDir/$name';
					sys.io.File.saveBytes(fullPath, data);
					var nestedResult = readJsonFromArchive(fullPath, fileName);
					if (nestedResult != null)
					{
						deleteDirectoryRecursive(tempDir);
						return nestedResult;
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('Nested archives inside zip failed: $zipPath - $e');
		}
		try { deleteDirectoryRecursive(tempDir); } catch (e:Dynamic) {}
		#end
		return null;
	}

	/**
	 * Inflates raw DEFLATE data (window bits -15, i.e. no zlib header),
	 * as used by ZIP file entries.
	 */
	static function inflateRaw(data:Bytes):Bytes
	{
		#if cpp
		var u = new Uncompress(-15);
		var bufsize:Int = 1 << 16;
		var tmp = Bytes.alloc(bufsize);
		var buffer = new haxe.io.BytesBuffer();
		var pos:Int = 0;
		u.setFlushMode(haxe.zip.FlushMode.SYNC);
		while (true)
		{
			var r = u.execute(data, pos, tmp, 0);
			buffer.addBytes(tmp, 0, r.write);
			pos += r.read;
			if (r.done) break;
		}
		u.close();
		return buffer.getBytes();
		#else
		return Uncompress.run(data);
		#end
	}

	/**
	 * Uses system commands (7z, tar) to extract from archives
	 */
	static function readJsonFromArchiveSystem(archivePath:String, fileName:String):Null<String>
	{
		trace('[Song] readJsonFromArchiveSystem: archive=$archivePath, file=$fileName');
		#if !web
		var tempDir:String = 'temp_extract_' + Math.round(Math.random() * 10000);
		FileSystem.createDirectory(tempDir);

		try
		{
			var ext:String = archivePath.toLowerCase();
			var cmd:String = null;
			var args:Array<String> = [];

			if (ext.endsWith('.7z'))
			{
				cmd = '7z';
				args = ['e', '-y', archivePath, '-o' + tempDir];
			}
			else if (ext.endsWith('.tar.xz') || ext.endsWith('.tar.zx') || ext.endsWith('.tar.gz') || ext.endsWith('.tgz') || ext.endsWith('.tar'))
			{
				cmd = 'tar';
				if (ext.endsWith('.xz') || ext.endsWith('.zx'))
					args = ['-xJf', archivePath, '-C', tempDir];
				else if (ext.endsWith('.gz') || ext.endsWith('.tgz'))
					args = ['-xzf', archivePath, '-C', tempDir];
				else
					args = ['-xf', archivePath, '-C', tempDir];
			}

			if (cmd != null)
			{
				var proc = new Process(cmd, args);
				proc.exitCode(); // block until the extraction is done

				// Try to find the extracted file
				var searchPath:String = '$tempDir/$fileName';
				if (FileSystem.exists(searchPath))
				{
					var content:String = NativeFileSystem.getContentAnywhere(searchPath);
					deleteDirectoryRecursive(tempDir);
					return content;
				}

				// Search recursively in temp dir
				for (file in FileSystem.readDirectory(tempDir))
				{
					var fullPath = '$tempDir/$file';
					if (file == fileName)
					{
						var content:String = NativeFileSystem.getContentAnywhere(fullPath);
						deleteDirectoryRecursive(tempDir);
						return content;
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('System extraction failed: $archivePath - $e');
		}

		try { deleteDirectoryRecursive(tempDir); } catch (e:Dynamic) {}
		#end

		return null;
	}

	/**
	 * Handles nested archives (e.g., .zip inside .7z, .tar inside .zip)
	 */
	static function readJsonFromNestedArchive(archivePath:String, fileName:String):Null<String>
	{
		trace('[Song] readJsonFromNestedArchive: archive=$archivePath, file=$fileName');
		#if !web
		var tempDir:String = 'temp_nested_' + Math.round(Math.random() * 10000);
		FileSystem.createDirectory(tempDir);

		try
		{
			var ext:String = archivePath.toLowerCase();
			var cmd:String = null;
			var args:Array<String> = [];

			if (ext.endsWith('.7z'))
			{
				cmd = '7z';
				args = ['e', '-y', archivePath, '-o' + tempDir];
			}
			else if (ext.endsWith('.tar.xz') || ext.endsWith('.tar.zx') || ext.endsWith('.tar.gz') || ext.endsWith('.tgz'))
			{
				cmd = 'tar';
				if (ext.endsWith('.xz') || ext.endsWith('.zx'))
					args = ['-xJf', archivePath, '-C', tempDir];
				else if (ext.endsWith('.gz') || ext.endsWith('.tgz'))
					args = ['-xzf', archivePath, '-C', tempDir];
			}

			if (cmd != null)
			{
				var proc = new Process(cmd, args);
				proc.exitCode(); // block until the extraction is done

				// Check if the target file was extracted
				for (file in FileSystem.readDirectory(tempDir))
				{
					var fullPath = '$tempDir/$file';
					if (file == fileName)
					{
						var content:String = NativeFileSystem.getContentAnywhere(fullPath);
						deleteDirectoryRecursive(tempDir);
						return content;
					}

					// If it's another archive, recursively extract it
					if (file.endsWith('.zip') || file.endsWith('.7z') || file.endsWith('.tar.xz') || file.endsWith('.tar.gz'))
					{
						var nestedResult = readJsonFromArchive(fullPath, fileName);
						if (nestedResult != null)
						{
							deleteDirectoryRecursive(tempDir);
							return nestedResult;
						}
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('Nested archive extraction failed: $archivePath - $e');
		}

		try { deleteDirectoryRecursive(tempDir); } catch (e:Dynamic) {}
		#end

		return null;
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
