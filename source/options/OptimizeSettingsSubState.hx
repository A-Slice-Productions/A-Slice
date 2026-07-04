package options;

class OptimizeSettingsSubState extends BaseOptionsMenu
{
	var cacheCount:Option;

	public static final SORT_PATTERN:Array<String> = [
		'Never',
		'After Note Spawned',
		'After Note Processed',
		'After Note Finalized',
		'Reversed',
		'Chaotic',
		'Random',
		'Shuffle',
	];

	public function new()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Optimizations Menu", null);
		#end
		
		title = 'Optimizations';
		rpcTitle = 'Optimization Settings Menu'; //for Discord Rich Presence

		//Working in Progress!
		var option:Option = new Option('Work in Progress', //Name
			"Make changes at your own risk.", //Description
			'openDoor', //Save data variable name
			STRING,
			['!']); //Variable type
		addOption(option);

		var option:Option = new Option('Show Notes',
			"If unchecked, appearTime is set to 0.\nAll notes will be processed as skipped notes.\nBotplay is forced on.",
			'showNotes',
			BOOL);
		addOption(option);

		var option:Option = new Option('Show Notes again after Skip',
			"If checked, it tries to prevent notes from showing only halfway through.",
			'showAfter',
			BOOL);
		addOption(option);

		var option:Option = new Option('Keep Notes in Screen',
			"If checked, notes will display from top to bottom, even if they are skippable.\nIf unchecked, it improves performance, especially if a lot of notes are displayed.",
			'keepNotes',
			BOOL);
		addOption(option);
		
		var option:Option = new Option('Note Sorting:',
			"If not set to 'Never', the notes array is sorted every frame when notes are added.\nUsing 'Never' improves performance, especially if a lot of notes are displayed.\nDefault: \"After Note Finalized\"",
			'sortNotes',
			STRING,
			SORT_PATTERN); //Variable type
		addOption(option);

		var option:Option = new Option('Faster Sort',
			"If checked, only visible notes will be sorted.",
			'fastSort',
			BOOL);
		addOption(option);

		var option:Option = new Option('Better Recycling',
			"If checked, the game will use NoteGroup's recycle system.\nIt boosts game performance massively.",
			'betterRecycle',
			BOOL);
		addOption(option);

		var option:Option = new Option('Single Note To Note Group',
			"If checked: Merges consecutive notes into 1 long image instead of thousands of sprites.\nMassively improves FPS on charts with 1M+ notes.\nMerges only when note count exceeds mergeThreshold.",
			'singleNoteToGroup',
			BOOL);
		addOption(option);

		var option:Option = new Option('Overlapped Threshold:',
			"Hides overlapped notes which can't be easily noticed by pixels according to the value.",
			'hideOverlapped',
			FLOAT);
		option.displayFormat = "%v pixels";
		option.scrollSpeed = 10.0;
		option.minValue = 0.0;
		option.maxValue = 10.0;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		var option:Option = new Option('Process Notes before Spawning',
			"If checked, the game processes notes before spawning any.\nIt boosts game performance massively.\nIt is recommended to enable this option.",
			'processFirst',
			BOOL);
		addOption(option);

		var option:Option = new Option('Note Skipping',
			"If checked, the game can skip notes.\nIt boosts game performance massively, but only in specific scenarios.\nIf you don't understand, enable this.",
			'skipSpawnNote',
			BOOL);
		addOption(option);

		var option:Option = new Option('Bulk Skipping',
			"If checked, enables bulk skipping.\nIt boosts game performance a lot, especially when handling millions of NPS.\nIf you don't understand, enable this.",
			'bulkSkip',
			BOOL);
		addOption(option);

		var option:Option = new Option('Aggressive Note Culling',
			"If checked, skips expensive per-frame note processing for notes that are already offscreen or well past their hit window.\nThis helps a lot on very dense charts at low speeds.",
			'aggressiveNoteCulling',
			BOOL);
		addOption(option);

		var option:Option = new Option('Heavy Chart Mode',
			"If checked, switches to a stricter performance mode for very dense charts by limiting note processing and skipping old notes more aggressively.\nUseful for 50k+ note charts and extremely high NPS charts.",
			'heavyChartMode',
			BOOL);
		addOption(option);

		var option:Option = new Option('Spawning Time Limit',
			"If checked, the note spawn loop cancels if the time limit is exceeded.\nIt may boost performance on some scenarios.",
			'breakTimeLimit',
			BOOL);
		addOption(option);

		var option:Option = new Option('Insta-Check Spawned Notes',
			"If checked, it judges whether or not to do hit logic\nimmediately after a note is spawned. It boosts game performance massively,\nbut only in specific scenarios. If you don't understand, enable this.",
			'optimizeSpawnNote',
			BOOL);
		addOption(option);

		var option:Option = new Option('noteHitPreEvents',
			"If unchecked, the game will not send any noteHitPreEvent on Lua/HScript.",
			'noteHitPreEvent',
			BOOL);
		addOption(option);

		var option:Option = new Option('noteHitEvents',
			"If unchecked, the game will not send any noteHitEvent on Lua/HScript.\nNot recommended to disable this option.",
			'noteHitEvent',
			BOOL);
		addOption(option);

		var option:Option = new Option('spawnNoteEvents',
			"If unchecked, the game will not send spawn event\non Lua/HScript for spawned notes. Improves performance.",
			'spawnNoteEvent',
			BOOL);
		addOption(option);

		var option:Option = new Option('noteHitEvents for stages',
			"If unchecked, the game will not send any noteHitEvent on stage.\nNot recommended to disable this option for vanilla stages.",
			'noteHitStage',
			BOOL);
		addOption(option);

		var option:Option = new Option('noteHitEvents for Skipped Notes',
			"If unchecked, the game will not send any hit event\non Lua/HScript for skipped notes. Improves performance.",
			'skipNoteEvent',
			BOOL);
		addOption(option);

		var option:Option = new Option('Disable Garbage Collector',
			"If checked, You can play the main game without GC lag.\nIt only works on loading/playing charts.",
			'disableGC',
			BOOL);
		addOption(option);

		var option:Option = new Option('Ghost Density',
			"If checked, merges overlapped notes and counts density.\nUsed by Andre HUD for real note counter.",
			'ghostDensity',
			BOOL);
		addOption(option);

		var option:Option = new Option('Notes Density Handling',
			"If checked, limits spawn rate per frame to prevent lag on extremely dense charts (200k+ NPS).\nAt high NPS with low scroll speed, this caps notes spawned per frame.",
			'notesDensityHandling',
			BOOL);
		addOption(option);

		var option:Option = new Option('Optimised Mode',
			"If checked, hides stage characters, backgrounds, and stage objects so only the notes, strumlines, and HUD remain visible on a black screen.",
			'optimisedMode',
			BOOL);
		addOption(option);

		var option:Option = new Option('Use AndreJr HUD (Haxe)',
			"If checked, uses built-in AndreJr HUD instead of Lua.\nNo Lua script needed, runs inside PlayState.",
			'useAndreHUD',
			BOOL);
		addOption(option);

		super();
	}
}
