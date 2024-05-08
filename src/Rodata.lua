--!strict
--[=[
	Made by robloxdestroyer1035 (Roblox) a.k.a Asiandayboy (GitHub)

	Features:
	- Session locking: only one server at a time can access a player's data, preventing item duplication and data overwrites
	- Simple: Very easy to use and setup for everyone
	- Threadsafe: All normal datastore operations are queued for processing so that each operation runs one at time time, avoiding race conditions
	- Direct indexing: Access the player's cached data directly with the dot . syntax 
	- Typechecking: Typechecking = good :]
	- Easy data migration: Create a Rodata database with your current datastore's name to start using Rodata
	- OrderedDataStores: You can create leaderboards with this
	- Change data globally: Set a user's data from any server anytime. They don't even have to be in game.
	- User metadata cache: An additional table used to store in-memory variables related to the player's data
	
	TODO: Handle possible dead sessions

]=]

local Rodata = { 
	--[[
		This variable is really only used to bypass certain checks so that errors don't pop up when I was testing this module.
		It literally only ignores one error check, which is the databaseName check in CreateUserDatabase()
	]]
	SAFE_MODE = true
}

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Util = require(script.Util)
local ThreadQueue = require(script.ThreadQueue)


type Schema = {[string]: number | string}

type SessionLock = { jobId: string?, placeId: string? } | nil

type UserCache = {
	dataLoaded: boolean,
	queue: ThreadQueue.ThreadQueue,
	data: Schema | nil,
	metadata: Schema
}

export type DataVersion = {
	CreatedTime_string: string,
	CreatedTime_ms: number,
	IsDeleted: boolean,
	VersionId: string,
	Data: Schema
}

export type UserDatabase = {
	DataStore: DataStore,
	MemStoreSortedMap: MemoryStoreSortedMap,
	_schema: Schema,
	_userCache: {[string]: UserCache},
	WaitForSessionOnLoad: boolean,
	DebugMode: boolean,
	ThreadQueueDebugMode: boolean,
	JobId: string,
	PlaceId: string
}

export type OrderedDatabase = {
	OrderedDataStore: OrderedDataStore,
	DebugMode: boolean,
}

export type UnboundedDatabase = {
	DataStore: DataStore,
	DebugMode: boolean,
}


local CURRENT_RUNNING_JOB_ID = game.JobId
local CURRENT_RUNNING_PLACE_ID = game.PlaceId

local SESSION_LOCKED_ERR_MSG = "Data is session-locked by another server."
local WAIT_FOR_SESSION_ERR_MSG = "WaitForSession"

local SETTINGS = {
	WaitForSession_MAX_RETRIES = 10,
	TIME_BETWEEN_RETRIES_SECONDS = 4,
	MSS_SESSION_LOCK_MAX_RETRIES = 10,
}


local GLOBAL_DATABASE_REFERENCES: { [string]: UserDatabase | OrderedDatabase | UnboundedDatabase } = {}





local function useDefaultData(schema: Schema, userId: string): Schema
	return schema, { userId }, { currDataGloballySet = false }
end

local function isNotSessionLocked(sessionLock: SessionLock, JOB_ID: string, PLACE_ID: string): boolean
	return sessionLock == nil or ( sessionLock.jobId == JOB_ID and sessionLock.placeId == PLACE_ID )
end

local function getSessionLockedMSS(map: MemoryStoreSortedMap, userId: string): (boolean, SessionLock)
	for i = 1, SETTINGS.MSS_SESSION_LOCK_MAX_RETRIES do
		local success, res: SessionLock = pcall(map.GetAsync, map, userId)
		
		if success then
			return true, res
		end
	end
	
	warn("Failed to get session lock after max retries.")
	return false, nil
end

local function setSessionLockMSS(
	map: MemoryStoreSortedMap, 
	userId: string, sessionLock: SessionLock, expiration_s: number
): (boolean, SessionLock)
	for i = 1, SETTINGS.MSS_SESSION_LOCK_MAX_RETRIES do
		local success
		if sessionLock == nil then
			success = pcall(map.RemoveAsync, map, userId)
		else
			success = pcall(map.SetAsync, map, userId, sessionLock, expiration_s)
		end
		if success then
			return true, sessionLock
		end
	end
	
	warn("Failed to set session lock after max retries.")
	return false, nil
end

local function isCurrDataGloballySet(metadata: { [string]: any }): boolean
	return metadata.currDataGloballySet
end

local function retryCall<T>(
	maxAttempts: number, 
	timeBetween: number, 
	callbackName: string,
	debugMode: boolean,
	lambda: () -> T
): T?
	for i = 1, maxAttempts do
		if debugMode then print(`{callbackName} attempt {i}...`) end
		local success, res = pcall(lambda)
		if success then
			return res
		end
		task.wait(timeBetween)
	end

	warn(debug.traceback(`Failed to execute the provided callback successfully after {maxAttempts} attempts.`, 2))
	return nil
end

local function loadUserData(
	datastore: DataStore, 
	map: MemoryStoreSortedMap,
	schema: Schema, 
	userId: string, 
	waitForSessionOnLoad: boolean,
	JOB_ID: string,
	PLACE_ID: string
): Schema | string
	local function fetchData(currData: Schema?, keyInfo: DataStoreKeyInfo): Schema?
		if currData == nil then return useDefaultData(schema, userId) end
		
		return Util.reconcileTable(currData, schema), { userId }, { currDataGloballySet = false }
	end
	
	local _, sessionLock = getSessionLockedMSS(map, userId)
	if not isNotSessionLocked(sessionLock, JOB_ID, PLACE_ID) then
		if waitForSessionOnLoad == true then error(WAIT_FOR_SESSION_ERR_MSG, 0) end

		error(SESSION_LOCKED_ERR_MSG, 0)
	end
	
	local res: Schema = datastore:UpdateAsync(userId, fetchData)
	
	local _, s = setSessionLockMSS(map, userId, { jobId = JOB_ID, placeId = PLACE_ID }, 86400) -- set expiration to 24hrs
	

	return res
end

local function saveUserData(
	datastore: DataStore,
	map: MemoryStoreSortedMap,
	schema: Schema, 
	data: Schema,
	userId: string,
	JOB_ID: string,
	PLACE_ID: string
): Schema | string
	local function saveData(currData: Schema?, keyInfo: DataStoreKeyInfo): Schema?
		if currData == nil then return useDefaultData(schema, userId) end
		
		local metadata = keyInfo:GetMetadata()
		local isGloballySet = isCurrDataGloballySet(metadata)
		
		local dataToSave = isGloballySet and currData or data

		return dataToSave, { userId }, { currDataGloballySet = false }
	end
	
	local _, sessionLock = getSessionLockedMSS(map, userId)
	if not isNotSessionLocked(sessionLock, JOB_ID, PLACE_ID) then
		error(SESSION_LOCKED_ERR_MSG, 0)
	end
	
	local res: Schema = datastore:UpdateAsync(userId, saveData)
	
	local _, s = setSessionLockMSS(map, userId, { jobId = JOB_ID, placeId = PLACE_ID }, 86400) -- set expiration to 24hrs
	

	return res
end

local function releaseSessionLock(
	datastore: DataStore, 
	map: MemoryStoreSortedMap,
	schema: Schema, 
	data: Schema, 
	userId: string,
	JOB_ID: string,
	PLACE_ID: string
): Schema | string
	local function release(currData: Schema?, keyInfo: DataStoreKeyInfo): Schema?
		if currData == nil then return useDefaultData(schema, userId) end

		local metadata = keyInfo:GetMetadata()
		local isGloballySet = isCurrDataGloballySet(metadata)

		local dataToSave = isGloballySet and currData or data

		return dataToSave, { userId }, { currDataGloballySet = false }
	end
	
	local _, sessionLock = getSessionLockedMSS(map, userId)
	if not isNotSessionLocked(sessionLock, JOB_ID, PLACE_ID) then
		error(SESSION_LOCKED_ERR_MSG, 0)
	end

	local res: Schema = datastore:UpdateAsync(userId, release)
	
	local _, s = setSessionLockMSS(map, userId, nil, 1) -- release session lock


	return res
end



---------------[[ API INTERFACE ]]----------------

--[[ USER:
	Creates and returns a new user database with a normal datastore with the provided schema, which is your data template.
	
	This function takes in two optional arguments: debugMode and threadQueueDebugMode, which are,
	as you guessed, used for debugging purposes. 
	
	This function is used to create a datastore that is USED ONLY TO SAVE PLAYER DATA (hence the name), to save
	things that relate to the player: level, money, inventory, whether they're an admin or not, or used a code, etc.
	
	If debugMode is true, you'll see print messages indicating when datastore operations have succeeded. 
	If threadQueueDebugMode is true, then you'll see print messages showing the queue structure of each 
	datastore call, waiting for its turn to execute. The debug modes are really just for visualization purposes, tbh.
	
	If WaitForSessionOnLoad is true, the server that tries to access the player's data without acquring 
	the session lock will wait for the other server to release their session lock before acquiring
	the session lock, instead of kicking the player and telling them to wait before rejoining. If even after
	all that, the server fails to load the data and acquire the lock, the player will just be kicked and told
	to rejoin.
	
	--------------------------------------[ !!IMPORTANT!! ]--------------------------------------
	----------------[ MAKE SURE TO USE UNIQUE NAMES FOR THE FIRST TWO ARGUMENTS ]----------------
]]
function Rodata.CreateNewUserDatabase(
	databaseName: string, 
	memoryStoreName: string,
	schema: {[string]: any}, 
	waitForSessionOnLoad: boolean?,
	debugMode: boolean?, 
	threadQueueDebugMode: boolean?,
	jobId: string?,
	placeId: string?
): UserDatabase
	if databaseName == nil then error("databaseName required.") end
	if memoryStoreName == nil then error("memoryStoreName required.") end
	
	if GLOBAL_DATABASE_REFERENCES[databaseName] and Rodata.SAFE_MODE then
		error(`A database with the name "{databaseName}" already exists in the cache. Use a different name.`)
	end
	
	local self: UserDatabase = {
		DataStore = DataStoreService:GetDataStore(databaseName),
		MemStoreSortedMap = MemoryStoreService:GetSortedMap(memoryStoreName),
		_schema = schema,
		_userCache = {},
		WaitForSessionOnLoad = waitForSessionOnLoad or false,
		DebugMode = debugMode or false,
		ThreadQueueDebugMode = threadQueueDebugMode or false,
		JobId = jobId or CURRENT_RUNNING_JOB_ID,
		PlaceId = placeId or CURRENT_RUNNING_PLACE_ID
	}
	
	GLOBAL_DATABASE_REFERENCES[databaseName] = self
	
	return self
end


--[[ ORDERED:
	Creates and returns a new database with an ordered datastore.
	
	This function can be used to create a database for leaderboards.
	
	----------------------------------[ !!IMPORTANT!! ]---------------------------------
	----------------[ MAKE SURE TO USE A UNIQUE NAME FOR YOUR DATABASE ]----------------
]]
function Rodata.CreateNewOrderedDatabase(databaseName: string, debugMode: boolean?): OrderedDatabase
	if databaseName == nil then error("databaseName required.") end
	
	if GLOBAL_DATABASE_REFERENCES[databaseName] then
		error(`A database with the name "{databaseName}" already exists in the cache. Use a different name.`)
	end
	
	local self: OrderedDatabase = {
		OrderedDataStore = DataStoreService:GetOrderedDataStore(databaseName),
		DebugMode = debugMode or false
	}
	
	GLOBAL_DATABASE_REFERENCES[databaseName] = self
	
	return self
end


--[[ UNBOUNDED:
	Creates and returns a new player-unbounded database with the provided schema
	and adds the database to the server cache for reference.
	
	Because this database is not bounded to player, it does not use any 
	security measures to prevent data risks, such as session-locking or a queue. 
	If you do know of any major security risks, hit me up.
	
	So, DO NOT use this database to store player data. Use a UserDatabase instead. :]
	
	Use this database to store things like codes for your game, anything that is not
	particularly bounded to players.
	
	For example, you can store a code in an unbounded database, and store whether or
	not the player used that code in the user database.
	
	----------------------------------[ !!IMPORTANT!! ]---------------------------------
	----------------[ MAKE SURE TO USE A UNIQUE NAME FOR YOUR DATABASE ]----------------
]]
function Rodata.CreateNewUnboundedDatabase(databaseName: string, debugMode: boolean?): UnboundedDatabase
	if databaseName == nil then error("databaseName required.") end
	
	if GLOBAL_DATABASE_REFERENCES[databaseName] then
		error(`A database with the name "{databaseName}" already exists in the cache. Use a different name.`)
	end
	
	local self: UnboundedDatabase = {
		DataStore = DataStoreService:GetDataStore(databaseName),
		DebugMode = debugMode or false
	}
	
	GLOBAL_DATABASE_REFERENCES[databaseName] = self
	
	return self
end


--[[ USER, ORDERED, UNBOUNDED:
	Returns the named database stored in the server cache. If it cannot
	be found then this function will wait for 5 seconds to see if it shows
	up in the cache. If it does, it will be retuend. If it doesn't, an error 
	will be thrown if it cannot be found after the timeout specified
	
	Default timeout is 5 seconds if a timeout argument is not given.
	
	While waiting for the db to appear in the cache, this function will
	yield the current thread because of the while loop.
	
	Use this function to retrieve the stored database after it has been created.
]]
function Rodata.GetDatabase(databaseName: string, timeout_s: number?): UserDatabase | OrderedDatabase | UnboundedDatabase
	local t: number = timeout_s or 5
	
	local db = GLOBAL_DATABASE_REFERENCES[databaseName]
	if db == nil then 
		local l = os.clock()
		while not GLOBAL_DATABASE_REFERENCES[databaseName] do
			if os.clock() - l >= t then break end
			
			if GLOBAL_DATABASE_REFERENCES[databaseName] ~= nil then
				return GLOBAL_DATABASE_REFERENCES[databaseName]
			end
		end
		
		error(`[Rodata]: Timed out -> Failed to find database with the name "{databaseName}."`, 0)
	else
		return db
	end
end


--[[ USER:
	Loads the user's data and acquires the session lock. This function yields the
	current thread when it enters the queue to until it gets dequeued to execute.
	
	Returns nil if an error occured while loading the data, else return the data.
	
	This function should only be called once for each player, when they join the game.
	To retrieve a player's data after they have joined, use Rodata.GetCachedUserData() 
]]
function Rodata.LoadUserData(database: UserDatabase, userId: string): Schema?
	return retryCall(5, 1, "load", database.DebugMode, function(): Schema?
		if type(database) ~= "table" then error("database must be a UserDatabase.") end
		
		--[[ Special Case:
			If a player rejoins the same server quickly and calls LoadUserData() while 
			the new data is still saving from the old session, add the request to the queue
		]]
		local q
		if (database._userCache[userId] and database._userCache[userId].queue) then
			q = database._userCache[userId].queue
		else
			q = ThreadQueue.new(database.ThreadQueueDebugMode)
		end
		
		--[[
			Adding this pre-load function to the queue will allow any ongoing save_release operation to finish, 
			which will avoid the pre-load error below, because without it, if the user joins the same server 
			quickly and LoadUserData() is called while a save is still executing, it will result in the error 
			below since dataLoaded doesn't get set to false until after the save_release finishes
		]]
		local preSuccess, preRes = ThreadQueue.Enqueue(
			q,
			`pre_load_{coroutine.running()}`,
			function()
				if database._userCache[userId] and database._userCache[userId].dataLoaded then 
					error(`User_{userId}'s data has already been loaded with LoadUserData(). Use GetCachedUserData() instead to access the loaded data.`, 0)
				end

				if database._userCache[userId] == nil then -- when the player first loads in the game
					database._userCache[userId] = {
						dataLoaded = false,
						queue = q,
						data = nil,
						metadata = {}
					}
				end
				return true
			end
		)
		
		if not preSuccess then
			warn(debug.traceback(preRes, 2))
			return nil
		end
		
		
		local success, res = ThreadQueue.Enqueue(
			database._userCache[userId].queue, 
			`load_{coroutine.running()}`, 
			loadUserData, database.DataStore, database.MemStoreSortedMap, database._schema, userId, database.WaitForSessionOnLoad,
			database.JobId, database.PlaceId
		)
		
		if success then
			-- add player to the server cache
			database._userCache[userId].data = res
			database._userCache[userId].dataLoaded = true

			if database.DebugMode then print("Data loaded successfully:", res) end

			return res
		end

		if res == WAIT_FOR_SESSION_ERR_MSG then
			if database.DebugMode then print("retrying to load data...") end
			-- keep retrying to load the data
			for i = 1, SETTINGS.WaitForSession_MAX_RETRIES do
				if (database.DebugMode and not database.ThreadQueueDebugMode) then print("retry_load_"..i) end
				task.wait(SETTINGS.TIME_BETWEEN_RETRIES_SECONDS)
				
				local s, retryRes = ThreadQueue.Enqueue(
					database._userCache[userId].queue, 
					`retry_{i}_load_{coroutine.running()}`, 
					loadUserData, database.DataStore, database.MemStoreSortedMap, database._schema, userId, database.WaitForSessionOnLoad,
					database.JobId, database.PlaceId
				)

				if s then
					-- add player to the server cache
					database._userCache[userId].data = retryRes
					database._userCache[userId].dataLoaded = true

					if database.DebugMode then print("Data loaded successfully:", retryRes) end

					return retryRes
				end
			end
		end
		
		-- run code below if data fails to load because of session lock or if
		-- data fails to load even after exhausting the retries

		local player = Players:GetPlayerByUserId(userId)
		player:Kick("Session locked by another server. Your data is safe. Please wait a moment before joining again.")
		ThreadQueue.Destroy(database._userCache[userId].queue) 
		database._userCache[userId] = nil
		return nil
	end)
end


--[[ USER:
	Retrieves the player's data held in server memory. This function does
	not yield.
	
	Throws an error if the player's data has not been loaded or is not in the cache.
	
	Use this function to retrieve a player's data after their data has been loaded
	with Rodata.LoadUserData()
]]
function Rodata.GetCachedUserData(database: UserDatabase, userId: string): Schema?
	if type(database) ~= "table" then error("database must be a UserDatabase.") end
	
	local cache = database._userCache[userId]
	if cache == nil then error(`User_{userId}'s cache is nil; User_{userId} has no data to access.`) end
	if not cache.dataLoaded then error(`Cannot retrieve User_{userId}'s data because their data is not loaded.`) end

	return database._userCache[userId].data
end


--[[ USER:
	Returns the user's metadata cache, which is an additioanl table to store in-memory
	variables related to a player's data, which means it does not get saved
	
	Throws an error if the player's data has not been loaded or is not in the cache
	
	One use case is to cache results from async calls, like MarketplaceService:UserOwnsGamePassAsync(),
	that you only need to call once
]]
function Rodata.GetUserMetadata(database: UserDatabase, userId: string): Schema
	if type(database) ~= "table" then error("database must be a UserDatabase.") end

	local cache = database._userCache[userId]
	if cache == nil then error(`User_{userId}'s cache is nil; User_{userId} has no data to access.`) end
	if not cache.dataLoaded then error(`Cannot retrieve User_{userId}'s metadata because their data is not loaded.`) end

	return database._userCache[userId].metadata
end


--[[ USER:
	Saves the player's cached data in UserCache.data while maintaining the session lock. This function 
	yields the current thread until it gets dequeued to execute.

	Returns true if the operation succeeded; returns false if an error occurred.
	
	Use this function to force save a player's current data manually (in an auto save loop, 
	or after some important change).
	
	DO NOT use this function to save a player's data when they leave.
]]
function Rodata.SaveUserData(database: UserDatabase, userId: string): boolean
	return retryCall(5, 1, "save", database.DebugMode, function(): boolean
		if type(database) ~= "table" then error("database must be a UserDatabase.") end
		if database._userCache[userId] == nil then warn(`User_{userId} has no data to access to save.`) return false end
		if not database._userCache[userId].dataLoaded then warn(`User_{userId} has not been loaded yet to save.`) return false end

		local success, res = ThreadQueue.Enqueue(
			database._userCache[userId].queue, 
			`save_{coroutine.running()}`, 
			saveUserData, database.DataStore, database.MemStoreSortedMap, database._schema, database._userCache[userId].data, userId,
			database.JobId, database.PlaceId
		)

		if not success then
			warn(res)
			return false
		end

		if database.DebugMode then print("Data saved successfully:", res) end

		return true
	end) or false
end


--[[ USER:
	Saves the player's data in UserCache.data and releases the session lock. This function yields the
	current thread until it gets dequeued to execute.
	
	Returns true if the operation succeeded; returns false if an error occurred. 
	
	This function should be called when the player leaves the server or during shutdown
]]
function Rodata.SaveAndReleaseUserData(database: UserDatabase, userId: string): boolean
	return retryCall(5, 1, "save_and_release", database.DebugMode, function(): boolean
		if type(database) ~= "table" then error("database must be a UserDatabase.") end
		if database._userCache[userId] == nil then warn(`User_{userId} has no data to access to save and release.`) return false end
		if not database._userCache[userId].dataLoaded then warn(`User_{userId} has not been loaded to save and release.`) return false end

		local success, res = ThreadQueue.Enqueue(
			database._userCache[userId].queue, 
			`save_release_{coroutine.running()}`, 
			releaseSessionLock, database.DataStore, database.MemStoreSortedMap, database._schema, database._userCache[userId].data, userId,
			database.JobId, database.PlaceId
		)

		if not success then
			warn(res)
			return false
		end

		--[[ Special Case:
			If a player rejoins the same server quickly and loads data while 
			the new data is still saving from the old session, the load request will
			be added to the queue. To prepare for when the request gets dequeued,
			we must reset the cache data for the new loaded data
		]]
		if not ThreadQueue.IsEmpty(database._userCache[userId].queue) then
			database._userCache[userId].dataLoaded = false
			database._userCache[userId].data = nil
		else
			ThreadQueue.Destroy(database._userCache[userId].queue) 
			database._userCache[userId] = nil
		end


		if database.DebugMode then print("Data saved and session lock released successfully:", res) end

		return true
	end) or false
end


--[[ ORDERED:
	Sets the value to the key by calling OrderedDataStore:SetAsync().
	
	Returns true if successful or false if an error occured.
]]
function Rodata.SetOrderedData(database: OrderedDatabase, key: string, value: number): boolean
	return retryCall(5, 1, "ordered_set", database.DebugMode, function(): boolean
		if type(database) ~= "table" then error("database must be an OrderedDatabase.") end
		if type(value) ~= "number" then error("Value must be a number.") end

		local orderedDataStore = database.OrderedDataStore
		local success, res = pcall(orderedDataStore.SetAsync, orderedDataStore, key, value)

		if not success then
			warn(res)
			return false
		end

		return true
	end) or false
end


--[[ ORDERED:
	This function iterates over the ordered data, going page by page, executing the provided
	callback function for each entry in the page in order. 
	
	The last four arguments of this function are the same as and used in OrderedDataStore:GetSortedAsync().
	
	Returns nothing; prints a warning message if an error occured while calling GetSortedAsync(), and
	exits out of the function early, skipping the callback iteration code.
]]
function Rodata.IterateOrderedData(
	database: OrderedDatabase, callback: (rank: number, value: {key: string, value: number}) -> (),
	ascendingOrder: boolean, entriesPerPage: number?, minVal: number?, maxVal: number?
)
	if type(database) ~= "table" then error("database must be an OrderedDatabase.") end
	
	local res = retryCall(5, 1, "ordered_iterate", database.DebugMode, function(): Pages?
		local success, r = pcall(database.OrderedDataStore.GetSortedAsync, database.OrderedDataStore,
			ascendingOrder, entriesPerPage or 50, minVal, maxVal 
		)

		if not success then
			warn(r)
			return nil
		end
		
		return r::Pages
	end) or nil
	
	if res == nil then 
		if database.DebugMode then warn("Max attempts exhausted for IterateOrderedData(); Callback cancelled.") end
		return
	end
	
	local pages = res::Pages
	local pageNumber = 1
	while true do
		for k, v in pairs(pages:GetCurrentPage()) do
			callback(pageNumber >= 2 and k+entriesPerPage::number*(pageNumber-1) or k, v)
		end
		
		if pages.IsFinished then break end
		pages:AdvanceToNextPageAsync()
		pageNumber += 1
		task.wait()
	end
end


--[[ ORDERED:
	This function removes a specified key from the ordered databse.
	
	Returns true if successful or false if an error occured.
]]
function Rodata.RemoveOrderedData(database: OrderedDatabase, key: string): boolean
	return retryCall(5, 1, "ordered_remove", database.DebugMode, function(): boolean
		if type(database) ~= "table" then error("database must be an OrderedDatabase.") end

		local orderedDataStore = database.OrderedDataStore
		local success, res = pcall(orderedDataStore.RemoveAsync, orderedDataStore, key)

		if not success then
			warn(res)
			return false
		end

		return true
	end) or false
end




--[[ USER:
	This function manually overwrites the player's current data with new data and saves it. 
	This function can be called globally, meaning from any server. Instead of taking in 
	the database, which is different for each server, it takes in the databse name. 
	
	Be sure that <newData> is in the same structure as the schema.
	
	Returns true if successful or false if an error occured.
	
	This function can be used in the command line by providing the name of the database as databaseRef.
	
	If called in the same server as the player, this function will get queued, update the server's cache,
	set dataLoaded to true, and accept an optional callback as the last argument with the new data passed in
	to allow the developer to finalize the change in data, such as update GUI information to reflect 
	the new data.

	Use this function if you want to just set data forcefully without caring about the player's current data.
	
	-------!![ Not wrapped in a retry call ]!!-------
]]
function Rodata.GlobalSetUserData(
	databaseRef: string | UserDatabase, 
	userId: string, 
	newData: Schema,
	callback: (newData: Schema) -> ()?
): boolean
	if type(databaseRef) ~= "string" and type(databaseRef) ~= "table" then 
		error("databaseRef must be the name of the UserDatabase or a UserDatabase.") 
	end
	
	local function globalSet(currData: Schema?, keyInfo: DataStoreKeyInfo)
		--[[
			If this function is called when the player is not in the same server or in game, the newData 
			will be tagged with a <currDataGloballySet = true> metadata, so that the next time a Rodata 
			load or save occurs, the data set by this function will take precendence, saving or loading 
			this data instead and setting currDataGloballySet back to false.
		]]
		return newData, { userId }, { currDataGloballySet = true }
	end
	
	local datastore
	local success, res
	if type(databaseRef) == "string" then
		datastore = DataStoreService:GetDataStore(databaseRef)
		success, res = pcall(function()
			return datastore:UpdateAsync(userId, globalSet)
		end)
	else 
		datastore = databaseRef.DataStore
		success, res = ThreadQueue.Enqueue(
			databaseRef._userCache[userId].queue,
			`globa_set_{coroutine.running()}`,
			function()
				return datastore:UpdateAsync(userId, globalSet)
			end
		)
	end
	
	if not success then
		warn(res)
		return false
	end
	
	local player = Players:GetPlayerByUserId(userId)
	if Players[player.Name] and type(databaseRef) == "table" then -- player in the same server
		if not RunService:IsRunMode() then return true end
		
		if databaseRef.DebugMode then print("Data globally set successfully:", res) end
		
		if databaseRef._userCache[userId] == nil or databaseRef._userCache[userId].dataLoaded == false then
			warn(`User_{userId}'s server cache does not exist or their data has not been loaded because LoadUserData() was not called yet.`)
			return true
		end
		
		databaseRef._userCache[userId].data = res
		
		if callback then callback(res) end
	end
	
	return true
end


--[[ USER:
    This function returns an array of all the previously saved versions of the player's data.
    
    The <limit> argument is the number of verions to return. This function yields the
    current thread; the higher the limit, the longer it will take this function to finish running.
    
    If no argument is provided for <ascendingOrder>, it will default to false, meaning that
    the versions will be sorted from newest to oldest
    
    One use case for this function is that you can use this function to revert a player's data by 
    seeing all the past versions of their data and use GlobalSetUserData() to pass in the
    old data version and set the player's current data to it.
    
    -------!![ Not wrapped in a retry call ]!!-------
]]
function Rodata.ListVersionsAsync(
	databaseName: string, 
	userId: string, 
	debugMode: boolean,
	limit: number?,
	ascendingOrder: boolean?,
	minDate: number?,
	maxDate: number?
): { DataVersion }
	if not limit then 
		limit = 100 
	end

	local datastore: DataStore = DataStoreService:GetDataStore(databaseName)
	
	if debugMode then warn("Retrieving user's data versions. This may take a while...") end

	local pages = datastore:ListVersionsAsync(
		userId, 
		ascendingOrder and Enum.SortDirection.Ascending or Enum.SortDirection.Descending,
		minDate, maxDate, limit
	)::DataStoreVersionPages

	local versions = {}

	for k, v:DataStoreObjectVersionInfo in pairs(pages:GetCurrentPage()) do
		local data = datastore:GetVersionAsync(userId, v.Version)::Schema
		local entry: DataVersion = {
			CreatedTime_string = Util.millisecondToDateTime(v.CreatedTime),
			CreatedTime_ms = v.CreatedTime,
			IsDeleted = v.IsDeleted,
			VersionId = v.Version,
			Data = data
		}

		versions[k] = entry
	end
	
	return versions
end


--[[ UNBOUNDED:
	Returns the data from the unbounded database for a specified key
	using GetAsync() or returns nil if no data can be found for the key.
	
	This function can be called globally, similar to GlobalSetUserData().
	
	-------!![ Not wrapped in a retry call ]!!-------
]]
function Rodata.GetUnboundedData(databaseRef: string | UnboundedDatabase, key: string): any
	if type(databaseRef) ~= "string" and type(databaseRef) ~= "table" then 
		error("databaseRef must be the name of the UnboundedDatabase or an UnboundedDatabase.")
	end

	local datastore 
	if type(databaseRef) == "string" then
		datastore = DataStoreService:GetDataStore(databaseRef)
	elseif type(databaseRef) == "table" then
		datastore = databaseRef.DataStore
	end
	
	local success, res = pcall(datastore.GetAsync, datastore, key)
	
	if not success then
		warn(res)
		return nil
	end
	
	return res
end


--[[ UNBOUNDED:
	Sets and saves data to an unbounded database using SetAsync(). 
	
	Returns true if successful or false if an error occurred.
	
	This function can be called globally, similar to GlobalSetUserData().
	
	-------!![ Not wrapped in a retry call ]!!-------
]]
function Rodata.SetUnboundedData(databaseRef: string | UnboundedDatabase, key: string, data: any): boolean
	if type(databaseRef) ~= "string" and type(databaseRef) ~= "table" then 
		error("databaseRef must be the name of the UnboundedDatabase or an UnboundedDatabase.")
	end
	
	local datastore 
	if type(databaseRef) == "string" then
		datastore = DataStoreService:GetDataStore(databaseRef)
	elseif type(databaseRef) == "table" then
		datastore = databaseRef.DataStore
	end

	local success, res = pcall(datastore.SetAsync, datastore, key, data)

	if not success then
		warn(res)
		return false
	end

	return true
end


--[[ UNBOUNDED:
	Removes the specified key value from an unbounded database using RemoveAsync(). 
	
	Returns true if successful or false if an error occurred.
	
	This function can be called globally, similar to GlobalSetUserData().
	
	-------!![ Not wrapped in a retry call ]!!-------
]]
function Rodata.RemoveUnboundedData(databaseRef: string | UnboundedDatabase, key: string): boolean
	if type(databaseRef) ~= "string" and type(databaseRef) ~= "table" then 
		error("databaseRef must be the name of the UnboundedDatabase or an UnboundedDatabase.")
	end

	local datastore 
	if type(databaseRef) == "string" then
		datastore = DataStoreService:GetDataStore(databaseRef)
	elseif type(databaseRef) == "table" then
		datastore = databaseRef.DataStore
	end

	local success, res = pcall(datastore.RemoveAsync, datastore, key)

	if not success then
		warn(res)
		return false
	end

	return true
end


--[[ USER:
	This function removes the user's data using RemoveAsync(). 
	
	Returns true if successful or false if an error occured.
	
	If this function is called while the player is in the same server,
	pass in the UserDatabase reference, otherwise pass in the databse name.
	
	If this function is called while the player is in the server, the datastore
	operation will also be added to the player's queue, and will also remove the 
	current data from the server cache, resetting it back to the default schema 
	that was provided in CreateNewUserDatabase. Which means back to 0, or whatever
	the default value you set for starting players were. It will also get rid
	of the user's cache in the server, which means any subsequent saves afterwards 
	will throw the expected warning "User_x has no data to access...". 
	
	In other words, DO NOT be trying to save data or do anything data-manipulated after it has been removed...
	
	If this function is called when the player is in a different server or not in game, pass in
	the name of the database and the name of the memory store you used to create the database
	for the first two arguments.
	
	If this function is called when the player is in a different server, there could be
	some risks involved, such as cached data overwrites by the player's server after a 
	RemoveUserData() was called. This is because the calling server has no way to track if
	a save will occur afterwards in another server. 
	
	If this function is called when the player is not ingame, then that's simpler. If they join
	the next time, the default schema you provided will be loaded in; new fresh data.
	
	-------!![ Not wrapped in a retry call ]!!-------
]]
function Rodata.RemoveUserData(
	databaseRef: string | UserDatabase, 
	memoryStoreRef: string?,
	userId: string
): boolean
	if type(databaseRef) ~= "string" and type(databaseRef) ~= "table" then
		error("databaseRef must be the name of the UserDatabase or a UserDatabase.", 0)
	end
	
	local success, res
	local success2, res2
	if type(databaseRef) == "string" then
		if memoryStoreRef == nil then
			error("You must provide the name of the database's memory store if you're using the database's name as the reference.")
		end
		
		local datastore = DataStoreService:GetDataStore(databaseRef)
		local map = MemoryStoreService:GetSortedMap(memoryStoreRef)
		success, res = pcall(datastore.RemoveAsync, datastore, userId)
		success2, res2 = pcall(map.RemoveAsync, map, userId)
	else
		local datastore = databaseRef.DataStore
		local map = databaseRef.MemStoreSortedMap
		success, res = ThreadQueue.Enqueue(
			databaseRef._userCache[userId].queue,
			`remove_{coroutine.running()}`,
			datastore.RemoveAsync, datastore, userId
		)
		success2, res2 = pcall(map.RemoveAsync, map, userId)
	end
	
	if not success then
		warn(res)
		return false
	end
	
	if not success2 then
		warn(res2)
		return false
	end
	
	
	
	if type(databaseRef) == "table" then
		ThreadQueue.Destroy(databaseRef._userCache[userId].queue)
		databaseRef._userCache[userId].dataLoaded = false
		databaseRef._userCache[userId].data = nil
		databaseRef._userCache[userId] = nil
		
		if databaseRef.DebugMode then print(`User_{userId}'s data removed successfully.`) end
	end
	
	return true
end


--[[ USER:
	This function completely erases all data bounded the player in a user
	database, removing every version of their data as well. This function
	will yield the current thread while executing each datastore operation.
	It may take a while.
	
	Returns nothing
	
	Use this function if you wish to wipe a user's data completely--100%
	
	This function is kind of buggy, though...use at your own risk.
	
	-------!![ Not wrapped in a retry call ]!!-------
	
	*Don't mind the name of the function, heh*
]]
function Rodata.ObliterateUserData(databaseName: string, userId: string)
	local datastore: DataStore = DataStoreService:GetDataStore(databaseName)
	local pages = datastore:ListVersionsAsync(userId, Enum.SortDirection.Descending)::DataStoreVersionPages

	local removedCount = 0
	local last = os.clock()
	warn(`Obliterating user_{userId}'s data...This will take a while.`)
	while true do
		for k, v:DataStoreObjectVersionInfo in pairs(pages:GetCurrentPage()) do
			for i = 1, 10 do
				local success, _ = pcall(function()
					datastore:RemoveVersionAsync(userId, v.Version)
				end)
				
				if success then break end
			end
			removedCount += 1
		end
		if pages.IsFinished then break end
		pages:AdvanceToNextPageAsync()
		task.wait()
	end
	local timeTaken = os.clock() - last
	
	warn(`Number of versions removed: {removedCount}, time taken: {timeTaken}s.`)
end


return Rodata
