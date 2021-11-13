local premake = require('premake')
local Store = require('store')
local State = require('state')

local StateRemoveTests = test.declare('StateRemoveTests', 'state')


local _global

function StateRemoveTests.setup()
	_global = State.new(premake.store())
end


---
-- Simplest case: a value is added and then removed at the same scope. The removed
-- value should be excluded from the query results.
---

function StateRemoveTests.shouldRemoveFromScope_whenRemovedAtScope()
	defines { 'A', 'B', 'C' }
	removeDefines 'B'
	test.isEqual({ 'A', 'C' }, _global.defines)
end


---
-- In most IDE project file formats there is no general way to remove a value which was
-- previously set. So we need to ensure that exporters only ever need to add new values,
-- and never have to deal with trying to remove anything. If a script adds a value at a
-- parent scope (eg. workspace), and then removes it from one of the child scopes (eg.
-- project), we need the workspace query to _not_ return the value, because then we'd
-- have to remove it from a project. Instead we'll have to add it back into the projects
-- which _did not_ remove the value to get the desired result without removes.
---

function StateRemoveTests.shouldRemoveFromWorkspace_whenRemovedFromProject()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global
		:select({ workspaces = 'Workspace1' })

	test.isEqual({ 'A', 'C' }, wks.defines)
end


---
-- If a value is defined by a parent scope (eg. workspace) and removed from a
-- child scope (eg. project), the value should not appear in the child which
-- performed the remove.
---

function StateRemoveTests.shouldRemoveFromProject_whenRemovedByThatProject_withNoInheritance()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local prj = _global
		:select({ workspaces = 'Workspace1' })
		:select({ projects = 'Project2' })

	test.isEqual({}, prj.defines)
end


---
-- If that same project is inheriting from the parent, it should get all values except
-- the one that was removed.
---

function StateRemoveTests.shouldRemoveFromProject_whenRemovedByThatProject_withInheritance()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local prj = _global
		:select({ workspaces = 'Workspace1' })
		:select({ projects = 'Project2' }):withInheritance()

	test.isEqual({ 'A', 'C' }, prj.defines)
end


---
-- Now check to make sure that the removed value which was not listed at the
-- parent scope gets added back into all the child scopes which did not remove
-- that value.
---

function StateRemoveTests.shouldAddToProject_whenRemovedByOtherProject_withNoInheritance()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local prj = _global
		:select({ workspaces = 'Workspace1' })
		:select({ projects = 'Project1' })

	test.isEqual({ 'B' }, prj.defines)
end


---
-- Same test as above but with inheritance enabled. Should now receive all
-- of the values set at the parent scope.
---

function StateRemoveTests.shouldAddToProject_whenRemovedByOtherProject_withInheritance()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local prj = _global
		:select({ workspaces = 'Workspace1' })
		:select({ projects = 'Project1' }):withInheritance()

	test.isEqual({ 'A', 'B', 'C' }, prj.defines)
end


---
-- Found this one while testing removeFiles(); could probably be folded into one of the
-- tests above but I don't want to mess with what's working. If a value is both added
-- and removed "above" my target scope, I shouldn't see any of the removed values at all.
---

function StateRemoveTests.projectsAdds_projectRemoves_doesNotAddToConfig()
	workspace('Workspace1', function ()
		configurations { 'Debug', 'Release' }
		project('Project1', function ()
			defines { 'A' }
			removeDefines { 'A' }
		end)
	end)

	local cfg = _global
		:select({ workspaces = 'Workspace1' }):withInheritance()
		:select({ projects = 'Project1' }):withInheritance()
		:select({ configurations = 'Debug' }):withInheritance()

	-- _LOG_PREMAKE_QUERIES = true
	test.isEqual({}, cfg.defines)
end



---
-- TODO: block tests scope plus something else that isn't matched (like system or kind); should not apply the block, right?
--   I think right now the missing value will be considered a pass? Or have I already handled this? it just gets
--   removed from the parent and added back in everywhere else? I think?
---





----------------------------------------------------------------------------------------------


function StateRemoveTests.workspaceAdds_projectRemoves_removesFromTarget_include()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }
	end)

	when({'projects:Project2'}, function ()
		removeDefines 'B'
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' }):fromScopes(_global)
	test.isEqual({}, prj.defines)
end


function StateRemoveTests.workspaceAdds_projectRemoves_addsToSiblings_include()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }
	end)

	when({'projects:Project2'}, function ()
		removeDefines 'B'
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project1' }):fromScopes(_global)
	test.isEqual({ 'B' }, prj.defines)
end


---
-- Verify more permutations of the same pattern for completeness.
---

function StateRemoveTests.globalAdds_projectRemoves_removesFromGlobal()
	defines { 'A', 'B', 'C' }

	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	test.isEqual({ 'A', 'C' }, _global.defines)
end


function StateRemoveTests.globalAdds_projectRemoves_ignoresWorkspace()
	defines { 'A', 'B', 'C' }

	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	test.isEqual({}, wks.defines)
end


function StateRemoveTests.globalAdds_projectRemoves_ignoresWorkspace_inherit()
	defines { 'A', 'B', 'C' }

	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' }):withInheritance()
	test.isEqual({ 'A', 'C' }, wks.defines)
end


function StateRemoveTests.globaleAdds_projectRemoves_removesFromTarget()
	defines { 'A', 'B', 'C' }
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' })
	test.isEqual({}, prj.defines)
end


function StateRemoveTests.globalAdds_projectRemoves_removesFromTarget_inherit()
	defines { 'A', 'B', 'C' }
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' }):withInheritance()
	local prj = wks:select({ projects = 'Project2' }):withInheritance()
	test.isEqual({ 'A', 'C' }, prj.defines)
end


function StateRemoveTests.globalAdds_projectRemoves_addsToSiblings()
	defines { 'A', 'B', 'C' }
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project1' })
	test.isEqual({ 'B' }, prj.defines)
end


function StateRemoveTests.globalAdds_projectRemoves_addsToSiblings_inheerit()
	defines { 'A', 'B', 'C' }
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		when({'projects:Project2'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' }):withInheritance()
	local prj = wks:select({ projects = 'Project1' }):withInheritance()
	test.isEqual({ 'A', 'B', 'C' }, prj.defines)
end


function StateRemoveTests.workspaceAdds_projConfigRemoves_removesFromWorkspace()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			when({'configurations:Debug'}, function ()
				removeDefines 'B'
			end)
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	test.isEqual({ 'A', 'C' }, wks.defines)
end


function StateRemoveTests.workspaceAdds_projConfigRemoves_removesFromWksCfg()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			when({'configurations:Debug'}, function ()
				removeDefines 'B'
			end)
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local cfg = wks:selectAny({ configurations='Debug', platforms='macOS' }):withInheritance()
	test.isEqual({ 'A', 'C' }, cfg.defines)
end


function StateRemoveTests.workspaceAdds_projConfigRemoves_removesFromTargetProj()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			when({'configurations:Debug'}, function ()
				removeDefines 'B'
			end)
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' }):withInheritance()
	test.isEqual({ 'A', 'C' }, prj.defines)
end


function StateRemoveTests.workspaceAdds_siblingProjConfigRemoves_removesFromProj()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2', 'configurations:Debug' }, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project1' }):withInheritance()

	test.isEqual({ 'A', 'B', 'C' }, prj.defines)
end


function StateRemoveTests.workspaceAdds_projConfigRemoves_removesFromProjCfg()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2', 'configurations:Debug' }, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' })
	local cfg = prj:selectAny({ configurations='Debug', platforms='macOS' })
	test.isEqual({}, cfg.defines)
end


function StateRemoveTests.workspaceAdds_projConfigRemoves_removesFromTarget_inherit()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			when({'configurations:Debug'}, function ()
				removeDefines 'B'
			end)
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' }):withInheritance()
	local cfg = prj:selectAny({ configurations='Debug', platforms='macOS' }):withInheritance()
	test.isEqual({ 'A', 'C' }, cfg.defines)
end


function StateRemoveTests.workspaceAdds_projConfigRemoves_addsToSiblings()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			when({'configurations:Debug'}, function ()
				removeDefines 'B'
			end)
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' })
	local cfg = prj:selectAny({ configurations='Release', platforms='macOS' })
	test.isEqual({ 'B' }, cfg.defines)
end


function StateRemoveTests.workspaceAdds_projConfigRemoves_addsToSiblings_inherit()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			when({'configurations:Debug'}, function ()
				removeDefines 'B'
			end)
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' }):withInheritance()
	local cfg = prj:selectAny({ configurations='Release', platforms='macOS' }):withInheritance()
	test.isEqual({ 'A', 'B', 'C' }, cfg.defines)
end


function StateRemoveTests.workspaceAdds_globProjConfigRemoves_removesFromTarget()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		configurations { 'Debug', 'Release' }
		platforms { 'macOS', 'iOS' }
		defines { 'A', 'B', 'C' }
	end)

	when({'projects:Project2'}, function ()
		when({'configurations:Debug'}, function ()
			removeDefines 'B'
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project2' }):fromScopes(_global)
	local cfg = prj:selectAny({ configurations='Debug', platforms='macOS' })
	test.isEqual({}, cfg.defines)
end


---
-- If a value is listed in a parent scope (eg. workspace) and then removed in a child scope
-- (eg. project), that value should _not_ be listed at the parent level, and should instead
-- get added to all of the children which did _not_ remove it. This ensures that the exported
-- projects are only ever adding values to scopes, since most IDEs do not have the ability to
-- generically remove values which were previously set.
---

function StateRemoveTests.workspaceAdds_projectRemoves_ignoresUnsetValues()
	workspace('Workspace1', function ()
		projects { 'Project1', 'Project2', 'Project3' }
		defines { 'A', 'B', 'C' }

		when({'projects:Project2'}, function ()
			removeDefines { 'B', 'D' }
		end)
	end)

	local wks = _global:select({ workspaces = 'Workspace1' })
	local prj = wks:select({ projects = 'Project1' })
	test.isEqual({ 'B' }, prj.defines)
end
