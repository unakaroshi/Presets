--[[***************************************************************************

	ONLRMenuPerfectLayers.lua
	
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

ONLRConduitUtils.logMessage("============= ONLRPerfectLayers Loaded " .. os.date() .. " =============")


LrTasks.startAsyncTask(
	function()	
	
	local productName = "com.ononesoftware.vcb.perfectlayersplugin"
	ONLRProductSettings.loadOnePlugin = false
	ONLRProductSettings.supportsBatch = false
    ONLRProductSettings.openAsLayers = false
	ONLRConduitUtils.doExport(productName)
	
			
	end
)

