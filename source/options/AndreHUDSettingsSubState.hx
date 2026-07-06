package options;

class AndreHUDSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'Andre HUD Settings';
		rpcTitle = 'Andre HUD Settings Menu';

		var option:Option = new Option('Use AndreJr HUD (Haxe)',
			"If checked, uses built-in AndreJr HUD instead of Lua.\nNo Lua script needed, runs inside PlayState.",
			'useAndreHUD',
			BOOL);
		addOption(option);

		var option:Option = new Option('Use Andre New HUD',
			"If checked, uses the native Andre HUD with NPS/combo stats at the top.\nUses camOther so it won't be affected by camera bop.",
			'useAndreHUDNew',
			BOOL);
		addOption(option);

		var option:Option = new Option('Ghost Density (Andre HUD)',
			"If checked, counts note density for Andre HUD's real note counter.\nWorks with 'Overlapped Density' option in Gameplay settings.\nApplies to both AndreJr HUD and Andre New HUD.",
			'andreGhostDensity',
			BOOL);
		addOption(option);

		super();
	}
}