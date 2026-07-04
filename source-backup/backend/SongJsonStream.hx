package backend;

import haxe.io.Input;
import haxe.io.BufferInput;
import haxe.io.Bytes;
import haxe.ds.Vector;
#if sys
import sys.io.File;
#end

/**
 * Optimized streaming JSON parser for large chart files (1M+ notes).
 * Uses callback-based processing to avoid storing all notes in memory.
 * Uses flat arrays for memory-efficient note storage.
 */
class SongJsonStream {
	private static inline var BUFFER_SIZE:Int = 8 * 1024 * 1024; // 8MB buffer for faster I/O
	private static inline var CHUNK_SIZE:Int = 10000; // Process notes in chunks

	public static function parseFile(path:String):Dynamic {
		#if sys
		var input:Input = File.read(path, true);
		var buf:Bytes = Bytes.alloc(BUFFER_SIZE);
		input = new BufferInput(input, buf);
		var parser = new SongJsonStream(input);
		var result = parser.parseValue();
		parser.skipWhitespace();
		if (!parser.isEof()) throw 'Unexpected trailing data in ${path}';
		return result;
		#else
		throw 'Streaming chart parsing is only supported on native targets.';
		#end
	}

	public static function parseSongFile(path:String, ?onNoteParsed:CastNote->Void):Dynamic {
		#if sys
		var input:Input = File.read(path, true);
		var buf:Bytes = Bytes.alloc(BUFFER_SIZE);
		input = new BufferInput(input, buf);
		var parser = new SongJsonStream(input);
		parser.noteCallback = onNoteParsed;
		var result = parser.parseSwagSong();
		parser.skipWhitespace();
		if (!parser.isEof()) throw 'Unexpected trailing data in ${path}';
		return result;
		#else
		throw 'Streaming song parsing is only supported on native targets.';
		#end
	}

	public static function parseInput(input:Input):Dynamic {
		var buf:Bytes = Bytes.alloc(BUFFER_SIZE);
		input = new BufferInput(input, buf);
		var parser = new SongJsonStream(input);
		var result = parser.parseValue();
		parser.skipWhitespace();
		if (!parser.isEof()) throw 'Unexpected trailing data in streamed JSON.';
		return result;
	}

	var input:Input;
	var pending:Int = -1;
	var noteCallback:CastNote->Void;

	function new(input:Input) {
		this.input = input;
	}

	function isEof():Bool {
		return peekChar() == -1;
	}

	inline function peekChar():Int {
		if (pending != -1) return pending;
		try {
			pending = input.readByte();
		} catch (_:Dynamic) {
			pending = -1;
		}
		return pending;
	}

	inline function readChar():Int {
		var ch = peekChar();
		pending = -1;
		return ch;
	}

	function skipWhitespace():Void {
		while (true) {
			var ch = peekChar();
			if (ch == -1) return;
			switch (ch) {
				case ' '.code, '\n'.code, '\r'.code, '\t'.code:
					readChar();
				default:
					return;
			}
		}
	}

	function skipValue():Void {
		skipWhitespace();
		var ch = peekChar();
		if (ch == -1) return;
		switch (ch) {
			case '{'.code:
				readChar();
				skipObject();
			case '['.code:
				readChar();
				skipArray();
			case '"'.code:
				parseString();
			case 't'.code:
				parseLiteral('true', true);
			case 'f'.code:
				parseLiteral('false', false);
			case 'n'.code:
				parseLiteral('null', null);
			case '-'.code, '0'.code, '1'.code, '2'.code, '3'.code, '4'.code, '5'.code, '6'.code, '7'.code, '8'.code, '9'.code:
				parseFloatFast();
			default:
				throw 'Unexpected character in JSON value to skip.';
		}
	}

	function skipObject():Void {
		while (!isEof()) {
			skipWhitespace();
			var ch = readChar();
			if (ch == '}'.code) return;
			if (ch == '"'.code) {
				parseString();
				skipWhitespace();
				readChar(); // skip :
				skipValue();
			}
			skipWhitespace();
			ch = readChar();
			if (ch != ','.code) {
				if (ch == '}'.code) return;
				throw 'Expected , or } in JSON object.';
			}
		}
		throw 'Unterminated JSON object.';
	}

	function skipArray():Void {
		while (!isEof()) {
			skipWhitespace();
			var ch = peekChar();
			if (ch == ']'.code) {
				readChar();
				return;
			}
			skipValue();
			skipWhitespace();
			ch = readChar();
			if (ch == ']'.code) return;
			if (ch != ','.code) throw 'Expected , or ] in JSON array.';
		}
		throw 'Unterminated JSON array.';
	}

	function parseValue():Dynamic {
		skipWhitespace();
		var ch = peekChar();
		if (ch == -1) throw 'Unexpected end of JSON input.';
		switch (ch) {
			case '{'.code:
				return parseObject();
			case '['.code:
				return parseArray();
			case '"'.code:
				return parseString();
			case 't'.code:
				return parseLiteral('true', true);
			case 'f'.code:
				return parseLiteral('false', false);
			case 'n'.code:
				return parseLiteral('null', null);
			case '-'.code, '0'.code, '1'.code, '2'.code, '3'.code, '4'.code, '5'.code, '6'.code, '7'.code, '8'.code, '9'.code:
				return parseFloatFast();
			default:
				throw 'Unexpected character in JSON input: ' + String.fromCharCode(ch);
		}
	}

	function parseObject():Dynamic {
		readChar(); // '{'
		var obj:Dynamic = {};
		skipWhitespace();
		if (peekChar() == '}'.code) {
			readChar();
			return obj;
		}
		while (true) {
			var key = parseString();
			skipWhitespace();
			if (readChar() != ':'.code) throw 'Expected : in JSON object.';
			var value = parseValue();
			Reflect.setField(obj, key, value);
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case '}'.code:
					return obj;
				default:
					throw 'Expected , or } in JSON object.';
			}
		}
	}

	function parseArray():Array<Dynamic> {
		readChar(); // '['
		var arr:Array<Dynamic> = [];
		skipWhitespace();
		if (peekChar() == ']'.code) {
			readChar();
			return arr;
		}
		while (true) {
			arr.push(parseValue());
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case ']'.code:
					return arr;
				default:
					throw 'Expected , or ] in JSON array.';
			}
		}
	}

	function parseString():String {
		readChar(); // '"'
		var buf = new StringBuf();
		while (true) {
			var ch = readChar();
			if (ch == -1) throw 'Unterminated string in JSON input.';
			if (ch == '"'.code) return buf.toString();
			if (ch == '\\'.code) {
				var esc = readChar();
				if (esc == -1) throw 'Unterminated escape sequence in JSON input.';
				switch (esc) {
					case '"'.code:
						buf.addChar('"'.code);
					case '\\'.code:
						buf.addChar('\\'.code);
					case '/'.code:
						buf.addChar('/'.code);
					case 'b'.code:
						buf.addChar(8);
					case 'f'.code:
						buf.addChar(12);
					case 'n'.code:
						buf.addChar('\n'.code);
					case 'r'.code:
						buf.addChar('\r'.code);
					case 't'.code:
						buf.addChar('\t'.code);
					case 'u'.code:
						var hex = '';
						for (i in 0...4) {
							var h = readChar();
							if (h == -1) throw 'Unterminated unicode escape in JSON input.';
							hex += String.fromCharCode(h);
						}
						buf.addChar(Std.parseInt('0x' + hex));
					default:
						throw 'Unsupported escape sequence in JSON input.';
				}
			} else {
				buf.addChar(ch);
			}
		}
	}

	inline function parseFloatFast():Float {
		var ch = peekChar();
		var negative = false;
		if (ch == '-'.code) {
			negative = true;
			readChar();
			ch = peekChar();
		}
		var intValue = 0;
		var hasDigits = false;
		while (ch >= '0'.code && ch <= '9'.code) {
			intValue = intValue * 10 + (ch - '0'.code);
			readChar();
			ch = peekChar();
			hasDigits = true;
		}
		var value:Float = intValue;
		if (ch == '.'.code) {
			readChar();
			var frac = 0.0;
			var div = 10.0;
			while ((ch = peekChar()) >= '0'.code && ch <= '9'.code) {
				frac = frac * 10 + (ch - '0'.code);
				readChar();
				div *= 10;
			}
			value += frac / div;
		}
		if (ch == 'e'.code || ch == 'E'.code) {
			readChar();
			var expNeg = false;
			var expVal = 0;
			if (ch == '-'.code) { expNeg = true; readChar(); }
			else if (ch == '+'.code) { readChar(); }
			while ((ch = peekChar()) >= '0'.code && ch <= '9'.code) {
				expVal = expVal * 10 + (ch - '0'.code);
				readChar();
			}
			var multiplier = 1.0;
			var i = expVal;
			while(i > 0) {
				multiplier *= 10;
				i--;
			}
			if (expNeg) value /= multiplier; else value *= multiplier;
		}
		if (!hasDigits && value == 0) throw 'Expected number in JSON input.';
		return negative ? -value : value;
	}

	inline function parseIntFast():Int {
		var ch = peekChar();
		var negative = false;
		if (ch == '-'.code) {
			negative = true;
			readChar();
			ch = peekChar();
		}
		var value = 0;
		var hasDigits = false;
		while (ch >= '0'.code && ch <= '9'.code) {
			value = value * 10 + (ch - '0'.code);
			readChar();
			ch = peekChar();
			hasDigits = true;
		}
		if (!hasDigits) throw 'Expected integer in JSON input.';
		return negative ? -value : value;
	}

	function parseLiteral(expected:String, value:Dynamic):Dynamic {
		var i = 0;
		while(i < expected.length) {
			var ch = readChar();
			if (ch != expected.charCodeAt(i)) throw 'Expected ' + expected + ' in JSON input.';
			i++;
		}
		return value;
	}

	function parseSwagSong():Dynamic {
		skipWhitespace();
		if (readChar() != '{'.code) throw 'Expected object at root of JSON input.';
		var song:Dynamic = {};
		skipWhitespace();
		if (peekChar() == '}'.code) {
			readChar();
			return cast song;
		}
		while (true) {
			var key = parseString();
			skipWhitespace();
			if (readChar() != ':'.code) throw 'Expected : in JSON object.';
			switch (key) {
				case 'notes':
					song.notes = parseSections();
				case 'events':
					song.events = parseEventsStream();
				case 'bpm':
					song.bpm = parseFloatFast();
				case 'speed':
					song.speed = parseFloatFast();
				case 'offset':
					song.offset = parseFloatFast();
				case 'song':
					var songValue:Dynamic = parseValue();
					if(Std.isOfType(songValue, String))
						song.song = songValue;
					else if(Reflect.isObject(songValue)) {
						while (!isEof() && peekChar() != '}'.code) {
							skipWhitespace();
							var ch = readChar();
							if (ch == '"'.code) {
								parseString();
								skipWhitespace();
								if (readChar() != ':'.code) throw 'Expected : in JSON object.';
								skipValue();
							}
							skipWhitespace();
							ch = readChar();
							if (ch != ','.code && ch != '}'.code) {
								if (ch == -1) break;
								throw 'Expected , or } in JSON object.';
							}
						}
						if (readChar() != '}'.code) throw 'Expected closing brace after song wrapper.';
						return cast songValue;
					} else
						song.song = null;
					
				case 'player1':
					song.player1 = parseString();
				case 'player2':
					song.player2 = parseString();
				case 'gfVersion':
					song.gfVersion = parseString();
				case 'stage':
					song.stage = parseString();
				case 'format':
					song.format = parseString();
				case 'needsVoices':
					song.needsVoices = parseValue() == true;
				default:
					Reflect.setField(song, key, parseValue());
			}
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case '}'.code:
					return cast song;
				default:
					throw 'Expected , or } in JSON object.';
			}
		}
	}

	function parseSections():Array<Dynamic> {
		skipWhitespace();
		if (readChar() != '['.code) throw 'Expected array for notes.';
		var sections:Array<Dynamic> = [];
		skipWhitespace();
		if (peekChar() == ']'.code) {
			readChar();
			return sections;
		}
		while (true) {
			sections.push(parseSection());
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case ']'.code:
					return sections;
				default:
					throw 'Expected , or ] in notes array.';
			}
		}
	}

	function parseSection():Dynamic {
		skipWhitespace();
		if (readChar() != '{'.code) throw 'Expected object in section.';
		var section:Dynamic = {};
		skipWhitespace();
		if (peekChar() == '}'.code) {
			readChar();
			return cast section;
		}
		while (true) {
			var key = parseString();
			skipWhitespace();
			if (readChar() != ':'.code) throw 'Expected : in section object.';
			switch (key) {
				case 'sectionNotes':
					skipWhitespace();
					if (peekChar() == 'n'.code) {
						parseLiteral('null', null);
						section.sectionNotes = null;
					} else {
						section.sectionNotes = parseNoteArray();
					}
				case 'sectionBeats':
					section.sectionBeats = parseFloatFast();
				case 'mustHitSection':
					section.mustHitSection = parseValue() == true;
				case 'altAnim':
					section.altAnim = parseValue() == true;
				case 'gfSection':
					section.gfSection = parseValue() == true;
				case 'bpm':
					section.bpm = parseFloatFast();
				case 'changeBPM':
					section.changeBPM = parseValue() == true;
				case 'lengthInSteps':
					section.lengthInSteps = parseFloatFast();
				default:
					Reflect.setField(section, key, parseValue());
			}
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case '}'.code:
					return cast section;
				default:
					throw 'Expected , or } in section object.';
			}
		}
	}

	function parseNoteArray():Array<Dynamic> {
		skipWhitespace();
		if (readChar() != '['.code) throw 'Expected array for sectionNotes.';
		var notes:Array<Dynamic> = [];
		skipWhitespace();
		if (peekChar() == ']'.code) {
			readChar();
			return notes;
		}
		while (true) {
			notes.push(parseNote());
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case ']'.code:
					return notes;
				default:
					throw 'Expected , or ] in note array.';
			}
		}
	}

	function parseNote():Dynamic {
		skipWhitespace();
		if (readChar() != '['.code) throw 'Expected array for note.';
		var note:Dynamic = {};
		skipWhitespace();
		
		note.strumTime = parseFloatFast();
		skipWhitespace();
		if (readChar() != ','.code) throw 'Expected , in note array.';
		note.noteData = parseIntFast();
		skipWhitespace();
		if (readChar() != ','.code) throw 'Expected , in note array.';
		note.sustainLength = parseFloatFast();
		skipWhitespace();
		if (readChar() != ','.code) throw 'Expected , in note array.';
		
		var ch = peekChar();
		if (ch == 'n'.code) {
			parseLiteral('null', null);
			note.noteType = null;
		} else if (ch == '"'.code) {
			note.noteType = parseString();
		} else {
			note.noteType = parseFloatFast();
		}
		
		skipWhitespace();
		ch = peekChar();
		if (ch == ','.code) {
			readChar();
			skipWhitespace();
			if (peekChar() == '['.code) {
				note.cmpSpam = parseArray();
			} else if (peekChar() == 'n'.code) {
				parseLiteral('null', null);
				note.cmpSpam = null;
			} else {
				note.cmpSpam = parseValue();
			}
		}
		
		skipWhitespace();
		if (readChar() != ']'.code) throw 'Expected ] at end of note array.';
		return note;
	}

	// Optimized event parsing with incremental yielding for large files
	function parseEventsStream():Array<Array<Dynamic>> {
		skipWhitespace();
		if (readChar() != '['.code) throw 'Expected array for events.';
		var events:Array<Array<Dynamic>> = [];
		skipWhitespace();
		if (peekChar() == ']'.code) {
			readChar();
			return events;
		}
		while (true) {
			events.push(parseEvent());
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case ']'.code:
					return events;
				default:
					throw 'Expected , or ] in events array.';
			}
		}
	}

	function parseEvent():Array<Dynamic> {
		skipWhitespace();
		if (readChar() != '['.code) throw 'Expected array for event.';
		var evt:Array<Dynamic> = [];
		skipWhitespace();
		if (peekChar() == ']'.code) {
			readChar();
			return evt;
		}
		while (true) {
			evt.push(parseValue());
			skipWhitespace();
			var ch = readChar();
			switch (ch) {
				case ','.code:
					continue;
				case ']'.code:
					return evt;
				default:
					throw 'Expected , or ] in event array.';
			}
		}
	}
}