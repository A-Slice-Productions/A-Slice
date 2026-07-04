#if desktop
package backend;

import lime.math.Rectangle;
import haxe.io.Bytes;
import lime.graphics.Image;
import flixel.FlxG;
import lime.ui.Window;
import sys.FileSystem;
import sys.io.Process;
import sys.thread.Mutex;
import sys.thread.Thread;
import options.GameRendererSettingsSubState;

class FFMpeg {
    var x:Int;
    var y:Int;
    var window:Window;
    var buffer:Rectangle;
    public var target:String = "render_video";
    public var fileName:String = "";
    public var fileExts:String = ".mp4";
    public var wentPreview:String = null;
    public var process:Process;
    public static var instance:FFMpeg;
    
    var writeQueue:Array<Bytes> = [];
    var queueMutex:Mutex = new Mutex();
    var writerThread:Thread;
    var writerRunning:Bool = false;
    var framesWritten:Int = 0;
    
    var oldMaxElapsed:Float; 
    
    static inline var MAX_QUEUE:Int = #if linux 45 #else 15 #end;
    
    public function new() {
        instance = this;
    }
    
    public function init():Void {
        if (!FileSystem.exists(target)) {
            FileSystem.createDirectory(target);
        }
        window = FlxG.stage.application.window;
        x = window.width;
        y = window.height;
        framesWritten = 0;
    }
    
    function findFFmpeg():String {
        #if windows
        if (FileSystem.exists("./ffmpeg.exe")) return "./ffmpeg.exe";
        return "ffmpeg.exe";
        #else
        if (FileSystem.exists("./ffmpeg")) {
            try { Sys.command("chmod +x ./ffmpeg"); } catch (e:Dynamic) {}
            return "./ffmpeg";
        }
        return "ffmpeg";
        #end
    }
    
    public function setup(testMode:Bool = false):Void {
        var exe = findFFmpeg();
        try {
            var check = new Process(exe, ["-version"]);
            check.close();
        } catch (e:Dynamic) {
            trace("[FFMPEG] not found: " + exe);
            wentPreview = exe + " not found - install with: sudo apt install ffmpeg";
            ClientPrefs.data.previewRender = true;
            return;
        }
        
        var codec = ClientPrefs.data.codec;
        var mapped = GameRendererSettingsSubState.codecMap[codec];
        var isGPU = CoolUtil.searchFromStrings(codec, ["QSV", "NVENC", "AMF", "VAAPI"]);
        fileExts = CoolUtil.searchFromString(codec, "VP") ? ".webm" : ".mp4";
        fileName = target + "/" + (testMode ? "test-" + codec : Paths.formatToSongPath(PlayState.SONG.song));
        
        if (FileSystem.exists(fileName + fileExts)) {
            fileName += "-" + Date.now().getTime();
        }
        
        var outPath = fileName + fileExts;
        var pixFmt = "rgba";
        var fps = "60";
        var args:Array<String> = [
            "-y",
            "-f", "rawvideo",
            "-pix_fmt", pixFmt,
            "-s", x + "x" + y,
            "-r", fps,
            "-i", "-",
            "-an",
            "-c:v", mapped
        ];
        
        if (mapped == "libx264" || mapped == "libx265") {
            args.push("-preset"); args.push("ultrafast");
            args.push("-tune"); args.push("zerolatency");
            args.push("-pix_fmt"); args.push("yuv420p");
        }
        if (mapped == "h264_vaapi" || mapped == "hevc_vaapi") {
            args.unshift("/dev/dri/renderD128");
            args.unshift("-vaapi_device");
            args.push("-vf"); args.push("format=nv12,hwupload");
        }
        
        switch (ClientPrefs.data.encodeMode) {
            case "CRF/CQP":
                args.push(isGPU ? "-qp" : "-crf");
                args.push(Std.string(ClientPrefs.data.constantQuality));
            case "VBR", "CBR":
                var br = Std.string(ClientPrefs.data.bitrate * 1000000);
                args.push("-b:v"); args.push(br);
                if (ClientPrefs.data.encodeMode == "CBR") {
                    args.push("-maxrate"); args.push(br);
                    args.push("-minrate"); args.push(br);
                    args.push("-bufsize"); args.push(br);
                }
        }
        
        args.push("-movflags"); args.push("+faststart");
        args.push("-max_muxing_queue_size"); args.push("9999");
        args.push(outPath);
        
        trace("[FFMPEG] " + exe + " " + args.join(" "));
        trace("[FFMPEG] Output: " + Sys.getCwd() + "/" + outPath);
        
        try {
            process = new Process(exe, args);
        } catch (e:Dynamic) {
            trace("[FFMPEG] Failed to start: " + e);
            wentPreview = "Failed to start ffmpeg";
            ClientPrefs.data.previewRender = true;
            return;
        }
        
        buffer = new Rectangle(0, 0, x, y);
        writeQueue = [];
        framesWritten = 0;
        writerRunning = true;
        writerThread = Thread.create(writerLoop);
        
        oldMaxElapsed = FlxG.maxElapsed;
        FlxG.maxElapsed = 1 / 60; 
        FlxG.autoPause = false;
        
        if (!testMode) {
            FlxG.sound.play(Paths.sound("confirmMenu"), ClientPrefs.data.sfxVolume);
        }
    }
    
    function writerLoop():Void {
        while (writerRunning || writeQueue.length > 0) {
            var frame:Bytes = null;
            queueMutex.acquire();
            if (writeQueue.length > 0) {
                frame = writeQueue.shift();
            }
            queueMutex.release();
            
            if (frame != null && process != null) {
                try {
                    if (process.exitCode(false) != null) {
                        writerRunning = false;
                        break;
                    }
                    process.stdin.writeBytes(frame, 0, frame.length);
                    framesWritten++;
                } catch (e:Dynamic) {
                    trace("[FFMPEG] Write error: " + e);
                    writerRunning = false;
                    break;
                }
            } else {
                Sys.sleep(0.003);
            }
        }
        try {
            if (process != null && process.stdin != null) {
                process.stdin.close();
            }
        } catch (e:Dynamic) {}
    }
    
    inline function enqueueFrame(data:Bytes):Void {
        var added = false;
        
        while (!added) {
            queueMutex.acquire();
            
            if (writeQueue.length < MAX_QUEUE) {
                writeQueue.push(data);
                added = true;
            }
            
            queueMutex.release();
            
            if (!added) {
                Sys.sleep(0.002);
            }
        }
    }
    
    public function pipeFrame():Void {
        if (process == null) return;
        
        // Grab the window pixels immediately
        var image:Image = window.readPixels();
        if (image == null) return;
        
        // Directly pull the byte array snapshot out of Lime's Image instead of caching it across frames.
        // This stops old data from mixing into the frame stream.
        var pixels = image.getPixels(buffer);
        if (pixels == null) return;

        var copy = Bytes.alloc(pixels.length);
        copy.blit(0, pixels, 0, pixels.length);
        
        enqueueFrame(copy);
    }
    
    public function destroy():Void {
        if (process == null) return;
        trace("[FFMPEG] Stopping... frames written: " + framesWritten);
        writerRunning = false;
        
        var waitTime = 0.0;
        while (waitTime < 3.0) {
            queueMutex.acquire();
            var remaining = writeQueue.length;
            queueMutex.release();
            if (remaining == 0) break;
            Sys.sleep(0.02);
            waitTime += 0.02;
        }
        
        try {
            if (process.stdin != null) process.stdin.close();
        } catch (e:Dynamic) {}
        
        var exitCode = -1;
        var stderr = "";
        try {
            exitCode = process.exitCode(true);
            stderr = process.stderr.readAll().toString();
        } catch (e:Dynamic) {}
        
        try {
            process.close();
        } catch (e:Dynamic) {}
        process = null;
        
        trace("[FFMPEG] Exit code: " + exitCode + ", frames: " + framesWritten);
        if (stderr.length > 0 && exitCode != 0) {
            trace("[FFMPEG] Error: " + stderr.substr(0, 300));
            wentPreview = "ffmpeg error";
        }
        
        var path = fileName + fileExts;
        if (FileSystem.exists(path)) {
            var size = FileSystem.stat(path).size;
            trace("[FFMPEG] File size: " + size + " bytes");
            if (size < 2048) {
                FileSystem.deleteFile(path);
                wentPreview = "Video too small - ffmpeg crashed";
            }
        }
        
        writeQueue = [];
        FlxG.maxElapsed = oldMaxElapsed; 
        FlxG.autoPause = ClientPrefs.data.autoPause;
    }
}
#end
