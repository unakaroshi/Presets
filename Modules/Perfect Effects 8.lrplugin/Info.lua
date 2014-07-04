--[[***************************************************************************

	Info.lua
	Copyright (c) 2008 onOneSoftware, Inc
	All Rights Reserved

******************************************************************************]]

return
{

	LrSdkVersion = 2.0,
	LrSdkMinimumVersion = 2.0,

	LrPluginName = LOC "$$$/PerfectEffects/Title=Perfect Effects 8",
	LrToolkitIdentifier = 'com.ononesoftware.conduit.PerfectEffects.8.lightroom',
	
	LrExportServiceProvider =
	{
		title = LOC "$$$/PerfectEffects/Service/Title=Perfect Effects 8",
		file = 'ONLRConduitService.lua',
	},
	
	LrExportMenuItems =
	{
        {
            title = LOC "$$$/PerfectEffects/ExportMenu/Title=Perfect Effects 8",
            file = 'ONLRMenuPerfectEffects.lua',
            enabledWhen = "photosAvailable",
        },
        
	},

	-- Specify a Lua script to be run when the plug-in is loaded or reloaded.
	-- We use this to provide global product-specific settings.
	LrInitPlugin = "PerfectEffectsLRInit.lua",

	VERSION = { major=8, minor=1, revision=0, build=0, },
}