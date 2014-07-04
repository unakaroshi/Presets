--[[***************************************************************************

	ONLRConduitService.lua
	
	Copyright (c) 2008 onOneSoftware, Inc.
	All Rights Reserved

******************************************************************************]]

	-- Lightroom SDK
local LrView			= import 'LrView'
local LrStringUtils		= import 'LrStringUtils'
local LrPathUtils		= import 'LrPathUtils'
local LrPhotoInfo		= import 'LrPhotoInfo'
local LrXml				= import "LrXml"
local lrHttp			= import "LrHttp"
local LrTasks			= import "LrTasks"
local LrDialogs			= import "LrDialogs"
local LrFileUtils		= import "LrFileUtils"
local LrApplication		= import "LrApplication"
local LrBinding			= import "LrBinding"
local bind				= LrView.bind

local LrFunctionContext	= import "LrFunctionContext"

local cmPerInch		= 2.54
local inchesPerCm	= 0.3937

require 'ONLRConduitUtils'

local ONLRConduitService = {}



--[[***************************************************************************
	Plugin-specific key values to remember between invocations of the Export dialog,
	along with initial default values.
******************************************************************************]]
-- This setting has special meaning for LR
ONLRConduitService.exportPresetFields = {
	{ key = 'settingsToExport',			default = 'exportPreset'	},

	{ key = 'editMode',					default = 'EditCopyWithAdjustments'	},
	{ key = 'presetFPN',				default = ''						},
	{ key = 'defaultPresetFPN',			default = ''						},
	
	{ key = 'selectedCategory',			default = 1					},
	{ key = 'selectedPreset',			default = 1					},

	{ key = 'selectedResizeType',		default = 'widthHeight'		},
	{ key = 'resizeWidth',				default = 0					},
	{ key = 'resizeHeight',				default = 0					},
	{ key = 'singleDimension',			default = 0					},
	{ key = 'selectedSizeUnits',		default = 'pixels'			},
	{ key = 'currentUnitsPrecision',	default = 0					},
	{ key = 'resizeResolution',			default = 300				},
	{ key = 'selectedResUnits',			default = 'pixelsPerInch'	},

	{ key = 'newPixelWidth',			default = 0					},
	{ key = 'newPixelHeight',			default = 0					},
	{ key = 'newResDPI',				default = 300				},
}

--[[***************************************************************************

******************************************************************************]]
-- This setting has special meaning for LR.  Perfect Resize hides these views because they are not necessary.
if ONLRProductSettings.supportsImageSizeAdjustments then
	ONLRConduitService.hideSections = { 'imageSettings', 'outputSharpening' }
end



--[[***************************************************************************

******************************************************************************]]
ONLRConduitService.canExportToTemporaryLocation = true

 --[[*************************************************************************** 

******************************************************************************]]
function ONLRConduitService.updateSingleDimension(propertyTable, resizeType)
	if resizeType == "widthHeight" then
		propertyTable.singleDimension = 0
	elseif resizeType == "longEdge" then
		if propertyTable.resizeHeight < propertyTable.resizeWidth then
			propertyTable.singleDimension = propertyTable.resizeWidth
		else
			propertyTable.singleDimension = propertyTable.resizeHeight
		end
	elseif resizeType == "shortEdge" then
		if propertyTable.resizeHeight > propertyTable.resizeWidth then
			propertyTable.singleDimension = propertyTable.resizeWidth
		else
			propertyTable.singleDimension = propertyTable.resizeHeight
		end
	end
	
	ONLRConduitUtils.logMessage("    propertyTable.selectedResizeType in updateSingleDimension	= " .. propertyTable.selectedResizeType)
end

--[[*************************************************************************** 

******************************************************************************]]
function ONLRConduitService.handleSizeUnitsChange(propertyTable, newSizeUnits)

	ONLRConduitUtils.logMessage(" ONLRConduitService.handleSizeUnitsChange" )

	if propertyTable.prevSizeUnits ~= newSizeUnits then
		local resDPI
		if propertyTable.selectedResUnits == "pixelsPerInch" then
			resDPI = propertyTable.resizeResolution
		else	-- "pixelsPerCm"
			resDPI = propertyTable.resizeResolution * cmPerInch
		end
		
		-- Compute conversion factor as a conversion first to pixels then to new units
		local convFactor = 1.0
		if propertyTable.prevSizeUnits == "inches" then
			convFactor = resDPI
		elseif propertyTable.prevSizeUnits == "centimeters" then
			convFactor = inchesPerCm * resDPI
		end
		if newSizeUnits == "inches" then
			convFactor = convFactor / resDPI
			propertyTable.currentUnitsPrecision = 3		-- 3 decimal places for inches
		elseif newSizeUnits == "centimeters" then
			convFactor  = cmPerInch * (convFactor / resDPI)
			propertyTable.currentUnitsPrecision = 3		-- 3 decimal places for centimeters
		else
			propertyTable.currentUnitsPrecision = 0		-- 0 decimal places (integer) for pixels
		end
		
		propertyTable.resizeWidth  = convFactor * propertyTable.resizeWidth
		propertyTable.resizeHeight = convFactor * propertyTable.resizeHeight
		propertyTable.singleDimension = convFactor * propertyTable.singleDimension
		
		propertyTable.prevSizeUnits = newSizeUnits
	end
	
end

--[[*************************************************************************** 

******************************************************************************]]
function ONLRConduitService.handleResizeTypeChange(propertyTable, newResizeType)
	if propertyTable.prevResizeType ~= newResizeType then
		
		-- Current aspect ratio
		local aspectRatio = 1.0
		if propertyTable.resizeHeight > 0 then
			aspectRatio = propertyTable.resizeWidth / propertyTable.resizeHeight
		end
		
		-- First update width and height based on previous resize type
		if propertyTable.prevResizeType == "longEdge" then
			if aspectRatio >= 1 then
				propertyTable.resizeWidth		= propertyTable.singleDimension
				propertyTable.resizeHeight		= propertyTable.resizeWidth / aspectRatio
			else
				propertyTable.resizeHeight		= propertyTable.singleDimension
				propertyTable.resizeWidth		= propertyTable.resizeHeight * aspectRatio
			end
		elseif propertyTable.prevResizeType == "shortEdge" then
			if aspectRatio >= 1 then
				propertyTable.resizeHeight		= propertyTable.singleDimension
				propertyTable.resizeWidth		= propertyTable.resizeHeight * aspectRatio
			else
				propertyTable.resizeWidth		= propertyTable.singleDimension
				propertyTable.resizeHeight		= propertyTable.resizeWidth / aspectRatio
			end
		-- else: If prev was widthHeight, then width & height are already correct.
		end
		
		-- Now update appropriate value(s) for new resize type
		ONLRConduitService.updateSingleDimension(propertyTable, newResizeType)
		
		propertyTable.prevResizeType = newResizeType
	end
	
end

--[[*************************************************************************** 

******************************************************************************]]
function ONLRConduitService.createXMLForResizeOptions(propertyTable)
	
	ONLRConduitUtils.logMessage("    propertyTable.selectedResizeType	= " .. propertyTable.selectedResizeType)
	ONLRConduitUtils.logMessage("    propertyTable.selectedSizeUnits	= " .. propertyTable.selectedSizeUnits)
	ONLRConduitUtils.logMessage("    propertyTable.resizeWidth			= " .. tostring(propertyTable.resizeWidth))
	ONLRConduitUtils.logMessage("    propertyTable.resizeHeight			= " .. tostring(propertyTable.resizeHeight))
	ONLRConduitUtils.logMessage("    propertyTable.singleDimension 		= " .. tostring(propertyTable.singleDimension))
	ONLRConduitUtils.logMessage("    propertyTable.resizeResolution		= " .. tostring(propertyTable.resizeResolution))
	ONLRConduitUtils.logMessage("    propertyTable.selectedResUnits		= " .. propertyTable.selectedResUnits)

	--This dictionary is strictly for Perfect Resize, the keys and values are defined in gfenum.h and GFModel.h
	 --For the Resize to fit option
	 local kPRResizeToFitWidthHeight = 1
	 local kPRResizeToFitLongEdge = 2
	 local kPRResizeToFitShortEdge = 3
	 
	 --For document units
	local DU_PIXELS = 0
	local DU_INCHES = 2
	local DU_CM = 4
	 
	 --For resolution units
	local RU_PIXELS_PER_INCH = 0
    local RU_PIXELS_PER_CM = 1
	 
	local bldr = LrXml.createXmlBuilder( true ) 
	bldr:beginBlock( "dict" )
	
		--Letting resize know it's a "Dynamic" preset
		bldr:tag("key", "Dynamic")
		bldr:tag("integer", tostring(1))
		
		--Units Pref -- kEXPrefsUnitsKey
		if propertyTable.selectedSizeUnits == "pixels" then
			bldr:tag("key", "UnitsPref")
			bldr:tag("integer", tostring(DU_PIXELS))
		elseif propertyTable.selectedSizeUnits == "inches" then
			bldr:tag("key", "UnitsPref")
			bldr:tag("integer", tostring(DU_INCHES))
		elseif propertyTable.selectedSizeUnits == "centimeters" then
			bldr:tag("key", "UnitsPref")
			bldr:tag("integer", tostring(DU_CM))
		end
		
		--Doc Resize Units Pref -- kEXPrefsDocResUnitsKey
		if propertyTable.selectedResUnits == "pixelsPerInch" then
			bldr:tag("key", "DocResUnitsPref")
			bldr:tag("integer", tostring(RU_PIXELS_PER_INCH))
		elseif propertyTable.selectedSizeUnits == "pixelsPerCm" then
			bldr:tag("key", "DocResUnitsPref")
			bldr:tag("integer", tostring(RU_PIXELS_PER_CM))
		end
		
		--Resolution -- kEXPrefsResolutionKey
		bldr:tag("key", "ResolutionPref")
		bldr:tag("integer", tostring(propertyTable.resizeResolution))
		
		--Resize to fit type -- kSCPrefsResizeToFit
		if propertyTable.selectedResizeType == "widthHeight" then
			bldr:tag("key", "ResizeToFit")
			bldr:tag("integer", tostring(kPRResizeToFitWidthHeight))
			
			--Width -- kEXPrefsWidthKey
			bldr:tag("key", "WidthPref")
			bldr:tag("integer", tostring(propertyTable.resizeWidth))
			
			--Height -- kEXPrefsHeightKey
			bldr:tag("key", "HeightPref")
			bldr:tag("integer", tostring(propertyTable.resizeHeight))
			
		elseif propertyTable.selectedResizeType == "longEdge" then
			bldr:tag("key", "ResizeToFit")
			bldr:tag("integer", tostring(kPRResizeToFitLongEdge))
			
			--Long Edge is Overloaded as Height -- kEXPrefsHeightKey
			bldr:tag("key", "HeightPref")
			bldr:tag("integer", tostring(propertyTable.singleDimension))
			
		elseif propertyTable.selectedResizeType == "shortEdge" then
			bldr:tag("key", "ResizeToFit")
			bldr:tag("integer", tostring(kPRResizeToFitShortEdge))
			
			--Short Edge is Overloaded as Height -- kEXPrefsHeightKey
			bldr:tag("key", "HeightPref")
			bldr:tag("integer", tostring(propertyTable.singleDimension))
		end


	bldr:endBlock()
	
	local xmlString = bldr:serialize()
	
	ONLRConduitUtils.logMessage("The XML for the resizing options looks like	= " .. xmlString)
	
	return xmlString
end


--[[*************************************************************************** 
This function is necessary for the ONLRConduitService to work,
even if Export is disabled.
******************************************************************************]]
function ONLRConduitService.startDialog( propertyTable )
	ONLRConduitUtils.logMessage("Entering ONLRConduitService.startDialog>")
		
	-- Start out with mostly the same export settings as in the Menu script.
	
	if ONLRProductSettings.supportsBatch then
		propertyTable.processAsBatch					= true
		propertyTable.LR_export_destinationType			= "sourceFolder"
		propertyTable.LR_export_useSubfolder			= false
		-- For the dialog, leave reimport true, but we'll override it later (see endDialog())
		propertyTable.LR_reimportExportedPhoto			= true
	else
		propertyTable.processAsBatch					= false
		propertyTable.LR_export_destinationType			= "specificFolder"
		propertyTable.LR_export_useSubfolder			= false
		propertyTable.LR_reimportExportedPhoto			= false
		propertyTable.LR_export_destinationPathPrefix 	= LrPathUtils.getStandardFilePath("temp")	
	end
	
	--propertyTable.LR_exportServiceProvider 		= _PLUGIN.id	-- I doubt we need this here, since we're already in it
		
	if ONLRProductSettings.supportsExport then
		propertyTable.LR_collisionHandling			= "overwrite"
	else
		propertyTable.LR_canExport = false
		propertyTable.LR_collisionHandling			= "rename"
	end
	
	propertyTable.showUI							= false		-- since we're doing an Export
	propertyTable.LR_minimizeEmbeddedMetadata		= false
	--previously defined in ONLRConduitUtils.lua - this define causes the lightroom export diaog to fail to load the conduit - commented out
	--pfExportSettings.LR_removeLocationMetadata		= false	
	propertyTable.LR_includeVideoFiles				= false
	propertyTable.fromExportDialog					= true		-- could be useful

	propertyTable.photosToExport					= {}

	  -- Default values for settings affected by LR prefs from Layers
	propertyTable.LR_format							= "PSD"
	propertyTable.LR_reimport_stackWithOriginal		= true
	propertyTable.use_original_for_single_PSDs		= true
	propertyTable.LR_export_colorSpace				= "AdobeRGB" 
	propertyTable.LR_export_bitDepth				= 8			-- should default be 16 ??? 
	propertyTable.LR_size_resolution				= 300
	propertyTable.LR_size_resolutionUnits			= "inch"
	
	propertyTable.editOriginal					= false
	
	propertyTable.operationMode						= 1		-- i.e. create new session (as opposed to merge with existing layers)

	ONLRConduitUtils.logMessage("ONLRConduitService.startDialog>  Done initializing propertyTable defaults.")
	

	-- Get latest LR prefs from Layers, via a prefs file.  This may overwrite a few things.
	-- We no longer get the prefs from the Layers server, because we don't want to require
	-- Layers to be running yet.  Launching Layers here would be premature, since it's possible
	-- that the user will cancel out of the Export dialog or switch to a different LR plugin
	-- (service provider) in the drop-down menu.
	
	ONLRConduitUtils.GetPerfectLayersPrefsFromFile(propertyTable)
	
	ONLRConduitUtils.logMessage("ONLRConduitService.startDialog>  Done updating propertyTable with prefs from Layers.")

	
	LrTasks.startAsyncTask(
	function()
	
		local activeCatalog = LrApplication.activeCatalog()
		activeCatalog:withReadAccessDo(
			function()
				local targetPhoto
				for i, targetPhoto in next, activeCatalog.targetPhotos, nil do
					propertyTable.photosToExport[i] = targetPhoto.path
				end
			end
		)

		-- IGNORE the "Use original for single PSDs" pref in the Export dialog, per Dan H.
		
		if ONLRProductSettings.supportsPresets then
			--ONLRConduitUtils.dumpPresetList()
			local categoryTable = ONLRConduitUtils.getCategoriesAndPresets()
			if #categoryTable ~= 0 then
				propertyTable.selectedCategory	= 1
				propertyTable.selectedPreset	= 1
				propertyTable.categoryTable		= categoryTable
				propertyTable.categoryItemsList	= ONLRConduitUtils.getCategoryList(categoryTable)
				propertyTable.presetItemsList	= ONLRConduitUtils.getPresetListForCategory(categoryTable[propertyTable.selectedCategory])
				propertyTable.presetInfo		= ONLRConduitUtils.getPresetInfo(categoryTable, 1, 1)
				propertyTable:addObserver(
					'selectedCategory',
					function(properties, key, newValue)
						propertyTable.presetItemsList	= ONLRConduitUtils.getPresetListForCategory(propertyTable.categoryTable[newValue])
						propertyTable.selectedPreset	= 1
						propertyTable.presetInfo		= ONLRConduitUtils.getPresetInfo(categoryTable, newValue, 1)
					end)
				propertyTable:addObserver(
					'selectedPreset',
					function(properties, key, newValue)
						propertyTable.presetInfo		= ONLRConduitUtils.getPresetInfo(categoryTable, propertyTable.selectedCategory, newValue)
					end)
			end
		else
			propertyTable.presetInfo = nil		-- or maybe {}
		end
	
	if ONLRProductSettings.supportsImageSizeAdjustments then
			-- Get info for the first selected image.
			local photoInfo
			local activeCatalog = LrApplication.activeCatalog()
			activeCatalog:withReadAccessDo(
				function()
					photoInfo = LrPhotoInfo.fileAttributes(activeCatalog.targetPhotos[1].path)
				end
			)

			-- Initialize to the first image's original size, in pixels.
			propertyTable.origWidth				= photoInfo.width
			propertyTable.origHeight			= photoInfo.height
			propertyTable.resizeWidth			= photoInfo.width
			propertyTable.resizeHeight			= photoInfo.height
						
			ONLRConduitService.updateSingleDimension(propertyTable, propertyTable.selectedResizeType)

			-- Convert from pixels to last used units, if necessary.
			propertyTable.prevSizeUnits = "pixels"
			ONLRConduitService.handleSizeUnitsChange(propertyTable, propertyTable.selectedSizeUnits)
			
			-- selectedResizeType, selectedSizeUnits, currentUnitsPrecision, resizeResolution, and
			-- selectedResUnits are all remembered from last time.
			
			--propertyTable.LR_size_doConstrain		= false
					
			propertyTable.prevResizeType		= propertyTable.selectedResizeType
			propertyTable.prevSizeUnits			= propertyTable.selectedSizeUnits
			
			propertyTable:addObserver(
				'selectedResizeType',
				function(properties, key, newValue)
					ONLRConduitService.handleResizeTypeChange(propertyTable, newValue)
				end)

			propertyTable:addObserver(
				'selectedSizeUnits',
				function(properties, key, newValue)
					ONLRConduitService.handleSizeUnitsChange(propertyTable, newValue)
				end)
		else
			propertyTable.newPixelWidth		= 0
			propertyTable.newPixelHeight	= 0
			propertyTable.newResDPI			= 0
		end
	
	end)		-- end of LrTasks.startAsyncTask
		
	ONLRConduitUtils.logMessage("Leaving ONLRConduitService.startDialog>")

end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitService.endDialog(propertyTable, why)
	
	ONLRConduitUtils.logMessage("ONLRConduitService.endDialog()>  why = " .. tostring(why))	-- tostring can handle nil
	
	-- Unfortunately, in Lightroom 2, why is always nil, which I guess is an LR bug.
	-- So we can't really try to use it, because attempting to use its value causes an error
	-- and then our Export dialog handling is hosed.
	
	
	if why == nil or why == "ok" then
	
		-- Even if why is nil (Lightroom 2), we have to do this, in case the Export button was clicked.
		-- It shouldn't hurt anything if we don't actually export.
		
		ONLRConduitUtils.logMessage("ONLRConduitService.endDialog()>  Export button clicked, export beginning, OR why is nil.")
		
		-- Note that changes to the propertyTable can still have an effect at this point.
		
		-- Suppress reimport, but remember what the setting was in the dialog.
		propertyTable.reimportIfSuccessful = propertyTable.LR_reimportExportedPhoto
		propertyTable.LR_reimportExportedPhoto = false
		
		--ONLRConduitUtils.logMessage("ONLRConduitService.endDialog()>  LR_reimport_stackWithOriginal = " .. tostring(propertyTable.LR_reimport_stackWithOriginal))

		-- Remember the setting in the dialog for stackWithOriginal.
		-- Apparently something happens during the export that can set it to false,
		-- when invoked from the Export dialog.
		propertyTable.stackWithOriginal = propertyTable.LR_reimport_stackWithOriginal
		
	else
		
		ONLRConduitUtils.logMessage("ONLRConduitService.endDialog()>  Export cancelled, or different service provider selected.")
		
	end
	
	-- Initialize these in case they don't get assigned elsewhere
	propertyTable.newPixelWidth		= 0
	propertyTable.newPixelHeight	= 0
	propertyTable.newResDPI			= 0
end

--[[***************************************************************************
This function is necessary for the ONLRConduitService to work.  It adds some
UI of our own to Lightroom's Export dialog.  If Export is disabled for the
product, our UI just says you can't use Export with that product.
******************************************************************************]]
function ONLRConduitService.sectionsForTopOfDialog( f, propertyTable )

	if not ONLRProductSettings.supportsExport then
	
		return {
			{
				title = ONLRProductSettings.productNameForMessages .. " - Not for Export",
				synopsis = "",

				f:static_text {
					title = ONLRProductSettings.productNameForMessages .. " should be accessed from the File > Plug-In Extras Menu. This export panel is disabled",
					-- truncation = "middle",
					selectable = false,
					alignment = "left",
					height_in_lines = -1,
					width_in_chars = 50
					-- text_color = LrColor("red")
				}
			}
		}

	elseif not ONLRProductSettings.supportsPresets and not ONLRProductSettings.supportsImageSizeAdjustments then
	
		--?????
		return {
		}
		
	else
		local leftMarginForMainViews
		if ONLRProductSettings.supportsPresets and ONLRProductSettings.supportsImageSizeAdjustments then
			leftMarginForMainViews = 20
		else
			leftMarginForMainViews = 0
		end
		
		local presetsView = {}
		local sizingView = {}
		
		if ONLRProductSettings.supportsPresets then
		
			presetsView =
				f:view
				{
					margin_left = leftMarginForMainViews,
					margin_bottom = 2,
					spacing = f:control_spacing(),
					f:row 
					{
						margin_left = 10,
						spacing = f:control_spacing(),
	
						f:static_text 
						{
							title =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/categoryLabel=Category"),
							alignment = 'right',
							fill_horizontal = 1,
							enabled = LrBinding.keyEquals('settingsToExport', 'exportPreset'),
						},
	
						f:popup_menu 
						{
							value = bind 'selectedCategory',
							width = 180,
							title = LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/favorites=Favorites"),	--???
							items = bind 'categoryItemsList',
							enabled = LrBinding.keyEquals('settingsToExport', 'exportPreset'),
						},
					},
					f:row 
					{
						margin_left = 10,
						spacing = f:control_spacing(),
	
						f:static_text 
						{
							title =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/presetLabel=Preset"),
							alignment = 'right',
							fill_horizontal = 1,
							enabled = LrBinding.keyEquals('settingsToExport', 'exportPreset'),
						},
	
						f:popup_menu 
						{
							value = bind 'selectedPreset',
							width = 180,
							items = bind 'presetItemsList',
							enabled = LrBinding.keyEquals('settingsToExport', 'exportPreset'),
						},
					},
				}
		end
		
		if ONLRProductSettings.supportsImageSizeAdjustments then

			sizingView =
				f:view
				{
					margin_left = leftMarginForMainViews,
					margin_bottom = 2,
					spacing = f:control_spacing(),
					
					f:row 
					{
						f:static_text 
						{
							title =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/resizeLabel=Resize to Fit:"),
							alignment = 'right',
							width = LrView.share "sizing_label_width",	-- shared binding
							--!!! fill_horizontal = 1,		-- Don't do this, everything ends up all the way to the right
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},

						f:popup_menu 
						{
							value = bind 'selectedResizeType',
							width = 180,
							items = { {title="Width & Height", value="widthHeight"},
									  {title="Long Edge", value="longEdge"},
									  {title="Short Edge", value="shortEdge"}, },
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},
						
					},
					
					f:row 
					{
					
						f:static_text 
						{
							visible =  LrBinding.keyEquals("selectedResizeType", "widthHeight"),	-- Width & Height
							title =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/widthLabel=W:"),
							alignment = 'right',
							width = LrView.share "sizing_label_width",	-- shared binding, to line up with "Resize to Fit"
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},
						
						f:edit_field 
						{
							visible =  LrBinding.keyEquals("selectedResizeType", "widthHeight"),	-- Width & Height
							value = bind 'resizeWidth',
							width = 50,
							precision = bind 'currentUnitsPrecision',
							--min = 1,
							validate = function(view, value)
								if value <= 0 then
									return false, 1, "The number entered must be more than 0."
								end
								return true, value
							end,
							immediate = false,
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},

						f:static_text 
						{
							visible =  LrBinding.keyEquals("selectedResizeType", "widthHeight"),	-- Width & Height
							title =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/heightLabel=H:"),
							alignment = 'right',
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},
				
						f:column	-- place three alternate views for a dimension in the same space
						{
							place = "overlapping",
							
							-- Additional edit field for height (with other Width & Height controls also visible)
							f:view
							{
								visible =  LrBinding.keyEquals("selectedResizeType", "widthHeight"),	-- Width & Height
								f:edit_field 
								{
									value = bind 'resizeHeight',
									width = 50,
									precision = bind 'currentUnitsPrecision',
									--min = 1,
									validate = function(view, value)
										if value <= 0 then
											return false, 1, "The number entered must be more than 0."
										end
										return true, value
									end,
									immediate = false,
									enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
								},
							},
						
							-- Single dimension edit field (with other controls hidden)
							f:view		-- place two alternate views for a single dimension
							{
								visible =  LrBinding.keyIsNot("selectedResizeType", "widthHeight"),
								
								place = "overlapping",
								
								-- Single dimension edit field for long edge or short edge
								f:view
								{
									visible = true,
									f:edit_field 
									{
										value = bind 'singleDimension',
										width = 50,
										precision = bind 'currentUnitsPrecision',
										--min = 1,
										validate = function(view, value)
											if value <= 0 then
												return false, 1, "The number entered must be more than 0."
											end
											return true, value
										end,
										immediate = false,
										enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
									},
								},
							},
							
						 },
							
						f:column	-- place two alternate views for size units in the same space
						{
							place = "overlapping",
							
							f:view
							{
								margin_top = 1,
								margin_bottom = 2,
								
								visible =  true,
								f:row
								{
									f:popup_menu 
									{
										value = bind 'selectedSizeUnits',
										width = 70,
										items = { {title="pixels", value="pixels"},
												  {title="in", value="inches"},
												  {title="cm", value="centimeters"}, },
										enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
									},
								},
							},
						},

						f:static_text 
						{
							title =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/resolutionLabel=Resolution:"),
							width = 60,
							alignment = 'right',
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},

						f:edit_field 
						{
							value = bind 'resizeResolution',
							width = 50,
							precision = 0,
							min = 1,
							validate = function(view, value)
								if value < 1 then
									return false, 1, "The number entered must be at least 1."
								end
								return true, value
							end,
							immediate = false,
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},

						f:popup_menu 
						{
							value = bind 'selectedResUnits',
							width = 120,
							items = { {title="pixels per inch", value="pixelsPerInch"},
									  {title="pixels per cm", value="pixelsPerCm"}, },
							enabled = LrBinding.keyEquals('settingsToExport', 'exportResizing'),
						},
						
				
						
					},		-- end of second f:row
					
				}		-- end of containing view
			
		end		
	
		-- Now put the appropriate pieces together for the section we add to the Export dialog...
		
		ONLRConduitUtils.logMessage("Returning from ONLRConduitService.sectionsForTopOfDialog>")
	
		if ONLRProductSettings.supportsPresets and ONLRProductSettings.supportsImageSizeAdjustments then
			return {
				-- Set up a section in the Export dialog for either selecting a category and preset
				-- or adjusting image sizing settings, depending on which radio button is selected.
				{
					title = LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/TopSectionTitle=" .. ONLRProductSettings.productNameForMessages),
					f:column
					{
						spacing = f:control_spacing(),
						
						f:row
						{
							f:radio_button
							{
								title = "Preset",
								value = bind 'settingsToExport',
								checked_value = 'exportPreset',
							},
						},
						
						presetsView,	-- defined above

						f:separator
						{
							fill_horizontal = 0.98,
						},
						
						f:row
						{
							f:radio_button
							{
								title = "Image Resizing",
								value = bind 'settingsToExport',
								checked_value = 'exportResizing',
							},
						},
						
						sizingView,		-- defined above
					},
				}
			}
		elseif ONLRProductSettings.supportsPresets then
			return {
				-- Set up a section in the Export dialog for selecting a category and preset.
				{
					title = LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/TopSectionTitle=" .. ONLRProductSettings.productNameForMessages .. " Preset"),
					f:column
					{
						spacing = f:control_spacing(),
						
						presetsView,	-- defined above
					},
				}
			}
		else		-- ONLRProductSettings.supportsImageSizeAdjustments
			return {
				-- Set up a section in the Export dialog for image sizing adjustments.
				{
					title = LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/TopSectionTitle=" .. ONLRProductSettings.productNameForMessages .. " Image Sizing"),
					f:column
					{
						spacing = f:control_spacing(),
						
						sizingView,		-- defined above
					},
				}
			}
		end
		
	end
end


--[[***************************************************************************

******************************************************************************]]
function ONLRConduitService.getLayersConduitStatus(portNumber)

	local layersStatus = -1		-- kConduitStatusInvalid
	
	if portNumber == nil then
		portNumber = ONLRConduitUtils.GetPerfectLayersPortNumber()
	end

	if portNumber == nil then
		ONLRConduitUtils.logMessage("*** ONLRConduitService.getLayersConduitStatus >  ERROR: portNumber is nil!!!")
	else
		local url = "http://127.0.0.1:" .. portNumber .. "/layers?cmd=check_conduit_status"
	
		local resultBody = nil
		local headersTable = nil
	
		resultBody, headersTable = lrHttp.get(url)  
	
		local connected = false
		local gotResponse = false
		local gotStatus = false
	
		if headersTable == nil then
			ONLRConduitUtils.logMessage("ONLRConduitService.getLayersConduitStatus> ERROR: headersTable is nil")
		elseif headersTable.status == nil then
			ONLRConduitUtils.logMessage("ONLRConduitService.getLayersConduitStatus> ERROR: headersTable.status is nil")
		elseif headersTable.status ~= 200 then
			ONLRConduitUtils.logMessage("ONLRConduitService.getLayersConduitStatus> ERROR: headersTable.status = " .. headersTable.status)
		else
			connected = true
			if resultBody == nil then
				ONLRConduitUtils.logMessage("ONLRConduitService.getLayersConduitStatus> ERROR: resultBody is nil")
			else
				gotResponse = true
					
				--ONLRConduitUtils.logMessage("getLayersConduitStatus> response string from Layers: " .. resultBody)

				-- Parse XML response
				local dom, dom2, idx, childCount, dictChildCount, key, value
				dom = LrXml.parseXml(resultBody)
				childCount = dom:childCount()
				for idx = 1, childCount do
					dom2 	= dom:childAtIndex(idx)
					--ONLRConduitUtils.logMessage("getLayersConduitStatus> first child name: " .. dom2:name()) 
					if dom2:name() == 'dict' then
						-- Get status code
						dictChildCount = dom2:childCount()
						for idy = 1, dictChildCount, 2 do
							key 	= dom2:childAtIndex(idy)
							value 	= dom2:childAtIndex(idy + 1)
						
							if key:text() == 'conduit_status' then
								local textValue = value:text()
								if textValue ~= nil then
									--ONLRConduitUtils.logMessage("getLayersConduitStatus> value for conduit_status key: " .. textValue) 
									local numberValue = tonumber(textValue)
									if numberValue ~= nil then
										--ONLRConduitUtils.logMessage("getLayersConduitStatus> numeric value: " .. numberValue) 
										layersStatus = numberValue
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
			ONLRConduitUtils.logMessage("ONLRConduitService.getLayersConduitStatus> Perfect Layers Server Communication Error")
		elseif not gotStatus then
			ONLRConduitUtils.logMessage("ONLRConduitService.getLayersConduitStatus> Error in response XML from Perfect Layers")
		end
	end

	return layersStatus
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitService.SendImagesToPerfectLayers(imagesList, sourceImageCount, canvasOutputImage, propertyTable)
  
	ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> In Method, sourceImageCount: " .. sourceImageCount)
	
	-- Form URL for HTTP request.
	-- Example (with one image file, no preset):
	--	 "http://127.0.0.1:62626/layers?cmd=open_layers&layer_operation=1&vcb_plugin_ID=com.ononesoftware.vcb.perfecteffectsplugin&path=/Pictures/UglyDog.jpg"
	
	local portNumber = ONLRConduitUtils.GetPerfectLayersPortNumber()
	if portNumber == nil then
		ONLRConduitUtils.logMessage("*** ONLRConduitService.SendImagesToPerfectLayers >  ERROR: portNumber is nil!!!")
	else
		local url = "http://127.0.0.1:" .. portNumber .. "/layers?cmd=open_layers"
	
		-- Add operation mode param (create or merge)
		url = url .. "&layer_operation=" .. propertyTable.operationMode
	
		-- Add plugin param, to tell Layers to launch the specified VCB plugin and pass the images to it.
		url = url .. "&vcb_plugin_ID=" .. ONLRProductSettings.vcbPluginID
		
		
		-- Add a param indicating whether to process images in batch mode.
		if propertyTable.processAsBatch or ONLRProductSettings.loadOnePlugin == true then
			url = url .. "&batch_mode=1"
		else
			url = url .. "&batch_mode=0"
		end
	
		ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers>  base URL is:" .. url)
	
		if propertyTable.settingsToExport == "exportResizing" then	-- For Perfect Resize if the user selects the custom sizes
			propertyTable.presetInfo = nil
			
			local xmlString = ONLRConduitService.createXMLForResizeOptions(propertyTable)
			url = url .. "&dynamic_preset=" .. ONLRConduitUtils.url_encode(xmlString)
		end
	
		-- Add preset params, if a preset is selected (Export dialog only).
		if propertyTable.presetInfo ~= nil then
			url = url .. "&preset_category=" .. ONLRConduitUtils.url_encode(propertyTable.presetInfo.category)
			url = url .. "&preset_name=" .. ONLRConduitUtils.url_encode(propertyTable.presetInfo.preset)
			if propertyTable.presetInfo.userPreset then
				url = url .. "&preset_user_preset=true"
			else
				url = url .. "&preset_user_preset=false"
			end
		end

		ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers>  URL with preset params:" .. url)
	
		if canvasOutputImage ~= nil then
			url = url .. "&path=" .. ONLRConduitUtils.url_encode(canvasOutputImage)
		
			ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> In Method, canvas Output Image: " .. canvasOutputImage )
		end
	
		local resultBody
		local headersTable
	
		for i = 1, sourceImageCount do
			if imagesList[i] == nil then
				ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> ***** ImagesList[" .. i .. "] is null. *******")	
			else
				url = url .. "&path=" .. ONLRConduitUtils.url_encode(imagesList[i])
   			end
   		end		
	
		ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> complete url is: " .. url)		

		resultBody, headersTable = lrHttp.get(url)  
	
		if headersTable ~= nil then
			ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> headersTable exists")
		
			if headersTable.status ~= nil then
				ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> status code: " .. headersTable.status)
			end
		
			if resultBody ~= nil then
				--ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> result string: " .. resultBody)
			end
		else 
			ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> headersTable does not exist")
			ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> Perfect Layers Server Communication Error")
		end
	
		ONLRConduitUtils.logMessage("ONLRConduitService.SendImagesToPerfectLayers> completed")
	end

end

function ONLRConduitService.processPhotosAsLayers2(rendMap, nPhotos, propertyTable, progressScope)
	local imagesList = {}
	local activeCatalog = LrApplication.activeCatalog()
	local reimportFilePath
	local lrPhotoOfOriginal

	if propertyTable.editOriginal then
		-- Special case...
		-- "Use original for single PSDs" pref is on, and there's only one image to process,
		-- and it's a PSD.  (At least, that's the only way this SHOULD happen.)
		
		local originalImage = propertyTable.photosToExport[1]	-- i.e. same as rendMap[1].srcPhoto
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> Single PSD, use original: " .. originalImage)
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers>    (exported copy goes to: " .. rendMap[1].rendPath .. ")")
		
		if LrFileUtils.exists(originalImage) ~= "file" then
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> ****** ORIGINAL FILE NOT PRESENT *******")
			
			local msg =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. The original file for the image, " .. originalImage .. ", no longer exists.")
			LrDialogs.message(msg, "critical")
			return
		end
		
		imagesList[1] = originalImage
		
		progressScope:setPortionComplete(1, nPhotos)
	else
		for i = 1, nPhotos do
			reimportFilePath = rendMap[i].rendPath

			--
			-- Find the original image that is untouched to stack our copy with.
			--
			activeCatalog:withReadAccessDo(
				function()
					lrPhotoOfOriginal = activeCatalog:findPhotoByPath(rendMap[i].srcPhoto)
				end
			)

			--
			-- Bring the copy back into Lightroom
			--
			activeCatalog:withWriteAccessDo( "Reimport layers images",
				function()
					if propertyTable.LR_reimport_stackWithOriginal then
						activeCatalog:addPhoto(reimportFilePath, lrPhotoOfOriginal, 'below')
					else
						activeCatalog:addPhoto(reimportFilePath)
					end
				end
			)

			imagesList[i] = reimportFilePath
			progressScope:setPortionComplete(i, nPhotos)
		end
	end
	--
	-- Send all of the copied images to layers.
	--
	
	ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> LrTasks.startAsyncTask: SendImagesToPerfectLayers")

	LrTasks.startAsyncTask(
		function()
			ONLRConduitService.SendImagesToPerfectLayers(imagesList, nPhotos, nil, propertyTable)
		end
	)
	
end


--[[***************************************************************************

	Processing of selected photos as a set of layers, e.g. by Perfect Layers
	or Perfect Mask.  The result is a single PSD.
	
******************************************************************************]]
function ONLRConduitService.processPhotosAsLayers(rendMap, nPhotos, propertyTable, progressScope)
	local imagesList 		= {}
	local largestImage	
	local largestImageSize
	local largestImageIndex
	local photoSize
	local reimportFilePath
	local lrPhotoOfOriginal

	local currentMode = propertyTable.operationMode
	
	ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers>  propertyTable.LR_format = " .. propertyTable.LR_format)
	ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers>  propertyTable.LR_reimportExportedPhoto = " .. tostring(propertyTable.LR_reimportExportedPhoto))

	if propertyTable.editOriginal then
		-- Special case...
		-- "Use original for single PSDs" pref is on, and there's only one image to process,
		-- and it's a PSD.  (At least, that's the only way this SHOULD happen.)
		
		local originalImage = propertyTable.photosToExport[1]
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> Single PSD, use original: " .. originalImage)
	
		if LrFileUtils.exists(originalImage) ~= "file" then
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> ****** ORIGINAL FILE NOT PRESENT *******")
			
			local msg =  LOC("$$$/" .. ONLRProductSettings.LOCRoot .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. The original file for the image, " .. originalImage .. ", no longer exists.")
			LrDialogs.message(msg, "critical")
			return
		end
		
		local nListSize, canvasImagePath
		nListSize = 0
        canvasImagePath = originalImage

		progressScope:setPortionComplete(1, nPhotos)
		
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> LrTasks.startAsyncTask: SendImagesToPerfectLayers")

		LrTasks.startAsyncTask(
		function()
			ONLRConduitService.SendImagesToPerfectLayers(imagesList, nListSize, canvasImagePath, propertyTable)
		end)
				
	
	else 
		 -- the user wants to create a new session in PerfectLayers with these images
	
		--keep track of the largest image, initialize to the first image
		largestImage 		= rendMap[1].rendPath
		largestImageIndex 	= 1
		local attribTable 	= LrPhotoInfo.fileAttributes(largestImage)
		largestImageSize = attribTable.width * attribTable.height
		
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> The Largest Image is Starting out as: " .. largestImage .. " it's size is: " .. largestImageSize)
	
		for i = 2, nPhotos do
			
			local psdCopyOfImage = rendMap[i].rendPath	-- copy (with adjustments)
			
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> PSD Copy: " .. psdCopyOfImage )
			
			if LrFileUtils.exists(psdCopyOfImage) ~= "file" then
				ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> ****** PSD COPY OF FILE NOT PRESENT *******")
				
				local msg =  LOC("$$$/" .. ONLRProductSettings.LOCRoot .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. The PSD copy of the image: " .. psdCopyOfImage .. " was not created.")
				LrDialogs.message(msg, "critical")
				return
				
			end
			
			attribTable = LrPhotoInfo.fileAttributes(psdCopyOfImage)
			photoSize = attribTable.width * attribTable.height
			
			if largestImageSize >= photoSize then
				imagesList[i - 1] = psdCopyOfImage -- we have to subtract 1 from i because we start the loop at 2
			else
				imagesList[i - 1] = largestImage -- we have to subtract 1 from i because we start the loop at 2
				largestImageSize = photoSize
				largestImage = psdCopyOfImage
				largestImageIndex = i
				
				ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> The Largest Image is now: " .. largestImage .. " it's size is: " .. largestImageSize)
				
			end		
			
			progressScope:setPortionComplete(i, nPhotos)
		end
		

		--reimport the copy of the largest image to lightroom and stack it with its original
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> Reimporting the largest File: " .. largestImage)
	
		reimportFilePath = rendMap[largestImageIndex].srcPhoto
	
        if propertyTable.LR_format ~= "ORIGINAL" then
        	ONLRConduitUtils.logMessage("WE ARE REPLACING THE EXTENSION WITH: " .. propertyTable.LR_format)
            reimportFilePath = LrPathUtils.replaceExtension(reimportFilePath, propertyTable.LR_format)
        end

		reimportFilePath = LrFileUtils.chooseUniqueFileName( reimportFilePath )
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> reimport location is: " .. reimportFilePath)
	
	
		local copySucceeded = LrFileUtils.copy( largestImage, reimportFilePath )
	
		if copySucceeded == true then
		
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> Copy to reimport location Succeeded")
			
					
			-- send the source images to PerfectLayers with the reimportFilePath file to be used as the
			-- "canvas" and also to be the output file, we write the image data back to.
			
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> LrTasks.startAsyncTask: SendImagesToPerfectLayers")
	
			LrTasks.startAsyncTask(
				function()
					ONLRConduitService.SendImagesToPerfectLayers(imagesList, nPhotos - 1, reimportFilePath, propertyTable)
				end
			)
            
		else
		
			local msg =  LOC("$$$/" .. ONLRProductSettings.LOCRoot .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. Copying the file " .. reimportFilePath .. " for reimport to lightroom failed.")
			LrDialogs.message(msg, "critical")
		
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> *****COPY TO REIMPORT LOCATION FAILED*******")
			return
		
		end
        
        ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers> Polling Layers for status")
        local canceled = ONLRConduitService.pollLayersForStatus()

        if canceled == true then

            --Delete the Copy of the largest image as well
            ONLRConduitUtils.logMessage("      Deleting " .. reimportFilePath)
            LrFileUtils.moveToTrash(reimportFilePath)

        else
            
            --if we didn't cancel reimport the canvas output image

            local activeCatalog = LrApplication.activeCatalog()
			activeCatalog:withReadAccessDo(
				function()
					lrPhotoOfOriginal = activeCatalog:findPhotoByPath(rendMap[largestImageIndex].srcPhoto)
				end
			)
		
			activeCatalog:withWriteAccessDo( "Reimport largest image",
				function()
					--??? Use propertyTable.stackWithOriginal instead?
					if propertyTable.LR_reimport_stackWithOriginal then
						activeCatalog:addPhoto(reimportFilePath, lrPhotoOfOriginal, 'below')
					else
						activeCatalog:addPhoto(reimportFilePath)
					end
                end)
        end
        
         -- Delete unneeded rendered copies
            ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosAsLayers>  Processing failed or was cancelled.  DELETING COPIED FILES...")
            for iPhoto = 1, nPhotos do
                ONLRConduitUtils.logMessage("      Deleting " .. rendMap[iPhoto].rendPath)
                LrFileUtils.moveToTrash(rendMap[iPhoto].rendPath)
			end
    
    end
    
end


--[[***************************************************************************

	Utility for Polling layers status
	
******************************************************************************]]
function ONLRConduitService.pollLayersForStatus()

-- Poll for status info from Layers to track processing progress, until it's finished.
	
	ONLRConduitUtils.logMessage(">>> ONLRConduitService.pollLayersForStatus>  Polling for status from Layers...")
	local done = false
	local canceled = false
	local portNumber = ONLRConduitUtils.GetPerfectLayersPortNumber()
	local layersStatus = -1
	while not done do
		LrTasks.sleep(1)
		layersStatus = ONLRConduitService.getLayersConduitStatus(portNumber)
		--ONLRConduitUtils.logMessage("    ... layersStatus = " .. layersStatus)
		if layersStatus == -1 or layersStatus > 3 then
			if layersStatus ~= 4 then
				canceled = true
			end
			done = true
		end
	end
	
	ONLRConduitUtils.logMessage("... ONLRConduitService.pollLayersForStatus>  Done polling -- layersStatus = " .. layersStatus)
	ONLRConduitUtils.logMessage("... canceled = " .. tostring(canceled))
	
	return canceled
	
end


--[[***************************************************************************

	Processing of selected photos with a VCB plugin that supports batch,
	presets, etc.  Each image will be processed individually by the plugin.
	
******************************************************************************]]
function ONLRConduitService.processPhotosIndividually(rendMap, nPhotos, propertyTable, progressScope)
	local imagesList 		= {}

	ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually>  propertyTable.LR_format = " .. propertyTable.LR_format)
	ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually>  propertyTable.LR_reimportExportedPhoto = " .. tostring(propertyTable.LR_reimportExportedPhoto))

	-- Side note:
	-- If the user has selected a format other than PSD (or selected ORIGINAL and the original is not PSD),
	-- the file Lightroom exports for us to operate on will not be PSD.  That's OK, but by default Layers
	-- will save it back out (modified) as a PSD.  Ideally we should have Layers export it to the same
	-- format that was input, when it comes from the conduit.
	
	-- Always treat as operationMode = 1 (Create).
	-- (If, on the first image, Layers already has images loaded, it should prompt whether to save
	-- changes before clearing them out.)
	
	if propertyTable.editOriginal then
		-- Special case...
		-- "Use original for single PSDs" pref is on, and there's only one image to process,
		-- and it's a PSD.  (At least, that's the only way this SHOULD happen.)
		
		local originalImage = propertyTable.photosToExport[1]	-- i.e. same as rendMap[1].srcPhoto
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually> Single PSD, use original: " .. originalImage)
		ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually>    (exported copy goes to: " .. rendMap[1].rendPath .. ")")
		
		if LrFileUtils.exists(originalImage) ~= "file" then
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually> ****** ORIGINAL FILE NOT PRESENT *******")
			
			local msg =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. The original file for the image, " .. originalImage .. ", no longer exists.")
			LrDialogs.message(msg, "critical")
			return
		end
		
		imagesList[1] = originalImage
		
		progressScope:setPortionComplete(1, nPhotos)
	else
		for i = 1, nPhotos do
			
			local copyOfImage = rendMap[i].rendPath	-- copy (with adjustments)
			
			ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually> image copy #" .. i .. ": " .. copyOfImage )
			
			if LrFileUtils.exists(copyOfImage) ~= "file" then
				ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually> ****** PSD COPY OF FILE NOT PRESENT *******")
				
				local msg =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. The PSD copy of the image: " .. copyOfImage .. " was not created.")
				LrDialogs.message(msg, "critical")
				return
				
			end
			
			imagesList[i] = copyOfImage
				
			progressScope:setPortionComplete(i, nPhotos)
		
		end
	end
	
	ONLRConduitUtils.logMessage("ONLRConduitService.processPhotosIndividually> LrTasks.startAsyncTask: SendImagesToPerfectLayers")

	LrTasks.startAsyncTask(
	function()
		ONLRConduitService.SendImagesToPerfectLayers(imagesList, nPhotos, nil, propertyTable)
	end)


	local canceled = ONLRConduitService.pollLayersForStatus()
	
	-- If processing was canceled, we don't want to keep around copies that were
	-- created only for this purpose.
	
	if not propertyTable.editOriginal then

		if canceled and not propertyTable.LR_reimportExportedPhoto then

			-- Delete unneeded file copies
			ONLRConduitUtils.logMessage("*** ONLRConduitService.processPhotosIndividually>  Processing failed or was cancelled.  DELETING COPIED FILES...")
			for iPhoto = 1, nPhotos do
				ONLRConduitUtils.logMessage("      Deleting " .. rendMap[iPhoto].rendPath)
				LrFileUtils.moveToTrash(rendMap[iPhoto].rendPath)
			end
			
		elseif not propertyTable.LR_reimportExportedPhoto and propertyTable.reimportIfSuccessful then

			-- We turned off LR_reimportExportedPhoto for the export, so that the rendition is NOT automatically
			-- added to the catalog, in case processing fails or is cancelled.  It succeeded, so now we explicitly
			-- add the rendition to the catalog here.
			
			-- Add all successfully processed renditions to the catalog.
			-- Stack them with their respective originals, if specified.
			ONLRConduitUtils.logMessage(">>> ONLRConduitService.processPhotosIndividually>  Adding successfully processed renditions to catalog...")
			local activeCatalog = LrApplication.activeCatalog()
			local existingItem = nil
			activeCatalog:withWriteAccessDo(
				"onOne add to catalog",		-- This doesn't really seem to matter, but some string is required
				function()
					for iPhoto, targetPhoto in next, activeCatalog.targetPhotos, nil do
						existingItem = activeCatalog:findPhotoByPath(rendMap[iPhoto].rendPath)
						if existingItem == nil then
							ONLRConduitUtils.logMessage("      Adding rendition for iPhoto = " .. tostring(iPhoto) .. " (stackWithOriginal " .. tostring(propertyTable.stackWithOriginal) .. "):")
							ONLRConduitUtils.logMessage("         " .. rendMap[iPhoto].rendPath)
							if propertyTable.stackWithOriginal then
								activeCatalog:addPhoto(rendMap[iPhoto].rendPath, targetPhoto)
							else
								activeCatalog:addPhoto(rendMap[iPhoto].rendPath)
							end
							
							-- Lightroom 3 only ...
							if ONLRConduitUtils.collectionAccessSupported() then
								-- Also add the modified copy to any collections the original is a member of.
								local collections = targetPhoto:getContainedCollections()
								if collections ~= nil and #collections > 0 then
									local collPhotos = { activeCatalog:findPhotoByPath(rendMap[iPhoto].rendPath) }
									local nCollections = #collections
									for iColl = 1, nCollections do
										ONLRConduitUtils.logMessage("      > Also adding it to collection " .. collections[iColl]:getName())
										collections[iColl]:addPhotos(collPhotos)
									end
								end
							end
						else
							ONLRConduitUtils.logMessage("      iPhoto = " .. tostring(iPhoto) .. " - Photo already in catalog, not adding:")
							ONLRConduitUtils.logMessage("         " .. rendMap[iPhoto].rendPath)
						end
					end
				end
			)
			
		end
	
	end
  
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitService.preFlightFiles(propertyTable, nPhotos)
	local allFilesPresent	= true
	
	for currentPhoto = 1, nPhotos do
		
		if LrFileUtils.exists(propertyTable.photosToExport[currentPhoto]) ~= "file" then
			ONLRConduitUtils.logMessage("ONLRConduitService.preFlightFiles When Pre-Flighting the files, this one is missing:  " .. propertyTable.photosToExport[currentPhoto])
			allFilesPresent = false
			break
		end
	
	end

	return allFilesPresent
	
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitService.handleMissingFileErr()

	local msg =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/exportFailed=Unable to complete the export. One or more files could not be found")
 	LrDialogs.message(msg, "critical")
end

--[[***************************************************************************

******************************************************************************]]
function ONLRConduitService.processRenderedPhotos( functionContext, exportContext )
	local exportSession 	= exportContext.exportSession
	local propertyTable		= exportContext.propertyTable
	local nPhotos 			= exportSession:countRenditions()
	local allFilesPresent  	= true
	
	ONLRConduitUtils.logMessage("ONLRConduitService.processRenderedPhotos> In Method")	
	
	--If we get called from export with previous we don't have the presets or the images to export... Tell the user and bail.
	if (propertyTable.photosToExport == nil) then
		local msg =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/exportFailed=Export with previous is not available. Use the export dialog instead.")
 		LrDialogs.message(msg, "critical")
		return
	end
	
	
	--preflight the files here
	 allFilesPresent = ONLRConduitService.preFlightFiles(propertyTable, nPhotos)
	 
	 if allFilesPresent == false then
	 	ONLRConduitService.handleMissingFileErr()
	 	return
	 end
	
	-- operationMode will come back:
		-- 0 for cancel
		-- 1 for create
		-- 2 for merge
		-- 404 for error

	ONLRConduitUtils.AskPerfectLayersForOperationMode(propertyTable)

	ONLRConduitUtils.logMessage("ONLRConduitService.processRenderedPhotos> operationMode is: " .. propertyTable.operationMode)

	if propertyTable.operationMode == 0 then
		ONLRConduitUtils.logMessage("ONLRConduitService> User Canceled")
		return
	elseif propertyTable.operationMode == 404 then
		ONLRConduitUtils.logMessage("ONLRConduitService> Error Asking Perfect Layers for Mode and Prefs, aborting")
		return
	end
	
	--currentMode should be one of:
		-- 1 for create
		-- 2 for merge
	local currentMode = propertyTable.operationMode
	
    if ONLRProductSettings.openAsLayers == true then
        -- ONLRProductSettings.openAsLayers is a legacy flag to support multiple files being stacked together with the largest one at the bottom
        propertyTable.operationMode = 2
    end

	local progressScope 	= exportContext:configureProgress
	{
		title = nPhotos > 1
		and LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/Progress=" .. ONLRProductSettings.productNameForMessages .. " exporting ^1 photos", nPhotos)
		or LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/Progress/One=" .. ONLRProductSettings.productNameForMessages .. " exporting one photo"),
	}
	
	local rendMap = {}
	for i, rendition in exportSession:renditions{ stopIfCanceled = true } do
		local success, pathOrMessage = rendition:waitForRender()
		local userErrorString, fileNotFoundMatch
 		if not success then
 			ONLRConduitUtils.logMessage("ONLRConduitService.processRenderedPhotos> ******* EXPORT FAILED: " .. pathOrMessage)
 			
 			--The Lightroom error messages are cryptic and hard for the user to understand so we are going to try to translate
 			--it to something more user friendly
 			
 			fileNotFoundMatch = string.find(pathOrMessage, "<AgErrorID>dng_error_file_not_found</AgErrorID>")
 			
 			if (fileNotFoundMatch ~= nil) then
 				--This is the file not found error
 				userErrorString = "The file offline or missing"
 				ONLRConduitUtils.logMessage("ONLRConduitService.processRenderedPhotos> switching message: " .. pathOrMessage .. "To user Friendly string: " .. userErrorString)
 			else
 				userErrorString = pathOrMessage
 			end
 			
 			local msg =  LOC("$$$/" .. ONLRProductSettings.dataFolderName .. "/Service/exportFailed=Sorry, Lightroom could not complete your request. The reason code appears below:")
 			LrDialogs.message(msg, userErrorString, "critical")
 			return
 		end
		
		
		rendMap[i] = { rendPath = pathOrMessage, srcPhoto = propertyTable.photosToExport[i] }
	end
	
	if propertyTable.processAsBatch or ONLRProductSettings.loadOnePlugin == true then
	
		ONLRConduitService.processPhotosIndividually(rendMap, nPhotos, propertyTable, progressScope)
	else
        
        if ONLRProductSettings.openAsLayers == true then
            
            -- ONLRProductSettings.openAsLayers is a legacy flag to support multiple files being stacked together with the largest one at the bottom
            ONLRConduitService.processPhotosAsLayers(rendMap, nPhotos, propertyTable, progressScope)
        else

            ONLRConduitService.processPhotosAsLayers2(rendMap, nPhotos, propertyTable, progressScope)
        end
	end
	
end


--[[***************************************************************************

	Script entry point
	
******************************************************************************]]

ONLRConduitUtils.logMessage("============= ONLRConduitService Loaded " .. os.date() .. " =============")

return ONLRConduitService

--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]
--[[***************************************************************************

******************************************************************************]]




