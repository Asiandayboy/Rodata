local Util = {}


function Util.deepCopyTable(t)
	local copy = {}

	for k,v in pairs(t) do
		if type(v) == "table" then
			copy[k] = Util.deepCopyTable(v)
		else
			copy[k] = v
		end
	end
	return copy
end

--[[
	Used to add any missing keys to the target if you make another change to your userTemplate
]]
function Util.reconcileTable(target, template)
	-- add new keys to target found in template
	for k,v in pairs(template) do
		-- only reconcile string keys
		if type(k) ~= "string" then continue end

		if target[k] == nil then					-- missing key
			if type(v) == "table" then
				target[k] = Util.deepCopyTable(v)
			else
				target[k] = v
			end
		elseif (type(target[k]) == "table" and type(v) == "table") then
			Util.reconcileTable(target[k], v)
		end
	end	

	return target
end


function Util.tableToString(tbl, indent)
	indent = indent or 0
	local indentStr = string.rep("  ", indent)  -- Two spaces per indentation level
	local result = ""

	for k, v in pairs(tbl) do
		if type(v) == "table" then
			result = result .. indentStr .. k .. ": {\n"
			result = result .. Util.tableToString(v, indent + 1)
			result = result .. indentStr .. "}\n"
		else
			result = result .. indentStr .. k .. ": " .. tostring(v) .. "\n"
		end
	end

	return result
end


function Util.millisecondToDateTime(ms: number): string
	local epoch = os.time{year=1970, month=1, day=1, hour=0}
	
	local seconds = ms // 1000
	local msRemainder = ms % 1000
	
	local days = seconds // (24 * 3600)
	seconds = seconds % (24 * 3600)
	local hours = seconds // 3600
	seconds = seconds % 3600
	local minutes = seconds // 60
	seconds = seconds % 60

	-- Epoch starts on January 1, 1970
	local epochStart = os.time{year=1970, month=1, day=1, hour=0}
	local dateTime = os.date("*t", epochStart + days * 24 * 3600 + hours * 3600 + minutes * 60 + seconds)

	-- Format the date-time
	local formattedDateTime = string.format("%02d/%02d/%d %02d:%02d:%02d", 
		dateTime.month, dateTime.day, dateTime.year, dateTime.hour, dateTime.min, dateTime.sec)

	return formattedDateTime
end





return Util
