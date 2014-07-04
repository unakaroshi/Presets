--[[***************************************************************************

	ONLRMenuPerfectEffects.lua
	
	Copyright (c) 2008 onOneSoftware, Inc.
	All Rights Reserved

******************************************************************************]]

local LrApplication 		= import 'LrApplication'
local LrPathUtils			= import 'LrPathUtils'
local LrStringUtils			= import 'LrStringUtils'
local LrExportSession 		= import 'LrExportSession'
local LrTasks 				= import 'LrTasks'


require 'ONLRConduitUtils'


--[[***************************************************************************

	Script entry point
	
******************************************************************************]]

ONLRConduitUtils.logMessage("============= ONLRMenuPerfectEffects Loaded " .. os.date() .. " =============")


LrTasks.startAsyncTask(
	function()	
	
	local vcbPluginID = "com.ononesoftware.vcb.perfecteffectsplugin"
	ONLRProductSettings.loadOnePlugin = true
    ONLRProductSettings.openAsLayers = false
	ONLRConduitUtils.doExport(vcbPluginID)
	
			
	end
)

