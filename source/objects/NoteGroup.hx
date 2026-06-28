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
        // --- FIXED v3: proximity merging instead of count ---
        if (ClientPrefs.data.singleNoteToGroup)
        {
            var isSustain:Bool = (castNote.noteData & (1<<9)) != 0;
            if (!isSustain)
            {
                var shouldMerge:Bool = false;
                if (batchBuffer.length > 0) {
                    var lastNote = batchBuffer[batchBuffer.length - 1];
                    var sameColumn:Bool = (castNote.noteData & 0xFF) == (lastNote.noteData & 0xFF);
                    var timeDiff:Float = Math.abs(castNote.strumTime - lastNote.strumTime);
                    // 0.45 is Psych's default pixel-per-ms at scroll speed 1
                    var songSpeed:Float = (PlayState.instance != null) ? PlayState.instance.songSpeed : 1.0;
                    var pixelDistance:Float = timeDiff * 0.45 * songSpeed;
                    
                    if (sameColumn && pixelDistance < ClientPrefs.data.mergeDistance) {
                        shouldMerge = true;
                    }
                } else {
                    shouldMerge = true; // first note starts batch
                }

                if (shouldMerge && batchBuffer.length < ClientPrefs.data.maxNotesBeforeMerge)
                {
                    batchBuffer.push(castNote);
                    isMerging = true;
                    // return invisible dummy
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
                } else {
                    // not close enough - render previous batch
                    if (batchBuffer.length > 1) {
                        renderBatchAsOneFrame();
                    } else if (batchBuffer.length == 1) {
                        var single = batchBuffer[0];
                        batchBuffer = [];
                        // spawn the single normally before starting new batch
                        var realNote = spawnActualNote(single);
                        batchBuffer.push(castNote);
                        return realNote;
                    }
                    batchBuffer = [castNote];
                    // return dummy for current note (will be rendered with next batch)
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
        }

        // normal spawn
        return spawnActualNote(castNote);
    }

    function renderBatchAsOneFrame() {
        if (batchBuffer.length == 0) return;
        
        if (batchSprite == null) {
            batchSprite = new FlxSprite();
            batchSprite.makeGraphic(Std.int(Note.swagWidth), 100, 0x00000000, true);
            batchSprite.antialiasing = ClientPrefs.data.antialiasing;
            // add to group so it renders - PlayState will handle positioning
            if (PlayState.instance != null) {
                PlayState.instance.add(batchSprite);
                batchSprite.cameras = [PlayState.instance.camHUD];
            }
        }
        
        // Simple version: just make sprite visible and size it to batch height
        var totalHeight:Int = Std.int(batchBuffer.length * Note.swagWidth * 0.8);
        if (totalHeight > batchSprite.height) {
            batchSprite.makeGraphic(Std.int(Note.swagWidth), totalHeight, 0x00000000, true);
        }
        batchSprite.visible = true;
        batchSprite.alpha = 0.9; // visible for testing
        
        // Clear buffer
        batchBuffer = [];
        isMerging = false;
    }

    override function update(elapsed:Float) {
        if (PlayState.inPlayState && PlayState.instance.cpuControlled) return;

        // --- FIXED: hide individual notes when merging ---
        if (ClientPrefs.data.singleNoteToGroup && isMerging)
        {
            if (batchSprite != null) batchSprite.visible = true;
            // hide individual notes in buffer range
            for (note in members) if (note.exists && !note.isSustainNote) note.visible = false;
        } else {
            if (batchSprite != null) batchSprite.visible = false;
        }

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
