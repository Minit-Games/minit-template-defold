-- Packages the game for upload to minit.studio. The menu item in
-- editor/minit.editor_script (Project > Minit: Package for Upload) calls
-- run() and shows the result in a dialog. Anything else can call it without
-- a dialog through the editor's HTTP API, while the editor is open:
--
--   POST http://localhost:<port>/eval         port:  .internal/editor.port
--   Authorization: Bearer <token>             token: .internal/editor.token
--   body: return require("editor.minit_package").run().ok
--
-- The response holds the printed report, then "=> true" or "=> false".
--
-- Everything runs inside the editor -- nothing else to install:
--   1. checks meta.json and the title
--   2. bundles a release HTML5 build with bob, single-threaded wasm only
--   3. checks the bundle (our shell with the audio repair, no pthread wasm)
--   4. zips the bundle contents + meta.json (with the game.project title
--      added) + notices to dist/<title>.zip
--
-- dist/ is cleared on every run and the raw bundle (dist/bundle/) is deleted
-- once zipped, so dist/ only ever holds the one ZIP to upload.
--
-- Not done here: measuring whether the game is audible (it needs a real
-- browser).
--
-- Kept identical in minit-template-defold and minit-sample-defold.
--
-- After editing this file: Project > Reload Editor Scripts.

local M = {}

local SORTINGS = { highestScore = true, lowestScore = true, fastestTime = true, slowestTime = true }
local VALUE_TYPES = { string = true, number = true, boolean = true, color = true }
local TITLE_MAX = 50
local DESCRIPTION_MAX = 2500
local ZIP_MAX = 52428800
local ZIP_RECOMMENDED = 5242880
-- The titles the templates ship with: a game still called this isn't named yet.
local TEMPLATE_TITLES = { ["My Minit"] = true, ["Defold Minit Template"] = true }

-- Paths ----------------------------------------------------------------------

local function project_root()
	return (editor.external_file_attributes(".").path:gsub("[/\\]+$", ""))
end

local function join(...)
	return table.concat({ ... }, "/")
end

local function exists(path)
	return editor.external_file_attributes(path).exists
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function write(path, s)
	local f = io.open(path, "wb")
	if not f then
		return false
	end
	f:write(s)
	f:close()
	return true
end

local function size(path)
	local f = io.open(path, "rb")
	if not f then
		return 0
	end
	local n = f:seek("end")
	f:close()
	return n
end

-- Length as the backend counts it (JavaScript string length, UTF-16 units),
-- so an emoji in the title counts 2, as it does there.
local function js_length(s)
	local n = 0
	for i = 1, #s do
		local b = s:byte(i)
		if b < 0x80 or b >= 0xC0 then
			n = n + (b >= 0xF0 and 2 or 1)
		end
	end
	return n
end

-- The editor's Lua ignores the precision in "%.2f", so round by hand.
local function megabytes(bytes, decimals)
	local scale = 10 ^ decimals
	local n = math.floor(bytes / 1048576 * scale + 0.5)
	local whole, frac = math.floor(n / scale), n % scale
	if decimals == 0 then
		return ("%d MB"):format(whole)
	end
	return ("%d.%0" .. decimals .. "d MB"):format(whole, frac)
end

-- The editor's Lua (LuaJ) turns a string into Java text by decoding UTF-8 of
-- at most 3 bytes, so a 4-byte character (most emoji) arrives garbled in
-- paths and dialog text. Writing it as a surrogate pair of 3-byte sequences
-- (CESU-8) arrives intact. print() and file contents take UTF-8 as-is.
local function editor_string(s)
	return (s:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", function(c)
		local b1, b2, b3, b4 = c:byte(1, 4)
		local u = (b1 % 8) * 262144 + (b2 % 64) * 4096 + (b3 % 64) * 64 + (b4 % 64) - 65536
		local function three(v)
			return string.char(0xE0 + math.floor(v / 4096), 0x80 + math.floor(v / 64) % 64, 0x80 + v % 64)
		end
		return three(0xD800 + math.floor(u / 1024)) .. three(0xDC00 + u % 1024)
	end))
end
M.editor_string = editor_string

-- A commented-out example must not count as reading a config key.
local function strip_comments(source)
	source = source:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	return (source:gsub("%-%-[^\n]*", ""))
end

-- The title ---------------------------------------------------------------------

local function project_title(root)
	local project = read(join(root, "game.project")) or ""
	return project:match("\n%s*title%s*=%s*([^\r\n]-)%s*[\r\n]") or project:match("^%s*title%s*=%s*([^\r\n]-)%s*[\r\n]")
end

-- The ZIP is named after the title, minus emoji and what file names can't
-- hold. ASCII spelled out: the editor's %c and %s don't follow C here.
local function file_name(title)
	local name = title:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", "")
	name = name:gsub("[\1-\31<>:\"/\\|%?%*]", "")
	name = name:gsub("[ \t]+", " ")
	return (name:match("^[ %.]*(.-)[ %.]*$"))
end

local function check_title(title, fail)
	if not title or title == "" then
		fail("game.project has no title. Set your game's name in Project Settings > Title.")
	elseif TEMPLATE_TITLES[title] then
		fail(("the game is still called \"%s\". Set its name in Project Settings > Title; players see it.")
			:format(title))
	elseif js_length(title) > TITLE_MAX then
		fail(("the title in Project Settings is %d chars; the backend cuts it to %d without telling you")
			:format(js_length(title), TITLE_MAX))
	-- ASCII spelled out: the editor's %w also matches bytes of an emoji.
	elseif not title:find("[A-Za-z0-9]") then
		fail("the title in Project Settings needs at least one letter or digit (Defold names the build files after it)")
	end
end

-- The editor's json.encode turns an empty "config": [] into {} and reorders
-- keys, so the title goes into meta.json's text instead of re-encoding it.
-- ASCII control range spelled out: the editor's %c doesn't follow C here.
local function json_quote(s)
	return "\"" .. s:gsub("[\1-\31\"\\]", function(c)
		if c == "\"" then
			return "\\\""
		elseif c == "\\" then
			return "\\\\"
		end
		return ("\\u%04x"):format(c:byte())
	end) .. "\""
end

local function string_end(text, i)
	local j = i + 1
	while j <= #text do
		local c = text:sub(j, j)
		if c == "\\" then
			j = j + 2
		elseif c == "\"" then
			return j
		else
			j = j + 1
		end
	end
end

-- Start and end of the string value of a top-level key, or nil.
local function top_level_string(text, key)
	local depth, i = 0, 1
	while i <= #text do
		local c = text:sub(i, i)
		if c == "\"" then
			local j = string_end(text, i)
			if not j then
				return nil
			end
			if depth == 1 and text:find("^%s*:", j + 1) and text:sub(i + 1, j - 1) == key then
				local from = text:find("\"", j + 1, true)
				return from, string_end(text, from)
			end
			i = j + 1
		else
			if c == "{" or c == "[" then
				depth = depth + 1
			elseif c == "}" or c == "]" then
				depth = depth - 1
			end
			i = i + 1
		end
	end
end

local function with_title(text, title)
	local from, to = top_level_string(text, "title")
	if from then
		return text:sub(1, from - 1) .. json_quote(title) .. text:sub(to + 1)
	end
	local open = text:find("{", 1, true)
	return text:sub(1, open) .. "\n  \"title\": " .. json_quote(title) .. "," .. text:sub(open + 1)
end

-- meta.json ------------------------------------------------------------------

-- Returns meta.json's text when it can be packaged.
local function check_meta(root, fail, warn)
	local text = read(join(root, "meta.json"))
	if not text then
		fail("meta.json is missing. The first upload would become \"Untitled Post\".")
		return
	end
	local ok, meta = pcall(json.decode, text)
	if not ok then
		fail("meta.json is not valid JSON: " .. tostring(meta))
		return
	end
	-- Valid JSON can still be null, a string or a number.
	if type(meta) ~= "table" then
		fail("meta.json: the top level must be a JSON object")
		return
	end
	local config = meta.config
	if config ~= nil and type(config) ~= "table" then
		fail("meta.json: config must be an array")
		config = nil
	end
	config = config or {}

	for _, key in ipairs({ "schemaVersion", "resultSorting" }) do
		if meta[key] == nil then
			fail("meta.json: missing required field: " .. key)
		end
	end
	if type(meta.title) == "string" then
		-- Quoted from the text, not meta.title: decoded emoji would show garbled.
		local from, to = top_level_string(text, "title")
		warn(("meta.json has its own title %s; the upload uses the game.project title instead")
			:format(text:sub(from, to)))
	elseif meta.title ~= nil then
		fail("meta.json: remove \"title\"; the title comes from Project Settings > Title")
	end

	local todo = {}
	for key, value in pairs(meta) do
		if type(value) == "string" and value:match("^%s*TODO") then
			todo[#todo + 1] = key
		end
	end
	for _, c in ipairs(config) do
		if type(c) == "table" and type(c.description) == "string" and c.description:match("^%s*TODO") then
			todo[#todo + 1] = ("config[\"%s\"].description"):format(tostring(c.key))
		end
	end
	table.sort(todo)
	for _, key in ipairs(todo) do
		fail("meta.json: " .. key .. " still starts with TODO; players would see it")
	end

	-- The texts are recommended, not required: one note when any is empty.
	local parts, missing = {}, false
	for _, key in ipairs({ "controls", "logic", "description" }) do
		local value = meta[key]
		if value ~= nil and type(value) ~= "string" then
			fail(("meta.json: %s must be a string"):format(key))
		elseif value == nil or not value:find("[^ \t\r\n]") then
			missing = true
		else
			parts[#parts + 1] = value
		end
	end
	if missing then
		warn("Recommended: add controls, game logic and a description to meta.json. Players see Controls and "
			.. "Game Logic under How to play (the (i) button under the game) and the description behind Show more; "
			.. "minit.studio shows '-' until you add them.")
	end
	local composed = js_length(table.concat(parts, "\n\n"))
	if composed > DESCRIPTION_MAX then
		fail(("meta.json: controls + logic + description is %d chars; over the %d limit minit.studio trims the "
			.. "description first, then game logic, then controls. See "
			.. "https://minit.studio/docs/limits-and-constraints"):format(composed, DESCRIPTION_MAX))
	elseif composed > DESCRIPTION_MAX - 100 then
		warn(("meta.json: controls + logic + description is %d chars, close to the %d limit; over it minit.studio "
			.. "trims the description first, then game logic, then controls"):format(composed, DESCRIPTION_MAX))
	end
	if meta.resultSorting ~= nil and not SORTINGS[meta.resultSorting] then
		fail(("meta.json: resultSorting \"%s\" is not one of highestScore, lowestScore, fastestTime, slowestTime")
			:format(tostring(meta.resultSorting)))
	end

	local declared = {}
	for _, c in ipairs(config) do
		local at = ("config[\"%s\"]"):format(type(c) == "table" and tostring(c.key) or "?")
		if type(c) ~= "table" then
			fail("meta.json: a config entry must be an object")
		elseif not c.key then
			fail("meta.json: a config entry has no key")
		else
			if declared[c.key] then
				fail("meta.json: " .. at .. " is declared twice")
			end
			declared[c.key] = true
			if c.key == "userData" then
				fail("meta.json: " .. at .. " uses the reserved key \"userData\"")
			end
			if not VALUE_TYPES[c.valueType] then
				fail(("meta.json: %s has valueType \"%s\""):format(at, tostring(c.valueType)))
			end
			local t = type(c.value)
			if c.value == nil then
				fail("meta.json: " .. at .. " has no default value")
			elseif (c.valueType == "number" and t ~= "number")
				or (c.valueType == "boolean" and t ~= "boolean")
				or ((c.valueType == "string" or c.valueType == "color") and t ~= "string") then
				fail(("meta.json: %s default should be a %s, got %s"):format(at, c.valueType, t))
			end
			if c.valueType == "number" and t == "number" then
				if c.min ~= nil and c.value < c.min then
					fail(("meta.json: %s default %s is below min %s"):format(at, c.value, c.min))
				end
				if c.max ~= nil and c.value > c.max then
					fail(("meta.json: %s default %s is above max %s"):format(at, c.value, c.max))
				end
			end
			if type(c.range) == "table" then
				local found = false
				for _, v in ipairs(c.range) do
					found = found or v == c.value
				end
				if not found then
					fail(("meta.json: %s default \"%s\" is not in its range"):format(at, tostring(c.value)))
				end
			end
			if not c.description then
				warn("meta.json: " .. at .. " has no description; players configuring a post see nothing")
			end
		end
	end

	-- A key in only one place is silently ignored at runtime.
	local source = strip_comments(read(join(root, "main", "game.script")) or "")
	local used = {}
	for key in source:gmatch("get_config_value%(%s*\"([^\"]+)\"") do
		used[key] = true
		if not declared[key] then
			fail(("meta.json: the game reads config \"%s\" but meta.json does not declare it"):format(key))
		end
	end
	for key in pairs(declared) do
		if not used[key] then
			fail(("meta.json: declares config \"%s\" but main/game.script never reads it"):format(key))
		end
	end
	return text
end

-- Bundle ---------------------------------------------------------------------

local function check_bundle(out, fail)
	local html = read(join(out, "index.html")) or ""
	-- Defold names the engine files after the title; the page says how.
	local exe = html:match("EngineLoader%.load%(%s*\"canvas\"%s*,%s*\"([^\"]+)\"")
	if not exe then
		fail("bundle: index.html does not load the engine (check [html5] htmlfile in game.project)")
		return
	end
	for _, name in ipairs({ "index.html", "dmloader.js", exe .. ".wasm", exe .. "_wasm.js", "archive" }) do
		if not exists(join(out, name)) then
			fail("bundle: missing " .. name)
		end
	end
	-- A pthread build only boots on a cross-origin-isolated page, which the
	-- Minit host does not serve.
	if exists(join(out, exe .. "_pthread.wasm")) then
		fail("bundle: a thread-support (pthread) wasm is present; the game would not start in the app")
	end
	if not html:find("Minit host shell", 1, true) then
		fail("bundle: index.html is not the Minit shell (check [html5] htmlfile in game.project)")
	end
	if not html:find("DROP-8164", 1, true) or not html:find("minit-audio", 1, true) then
		fail("bundle: index.html has lost the audio repair; the game would be silent in the app")
	end
	if html:find("localStorage", 1, true) or html:find("sessionStorage", 1, true) then
		fail("bundle: index.html touches web storage, which the platform forbids")
	end
end

-- Run ------------------------------------------------------------------------

-- Returns { ok, heading, lines, text, dist }; prints the same report.
function M.run()
	editor.save()
	local root = project_root()
	local problems, notes = {}, {}
	local fail = function(m) problems[#problems + 1] = "FAIL: " .. m end
	local warn = function(m) notes[#notes + 1] = "note: " .. m end
	local function result(ok, heading, lines, dist)
		if not ok and #notes > 0 then
			-- A failure still shows the notes; on success they are already in lines.
			lines[#lines + 1] = ""
			for _, n in ipairs(notes) do
				lines[#lines + 1] = n
			end
		end
		local text = heading .. "\n\n" .. table.concat(lines, "\n")
		print(text)
		return { ok = ok, heading = heading, lines = lines, text = text, dist = dist }
	end

	print("Minit: checking meta.json and the title")
	local meta_text = check_meta(root, fail, warn)
	local title = project_title(root)
	check_title(title, fail)
	if #problems > 0 then
		return result(false, "Minit: packaging FAILED - nothing was built", problems)
	end

	-- Checked on the text: the editor's json.decode returns emoji in a
	-- different byte form (CESU-8), so a decoded title never equals it.
	local upload_meta = with_title(meta_text, title)
	local from, to = top_level_string(upload_meta, "title")
	if not pcall(json.decode, upload_meta) or not from
		or upload_meta:sub(from, to) ~= json_quote(title) then
		fail("could not add the title to meta.json; please report this with your meta.json")
		return result(false, "Minit: packaging FAILED - nothing was built", problems)
	end

	-- The raw bundle is deleted once zipped, so dist/ only ever holds the
	-- upload. (bob refuses to bundle into build/.)
	local dist = join(root, "dist")
	local bundle = join(dist, "bundle")
	local out = join(bundle, editor_string(title))
	local zip_name = file_name(title) .. ".zip"
	local zip_path = join(dist, zip_name)

	print("Minit: bundling release HTML5 (wasm-web) - this takes a moment")
	editor.delete_directory("/dist")
	local built, err = pcall(editor.bob, {
		platform = "wasm-web",
		architectures = "wasm-web",
		variant = "release",
		archive = true,
		output = "build/minit",
		bundle_output = bundle,
	}, "build", "bundle")
	if not built then
		return result(false, "Minit: packaging FAILED - the build did not finish", {
			"FAIL: bob stopped: " .. tostring(err),
			"",
			"The build errors are in the Console pane.",
			"If it mentions a missing library: Project > Fetch Libraries, then try again.",
		})
	end

	check_bundle(out, fail)
	if #problems > 0 then
		return result(false, "Minit: packaging FAILED - no ZIP was written", problems)
	end

	local meta_path = join(root, "build", "minit-upload-meta.json")
	if not write(meta_path, upload_meta) then
		fail("could not write " .. meta_path)
		return result(false, "Minit: packaging FAILED - no ZIP was written", problems)
	end

	print("Minit: writing " .. zip_path)
	zip.pack(zip_path, {
		{ out, "." },
		{ meta_path, "meta.json" },
		{ join(root, "THIRD-PARTY-NOTICES.txt"), "THIRD-PARTY-NOTICES.txt" },
	})
	editor.delete_directory("/dist/bundle")

	local bytes = size(zip_path)
	if bytes > ZIP_MAX then
		os.remove(zip_path)
		fail(("the ZIP is %s, over the 50 MB upload limit; it was deleted"):format(megabytes(bytes, 1)))
		return result(false, "Minit: packaging FAILED", problems)
	elseif bytes > ZIP_RECOMMENDED then
		warn(("the ZIP is %s, over the recommended 5 MB"):format(megabytes(bytes, 1)))
	end

	local lines = {
		("Ready to upload: dist/%s (%s)"):format(zip_name, megabytes(bytes, 2)),
		"",
		("Upload title: \"%s\", taken from Project Settings > Title."):format(title),
		"minit.studio uses it on the first upload only; after that, rename the game there.",
		"",
		"Release build, single-threaded wasm, meta.json included.",
		"Upload it at https://minit.studio",
		"",
		"Not checked here: whether the game is audible in the app.",
	}
	for _, n in ipairs(notes) do
		lines[#lines + 1] = n
	end
	return result(true, "Minit: ready to upload", lines, dist)
end

return M
