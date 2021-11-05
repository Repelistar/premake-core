local xcode = require('xcode')
local xcodeproj = xcode.xcodeproj

local XcPrjExcludedSourceFileTests = test.declare('XcPrjExcludedSourceFileTests', 'xcodeproj', 'xcode')


local function _execute(fn)
	workspace('MyWorkspace', function ()
		configurations { 'Debug', 'Release' }
		project('MyProject', function ()
			fn()
		end)
	end)

	return xcodeproj.prepare(xcode.buildDom(12)
		.workspaces['MyWorkspace']
		.projects['MyProject'])
end


---
-- If no files are excluded, no value should be written.
---

function XcPrjExcludedSourceFileTests.onNoValues()
	local prj = _execute(function () end)
	xcodeproj.EXCLUDED_SOURCE_FILE_NAMES(prj.configs['Debug'])
	test.noOutput()
end


---
-- File excluded from a configuration should get listed.
---

function XcPrjExcludedSourceFileTests.onRemovedFromConfig()
	local prj = _execute(function ()
		files { 'file1.c', 'file2.c', 'file3.c' }
		when({ 'configurations:Debug' }, function ()
			removeFiles 'file2.c'
		end)
	end)

	xcodeproj.EXCLUDED_SOURCE_FILE_NAMES(prj.configs['Debug'])

	test.capture [[
EXCLUDED_SOURCE_FILE_NAMES = (
	file2.c,
);
	]]
end
