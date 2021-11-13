local Condition = require('condition')
local Field = require('field')
local set = require('set')

local ConditionConflictTests = test.declare('ConditionConflictTests', 'condition')

-- Scopes & values are keyed with Field instances
local FLD_KIND = Field.get('kind')
local FLD_PROJECTS = Field.get('projects')
local FLD_WORKSPACES = Field.get('workspaces')


---
-- A condition with no clauses should never conflict with anything.
---

function ConditionConflictTests.returnsFalse_onEmptyCondition()
	local cond = Condition.new({})
	test.isFalse(cond:hasConflictingValues(
		{},
		{}
	))
end


---
-- If the value tested by the condition does not exist in the provided values, it
-- should not be considered a conflict.
---

function ConditionConflictTests.returnsFalse_onMissingValue()
	local cond = Condition.new({ workspaces = 'Workspace1' })
	test.isFalse(cond:hasConflictingValues(
		{},
		{}
	))
end


---
-- If the values being tested do exist, and can match the condition, there is no conflict.
---

function ConditionConflictTests.returnsFalse_onScopeMatches()
	local cond = Condition.new({ workspaces = 'Workspace1', projects = 'Project1' })
	test.isFalse(cond:hasConflictingValues(
		{
			{
				[FLD_WORKSPACES] = {'Workspace1'},
				[FLD_PROJECTS] = {'Project1'}
			}
		},
		{}
	))
end

function ConditionConflictTests.returnsFalse_onValueMatches()
	local cond = Condition.new({ kind = 'ConsoleApplication' })
	test.isFalse(cond:hasConflictingValues(
		{
			{
				[FLD_WORKSPACES] = {'Workspace1'},
				[FLD_PROJECTS] = {'Project1'}
			}
		},
		{
			[FLD_KIND] = 'ConsoleApplication'
		}
	))
end


---
-- If the values being tested do exist, but cannot match the condition, it's a conflict.
---

function ConditionConflictTests.returnsTrue_onScopeMismatch()
	local cond = Condition.new({ workspaces = 'Workspace1', projects = 'Project1' })
	test.isTrue(cond:hasConflictingValues(
		{
			{
				[FLD_WORKSPACES] = {'Workspace1'},
				[FLD_PROJECTS] = {'Project2'}
			}
		},
		{}
	))
end

function ConditionConflictTests.returnsTrue_onValueMismatch()
	local cond = Condition.new({ kind = 'ConsoleApplication' })
	test.isTrue(cond:hasConflictingValues(
		{
			{
				[FLD_WORKSPACES] = {'Workspace1'},
				[FLD_PROJECTS] = {'Project2'}
			}
		},
		{
			[FLD_KIND] = 'StaticLibrary'
		}
	))
end
