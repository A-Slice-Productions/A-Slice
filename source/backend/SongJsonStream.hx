package backend;

// Intentionally not enabled in this build.
// A previous streaming parser caused chart load failures.
// Charts will use the non-streaming SongJson parser (backend/SongJson.hx).
class SongJsonStream {
	public static inline function parseFile(path:String):Dynamic {
		throw 'SongJsonStream is disabled (chart stream parser causes chart load breaks).';
	}
	public static inline function parseSongFile(path:String, ?onNoteParsed:Dynamic->Void):Dynamic {
		throw 'SongJsonStream is disabled (chart stream parser causes chart load breaks).';
	}
	public static inline function parseInput(input:Dynamic):Dynamic {
		throw 'SongJsonStream is disabled (chart stream parser causes chart load breaks).';
	}
}

