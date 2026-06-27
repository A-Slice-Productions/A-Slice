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

    public function push(n:Note) {
        pool.push(n);
    }

    public function spawnNote(castNote:CastNote) {
        // Single Note To Note Group optimization
        if (ClientPrefs.data.singleNoteToGroup && !((castNote.noteData & (1<<9)) != 0)) // skip sustains for now
        {
            batchBuffer.push(castNote);
            // Return a dummy recycled note that won't render
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

        // Update batch sprite if Single Note To Note Group is enabled
        if (ClientPrefs.data.singleNoteToGroup && batchBuffer.length > 0)
        {
            if (batchSprite == null) {
                batchSprite = new FlxSprite().makeGraphic(1, 1, 0x00FFFFFF);
                batchSprite.visible = false; // placeholder - actual drawTriangles would go here
            }
            // TODO: Implement drawTriangles batch rendering using batchBuffer data
            // For now, we just keep notes in buffer for hit detection
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
