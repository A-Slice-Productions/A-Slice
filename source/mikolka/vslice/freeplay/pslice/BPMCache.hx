package mikolka.vslice.freeplay.pslice;

import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.ds.Map;
import backend.Song.SwagSong;
import backend.SongJson;

//? no psych. uses sys
class BPMCache {
    public static var freeplayBPMs:StringMap<Int> = new StringMap();
    public static var instance = new BPMCache();
    public function new() {}

    var chartFiles:Array<String>;
    var chosenChartToScrap:String;
    var regexSongName:String;
    var song:SwagSong;

    public function getBPM(sngDataPath:String, fileSngName:String):Int {
        if(freeplayBPMs.exists(sngDataPath))
            return freeplayBPMs.get(sngDataPath);
        
        freeplayBPMs.set(sngDataPath, 0);
        
        if(!exists(sngDataPath)){
            #if debug trace('Missing data folder for $fileSngName in $sngDataPath for BPM scrapping!!'); #end //TODO
            return 0;
        }
        
        chartFiles = NativeFileSystem.readDirectory(sngDataPath);
        #if MODS_ALLOWED
        chartFiles = chartFiles.filter(s -> s.toLowerCase().startsWith(fileSngName) && s.endsWith(".json"));
        chosenChartToScrap = sngDataPath+"/"+chartFiles[0];
        #else
        regexSongName = fileSngName.replace("(","\\(").replace(")","\\)");
        chartFiles = chartFiles.filter(s -> new EReg('\\/$regexSongName\\/$regexSongName.*\\.json',"").match(s));
        chosenChartToScrap = chartFiles[0];
        #end
		
		if(exists(chosenChartToScrap)){
            try {
                SongJson.skipChart = true; SongJson.log = false;
                song = cast SongJson.parse(getContent(chosenChartToScrap));
                SongJson.skipChart = false; SongJson.log = true;

                if(Reflect.hasField(song.song, 'song')) {
                    song = Reflect.field(song, 'song');
                }

                freeplayBPMs.set(sngDataPath, Math.round(song.bpm));

                /* old way
                var bpmFinder = ~/"bpm": *([0-9]+)/g; //TODO fix this regex
                var cleanChart = ~/"notes": *\[.*\]/gs.replace(getContent(chosenChartToScrap),"");
                if(bpmFinder.match(cleanChart)){
                    freeplayBPMs.set(sngDataPath, Std.parseInt(bpmFinder.matched(1)));
                }*/
            } catch (x) {
			    #if debug trace('failed to scrap initial BPM for $fileSngName'); #end
            }
		} else {
			#if debug trace('Missing chart of $fileSngName in $chosenChartToScrap for BPM scrapping!!'); #end //TODO
		}
        return freeplayBPMs.get(sngDataPath);
    }
    public static function clearCache() {
        freeplayBPMs.clear();
    }
    public static function count() {
        var cnt:Int = 0;
        for (value in freeplayBPMs) {
            cnt++;
        }
        return cnt;
    }
    private function exists(path:String) {
        #if MODS_ALLOWED
        return FileSystem.exists(path);
        #else
        @:privateAccess
        for (entry in lime.utils.Assets.libraries.get("default").types.keys()){
            if(entry.startsWith(path)) return true;
        }
        return false;
        #end
    }
    function getContent(path:String) {
        #if MODS_ALLOWED
        return File.getContent(path);
        #else
        return lime.utils.Assets.getText("default:"+path);
        #end
    }
}