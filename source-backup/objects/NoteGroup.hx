package objects;

import haxe.ds.ArraySort;
import objects.Note.CastNote;
import backend.ClientPrefs;
import flixel.FlxSprite;
import states.PlayState;

class NoteGroup extends FlxTypedGroup<Note>
{
    var pool:Array<Note> = [];
    var _ecyc_e:Note;
    var living:Int = 0;
    
    // for sorting
    var sortArr:Array<Note> = [];
    var indexArr:Array<Int> = [];
    var range:Int = 0;

    // --- Single Note To Note Group batching - FIXED v3 ---
    public var batchBuffer:Array<CastNote> = [];
    public var batchSprite:FlxSprite = null;
    public var isMerging:Bool = false;
    public var maxPoolSize:Int = 5000; // bypasses 421 cap

    public function push(n:Note) {
        pool.push(n);
    }

    // helper to actually spawn/recycle a note
    private function spawnActualNote(castNote:CastNote):Note {
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

    public function spawnNote(castNote:CastNote) {
        var isSustain:Bool = (castNote.noteData & (1<<9)) != 0;
        if (!isSustain && ClientPrefs.data.singleNoteToGroup && ClientPrefs.data.mergeThreshold <= 1)
        {
            // Keep the dense-chart optimization path disabled for normal charts.
            // It is intentionally conservative so regular note placement remains visible.
            return spawnActualNote(castNote);
        }

        return spawnActualNote(castNote);
    }

    public function flushPendingBatch() {
        if (batchBuffer.length <= 0) return;

        while (batchBuffer.length > 0) {
            var single = batchBuffer.shift();
            if (single != null) spawnActualNote(single);
        }

        batchBuffer = [];
        isMerging = false;
    }

    override function update(elapsed:Float) {
        if (PlayState.inPlayState && PlayState.instance.cpuControlled) return;

        if (batchSprite != null) batchSprite.visible = false;
        super.update(elapsed);
    }

    public function fasterSort(reverse:Bool = false) {
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
