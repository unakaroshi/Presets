--[[***************************************************************************

	ONLRConduitUtils.lua
	
	Copyright (c) 2011 onOneSoftware, Inc.
	All Rights Reserved

******************************************************************************]]

	-- Lightroom SDK
local LrPathUtils		= import 'LrPathUtils'
local LrFileUtils		= import "LrFileUtils"
local LrDialogs			= import "LrDialogs"
local LrTasks 			= import 'LrTasks'
local LrHttp			= import "LrHttp"
local LrXml				= import "LrXml"
local LrApplication		= import 'LrApplication'
local LrStringUtils		= import 'LrStringUtils'
local LrLogger			= import "LrLogger"
local LrExportSession 	= import 'LrExportSession'

local logger


ONLRConduitUtils = {}


--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.isSuiteConduit()


	local pluginID = _PLUGIN.id
	--ONLRConduitUtils.logMessage("ONLRConduitUtils.isSuiteConduit >  pluginID = " .. pluginID)

	local suitePos = string.find(pluginID, ".suite")
	if suitePos == nil then
		-- Try an alternate form.
		suitePos = string.find(pluginID, "_suite")
	end
	
	if suitePos == nil then
		ONLRConduitUtils.logMessage("   >>> ONLRConduitUtils.isSuiteConduit >  pluginID does not contain '.suite' or '_suite', returning false")
		return false
	else
		ONLRConduitUtils.logMessage("   >>> ONLRConduitUtils.isSuiteConduit >  pluginID contains '.suite' or '_suite' at " .. suitePos .. ", returning true")
		return true
	end
end


--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.getLightroomVersion()
	local version = LrApplication.versionTable()
	ONLRConduitUtils.logMessage("ONLRConduitUtils.getLightroomVersion >  major = " .. version.major .. ", minor = " .. version.minor)
	
	return version.major
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.collectionAccessSupported()
	return ONLRConduitUtils.getLightroomVersion() >= 3
end


--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.logMessage(inMessage)

	if ONLRProductSettings.enableLogging then
		local logMessage = tostring(inMessage)
		logger:trace(logMessage)
	end

end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.logStringFromTable(inTable, inTableCount)

    local logString
    
    for i=1, inTableCount do
      logString = logString .. inTable[i] .. "  " 
    end

	return logString
end


--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.metadataAccessSupported()
	return ONLRConduitUtils.getLightroomVersion() >= 3
end


--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.doExport(vcbPluginID)
	
	local pfExportSettings = {}
	ONLRConduitUtils.getExportSettings(pfExportSettings)
	
	ONLRProductSettings.vcbPluginID	= vcbPluginID
	
	local activeCatalog = LrApplication.activeCatalog()
			
	local exportSession = LrExportSession
	{
		photosToExport = activeCatalog.targetPhotos,
		exportSettings = pfExportSettings
	}
		
		exportSession:doExportOnCurrentTask()	
	
end


--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.getExportSettings(pfExportSettings)
		
		local activeCatalog = LrApplication.activeCatalog()
		local filmstrip = {}
		local overrideOriginal = false

		
		activeCatalog:withReadAccessDo(
			function()
				local targetPhoto
				for i, targetPhoto in next, activeCatalog.targetPhotos, nil do
					filmstrip[i] = targetPhoto.path
					
					ONLRConduitUtils.logMessage("ONLRConduitUtils.getExportSettings> PhotoPath to source image: " .. targetPhoto.path)
					
					local ext = LrStringUtils.lower(LrPathUtils.extension(targetPhoto.path))
					if  not ONLRProductSettings.supportedFileTypes[ext] then
						ONLRConduitUtils.logMessage("ONLRConduitUtils.getExportSettings> Overriding Extension  " .. ext)
						overrideOriginal = true
					end
				end
			end
		)
		
		-- Some of these are defaults that may be overridden by prefs from Perfect Layers or a VCB plugin
		if ONLRProductSettings.supportsBatch and ONLRProductSettings.menuInvokesBatch then
			pfExportSettings.processAsBatch = true
		else
			pfExportSettings.processAsBatch = false
		end
	
		if pfExportSettings.processAsBatch or ONLRProductSettings.loadOnePlugin then
			pfExportSettings.LR_export_destinationType			= "sourceFolder"
			pfExportSettings.LR_export_useSubfolder				= false
			pfExportSettings.LR_reimportExportedPhoto			= false
		else
			pfExportSettings.LR_export_destinationType			= "sourceFolder"
			pfExportSettings.LR_export_useSubfolder				= false
			pfExportSettings.LR_reimportExportedPhoto			= false
		end

		pfExportSettings.reimportIfSuccessful				= true
		
		pfExportSettings.LR_format							= "PSD" --this is the default, but we will override with settings
		pfExportSettings.LR_reimport_stackWithOriginal		= true 
		pfExportSettings.use_original_for_single_PSDs		= true
		
		pfExportSettings.editOriginal						= false
		
		-- Also set our own copy of stackWithOriginal (see ONLRConduitService.endDialog() for an explanation).
		pfExportSettings.stackWithOriginal					= pfExportSettings.LR_reimport_stackWithOriginal
		
		pfExportSettings.LR_export_colorSpace				= "AdobeRGB" 
		pfExportSettings.LR_export_bitDepth					= 8			-- should default be 16 ??? 
		pfExportSettings.LR_size_resolution					= 300
		pfExportSettings.LR_size_resolutionUnits			= "inch"
		
		pfExportSettings.LR_minimizeEmbeddedMetadata		= false		-- (formerly not specified)
		pfExportSettings.LR_removeLocationMetadata			= false	
		
		pfExportSettings.LR_includeVideoFiles				= false
		
		pfExportSettings.LR_exportServiceProvider 			= _PLUGIN.id

		pfExportSettings.LR_export_useSubfolder				= false
		pfExportSettings.LR_collisionHandling				= "rename"
		pfExportSettings.photosToExport						= filmstrip
		
		pfExportSettings.presetInfo							= nil
		
		pfExportSettings.fromExportDialog					= false
		
				
		ONLRConduitUtils.GetPerfectLayersPrefsFromFile(pfExportSettings)

		--We need to override original to PSD if any of the filetypes were not supported
		if overrideOriginal and pfExportSettings.LR_format == "ORIGINAL" then
			pfExportSettings.LR_format						= "PSD"
		end
		
		-- If 'Use original for single PSDs' is set AND only one item is selected AND it's a PSD,
		-- then we want the plugin to process the original, i.e. the selected image, rather than
		-- processing an exported copy.  There is also some special handling for this in ONLRConduitService.lua.
		if pfExportSettings.use_original_for_single_PSDs == true then
		
			ONLRConduitUtils.logMessage("ONLRConduitUtils.getExportSettings>  #pfExportSettings.photosToExport = " .. tostring(#pfExportSettings.photosToExport))
			if #pfExportSettings.photosToExport == 1 then
			
				local ext = LrStringUtils.lower(LrPathUtils.extension(pfExportSettings.photosToExport[1]))
				ONLRConduitUtils.logMessage("ONLRConduitUtils.getExportSettings>  Single selection, with extension:  " .. ext)
				
				if (ext == "psd") then
					ONLRConduitUtils.logMessage("  ==>  ONLRConduitUtils.getExportSettings>  Setting editOriginal flag")
					pfExportSettings.editOriginal = true
					--pfExportSettings.LR_format = "ORIGINAL"
					
					-- Also revise the export destination folder, so we don't clutter up the source folder
					pfExportSettings.LR_export_destinationType = "tempFolder"
				end
			end
		end

	
	 return pfExportSettings
end

--[[***************************************************************************

******************************************************************************]]
function processIsRunning(pidString)
	local result = false
	local command
	local retCode
	
	if pidString == nil then
		ONLRConduitUtils.logMessage("   *** UH-OH, pid is nil!!!")
	--elseif WIN_ENV == true then
	--	command = "tasklist /fi " .. '"' .. "PID eq " .. pidString .. '"' .. " /nh >> NUL"
	--	retCode = LrTasks.execute(command)
	--	ONLRConduitUtils.logMessage("processIsRunning>  retCode = " .. retCode .. " from command " .. command)
	--	if retCode == 0 then
	--		result = true
	--	end
	else
		command = "ps -p " .. pidString .. " >> /dev/null"
		retCode = LrTasks.execute(command)
		ONLRConduitUtils.logMessage("processIsRunning>  retCode = " .. retCode .. " from command " .. command)
		if retCode == 0 then
			result = true
		end
	end
	
	return result
end

--[[***************************************************************************
	Get port number for running instance (if any) of PerfectLayers,
	via a plist file that PerfectLayers writes out as it launches
	and deletes as it exits.
******************************************************************************]]
function ONLRConduitUtils.GetPerfectLayersPortNumber()

	--ONLRConduitUtils.logMessage("GetPerfectLayersPortNumber> In Method")

	local delim
	if WIN_ENV == true then
		delim = "\\"
	else
		delim = "/"
	end

	local appDataPath = LrPathUtils.getStandardFilePath("appData")
	--ONLRConduitUtils.logMessage("   appData path:  " .. appDataPath)
	-- Sadly, "appData" gives us a Lightroom-specific path, such as "C:\Users\jjones\AppData\Roaming\Adobe\Lightroom",
	-- but we can simply back up from that, to "Roaming".
	local appDataRoot = appDataPath .. delim .. ".." .. delim .. ".."
	plistPath = appDataRoot .. delim .. "onOne Software" .. delim .. ONLRProductSettings.userDataFolderName .. delim .. "ServerData.plist"
	--ONLRConduitUtils.logMessage("   plist path:  " .. plistPath)

	local portNumberString = nil
	local pidString = nil

	if LrFileUtils.exists(plistPath) == "file" then
		local fp = io.open(plistPath)
		local xmlSettings = fp:read("*a")
		fp:close()
		
		local rootDom, dom, idx, childCount, keyValCount, idy, ikey, ivalue, key, value
		rootDom = LrXml.parseXml(xmlSettings)
		childCount = rootDom:childCount()
		for idx = 1, childCount do
			dom 	= rootDom:childAtIndex(idx)
			if dom:name() == 'dict' then
				keyValCount = dom:childCount() / 2
				--ONLRConduitUtils.logMessage("GetPerfectLayersPortNumber >  keyValCount = " .. keyValCount)
				for idy = 1, keyValCount do
					ivalue = idy * 2
					ikey = ivalue - 1
					key 	= dom:childAtIndex(ikey)
					value 	= dom:childAtIndex(ivalue)
					--ONLRConduitUtils.logMessage("    idy = " .. idy .. ", key = " .. key:text() .. ", value = " .. value:text())

					if key:text() == 'listen_port' then
						portNumberString = value:text()
						--ONLRConduitUtils.logMessage("GetPerfectLayersPortNumber > found portNumberString:  " .. portNumberString)
						--break
					elseif key:text() == 'pid' then
						pidString = value:text()
					end
				end
			end
		end
	else
		ONLRConduitUtils.logMessage("ONLRConduitUtils.GetPerfectLayersPortNumber >  plist file not found, at " .. plistPath)
	end

	return portNumberString
end

--[[***************************************************************************
This (Windows only) method will return a string which is the path to perfect layers.
It looks under every drive letter starting with C: until it finds a "Program Files" folder.
At the time we could not find a more direct way to determine the location of Program Files.
This was the next best thing that should work most of the time without user interaction
and sometimes with user interaction...

Recently we found a way to get values for environment variables, such as ProgramFiles,
but we're not using that yet.
******************************************************************************]]
function findPerfectLayersWin()
	
-- A potential alternative approach using environment variables:
--local progFilesPath = ONLRConduitUtils.getEnvironmentVarWin("ProgramFiles")
--if progFilesPath ~= nil then
--	local pathRoot = progFilesPath .. "\\OnOne\ Software\\"
--	ONLRConduitUtils.logMessage(" >>> onOne app path root, using env. var.:  " .. progFilesPath)
--end

	local perfectLayersPath

	local filesToTry = {}
	local pathRoot
	local found = false
		
	local appDisplayName = ONLRProductSettings.productNameForMessages

	filesToTry[1] = ONLRProductSettings.hostAppFolderName .. "\\" .. ONLRProductSettings.hostAppFolderName .. ".exe"

--[[*********
	if isSuite then
		filesToTry[1] = "Perfect\ Photo\ Suite\ 6\\PerfectPhotoSuite.exe"
		--filesToTry[2] = "Perfect\ Photo\ Suite\\PerfectLayers.exe"		-- TEMP, until the installer is finalized
		--filesToTry[3] = "Perfect\ Layers\\PerfectPhotoSuite.exe"		-- TEMP, until the installer is finalized
		--filesToTry[4] = "Perfect\ Layers\\PerfectLayers.exe"			-- TEMP, until the installer is finalized
	else
		filesToTry[1] = "Perfect\ Layers\\PerfectLayers.exe"
	end
*********]]
	
	local fileCount = #filesToTry
		
	pathRoot = ":\\Program\ Files\\OnOne\ Software\\"
	
	-- Look in Program Files on a bunch of potential drive locations.
	local driveLetters = {"C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}

	local nDrives = #driveLetters
	for i = 1, nDrives do
		for iName = 1, fileCount do
			perfectLayersPath = driveLetters[i] .. pathRoot .. filesToTry[iName]
			--ONLRConduitUtils.logMessage("Searching for " .. appDisplayName .. " at: " .. perfectLayersPath)

			if LrFileUtils.exists(perfectLayersPath) == "file" then
				found = true
				ONLRConduitUtils.logMessage("Found " .. appDisplayName .. " at: " .. perfectLayersPath)
				perfectLayersPath = '"' .. perfectLayersPath .. '"'
				break
			end
		end
		
		if found then
			break
		end
	end

	--If we couldn't find the app in the usual places, ask the user where it is
	if not found then

		local dialogResult = LrDialogs.runOpenPanel {
			title = 'Please Locate the ' .. appDisplayName .. ' app',
			canChooseFiles = true,
			canChooseDirectories = false,
			canCreateDirectories = false,
			allowsMultipleSelection = false,
			fileTypes = 'exe'
		}

		perfectLayersPath = dialogResult and dialogResult[1] or nil

		if perfectLayersPath == nil then
			ONLRConduitUtils.logMessage("findPerfectLayers() The dialog returned nil, user canceled or we didn't find the host app .exe file")
		else
			ONLRConduitUtils.logMessage("User Located " .. appDisplayName .. " at: " .. perfectLayersPath)
			perfectLayersPath = '"' .. perfectLayersPath .. '"'
		end
		
	end


	return perfectLayersPath
end

--[[***************************************************************************

******************************************************************************]]
function pathToLayersExecutableInMacBundle(path, isSuite)
	local executablePath = nil
	
	-- Look for an executable called "Perfect Layers" or whatever it's supposed to be for the product.
	local executablePath1 = path .. "/Contents/MacOS/" .. ONLRProductSettings.hostAppExecName
	if LrFileUtils.exists(executablePath1) == "file" then
		executablePath = '"' .. executablePath1 .. '"'
	elseif isSuite then
		-- Also try "Perfect Photo Suite"
		local executablePath2 = path .. "/Contents/MacOS/Perfect\ Photo\ Suite"
		if LrFileUtils.exists(executablePath2) == "file" then
			executablePath = '"' .. executablePath2 .. '"'
		else
			ONLRConduitUtils.logMessage("  *** But the app bundle is malformed -- executable not found at:  " .. executablePath1 .. " or " .. executablePath2)
		end
	else
		ONLRConduitUtils.logMessage("  *** But the app bundle is malformed -- executable not found at:  " .. executablePath1)
	end
	
	-- Return full path to executable, or nil if not found
	return executablePath
end

--[[***************************************************************************
This (Mac only) method will return a string which is the path to the
Perfect Layers executable.  First it looks in the Applications folder, which
is the most likely location.  If it doesn't find it there, the user is prompted
for the app (bundle) location, and then we fill in the path to the executable
in the bundle.
******************************************************************************]]
function findPerfectLayersMac()
	
	local executablePath = nil
	
	local pathsToTry = {}
	local path
	
	local isSuite = ONLRConduitUtils.isSuiteConduit()
	
	local appDisplayName = ONLRProductSettings.productNameForMessages
	
	-- Look in the Applications folder.
	
	pathsToTry[1] = "/Applications/" .. ONLRProductSettings.hostAppFolderName .. "/" .. ONLRProductSettings.hostAppFolderName .. ".app"
		-- For Suite 5.5.4, we had to add a space before ".app", to address a Time Machine issue.
		-- So include that as a possible name.
	pathsToTry[2] = "/Applications/" .. ONLRProductSettings.hostAppFolderName .. "/" .. ONLRProductSettings.hostAppFolderName .. " .app"

--[[**********
	if isSuite then
		-- Some of these alternates will not be needed once everything is finalized.
		pathsToTry[1] = "/Applications/Perfect\ Photo\ Suite\ 6/Perfect\ Photo\ Suite.app"
		pathsToTry[2] = "/Applications/Perfect\ Photo\ Suite/Perfect\ Photo\ Suite.app"
		pathsToTry[3] = "/Applications/Perfect\ Layers/Perfect\ Photo\ Suite.app"
		pathsToTry[4] = "/Applications/Perfect\ Photo\ Suite/Perfect\ Layers\ Suite.app"
	else
		-- For Suite 5.5.4, we had to add a space before ".app", to address a Time Machine issue.
		-- So include that as a possible name.
		pathsToTry[1] = "/Applications/Perfect\ Layers/Perfect\ Layers.app"
		pathsToTry[2] = "/Applications/Perfect\ Layers/Perfect\ Layers\ .app"
		pathsToTry[3] = "/Applications/Perfect\ Photo\ Suite/Perfect\ Layers.app"
		pathsToTry[4] = "/Applications/Perfect\ Photo\ Suite\ 6/Perfect\ Layers.app"
	end
*********]]
	
	count = #pathsToTry
	for iPath = 1, count do
		path = pathsToTry[iPath]
		ONLRConduitUtils.logMessage(tostring(iPath) .. ". Searching for " .. appDisplayName .. " app at: " .. path)

		if LrFileUtils.exists(path) == "directory" then
			ONLRConduitUtils.logMessage("Found " .. appDisplayName .. " app at: " .. path)
			-- Locate the executable
			executablePath = pathToLayersExecutableInMacBundle(path, isSuite)
			if executablePath ~= nil then
				break
			end
		end
	end
	
	--If we couldn't find the app in the usual places, ask the user where it is
	if executablePath == nil then

		local dialogResult = LrDialogs.runOpenPanel {
			title = 'Please Locate the ' .. appDisplayName .. ' application',
			canChooseFiles = true,
			canChooseDirectories = false,
			canCreateDirectories = false,
			allowsMultipleSelection = false,
			fileTypes = 'app'
		}

		path = dialogResult and dialogResult[1] or nil

		if path == nil then
			ONLRConduitUtils.logMessage("findPerfectLayers() The dialog returned nil, user canceled or we didn't find the " .. appDisplayName .. ".app file")
		elseif LrFileUtils.exists(path) == "directory" then
			ONLRConduitUtils.logMessage("User Located " .. appDisplayName .. " at: " .. path)
			-- Locate the executable
			executablePath = pathToLayersExecutableInMacBundle(path, isSuite)
			if executablePath == nil then
				ONLRConduitUtils.logMessage("  *** But the app bundle is malformed -- executable not found at:  " .. path)
				LrDialogs.message(
						"The file you selected is not a valid " .. appDisplayName .. " application.  You might need to reinstall " .. appDisplayName .. ".",
						"Error locating " .. appDisplayName,
						"critical"
				)
			end
		else
			ONLRConduitUtils.logMessage("*** User located " .. appDisplayName .. ", but path doesn't exist: " .. path)
		end
		
	end
	
	return executablePath
end

--[[***************************************************************************

******************************************************************************]]
function findPerfectLayers()

	if WIN_ENV == true then
		return findPerfectLayersWin()
	else
		return findPerfectLayersMac()
	end

end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.getLayersAppReadyStatus(portNumber)

	local layersReady = -1
	
	if portNumber == nil then
		portNumber = ONLRConduitUtils.GetPerfectLayersPortNumber()
	end
	
	if portNumber == nil then
		ONLRConduitUtils.logMessage("ONLRConduitUtils.getLayersAppReadyStatus> " .. ONLRProductSettings.productNameForMessages .. " Server Communication Error (portNumber is nil)")
	else
		local url = "http://127.0.0.1:" .. portNumber .. "/layers?cmd=check_conduit_status"
		
		local resultBody = nil
		local headersTable = nil
		
		resultBody, headersTable = LrHttp.get(url)  
		
		local connected = false
		local gotResponse = false
		local gotStatus = false
		
		if headersTable == nil then
			ONLRConduitUtils.logMessage("ONLRConduitUtils.getLayersAppReadyStatus> ERROR: headersTable is nil")
		elseif headersTable.status == nil then
			ONLRConduitUtils.logMessage("ONLRConduitUtils.getLayersAppReadyStatus> ERROR: headersTable.status is nil")
		elseif headersTable.status ~= 200 then
			ONLRConduitUtils.logMessage("ONLRConduitUtils.getLayersAppReadyStatus> ERROR: headersTable.status = " .. headersTable.status)
		else
			connected = true
			if resultBody == nil then
				ONLRConduitUtils.logMessage("ONLRConduitUtils.getLayersAppReadyStatus> ERROR: resultBody is nil")
			else
				gotResponse = true
						
				--ONLRConduitUtils.logMessage("getLayersAppReadyStatus> response string from Layers: " .. resultBody)

				-- Parse XML response
				local dom, dom2, idx, childCount, dictChildCount, key, value
				dom = LrXml.parseXml(resultBody)
				childCount = dom:childCount()
				for idx = 1, childCount do
					dom2 	= dom:childAtIndex(idx)
					--ONLRConduitUtils.logMessage("getLayersAppReadyStatus> first child name: " .. dom2:name()) 
					if dom2:name() == 'dict' then
						-- Get status code
						dictChildCount = dom2:childCount()
						for idy = 1, dictChildCount, 2 do
							key 	= dom2:childAtIndex(idy)
							value 	= dom2:childAtIndex(idy + 1)
							
							if key:text() == 'app_ready_to_run' then
								local textValue = value:text()
								if textValue ~= nil then
									--ONLRConduitUtils.logMessage("getLayersAppReadyStatus> value for app_ready_to_run key: " .. textValue) 
									local numberValue = tonumber(textValue)
									if numberValue ~= nil then
										--ONLRConduitUtils.logMessage("getLayersAppReadyStatus> numeric value: " .. numberValue) 
										layersReady = numberValue
										gotStatus = true
									end
								end
							end
						end
					
					end
				end
			end
		end

		if not connected or not gotResponse then
			ONLRConduitUtils.logMessage("ONLRConduitUtils.getLayersAppReadyStatus> " .. ONLRProductSettings.productNameForMessages .. " Server Communication Error")
		elseif not gotStatus then
			ONLRConduitUtils.logMessage("ONLRConduitUtils.getLayersAppReadyStatus> Error in response XML from " .. ONLRProductSettings.productNameForMessages)
		end
	end
	
	return layersReady
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.waitForLayersAppReady(portNumber)

	layersReady = false

	-- Poll for status info from Layers, until it says it's done initializing and ready to run.
	
	ONLRConduitUtils.logMessage(">>> ONLRConduitUtils.waitForLayersAppReady>  Polling for app ready status from Layers...")
	local done = false
	local canceled = false
	while not done do
		LrTasks.sleep(1)
		local layersReadyStatus = ONLRConduitUtils.getLayersAppReadyStatus(portNumber)
		ONLRConduitUtils.logMessage("    ... layersReadyStatus = " .. layersReadyStatus)
		if layersReadyStatus == -1 then
			canceled = true
			done = true
		elseif layersReadyStatus == 1 then
			layersReady = true
			done = true
		end
	end
	ONLRConduitUtils.logMessage("... ONLRConduitUtils.waitForLayersAppReady>  Done polling")
	ONLRConduitUtils.logMessage("... canceled = " .. tostring(canceled))
	
	return layersReady
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.LaunchPerfectLayers(processingAsBatch)

	local layersLaunched = false

	--ONLRConduitUtils.logMessage("ONLRConduitUtils.LaunchPerfectLayers>  In method")

	local command

	command = findPerfectLayers()
	if command ~= nil then
		command = command .. " --host=lightroom --plugin=com.ononesoftware.emptyplugin"
		--if ONLRProductSettings.launchLayersForSinglePlugin then
		if processingAsBatch  or ONLRProductSettings.loadOnePlugin == true then
			-- Add args to streamline the UI for a single plugin.
			command = command .. " --one-plugin"
		end
		if MAC_ENV == true then
			  -- Make it run as a background process, so that LrTasks.execute doesn't block
			  -- (and Lightroom doesn't end up with an async task waiting for Layers to quit).  Fixes #3209.
			command = command .. " &"
		end
	end

		-- The open command is a much nicer approach for Mac, but unfortunately the --args option
		-- is not supported prior to Mac OS 10.6.1.  We need to support 10.5.x as well.
		--command = "open -b com.ononesoftware.perfectlayers --args --host=lightroom"
	
	if command ~= nil then
		
		--Throw a couple more quotes on the windows side to deal with the "&" in B&W
		if WIN_ENV == true then
			command = '"' .. command .. '"'
		end
		
		ONLRConduitUtils.logMessage("ONLRConduitUtils.LaunchPerfectLayers>  Command: " .. command)

		LrTasks.startAsyncTask(
			function()
				LrTasks.execute(command)
			end
		)
		
		layersLaunched = true
	end

	return layersLaunched
end

--[[***************************************************************************

	Get LR prefs from Layers by reading the prefs file it writes out.
	Layers stores prefs using Qt's QSettings class.
	
	On Mac the prefs are stored in a .plist file in the standard user prefs location.
	
	On Windows they're stored in a .ini file in
	%APPDATA%\Roaming\onOne Software\Perfect Layers\PerfectLayers.ini
	(we chose that option rather than the Registry).
	
******************************************************************************]]
function ONLRConduitUtils.GetPerfectLayersPrefsFromFile(exportSettings)

	local prefsRoot, prefsPath
	if WIN_ENV == true then
		-- The following might not work on XP.
		prefsRoot = LrPathUtils.getStandardFilePath('home') .. "\\AppData\\Roaming\\onOne Software\\" .. ONLRProductSettings.userDataFolderName
		prefsPath = prefsRoot .. "\\PerfectLayersLRPrefs.plist"
	else
		prefsRoot = LrPathUtils.standardizePath("~/Library/Application Support/onOne Software/" .. ONLRProductSettings.userDataFolderName)
		prefsPath = prefsRoot .. "/PerfectLayersLRPrefs.plist"
		-- The Layers app prefs file didn't work on Mac.  Couldn't read it with LrXml, perhaps because it's binary?
		--prefsPath = LrPathUtils.standardizePath("~/Library/Preferences/com.ononesoftware.PerfectLayers.plist")
	end

	ONLRConduitUtils.logMessage("GetPerfectLayersPrefsFromFile>  Layers prefs path: " .. prefsPath)
	
	if LrFileUtils.exists(prefsPath) ~= "file" then
		ONLRConduitUtils.logMessage("GetPerfectLayersPrefsFromFile>  Prefs file not found, keeping defauts")
		return
	end
	
	--ONLRConduitUtils.logMessage("GetPerfectLayersPrefsFromFile>  Layers prefs file exists.")
	
	local fp = io.open(prefsPath)
	local xmlSettings = fp:read("*a")
	fp:close()
	
	--ONLRConduitUtils.logMessage("GetPerfectLayersPrefsFromFile>  Contents of prefs file:")
	--ONLRConduitUtils.logMessage(xmlSettings)
	
	ONLRConduitUtils.GetLRPrefsFromXML(xmlSettings, exportSettings)
		
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.GetLRPrefsFromXML(resultBody, exportSettings)

	local dom, dom2, idx, childCount, dictChildCount, key, value
	dom = LrXml.parseXml(resultBody)
	childCount = dom:childCount()
	for idx = 1, childCount do
		dom2 	= dom:childAtIndex(idx)
		--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> first child name: " .. dom2:name()) 
		
		if dom2:name() == 'dict' then
			
			-- Get Lightroom conduit prefs
			
			dictChildCount = dom2:childCount()
			for idy = 1, dictChildCount, 2 do
				key 	= dom2:childAtIndex(idy)
				value 	= dom2:childAtIndex(idy + 1)
				
				if key:text() == 'color_space' then
					--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> value text for color_space is: " .. value:text())
					exportSettings.LR_export_colorSpace = value:text()
				elseif key:text() == 'file_type' then
					--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> value text for file_type is: " .. value:text())
					exportSettings.LR_format = value:text()
				elseif key:text() == 'bit_depth' then
					--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> value text for bit_depth is: " .. value:text())
					exportSettings.LR_export_bitDepth = tonumber(value:text())
				elseif key:text() == 'resolution' then
					--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> value text for resolution is: " .. value:text())
					exportSettings.LR_size_resolution = tonumber(value:text())
				elseif key:text() == 'resolution_units' then
					--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> value text for resolution_units is: " .. value:text())
					exportSettings.LR_size_resolutionUnits = value:text()
				elseif key:text() == 'stack_with_original' then
					--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> value text for stack_with_original is: " .. value:text())
					exportSettings.LR_reimport_stackWithOriginal = (value:text() == 'true')
					exportSettings.stackWithOriginal = exportSettings.LR_reimport_stackWithOriginal
				elseif key:text() == 'use_original_for_single_PSD' then
					--ONLRConduitUtils.logMessage("GetLRPrefsFromXML> value text for use_original_for_single_PSD is: " .. value:text())
					exportSettings.use_original_for_single_PSDs = (value:text() == 'true')
					-- This will apply only if a single item is selected and it's already a PSD, otherwise it's ignored.
				end
			end
		end
	end
	
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.GetOperationModeFromXML(resultBody, exportSettings)
			
	local dom, dom2, idx, childCount, dictChildCount, key, value
	dom = LrXml.parseXml(resultBody)
	childCount = dom:childCount()
	for idx = 1, childCount do
		dom2 	= dom:childAtIndex(idx)
		--ONLRConduitUtils.logMessage("GetOperationModeFromXML> first child name: " .. dom2:name()) 
		
		if dom2:name() == 'dict' then
			
			-- Get operation mode
			
			dictChildCount = dom2:childCount()
			for idy = 1, dictChildCount, 2 do
				key 	= dom2:childAtIndex(idy)
				value 	= dom2:childAtIndex(idy + 1)
				
				if key:text() == 'layer_operation' then
					if value:text() == '0' then
						--cancel
						exportSettings.operationMode = 0
					elseif value:text() == '1' then
						-- create
						exportSettings.operationMode = 1
					elseif value:text() == '2' then
						-- merge 
						exportSettings.operationMode = 2
					end
				
					--ONLRConduitUtils.logMessage("GetOperationModeFromXML> value text for layer_operation is: " .. value:text())
				end
			end
		end
	end
	
end

--[[***************************************************************************
	
******************************************************************************]]
function pingPerfectLayers(portNumber)

	local connected = false
	local gotResponse = false
	
	local url = "http://127.0.0.1:" .. portNumber .. "/layers?cmd=ping"
	ONLRConduitUtils.logMessage("pingPerfectLayers>  Request URL is:" .. url)
	
	local resultBody = nil
	local headersTable = nil
	
	--ONLRConduitUtils.logMessage("pingPerfectLayers> about to send HTTP GET")
	resultBody, headersTable = LrHttp.get(url)  
	--ONLRConduitUtils.logMessage("pingPerfectLayers> sent THE HTTP GET")
	
	if headersTable == nil then
		ONLRConduitUtils.logMessage("pingPerfectLayers(" .. portNumber .. ") > ERROR: headersTable is nil")
	elseif headersTable.status == nil then
		ONLRConduitUtils.logMessage("pingPerfectLayers(" .. portNumber .. ") > ERROR: headersTable.status is nil")
	elseif headersTable.status ~= 200 then
		ONLRConduitUtils.logMessage("pingPerfectLayers(" .. portNumber .. ") > ERROR: headersTable.status = " .. headersTable.status)
	else
		connected = true
		if resultBody == nil then
			ONLRConduitUtils.logMessage("pingPerfectLayers(" .. portNumber .. ") > ERROR: resultBody is nil")
		else
			gotResponse = true
					
			--ONLRConduitUtils.logMessage("pingPerfectLayers(" .. portNumber .. ") > response string from Layers: " .. resultBody)

			-- For a "ping" request, we don't really need to parse the response, it's just a formality.
			-- The expected response from Layers would be "pong".
			
			result = true
		end
	end

	if not connected or not gotResponse then
		ONLRConduitUtils.logMessage("pingPerfectLayers(" .. portNumber .. ") > " .. ONLRProductSettings.productNameForMessages .. " Server Communication Error")
	end
	
	return gotResponse
end

--[[***************************************************************************
	
******************************************************************************]]
function ONLRConduitUtils.EstablishConnection(maxAttempts)

	ONLRConduitUtils.logMessage("ONLRConduitUtils.EstablishConnection> In Method")
	
	local portNumber = nil

	for i = 1, maxAttempts do
	
		if i > 1 then
			LrTasks.sleep(1)
		end
		
			-- Get the port number from ServerData.plist.  Do this each time through the loop,
			-- in case there was a stale ServerData.plist file initially.
		portNumber = ONLRConduitUtils.GetPerfectLayersPortNumber()
		
		if portNumber ~= nil then
				-- We got a port number from ServerData.plist, but test the connection to
				-- make sure it's legitimate, i.e. make sure Layers is really running.
			if pingPerfectLayers(portNumber) then
				break
			else
				portNumber = nil
			end
		end
	end
	
	return portNumber
end


--[[***************************************************************************

	This is where Layers gets launched if it is not running.
	
******************************************************************************]]
function ONLRConduitUtils.ConnectToPerfectLayers(waitForAppReady, processingAsBatch)
	
	ONLRConduitUtils.logMessage("ONLRConduitUtils.ConnectToPerfectLayers> In Method")
	
	local portNumber = nil
	
	portNumber = ONLRConduitUtils.EstablishConnection(1)
	if portNumber == nil then
		ONLRConduitUtils.logMessage("ONLRConduitUtils.ConnectToPerfectLayers>  " .. ONLRProductSettings.productNameForMessages .. " Server Not running.  Attempting to launch Layers.")
		local layersLaunched = ONLRConduitUtils.LaunchPerfectLayers(processingAsBatch)
		ONLRConduitUtils.logMessage("ONLRConduitUtils.ConnectToPerfectLayers>  layersLaunched = " .. tostring(layersLaunched))
		
		if layersLaunched then
			portNumber = ONLRConduitUtils.EstablishConnection(120)
		end
	end
	
	if portNumber ~= nil and waitForAppReady then
		-- We know Layers is running, but in case it was just launched,
		-- first make sure it's fully initialized and ready to process requests.
		local layersReady = ONLRConduitUtils.waitForLayersAppReady(portNumber)
			-- true means Layers is ready to process our requests.
			-- false means something went wrong and we should cancel out.
		if not layersReady then
			ONLRConduitUtils.logMessage("*** ONLRConduitUtils.ConnectToPerfectLayers>  waitForLayersAppReady returned false.  Something went wrong.")
			portNumber = nil
		end
	end
	
	if portNumber == nil then
		ONLRConduitUtils.logMessage("ONLRConduitUtils.ConnectToPerfectLayers> ******* UNABLE TO SET UP COMMUNICATION WITH HOST APP ********")
	end
	
	return portNumber
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.AskPerfectLayersForInfo(includeMode, includePrefs, exportSettings)

	ONLRConduitUtils.logMessage("ONLRConduitUtils.AskPerfectLayersForInfo> In Method")

	local commError = true
	
	local resultBody = nil
	local headersTable = nil

	exportSettings.operationMode = 404		-- in case it fails
	
		-- Launch Layers if necessary, connect to it, wait for it to be ready to process requests.
	local portNumber = ONLRConduitUtils.ConnectToPerfectLayers(true, exportSettings.processAsBatch)
	
	if portNumber ~= nil then
			-- Send Layers an open_layers_start command, with a request for info.
		local url = "http://127.0.0.1:" .. portNumber .. "/layers?cmd=open_layers_start"
		ONLRConduitUtils.logMessage("AskPerfectLayersForInfo> Request URL is:" .. url)

		--ONLRConduitUtils.logMessage("AskPerfectLayersForInfo> about to send HTTP GET")
		resultBody, headersTable = LrHttp.get(url) 
		--ONLRConduitUtils.logMessage("AskPerfectLayersForInfo> sent THE HTTP GET")
	
		if headersTable == nil then
			ONLRConduitUtils.logMessage("AskPerfectLayersForInfo > ERROR: headersTable is nil")
		elseif headersTable.status == nil then
			ONLRConduitUtils.logMessage("AskPerfectLayersForInfo > ERROR: headersTable.status is nil")
		elseif headersTable.status ~= 200 then
			ONLRConduitUtils.logMessage("AskPerfectLayersForInfo > ERROR: headersTable.status = " .. headersTable.status)
		else
			commError = false
			
			if includeMode then
				ONLRConduitUtils.GetOperationModeFromXML(resultBody, exportSettings)
			else
				exportSettings.operationMode = 1	-- Default to "Create"
			end
			
			if includePrefs then
				ONLRConduitUtils.GetLRPrefsFromXML(resultBody, exportSettings)
			end
		end
	end	

	if commError then
		ONLRConduitUtils.logMessage("AskPerfectLayersForInfo> ******* UNABLE TO SET UP COMMUNICATION WITH HOST APP ********")
		
		local msg =  LOC("$$$/" .. ONLRProductSettings.productNameForMessages .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. Unable to set up communication with " .. ONLRProductSettings.productNameForMessages .. ".")
		LrDialogs.message(msg, "critical")
	end

end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.AskPerfectLayersForPrefs(exportSettings)

	ONLRConduitUtils.logMessage("AskPerfectLayersForPrefs> In Method")
	
	ONLRConduitUtils.AskPerfectLayersForInfo(false, true, exportSettings)
	
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.AskPerfectLayersForOperationMode(exportSettings)

	ONLRConduitUtils.logMessage("AskPerfectLayersForOperationMode> In Method")
	
	ONLRConduitUtils.AskPerfectLayersForInfo(true, false, exportSettings)
	
end

--[[***************************************************************************
encoding strings for transfer over the HTTP protocol
******************************************************************************]]
function ONLRConduitUtils.url_encode(str)
  if (str) then
    str = string.gsub (str, "\n", "\r\n")
    str = string.gsub (str, "([^%w ])",
        function (c) return string.format ("%%%02X", string.byte(c)) end)
    str = string.gsub (str, " ", "%%20")
  end
  return str	
end

--[[***************************************************************************
	getEnvironmentVarWin

	IMPORTANT:  This must be called from within an async task, either one
	we've explicitly set up or one Lightroom sets up automatically
	(for example, in processRenderedPhotos() we're already in an async task).
	
	Note that os.getenv() is not available in the Lightroom SDK's limited subset of Lua.  Too bad.
******************************************************************************]]
function ONLRConduitUtils.getEnvironmentVarWin(varName)
	local value = nil
	
	if WIN_ENV == true then
		if varName == nil or varName == "" then
			ONLRConduitUtils.logMessage("   *** ONLRConduitUtils.getEnvironmentVarWin >  UH-OH, invalid varName arg: " .. tostring(varName))
		else
			--ONLRConduitUtils.logMessage("Entering getEnvironmentVarWin(" .. varName .. ")")
			local command
			local retCode = nil
			
			-- We use LrTasks.execute() to issue a (DOS) shell command that spits out the value of the
			-- environment variable.  Unfortunately, we can't get the output from the command directly,
			-- all we get is an exit code.  So we have the command output go to a temp file and then read the file.

			local destFile = LrPathUtils.getStandardFilePath('temp') .. "\\onOne_LR_env_output.txt"
			ONLRConduitUtils.logMessage("   getEnvironmentVarWin >  destFile is " .. destFile)
		
			command = "echo %" .. varName .. "% > " .. '"' .. destFile .. '"'

				-- Note that LrTasks.execute must be called from within an async task.
				-- If ONLRConduitUtils.getEnvironmentVarWin is not called from within an async task,
				-- the call to LrTasks.execute will cause an error.
			retCode = LrTasks.execute(command)
			ONLRConduitUtils.logMessage("   getEnvironmentVarWin(" .. varName .. ") >  retCode = " .. retCode .. " from command " .. command)

			if retCode == 0 then
				if LrFileUtils.exists(destFile) == 'file' then
					local fp = io.open(destFile)
					local valueString = fp:read("*l")		-- reads one line (avoids newline at the end)
						-- WARNING: There's still an extra space at the end.
					--local valueString = fp:read("*a")		-- reads whole file
					fp:close()

					ONLRConduitUtils.logMessage("   ==>  value of environment var read from temp file:  " .. tostring(valueString))
					if valueString ~= nil then
						value = LrStringUtils.trimWhitespace(valueString)
						if value == "" then
							value = nil
						end
					end

					-- Delete the temp file.
					local deleteSucceeded = LrFileUtils.moveToTrash(destFile)
					ONLRConduitUtils.logMessage("   File " .. destFile .. " deleted:  " .. tostring(deleteSucceeded))
				end
			end
		end
	end
	
	return value
end

--[[***************************************************************************

  Getting locations of user data and shared data on a given OS ...
  
  Mac:
	
	We can probably continue to use:
		 "~/Library/Application Support/onOne Software/"
		 "/Library/Application Support/onOne Software/"
				
  Windows:

	Where we normally put onOne stuff on various Windows OSes (this may change):
	
		Vista, Win7:
		
			C:\Users\jjones\AppData\Roaming\onOne Software\
			C:\ProgramData\onOne Software\						(shared)
			(also, C:\Users\All Users\  should be a shortcut to C:\ProgramData)
			
		XP:
		
			C:\Documents and Settings\jjones\Application Data\onOne Software\
			C:\Documents and Settings\All Users\Application Data\onOne Software	\	(shared)
			
	Results from LrPathUtils.getStandardFilePath() on Windows (Vista):
	
       'home'        = C:\Users\jjones
       'temp'        = C:\Users\jjones\AppData\Local\Temp\
       'desktop'     = C:\Users\jjones\Desktop
       'appPrefs'    = C:\Users\jjones\AppData\Roaming\Adobe\Lightroom\Preferences
       'pictures'    = C:\Users\jjones\Pictures
       'documents'   = C:\Users\jjones\Documents

	   Lightroom 3 only:
	   'appData'	 = C:\Users\jjones\AppData\Roaming\Adobe\Lightroom    [not very helpful]

******************************************************************************]]

--[[***************************************************************************
This (Windows only) method will return a string which is the path to the
ProgramData folder, which is where shared data normally goes on Vista and Win 7.
It also looks for an XP-style location, so it should also work on XP.
Currently a brute-force method is used, trying drive letters until the path is found.
An alternative using environment variables may also be possible. 
******************************************************************************]]
function findWinProgramData()
	
-- A potential alternative approach using environment variables:
--local programDataPath = ONLRConduitUtils.getEnvironmentVarWin("ProgramData")		-- does this work on XP?

	local programDataPath = nil

	local pathRoot
	local testPath
	local found = false
		
	-- Since we don't have a good way to tell what the OS is, try all possibilities.
	-- For example, on the C: drive try ":\\ProgramData" for Vista and Win7,
	-- and try ":\\Documents and Settings\\All Users" for XP.
	local rootsToTry = {":\\ProgramData", ":\\Documents and Settings\\All Users\\Application Data"}
	local rootCount = #rootsToTry
	
	-- Look for ProgramData on a bunch of potential drive locations.
	local driveLetters = {"C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}

	local nDrives = #driveLetters
	for i = 1, nDrives do
		for iRoot = 1, rootCount do
			pathRoot = rootsToTry[iRoot]
			testPath = driveLetters[i] .. pathRoot
			ONLRConduitUtils.logMessage("Searching for " .. pathRoot .. " at: " .. testPath)

			if LrFileUtils.exists(testPath) == "directory" then
				found = true
				ONLRConduitUtils.logMessage("Found " .. pathRoot .. " at: " .. testPath)
				programDataPath = testPath
				--programDataPath = '"' .. testPath .. '"'
				break
			end
		end
		
		if found then
			break
		end
	end

	--If we couldn't find the app in any of the above places, just give up.
	if programDataPath == nil then
		ONLRConduitUtils.logMessage("*** findWinProgramData:  Unable to find ProgramData folder!!!  Using a default.")
		-- But we'll set it something so nil doesn't cause problems upstream.
		programDataPath = "C:\\ProgramData"
	else
		ONLRConduitUtils.logMessage(">>> findWinProgramData - Found shared ProgramData folder:  " .. programDataPath)
	end

	return programDataPath
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.getUserProductDataPath()
	local appDataPath
	if WIN_ENV == true then
		local adobeAppDataPath = LrPathUtils.getStandardFilePath('appData')
		ONLRConduitUtils.logMessage("ONLRConduitUtils.getUserProductDataPath >   adobeAppDataPath:  " .. adobeAppDataPath)
		-- Sadly, "appData" gives us a Lightroom-specific path, such as "C:\Users\jjones\AppData\Roaming\Adobe\Lightroom",
		-- but we can simply back up from that, to "Roaming".
		appDataPath = adobeAppDataPath .. "\\..\\.."
		ONLRConduitUtils.logMessage("ONLRConduitUtils.getUserProductDataPath >   appDataPath:  " .. appDataPath)
		-- Resolve ".."
		appDataPath = LrPathUtils.standardizePath(appDataPath)
		ONLRConduitUtils.logMessage("ONLRConduitUtils.getUserProductDataPath >   standardized appDataPath:  " .. appDataPath)
	else
		appDataPath = LrPathUtils.standardizePath("~/Library/Application Support")
	end
	
	local onOnePath = LrPathUtils.child(appDataPath, "onOne Software")
	local productPath = LrPathUtils.child(onOnePath, ONLRProductSettings.dataFolderName)
	
	ONLRConduitUtils.logMessage("ONLRConduitUtils.getUserProductDataPath >>>   resulting productPath:  " .. productPath)

	return productPath
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.getSharedProductDataPath()
	local appDataPath = nil
	if WIN_ENV == true then
		-- Since there's no direct way to get this from the LR SDK, use a brute force approach.
		appDataPath = findWinProgramData()
	else
		appDataPath = LrPathUtils.standardizePath("/Library/Application Support")
	end
	
	local onOnePath = LrPathUtils.child(appDataPath, "onOne Software")
	local productPath = LrPathUtils.child(onOnePath, ONLRProductSettings.dataFolderName)
	
	ONLRConduitUtils.logMessage("ONLRConduitUtils.getSharedProductDataPath >>>   resulting productPath:  " .. productPath)

	return productPath
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitUtils.getCategoriesAndPresets()

	local categoryTable = {} -- start fresh

	local userProductDataPath = ONLRConduitUtils.getUserProductDataPath()
	local sharedProductDataPath = ONLRConduitUtils.getSharedProductDataPath()
	
	local factoryPresetsPath = LrPathUtils.child(sharedProductDataPath, "FactoryPresets")
	local userPresetsPath = LrPathUtils.child(userProductDataPath, "Presets")
	
	ONLRConduitUtils.logMessage("Factory presets path: " .. factoryPresetsPath)
	ONLRConduitUtils.logMessage("User presets path:    " .. userPresetsPath)
	
	local presetsPaths = { factoryPresetsPath, userPresetsPath }
	
	if LrFileUtils.exists(factoryPresetsPath) ~= "directory" and LrFileUtils.exists(userPresetsPath) ~= "directory" then
		ONLRConduitUtils.logMessage("ONLRConduitUtils.getCategoriesAndPresets> ****** NO PRESETS FOLDERS WERE FOUND *******")
		
		--local msg =  LOC("$$$/ONLRConduitUtils/Service/exportFailed=Sorry, Lightroom could not complete your request. The original file for the image, " .. originalImage .. ", no longer exists.")
		--LrDialogs.message(msg, "critical")
		return categoryTable
	end
	
	local presetExt = ONLRProductSettings.presetFileExtension
	if presetExt ~= nil then
		ONLRConduitUtils.logMessage(" >>> Preset extension for this product:  " .. presetExt)
	else
		ONLRConduitUtils.logMessage(" *** WARNING:  Preset extension for this product is NIL")
	end
	
	-- Traverse the subfolders to get categories, and get preset names from the files in them.
	
	local categoryName
	local categoryCount = 0
	
	local presetTable = {}
	local presetCount = 0
	local filename
	local extension
	local presetName
	
	local isUser
	
	--ONLRConduitUtils.logMessage("  Number of root paths for presets:  " .. tostring(#presetsPaths))
	
	for i, path in next, presetsPaths, nil do

		if LrFileUtils.exists(path) == "directory" then
			isUser = (LrPathUtils.leafName(path) ~= "FactoryPresets")
			--ONLRConduitUtils.logMessage("  " .. tostring(i) .. ".  Looking for categories in " .. path)
			--ONLRConduitUtils.logMessage("       (isUser =  " .. tostring(isUser) .. ")")
			
			-- Each child folder should represent a preset category.
			for dir in LrFileUtils.directoryEntries(path) do
				if LrFileUtils.exists(dir) == "directory" then
					-- Found a category folder.
					categoryName = LrPathUtils.leafName(dir)
					--ONLRConduitUtils.logMessage("    Category folder:  " .. categoryName)
					
					-- Each file in the category folder should be a preset in the category.
					presetTable = {}	-- start fresh for each loop
					presetCount = 0
					for file in LrFileUtils.directoryEntries(dir) do
						if LrFileUtils.exists(file) == "file" then
							-- First make sure it's a valid preset file
							filename = LrPathUtils.leafName(file)
							extension = LrPathUtils.extension(file)
							--ONLRConduitUtils.logMessage(" > Filename: " .. filename .. ",  Extension = " .. extension)
							if filename == ".DS_Store" then
								ONLRConduitUtils.logMessage("   Ignoring non-preset file " .. filename .. " in category folder " .. categoryName)
							elseif filename == "__exclude" then
								-- Found the file marking this category to exclude
                                presetCount = 0
                                presetTable = {}
                                break
							elseif presetExt ~= nil and extension ~= presetExt then
								ONLRConduitUtils.logMessage("   Ignoring non-preset file " .. filename .. " in category folder " .. categoryName)
							else
								-- Found a preset in the category
								presetName = LrPathUtils.leafName(LrPathUtils.removeExtension(file))
								presetCount = presetCount + 1
								presetTable[presetCount] = {["name"]=presetName, ["category"]=categoryName, ["userPreset"]=isUser}
								--ONLRConduitUtils.logMessage("      Preset:  " .. presetName .. "   (file:  " .. LrPathUtils.leafName(file) .. ")")
							end
						else
							ONLRConduitUtils.logMessage("   Non-file child " .. LrPathUtils.leafName(file) .. " in category folder " .. LrPathUtils.leafName(dir))
						end
					end
					
					if presetCount > 0 then
						categoryCount = categoryCount + 1
						categoryTable[categoryCount] = {["name"]=categoryName, ["userCategory"]=isUser, ["presetTable"]=presetTable}
						--ONLRConduitUtils.logMessage(" Category " .. categoryName .. " has " .. tostring(presetCount) .. " presets.")
					else
						--ONLRConduitUtils.logMessage(" Category " .. categoryName .. " has -NO- presets.")
					end
				else
					ONLRConduitUtils.logMessage(" Non-directory child " .. LrPathUtils.leafName(dir) .. " in folder " .. LrPathUtils.leafName(path))
				end
			end
		end
		
	end
	
	return categoryTable
end

--[[*************************************************************************** 

******************************************************************************]]
function ONLRConduitUtils.dumpPresetList( propertyTable )
	
	local categoryTable = ONLRConduitUtils.getCategoriesAndPresets()
	
	ONLRConduitUtils.logMessage("Categories and Presets for " .. ONLRProductSettings.productNameForMessages .. ":")
	
	local nCategories = #categoryTable
	ONLRConduitUtils.logMessage("    Number of categories:  " .. tostring(nCategories))
	
	local category
	local preset
	
	for c, category in next, categoryTable, nil do
		ONLRConduitUtils.logMessage("    Category: "  .. category.name .. "  (userCategory = " .. tostring(category.userCategory) .. ")")
		
		for p, preset in next, category.presetTable, nil do
			ONLRConduitUtils.logMessage("        Preset: "  .. preset.name .. "  (category = " .. preset.category .. ", userPreset = " .. tostring(preset.userPreset) .. ")")
		end
	end
	
end

--[[***************************************************************************

******************************************************************************]]
 function ONLRConduitUtils.getCategoryList( categoryTable )
 	local categoryList = {}
	
	if categoryList ~= nil then
		local count = #categoryTable
		for idx = 1, count do
			categoryList[idx] = { title=categoryTable[idx].name, value=idx }
		end
	end
	
 	return categoryList
 end
 
--[[*************************************************************************** 

******************************************************************************]]
 function ONLRConduitUtils.getPresetListForCategory( category )
 	
 	local presetList = {}
	
	if category ~= nil then
		local count = #category.presetTable		-- category.presetTable.Count ?
		for idx = 1, count do
			presetList[idx] = { title=category.presetTable[idx].name, value=idx }
		end
	end
 
 	return presetList
 end
 
--[[*************************************************************************** 	

******************************************************************************]]
function ONLRConduitUtils.getPresetInfo(categoryTable, categoryIdx, presetIdx)

	local presetInfo = {}
	
	if categoryTable ~= nil then
		local categoryName = categoryTable[categoryIdx].name
		local presetName = categoryTable[categoryIdx].presetTable[presetIdx].name
		local isUserPreset = categoryTable[categoryIdx].presetTable[presetIdx].userPreset
		
		presetInfo = { category = categoryName, preset = presetName, userPreset = isUserPreset }
	end
	
	return presetInfo
end

--[[*************************************************************************** 	

  NOT USED:  getPresetPath

******************************************************************************]]
--[[*************************************************************************** 	
	function ONLRConduitUtils.getPresetPath(categoryTable, categoryIdx, presetIdx)
		local categoryName = categoryTable[categoryIdx].name
		local presetName = categoryTable[categoryIdx].presetTable[presetIdx].name
		
		local path = categoryTable.basePath .. categoryTable.pathSeparator
		path = path .. categoryName .. categoryTable.pathSeparator
		path = path .. presetName .. "." .. categoryTable.presetSuffix
	 
		ONLRConduitUtils.logMessage("ONLRConduitUtils.getPresetPath> path= " .. path)
		
		return path
	end
******************************************************************************]]


--[[***************************************************************************

	Script entry point
	
******************************************************************************]]

if ONLRProductSettings.enableLogging then

	logger = LrLogger(ONLRProductSettings.loggerName)
	logger:enable("logfile")

	ONLRConduitUtils.logMessage("============= ONLRConduitUtils Loaded " .. os.date() .. " =============")
end

--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]




