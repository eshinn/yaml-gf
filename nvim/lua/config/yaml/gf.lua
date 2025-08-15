local M = {}

-- Parse JSON Pointer according to RFC 6901
local function parse_json_pointer(pointer)
  if pointer == "" then
    return {}
  end

  -- Handle case where pointer doesn't start with /
  if not pointer:match("^/") then
    pointer = "/" .. pointer
  end

  -- Remove leading slash and split by slash
  local segments = vim.split(pointer:sub(2), "/")

  -- Unescape special characters
  local function unescape_segment(segment)
    return segment:gsub("~1", "/"):gsub("~0", "~")
  end

  local result = {}
  for _, segment in ipairs(segments) do
    result[#result + 1] = unescape_segment(segment)
  end

  return result
end


-- Enhanced text-based search that better handles arrays and nested structures
local function find_yaml_target_text_based(path_segments)
  vim.cmd("normal! gg") -- Go to top of file

  local current_line = 1
  local current_indent = -1

  for i, segment in ipairs(path_segments) do
    local found = false

    -- Determine if this should be treated as an array index or object key
    -- In YAML/OpenAPI context, numeric segments are usually object keys (like HTTP status codes)
    -- unless we're clearly in an array context (like "items", "examples", etc.)
    local is_array_context = false
    if i > 1 then
      local previous_segment = path_segments[i - 1]
      -- Common array-indicating keys in OpenAPI/YAML
      local array_keys = {
        "items",
        "examples",
        "enum",
        "required",
        "tags",
        "servers",
        "parameters",
        "requestBodies",
        "headers",
        "links",
        "callbacks",
      }
      for _, array_key in ipairs(array_keys) do
        if previous_segment == array_key then
          is_array_context = true
          break
        end
      end
    end

    local array_index = is_array_context and tonumber(segment) or nil

    if array_index ~= nil then
      -- Handle array index: find the Nth array item
      local items_found = 0
      local target_indent = current_indent + 2 -- Typical YAML indentation for array items

      for line_num = current_line, vim.fn.line("$") do
        local line = vim.fn.getline(line_num)

        -- Skip empty lines and comments
        if line:match("^%s*$") or line:match("^%s*#") then
          goto continue_array
        end

        local indent_match = line:match("^(%s*)")
        local indent_level = #indent_match

        -- Stop if we've gone past the expected indentation level
        if indent_level < target_indent then
          break
        end

        -- Check if this is an array item at the right level
        if indent_level == target_indent and line:match("^%s*-") then
          if items_found == array_index then
            vim.fn.cursor(line_num, 1)
            current_line = line_num + 1
            current_indent = indent_level
            found = true
            break
          end
          items_found = items_found + 1
        end

        ::continue_array::
      end
    else
      -- Handle object key
      local target_indent = i == 1 and -1 or current_indent + 2

      for line_num = current_line, vim.fn.line("$") do
        local line = vim.fn.getline(line_num)

        -- Skip empty lines and comments
        if line:match("^%s*$") or line:match("^%s*#") then
          goto continue_key
        end

        local indent_match = line:match("^(%s*)")
        local indent_level = #indent_match

        -- For nested keys, stop if we hit same or lesser indentation than parent
        -- But skip the very first line we're checking (current_line)
        if i > 1 and line_num > current_line and indent_level <= current_indent then
          break
        end

        -- Check if this line contains our key
        local key_patterns = {
          "^%s*" .. vim.pesc(segment) .. "%s*:", -- unquoted key
          '^%s*"' .. vim.pesc(segment) .. '"%s*:', -- double-quoted key
          "^%s*'" .. vim.pesc(segment) .. "'%s*:", -- single-quoted key
        }

        local matched = false
        for _, pattern in ipairs(key_patterns) do
          if line:match(pattern) then
            matched = true
            break
          end
        end

        if matched then
          -- Accept this key if it's at the right level
          if i == 1 or (target_indent >= 0 and indent_level >= target_indent) then
            vim.fn.cursor(line_num, 1)
            current_line = line_num + 1
            current_indent = indent_level
            found = true
            break
          end
        end

        ::continue_key::
      end
    end

    if not found then
      -- Fallback: global search for keys only
      if not array_index then
        vim.cmd("normal! gg")
        if vim.fn.search(vim.pesc(segment) .. ":", "W") > 0 then
          found = true
        end
      end

      if not found then
        break -- Stop if we can't find the segment
      end
    end
  end
end

-- Main search function
local function perform_fragment_search(json_pointer)
  local path_segments = parse_json_pointer(json_pointer)
  find_yaml_target_text_based(path_segments)
end

function M.yaml_include_expr(fname)
  -- Check if the string under cursor looks like a $ref with #fragment.
  local parts = vim.split(fname, "#")
  if #parts < 2 then
    -- No fragment: treat as normal file path.
    return fname
  end

  local file_path = parts[1]
  local fragment = parts[2]

  -- Schedule the search to happen after the file is opened
  vim.schedule(function()
    -- Wait a bit for file to be fully loaded
    vim.defer_fn(function()
      perform_fragment_search(fragment)
    end, 25) -- Reduced delay to minimize cursor flash
  end)

  -- Return the file path for gf to open.
  return file_path
end

return M
