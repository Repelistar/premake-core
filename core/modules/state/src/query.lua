local Block = require('block')
local Condition = require('condition')
local Field = require('field')
local Store = require('store')

local Query = {}

-- result values for block tests
local ADD = Block.ADD
local REMOVE = Block.REMOVE
local OUT_OF_SCOPE = 'OUT_OF_SCOPE'
local UNKNOWN = 'UNKNOWN'


-- Enabling the debug statements is a big performance hit.
-- local function _debug(...) if _LOG_PREMAKE_QUERIES then print(...) end end


---
-- Aggregate values from a block into an existing value collection. Each time a new
-- block gets enabled (its condition is tested and passed), this gets called to
-- merge its contents into the accumulated value snaphot.
---

local function _accumulateValuesFromBlock(allFieldsTested, values, block, operation)
	for field, value in pairs(block.data) do
		-- we only care about fields that are used to satisfy block conditions; ignore others
		if allFieldsTested[field] then
			if operation == ADD then
				values[field] = Field.mergeValues(field, values[field], value)
			else
				values[field] = Field.removeValues(field, values[field], value)
			end
		end
	end
	return values
end


---
-- Aggregate values for a specific field from the currently enabled blocks. Used
-- by value removal logic.
---

local function _fetchFieldValue(field, blockResults)
	local values = {}

	for i = 1, #blockResults do
		local blockResult = blockResults[i]
		local value = blockResult.sourceBlock.data[field]
		if value ~= nil then
			local operation = blockResult.globalOperation
			if operation == ADD then
				values = Field.mergeValues(field, values, value)
			elseif operation == REMOVE then
				values = Field.removeValues(field, values, value)
			end
		end
	end

	return values
end


---
-- Test an individual settings block, and decide whether it should be added to the
-- accumulated results or not.
--
-- @returns
--    Two values indicating the disposition of the block for both the global full inheritance
--    state, and the target state. Ex. a return value of `ADD, UNKNOWN` means "add this block
--    into the full inheritance state, but skip over it for the target state".
---

local function _testBlock(state, blockCondition, blockOperation, globalScopes, globalValues, targetScopes, targetValues)
	if blockOperation == ADD then

		-- If this block can't match anything in the full inheritance state, then it definitely will
		-- not match anything in the target state, so we can just ignore it for now and see if it
		-- comes into scope later as a result of accumulated state changes.
		if not Condition.matchesScopeAndValues(blockCondition, globalValues, globalScopes) then
			return UNKNOWN, UNKNOWN
		end

		-- The block matched the full inheritance state, so we want to add it to our accumulated full
		-- inheritance state. Now check to see if it is also compatible with our target state.
		if not Condition.matchesScopeAndValues(blockCondition, targetValues, targetScopes) then
			return ADD, UNKNOWN
		end

		-- Matched both full inheritance & target states, so add to both
		return ADD, ADD

	end

	if blockOperation == REMOVE then

		-- Test to see if this condition could match against any part of my potential
		-- inheritance tree. If it can't match anything, in any potential inheritance
		-- setup, then it doesn't apply to me at all I can safely ignore it. I test
		-- for this by looking for any values current accumulated which conflict with
		-- what is asked for by the condition. If the value hasn't been set yet, that's
		-- considered okay. But if the value *is* set, but fails to match the condition,
		-- that's a conflict and a fail.
		--
		-- So for a condition `{ workspaces='Workspace1' }...
		--   - a value of `{ workspaces= nil }` is not a conflict
		--   - a value of `{ workspaces='Workspace1' }` is not a conflict
		--   - a value of `{ workspaces='Workspace2'}` is a conflct
		--
		-- Note that I'm passing in the values where I'd normally be passing in the
		-- scopes (the second argument). That's to catch the case of a "sibling" scope.
		-- If I'm trying to pull the state for `{ Workspace1, Project1 }` then a condition
		-- testing `{ Workspace1, Project2 }` would not match any inherited scope, but if
		-- Project2 is part of Workspace1, then it would appear in the Workspace1 values.
		-- So this test detects state that lives "next" to me.
		--
		-- Also note that I can't yet mark it as OUT_OF_SCOPE because it is still
		-- possible that more objects will get added to inheritance tree later on in the
		-- script, which could change the outcome of this test.
		--
		-- This is confusing as hell. I tried to explain it better in the unit tests.
		-- Basically, "look at all my possible parents and siblings, and see if this
		-- condition could match any of them. If not, ignore this block".

		if Condition.hasConflictingValues(blockCondition, globalValues, globalValues) then
			return UNKNOWN, UNKNOWN
		end

		-- I now know that this block's condition could match something in my full
		-- inheritance tree. Try the same test again, but this time test against the
		-- full inheritance scopes, instead of passing the collected values for both
		-- parameters. If no conflicts are found, that means that this block does apply
		-- to me one way or the other, so the values should be removed. Or, "look at
		-- myself and my direct line of inheritance, and see if this condition could
		-- match any of them. If so, apply this block and remove the values".

		if not Condition.hasConflictingValues(blockCondition, globalScopes, globalValues) then
			return REMOVE, REMOVE
		end

		-- If I get here, that means that the values are actually going to be removeed
		-- by one of my siblings, or something "next" to me in the full inheritance tree.
		-- In order to keep the exported projects additive only, the values would have
		-- actually have been removed already by the shared parent in that tree (again, I
		-- tried to explain this better in the unit tests). So since the value has effectively
		-- not yet been set, and since I'm not the one who asked for it to be removed, I need
		-- to add it here, rather than remove it.

		return REMOVE, ADD

	end
end


---
-- Evaluate a state query.
--
-- @returns
--    A list of state blocks which apply to the state's scopes and initial values.
---

function Query.evaluate(state)
	-- In order to properly handle removed values (see `state_remove_tests.lua`), evaluation must
	-- accumulate two parallels states: a "target" state, or the one requested by the caller, and
	-- a "global" state which includes all values that could possibly be inherited by the target
	-- scope, if all levels of inheritance were enabled. When a request is made to remove a value,
	-- we check this global state to see if the value has actually been set, and make the appropriate
	-- corrections to ensure the change gets applied correctly.
	local targetValues = Field.receiveAllValues(state._initialValues)
	local globalValues = Field.receiveAllValues(state._initialValues)

	local sourceBlocks = state._sourceBlocks
	local targetScopes = state._targetScopes
	local globalScopes = state._globalScopes

	-- _debug('TARGET SCOPES:', table.toString(targetScopes))
	-- _debug('GLOBAL SCOPES:', table.toString(globalScopes))
	-- _debug('INITIAL VALUES:', table.toString(targetValues))

	-- The list of incoming source blocks is shared and shouldn't be modified. Set up a parallel
	-- list to keep track of which blocks we've tested, and the per-block test results.

	local blockResults = {}

	for i = 1, #sourceBlocks do
		table.insert(blockResults, {
			targetOperation = UNKNOWN,
			globalOperation = UNKNOWN,
			sourceBlock = sourceBlocks[i]
		})
	end

	-- Optimization: only fields actually mentioned by block conditions are aggregated
	local allFieldsTested = Condition.allFieldsTested()

	-- Set up to iterate the list of blocks multiple times. Each time new values are
	-- added or removed from the target state, any blocks that had been previously skipped
	-- over need to be rechecked to see if they have come into scope as a result.

	local i = 1

	while i <= #blockResults do
		local blockResult = blockResults[i]
		local sourceBlock = blockResult.sourceBlock

		local targetOperation = blockResult.targetOperation
		local globalOperation = blockResult.globalOperation

		if globalOperation ~= UNKNOWN then

			-- We've already made a decision on this block, can skip over it now
			i = i + 1

		else
			local blockCondition = sourceBlock.condition
			local blockOperation = sourceBlock.operation

			-- _debug('----------------------------------------------------')
			-- _debug('BLOCK #:', i)
			-- _debug('BLOCK OPER:', blockOperation)
			-- _debug('BLOCK EXPR:', table.toString(blockCondition))
			-- _debug('TARGET VALUES:', table.toString(targetValues))
			-- _debug('GLOBAL VALUES:', table.toString(globalValues))

			globalOperation, targetOperation = _testBlock(state, blockCondition, blockOperation, globalScopes, globalValues, targetScopes, targetValues)
			-- _debug('GLOBAL RESULT:', globalOperation)
			-- _debug('TARGET RESULT:', targetOperation)

			if targetOperation == ADD and globalOperation == REMOVE then
				-- I've hit the sibling of a scope which removed values. To stay additive, the values were actually
				-- removed by my container. Now I'm in the awkward position of needing to add them back in. Can't be
				-- just a simple add though: have to make sure I only add in values that might have actually been set.
				-- Might have to deal with wildcard matches. Need to synthesize a new ADD block for this. Start by
				-- excluding the current remove block from the target results.
				blockResult.targetOperation = OUT_OF_SCOPE

				-- Then build a new block and insert values that would be removed by the container
				local newAddBlock = Block.new(Block.ADD, _EMPTY)

				for field, removePatterns in pairs(sourceBlock.data) do
					local currentGlobalValues = _fetchFieldValue(field, blockResults)
					local currentTargetValues = targetValues[field] or _EMPTY

					-- Run the block's remove patterns against the accumulated global state. Check to see if any of
					-- the removed values are *not* present in the current target state. Those are the values that now
					-- need to be added back in to the target state. I iterate and add them individually because in
					-- this case we don't want to add duplicates even if the field would otherwise allow it.
					local removedValues
					currentGlobalValues[field], removedValues = Field.removeValues(field, currentGlobalValues, removePatterns)

					for i = 1, #removedValues do
						local value = removedValues[i]
						if not Field.matches(field, currentTargetValues, value) then
							Block.receive(newAddBlock, field, value)
						end
					end

				end

				-- Insert the new block into my result list

				table.insert(blockResults, i, {
					targetOperation = ADD,
					globalOperation = OUT_OF_SCOPE,
					sourceBlock = newAddBlock
				})

				targetValues = _accumulateValuesFromBlock(allFieldsTested, targetValues, newAddBlock, ADD)

			elseif targetOperation ~= UNKNOWN then
				blockResult.targetOperation = targetOperation
				targetValues = _accumulateValuesFromBlock(allFieldsTested, targetValues, sourceBlock, targetOperation)
			end

			if globalOperation ~= UNKNOWN then
				blockResult.globalOperation = globalOperation -- TODO: do I need to store this? Once values have been processed at the global scope I'm done?
				globalValues = _accumulateValuesFromBlock(allFieldsTested, globalValues, sourceBlock, globalOperation)
			end


			-- If accumulated state changed rerun previously skipped blocks to see if they should now be enabled
			if globalOperation ~= UNKNOWN then
				-- _debug('STATE CHANGED, rerunning skipped blocks')
				i = 1
			else
				i = i + 1
			end
		end
	end

	-- Create a new list of just the enabled blocks to return to the caller

	local enabledBlocks = {}

	for i = 1, #blockResults do
		local blockResult = blockResults[i]
		local operation = blockResult.targetOperation
		if operation == ADD or operation == REMOVE then
			table.insert(enabledBlocks, Block.new(operation, _EMPTY, blockResult.sourceBlock.data))
		end
	end

	return enabledBlocks
end


return Query
