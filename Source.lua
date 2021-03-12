--[[
	* Timer Module, by avozzo (Contributions from CntKillMe)

	# Documentation

	* Timer:GetEnums()
		# Description
			Returns all the StateEnums, in a read-only table.
		# Returns
			Enum StateEnum


	* Timer.new(number Wait)
		# Description
			Creates a new TimerObject
		# Arguments:
			number Wait
				How long the TimerObject will run for.
		# Returns
			TimerObject


			* TimerObject:Start()
				# Description
					Statrts the TimerObject.


			* TimerObject:GetLength()
				# Description
					Returns how long the TimerObject is running for.
				# Returns
					number Length


			* TimerObject:GetRemaining()
				# Description
					Returns how long unitl the TimerObject will finish.
				# Returns
					number Remaining


			* TimerObject:GetState()
				# Description
					Returns what state the TimerObject is currently in.
				# Returns
					Enum StateEnum


			* TimerObject:IsPaused()
				# Description
					Returns whether the TimerObject's current state is ``Paused``.
				# Returns
					boolean IsPaused


			* TimerObject:IsRunning()
				# Description
					Returns whether the TimerObject is currently running (alive).
				# Returns
					boolean IsRunning


			* TimerObject:IsDead()
				# Description
					Returns whether the TimerObject has died, either from finishing playing or being cancelled.
				# Returns
					boolean IsDead


			* TimerObject:Wait()
				# Description
					Yields the thread this was called from until the TimerObject has finished playing.
					Returns it's state and the time it yielded for in total.
				# Returns
					Enum StateEnum, number YieldedTime


			*  TimerObject:Pause()
				# Description
					Pauses the TimerObject.


			* TimerObject:Resume()
				# Description
					Resumes the TimerObject. If the TimerObjects state isn't ``Paused``, this will throw an error.


			* TimerObject:Stop()
				# Description
					Prematurely cancels the TimerObject before it finishes.


			* TimerObject:On[State](function Callback)
				# Description
					calls Callback when state is changed to [State].


			* TimerObject.Length = number Length
			* TimerObject.State = Enum StateEnum
]]

local Timer = {}
local TimerEnum = setmetatable({
	Running = 'Running',
	Paused = 'Paused',
	Finished = 'Finished',
	Stopped = 'Stopped',
	Dead = 'Dead',
	Died = 'Died'
}, {
	__index = function(_, key)
		return error(string.format('%s is not a valid member of %s', key, 'TimerEnum'), 2)
	end,
	__newindex = function()
		return error('attempt to modify a readonly table', 2)
	end,
	__metatable = false,
	__tostring = 'TimerEnum'
})

local TimerArrays = {}
local RunService = game:GetService('RunService')

local TimerClass = {}
TimerClass.__index = TimerClass

local function StateCallback(TimerObject, State, ...)
	if TimerObject.BotherChecking then
		for _, Function in next, TimerObject.CallbackStates[State] do
			coroutine.wrap(Function)(State, ...)
		end
	end
end

local function EndTimer(TimerObject, State, ...)
	if TimerObject.Callback then
		coroutine.wrap(TimerObject.Callback)(State)
	end

	if TimerObject.BotherChecking then
		if State == TimerEnum.Stopped or State == 'Finished' then
			for _, StateName in next, {TimerEnum.Dead, TimerEnum.Died} do
				for _, Function in next, TimerObject.CallbackStates[StateName] do
					coroutine.wrap(Function)(StateName, ...)
				end
			end
		end

		for _, Function in next, TimerObject.CallbackStates[State] do
			coroutine.wrap(Function)(State, ...)
		end
	end
	TimerObject.State = TimerEnum.Dead
end

--// Thank you CntKillMe
local function FindBestSpot(CompletionTime)
	local LeftIdx = 1
	local RightIdx = #TimerArrays

	if RightIdx == 0 then
		return 1
	end
	while LeftIdx <= RightIdx do
		local CenterIdx = math.floor((LeftIdx + RightIdx) / 2)
		local CenterTimer = TimerArrays[CenterIdx]

		if CenterTimer == nil then
			return RightIdx
		end
		if CompletionTime > CenterTimer:GetRemaining() then
			RightIdx = CenterIdx - 1
		elseif CompletionTime < CenterTimer:GetRemaining() then
			LeftIdx = CenterIdx + 1
		else
			LeftIdx = CenterIdx
			break
		end
	end

	return LeftIdx
end
local function AddToArray(TimerObj)
	table.insert(TimerArrays, FindBestSpot(TimerObj:GetRemaining()), TimerObj)
end
local function RemoveFromArray(TimerObj)
	local Index = table.find(TimerArrays, TimerObj)
	if Index then
		table.remove(TimerArrays, Index)
	end
end

function TimerClass:GetLength()
	return self.Length
end
function TimerClass:GetRemaining()
	local Time = self.FrozenRemaining or self.Length - (time() - self.Started)
	return Time > 0 and Time or 0
end
function TimerClass:GetState()
	return self.State
end

for _, Enum in next, TimerEnum do
	TimerClass['Is' .. Enum] = function(self)
		assert(self, 'Expected \':\' not \'.\' calling member function Is' .. Enum)
		return self.State == Enum
	end
end

function TimerClass:Start()
	self.Started = time()
	AddToArray(self)
	self.State = TimerEnum.Running
	StateCallback(self, self.State, self:GetRemaining())
end
function TimerClass:Wait()
	table.insert(self.YieldedThreads, coroutine.running())
	return coroutine.yield()
end
function TimerClass:Pause()
	RemoveFromArray(self)
	self.State = TimerEnum.Paused
	self.FrozenRemaining = self:GetRemaining()
	StateCallback(self, self.State, time() - self.Started)
end
function TimerClass:Resume()
	assert(self.State == TimerEnum.Paused, 'Attempt to resume a non-frozen timer (State: ' .. self.State .. ')')
	AddToArray(self)
	self.State = TimerEnum.Running
	self.FrozenRemaining = nil
	StateCallback(self, self.State, time() - self.Started)
end
function TimerClass:Stop()
	assert(self.State ~= TimerEnum.Stopped, 'Attempt to stop a dead timer (State: ' .. self.State .. ')')
	self.State = TimerEnum.Stopped
	RemoveFromArray(self)
	EndTimer(self, self.State, time() - self.Started)
end
function TimerClass:IncrementTime(Delta)
	self.Length += Delta
end

-- Aliases
TimerClass.Yield = TimerClass.Wait
TimerClass.Yield = TimerClass.Wait
TimerClass.Play = TimerClass.Start
TimerClass.Cancel = TimerClass.Stop
TimerClass.Kill = TimerClass.Stop


for State in next, TimerEnum do
	TimerClass['On' .. State] = function(self, f)
		assert(type(f) == 'function', 'Invalid argument #1 to On' .. State .. ' (function expected, got ' .. typeof(f) .. ')')
		self.BotherChecking = true
		table.insert(self.CallbackStates[State], f)
	end
end

Timer.new = function(Wait)
	local CallbackStates = {}
	for State in next, TimerEnum do
		CallbackStates[State] = {}
	end

	return setmetatable({
		Length = Wait,
		Started = time(),
		State = TimerEnum.Paused,
		YieldedThreads = {},
		CallbackStates = CallbackStates
	}, TimerClass)
end

RunService.Stepped:Connect(function()
	local time = time()
	local DyingObj = TimerArrays[#TimerArrays]

	while DyingObj do
		if DyingObj:GetRemaining() <= 0 then
			local Time = time - DyingObj.Started

			TimerArrays[#TimerArrays] = nil
			EndTimer(DyingObj, TimerEnum.Finished, Time)

			for _, Thread in next, DyingObj.YieldedThreads do
				coroutine.resume(Thread, TimerEnum.Finished, Time)
			end
			DyingObj = TimerArrays[#TimerArrays]
			continue
		end
		DyingObj = nil
	end
end)
Timer.Enums = TimerEnum
function Timer:GetEnums()
	return TimerEnum
end

return Timer