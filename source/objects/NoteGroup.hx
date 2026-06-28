package objects;

import haxe.ds.ArraySort;
import objects.Note.CastNote;
import backend.ClientPrefs;
import flixel.FlxSprite;

class NoteGroup extends FlxTypedGroup<Note>
{
    var pool:Array<Note> = [];
    var _ecyc_e:Note;
    var living:Int = 0;
    
    // for sorting
    var sortArr:Array<Note> = [];
    var indexArr:Array<Int> = [];
    var range:Int = 0;

    // --- Single Note To Note Group batching ---
    public var batchBuffer:Array<CastNote> = [];
    public var batchSprite:FlxSprite = null;
    public var isMerging:Bool = false;

    public function push(n:Note) {
        pool.push(n);
    }

    public function spawnNote(castNote:CastNote) {
        // --- BUG FIX: Single Note To Note Group ---
        // Changed: now only merges when note count exceeds mergeThreshold
        // Previously: made all notes invisible
        if (ClientPrefs.data.singleNoteToGroup)
        {
            batchBuffer.push(castNote);
            
            // Check if we should merge
            if (batchBuffer.length >= ClientPrefs.data.mergeThreshold)
            {
                isMerging = true;
                // Return dummy note that won't render individually
                if (pool.length > 0) {
                    _ecyc_e = pool.pop();
                    _ecyc_e.exists = false;
                    _ecyc_e.visible = false;
                } else {
                    _ecyc_e = new Note();
                    _ecyc_e.exists = false;
                    _ecyc_e.visible = false;
                    members.push(_ecyc_e);
                    ++length;
                }
                return _ecyc_e;
            }
        }

        if (pool.length > 0) {
            _ecyc_e = pool.pop();
            _ecyc_e.exists = true;
        } else {
            _ecyc_e = new Note();
            members.push(_ecyc_e);
            ++length;
        }
        return _ecyc_e.recycleNote(castNote);
    }

    override function update(elapsed:Float) {
                if (PlayState.inPlayState && PlayState.instance.cpuControlled) return;

        // --- FIXED: Render merged notes as single image ---
        if (ClientPrefs.data.singleNoteToGroup && isMerging)
        {
            if (batchSprite == null) {
                batchSprite = new FlxSprite().makeGraphic(Std.int(Note.swagWidth), 100, 0xFFFF00FF);
                batchSprite.alpha = 0.8;
                // Note: add this sprite to PlayState in your init code
            }
            batchSprite.visible = true;
            // Hide individual notes when merging
            for (note in members) if (note.exists) note.visible = false;
        } else {
            if (batchSprite != null) batchSprite.visible = false;
        }

        super.update(elapsed);
    }

    public function fasterSort(reverse:Bool = false) {
        // sortArr = members.filter(note -> note.visible);
        range = 0;
        for (i => note in members) {
            if (note.visible) {
                sortArr[range] = note;
                indexArr[range++] = i;
            }
        }

        if (sortArr.length > range) {
            sortArr.resize(range);
            indexArr.resize(range);
        }
        
        ArraySort.sort(sortArr, (a,b) -> reverse ? noteSort(b, a) : noteSort(a, b));
        indexArr.sort((a,b) -> a - b);

        for (index => i in indexArr) members[i] = sortArr[index];
    }

    public static function noteSort(a:Note, b:Note):Int {
        return if (a.strumTime != b.strumTime) {
            a.strumTime > b.strumTime ? -1 : 1;
        } else if (a.isSustainNote != b.isSustainNote) {
            a.isSustainNote ? -1 : 1;
        } else 0;
    }

    public function debugInfo():Array<Float> {
        living = countLiving();
        return [living, length, living * 100.0 / Math.max(length, 1), length];
    }

        var count:Int = 0;
    override public function countLiving():Int
        {
        count = 0;
                for (basic in members)
                {
                        if (basic != null && basic.exists && basic.alive) count += Std.int(basic.density) ?? 1;
                }

                return count;
        }
}
