# Rodata

Rodata is a module script to help you save data in your Roblox games.

With Rodata, you can create a `database` to save your data. There are three different types of databases depending on the data you're storing:
- `UserDatabase` - A database for storing only player data
- ``OrderedDatabase`` - A database for storing sorted numbers, such as leaderboards
- ``UnboundedDatabase`` - A database for storing data that is not bound to a player; things like game codes.


### Features
- **Session locking**: only one server at a time can access a player's data, preventing item duplication and data overwrites
- **OrderedDataStores**: OrderedDatabases allow you to create leaderboards 
- **UnboundedDataStores**: UnboundedDatabases allow you to save global game data, such as game codes or guilds created by players
- **Autosaving**: You have the option to enable autosaving or use your own autosaving logic 
- **Simple**: Very easy to use and setup 
- **Change data globally**: Set a user's data from any server anytime. They don't even have to be in game.
- **Typechecking**: This module is written in strict lua; Typechecking = good :]
- **User metadata cache**: An additional table is provided so you can store in-memory variables related to the player's data
- **Threadsafe**: All normal datastore operations are queued for processing so that each operation runs one at time time, avoiding race conditions



### Installation
Go into the src folder, and add the code from the files in the children folder, paste them into their own module scripts using the same file name (minus the .lua part). Then copy the code
from Rodata.lua into a module script named `Rodata`, and make sure to add those two child module scripts under the Rodata  module script.  

# Example
This is an example using `UserDatabase`
```lua
local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Rodata = require(SSS.Rodata)

local udb = Rodata.CreateNewUserDatabase("beta_score_test.1", "beta_score_test.1map", {
    score = 0,
}, false, true, false)

udb.AutosaveCallbacks = {
    function(userId, data, metadata)
        print(`autosaved for user_{userId}.`)
    end,
}

Rodata.StartAutoSaveUserDataLoop(udb)


Players.PlayerAdded:Connect(function(player)
    local data = Rodata.LoadUserData(udb, player.UserId)
    if not data then
        warn("no data for:", player.Name)
        return
    end
	
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player
	
    local score = Instance.new("IntValue")
    score.Name = "Score"
    score.Value = data.score
    score.Parent = leaderstats
end)


Players.PlayerRemoving:Connect(function(player)	
    Rodata.SaveAndReleaseUserData(udb, player.UserId)
end)


game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        warn("BIND TO CLOSE")
        Rodata.SaveAndReleaseUserData(udb, player.UserId)
    end
    if RunService:IsStudio() then task.wait(1) end -- give studio enough time to allow the data to save instead of shutting down right away
end)



```


# Documentation
## Rodata.CreateNewUserDatabase()
```lua
Rodata.CreateNewUserDatabase(
  databaseName: string, 		-- A unique name to identify the database
  memoryStoreName: string, 		-- A unique name to identify the memory store sorted map; used for session-locking
  schema: { [string]: any }, 		-- the structure of your player data (your values must be numbers or strings or a table of them)
  waitForSessionOnLoad: boolean?, 	-- if true, a server waiting for the session lock will attempt to wait for the session lock to release before loading data, else the server will just kick the player with a message
  debugMode: boolean?, 			-- enable print statements to help with debugging
  threadQueueDebugMode: boolean?, 	-- enable print statements to show the structure of the queue for each player
  jobId: string?, 			-- you can just ignore this
  placeId: string? 			-- you can just ignore this
): UserDatabase
```
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

## Rodata.CreateNewOrderedDatabase()
Creates and returns a new database with an ordered datastore.

This function can be used to create a database for leaderboards.
```lua
Rodata.CreateNewOrderedDatabase(databaseName: string, debugMode: boolean?): OrderedDatabase
```
## Rodata.CreateNewUnboundedDatabase()
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
```lua
Rodata.CreateNewUnboundedDatabase(databaseName: string, debugMode: boolean?): UnboundedDatabase
```
## Rodata.GetDatabase()
Returns the named database stored in the server cache. If it cannot
be found then this function will wait for 5 seconds to see if it shows
up in the cache. If it does, it will be retuend. If it doesn't, an error 
will be thrown if it cannot be found after the timeout specified

Default timeout is 5 seconds if a timeout argument is not given.

While waiting for the db to appear in the cache, this function will
yield the current thread because of the while loop.

Use this function to retrieve the stored database after it has been created.
```lua
Rodata.GetDatabase(databaseName: string, timeout_s: number?): UserDatabase | OrderedDatabase | UnboundedDatabase
```
## Rodata.GetCachedUserData()
Retrieves the player's data held in server memory. This function does
not yield.

Throws an error if the player's data has not been loaded or is not in the cache.

Use this function to retrieve a player's data after their data has been loaded
with Rodata.LoadUserData()
```lua
Rodata.GetCachedUserData(database: UserDatabase, userId: string): Schema?
```
## Rodata.GetUserMetadata()
Returns the user's metadata cache, which is an additioanl table to store in-memory
variables related to a player's data, which means it does not get saved

Throws an error if the player's data has not been loaded or is not in the cache

One use case is to cache results from async calls, like MarketplaceService:UserOwnsGamePassAsync(),
that you only need to call once
```lua
Rodata.GetUserMetadata(database: UserDatabase, userId: string): Schema
```
## Rodata.LoadUserData()
Loads the user's data and acquires the session lock. This function yields the
current thread when it enters the queue to until it gets dequeued to execute.

Returns nil if an error occured while loading the data, else return the data.

This function should only be called once for each player, when they join the game.
To retrieve a player's data after they have joined, use Rodata.GetCachedUserData() 
```lua
Rodata.LoadUserData(database: UserDatabase, userId: string): Schema?
```
## Rodata.SaveUserData()
Saves the player's cached data in UserCache.data while maintaining the session lock. This function 
yields the current thread until it gets dequeued to execute.

Returns true if the operation succeeded; returns false if an error occurred.

Use this function to force save a player's current data manually (in an auto save loop, 
or after some important change).

DO NOT use this function to save a player's data when they leave.
```lua
Rodata.SaveUserData(database: UserDatabase, userId: string): boolean
```
## Rodata.SaveAndReleaseUserData()
Saves the player's data in UserCache.data and releases the session lock. This function yields the
current thread until it gets dequeued to execute.

Returns true if the operation succeeded; returns false if an error occurred. 

This function should be called when the player leaves the server or during shutdown
```lua
Rodata.SaveAndReleaseUserData(database: UserDatabase, userId: string): boolean
```

## Rodata.SetOrderedData()
Sets the value to the key by calling OrderedDataStore:SetAsync().

Returns true if successful or false if an error occured.
```lua
Rodata.SetOrderedData(database: OrderedDatabase, key: string, value: number): boolean
```
## Rodata.IterateOrderedData()
This function iterates over the ordered data, going page by page, executing the provided
callback function for each entry in the page in order. 

The last four arguments of this function are the same as and used in OrderedDataStore:GetSortedAsync().

Returns nothing; prints a warning message if an error occured while calling GetSortedAsync(), and
exits out of the function early, skipping the callback iteration code.
```lua
Rodata.IterateOrderedData(
  database: OrderedDatabase, callback: (rank: number, value: {key: string, value: number}) -> (),
  ascendingOrder: boolean, entriesPerPage: number?, minVal: number?, maxVal: number?
)
```
## Rodata.RemoveOrderedData()
This function removes a specified key from the ordered databse.

Returns true if successful or false if an error occured.
```lua
Rodata.RemoveOrderedData(database: OrderedDatabase, key: string): boolean
```
## Rodata.GlobalSetUserData()
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
```lua
Rodata.GlobalSetUserData(
  databaseRef: string | UserDatabase,
  userId: string,
  newData: Schema,
  callback: (newData: Schema) -> ()?
): boolean
```
## Rodata.ListVersionsAsync()
  This function returns an array of all the previously saved versions of the player's data.
  
  The <limit> argument is the number of verions to return. This function yields the
  current thread; the higher the limit, the longer it will take this function to finish running.
  
  If no argument is provided for <ascendingOrder>, it will default to false, meaning that
  the versions will be sorted from newest to oldest
  
  One use case for this function is that you can use this function to revert a player's data by 
  seeing all the past versions of their data and use GlobalSetUserData() to pass in the
  old data version and set the player's current data to it.
```lua
Rodata.ListVersionsAsync(
  databaseName: string,
  userId: string,
  debugMode: boolean,
  limit: number?,
  ascendingOrder: boolean?,
  minDate: number?,
  maxDate: number?
): { DataVersion }
```
## Rodata.GetUnboundedData()
Returns the data from the unbounded database for a specified key
using GetAsync() or returns nil if no data can be found for the key.

This function can be called globally, similar to GlobalSetUserData().
```lua
Rodata.GetUnboundedData(databaseRef: string | UnboundedDatabase, key: string, data: any): any
```
## Rodata.SetUnboundedData()
Sets and saves data to an unbounded database using SetAsync(). 

Returns true if successful or false if an error occurred.

This function can be called globally, similar to GlobalSetUserData().
```lua
Rodata.SetUnboundedData(databaseRef: string | UnboundedDatabase, key: string): boolean
```
## Rodata.RemoveUnboundedData()
Removes the specified key value from an unbounded database using RemoveAsync(). 

Returns true if successful or false if an error occurred.

This function can be called globally, similar to GlobalSetUserData().
```lua
Rodata.RemoveUnboundedData(databaseRef: string | UnboundedDatabase, key: string): boolean
```
## Rodata.RemoveUserData()
This function removes the user's data using RemoveAsync(). 

Returns true if successful or false if an error occurred.

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
```lua
Rodata.RemoveUserData(databaseRef: string | UserDatabase, memoryStoreRef: string?, userId: string): boolean
```
## Rodata.ObliterateUserData()
This function completely erases all data bounded to the player in a user
database, removing every version of their data as well. This function
will yield the current thread while executing each datastore operation.
It may take a while.
```lua
Rodata.ObliterateUserData(databaseName: string, userId: string)
```
## Rodata.StartAutoSaveUserDataLoop()
Starts the auto-save loop for the specified `UserDatabase`
```lua
Rodata.StartAutoSaveUserDataLoop(database: UserDatabase)
```





























