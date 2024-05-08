# Rodata

Rodata is a module script to help you save data in your Roblox games.

With Rodata, you can create a `database` to save your data. There are three different types of databases depending on the data you're storing:
- `UserDatabase` - A database for storing only player data
- ``OrderedDatabase`` - A database for storing sorted numbers, such as leaderboards
- ``UnboundedDatabase`` - A database for storing data that is not bound to a player; things like game codes.


### Features
- **Session-locking**: In a `UserDatabase`, only one server at a time can access a player's data, preventing item duplication and data overwrites.
- **Simple**: Rodata is very easy to use for anyone. 
- **Threadsafe**: In a `UserDatabase`, each datastore request is added to a queue, which helps solve concurrency problems, like a player rejoining the same server quickly when their data hasn't finished saving from leaving the server the first time.
- **Change user data globally**: Rodata provides a function that allows you to change a user's data from anywhere anytime. This is handy if you want to revert a player's data or manually set it to something else.
- **OrderedDataStores**: With Rodata, you can use an `OrderedDatabase` to help you create leaderboards.
- **Direct indexing**: In a `UserDatabase`, the player's data is cached in a table, which allows you to use the dot . syntax to easily access the player's data.



### Installation
- Option 1 - If you want to get it on [GitHub](https://github.com/Asiandayboy/Rodata), go into the src folder, and add the code from the files in the children folder, paste them into their own module scripts. Then copy the code
from Rodata.lua into a module script (name it "Rodata" if you want), and make sure to add those two child module scripts under the Rodata.lua module script.  
- Option 2 - Get the Roblox module script [here], and put it into your game somewhere in ServerScriptService.



# Documentation
```lua
Rodata.CreateNewUserDatabase(
  databaseName: string,
  memoryStoreName: string,
  schema: { [string]: any },
  waitForSessionOnLoad: boolean?,
  debugMode: boolean?,
  threadQueueDebugMode: boolean?,
  jobId: string?,
  placeId: string?
): UserDatabase
```
```lua
Rodata.CreateNewOrderedDatabase()
```
```lua
Rodata.CreateNewUnboundedDatabase()
```
```lua
Rodata.GetDatabase()
```
```lua
Rodata.GetCachedUserData()
```
```lua
Rodata.GetUserMetadata()
```
```lua
Rodata.LoadUserData()
```
```lua
Rodata.SaveUserData()
```
```lua
Rodata.SaveAndReleaseUserData()
```
```lua
Rodata.SetOrderedData()
```
```lua
Rodata.IteratedOrderedData()
```
```lua
Rodata.RemoveOrderedData()
```
```lua
Rodata.GlobalSetUserData()
```
```lua
Rodata.ListVersionsAsync()
```
```lua
Rodata.GetUnboundedData()
```
```lua
Rodata.SetUnboundedData()
```
```lua
Rodata.RemoveUserData()
```
```lua
Rodata.ObliterateUserData()
```






























