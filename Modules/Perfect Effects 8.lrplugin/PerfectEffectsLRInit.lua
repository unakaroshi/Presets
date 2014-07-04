--[[***************************************************************************

	PerfectEffectsLRInit.lua
	
	Copyright (c) 2014 onOneSoftware, Inc.
	All Rights Reserved.
	
	Provides product-specific settings for PerfectEffects.

******************************************************************************]]
---declare ONLRProductSettings, and set the log name and if logging is enabled
--we need to do this BEFORE the "require ONLRConduitUtils" as all logging goes through there now
ONLRProductSettings = {}
ONLRProductSettings.loggerName					= "PerfectEffects4_Conduit"
ONLRProductSettings.enableLogging				= false

require 'ONLRConduitUtils'


local isSuite = ONLRConduitUtils.isSuiteConduit()

ONLRConduitUtils.logMessage("PerfectEffectsLRInit:  isSuite = " .. tostring(isSuite))

-- A number of things depend on what product configuration we're running: Suite, Standalone, or Free.

if isSuite then
	-- Perfect Effects as part of Perfect Photo Suite
    
	ONLRProductSettings.hostAppFolderName			= "Perfect Photo Suite 8"

	ONLRProductSettings.hostAppExecName				= "Perfect Photo Suite"			-- used for Mac only
	ONLRProductSettings.productNameForMessages		= "Perfect Photo Suite"
	
	ONLRProductSettings.userDataFolderName          = "Perfect Layers 8"
	
		-- (For Suite menuInvokesBatch is irrelevant, since currently there's no menu item 
		--  at all for Effects or Portrait.  If that changes, we'll want it true only for
		--  Effects and Portrait.)
	ONLRProductSettings.menuInvokesBatch			= true

else
	-- Perfect Effects standalone
		
	ONLRProductSettings.hostAppFolderName			= "Perfect Effects 8"

    ONLRProductSettings.hostAppExecName				= "Perfect Effects"		-- used for Mac only
	ONLRProductSettings.productNameForMessages		= "Perfect Effects"
	
	ONLRProductSettings.userDataFolderName          = "Perfect Effects 8"

	ONLRProductSettings.menuInvokesBatch			= false
	
end

ONLRProductSettings.dataFolderName              = "Perfect Effects 8"

ONLRProductSettings.vcbPluginID					= "com.ononesoftware.vcb.perfecteffectsplugin"
ONLRProductSettings.vcbPluginName					= "PerfectEffects"

ONLRProductSettings.supportsPresets					= true
ONLRProductSettings.supportsBatch					= true
ONLRProductSettings.supportsExport					= true

ONLRProductSettings.allowMultipleImageSelections	= true

ONLRProductSettings.presetFileExtension			= "ONEffects"

ONLRProductSettings.supportedFileTypes			= { ["psd"]=1, ["tif"]=1, ["tiff"]=1, ["jpg"]=1, ["jpeg"]=1 }


--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]
