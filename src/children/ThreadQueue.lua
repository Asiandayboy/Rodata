--!strict
local ThreadQueue = {}



export type Callback = (...any) -> any

export type QueueEntry = {
	callback: Callback,
	args: { any },
	thread: thread,
	taskName: string?
}

export type ThreadQueue = {
	_queue: { QueueEntry },
	_isQueueRunning: boolean,
	_timeBetweenTasks: number,
	debugMode: boolean,
	_destroying: boolean,
}


local function printQueueEnqueued(q: { QueueEntry })
	warn("ThreadQueue - Enqueued:")
	for _, v in ipairs(q) do
		warn(string.format("\t %s", v.taskName::string))
	end
end


function ThreadQueue._startQueue(self: ThreadQueue)
	task.defer(function()
		if self._isQueueRunning or self._destroying then return end
		--if not self._queue then return end -- self was destroyed

		self._isQueueRunning = true

		while #self._queue > 0 do
			-- during ThreadQueue._dequeue(self), self could be destroyed, which means all references
			-- to self after will be indexing nil
			-- So, we need to add checks to make sure properties exists before altering them
			ThreadQueue._dequeue(self) 
			
			--if self._timeBetweenTasks == nil then return end -- self was destroyed

			if self._timeBetweenTasks > 0 then
				task.wait(self._timeBetweenTasks)
			end
		end

		self._isQueueRunning = false 
	end)
end

function ThreadQueue.IsEmpty(self: ThreadQueue)
	return #self._queue == 0
end


function ThreadQueue.new(debugMode: boolean?): ThreadQueue
	local self: ThreadQueue = {
		_queue = {},
		_isQueueRunning = false,
		_timeBetweenTasks = 0,
		debugMode = debugMode or false,
		_destroying = false
	}
	
	return self
end


--[[ 
	adds the function to the queue, and calls it later with pcall with its arguments;
	Returns the results of the callback wrapped in pcall()
	
	taskName is used for debugging purposes
	
]]
function ThreadQueue.Enqueue(self: ThreadQueue, taskName: string?, f: Callback, ...: any): (boolean, any)
	if self._destroying then
		error(`Cannot add to ThreadQueue when queue is about to be destroyed.`)
	end
	
	if self.debugMode and taskName == nil then
		error("taskName argument must be provided if debugMode for ThreadQueue is true.")
	end
	
	local queueEntry: QueueEntry = {
		callback = f,
		args = {...},
		thread = coroutine.running(),
		taskName = taskName
	}
	table.insert(self._queue, queueEntry)
	
	if self.debugMode then printQueueEnqueued(self._queue) end
	
	ThreadQueue._startQueue(self)
	
	return coroutine.yield()
end

function ThreadQueue._dequeue(self: ThreadQueue)
	local queueEntry = table.remove(self._queue, 1)::QueueEntry
	
	local success, res = pcall(queueEntry.callback, table.unpack(queueEntry.args))
	
	coroutine.resume(queueEntry.thread, success, res) -- return the arguments of pcall to coroutine.yield's return
end

--[[
	.Destroy() yields the current thread to wait for the the queue
	to stop running before destroying
]]
function ThreadQueue.Destroy(self: ThreadQueue)
	self._destroying = true
	while self._isQueueRunning do
		if self.debugMode then
			warn("Waiting for queue to stop running before destroying.")	
		end
		task.wait() 
	end

	table.clear(self._queue)
	table.clear(self)
end




return ThreadQueue
