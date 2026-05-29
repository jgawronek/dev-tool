# Tool Stub Specs

Lightweight specs derived from screenshots to guide stub implementations. Each tool must render the listed UI and wire no-op actions where logic is not yet required.

## unix_time_converter
Layout: multi-section form (single column with right-side metrics)
UI:
- Input row: text field + buttons Now, Clipboard, Clear, Gear
- Input format dropdown (Unix time seconds since epoch)
- Output grid: Local, UTC (ISO 8601), Relative, Unix time, Day of year, Week of year, Is leap year?, Other formats (local), each with copy button
- Other timezones row: dropdown + Add button
Behavior: populate outputs from input; stubbed conversions acceptable except for main Unix seconds/ms/ISO as required later.

## json_format_validate
Layout: split editors
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear, format dropdown JSON
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: format/validate JSON; errors inline.

## base64_string_encode_decode
Layout: vertical editors
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Mode radios: Encode / Decode
- Output toolbar: Copy, Use as input
Behavior: base64 encode/decode.

## base64_image_encode_decode
Layout: split (string left, image preview right)
UI:
- String toolbar: Clipboard, Sample, Clear, Copy
- Image toolbar: Clipboard, Load File..., Clear, Save, Copy
- Demo pill
Behavior: stub OK; wire file picker and preview placeholder.

## jwt_debugger
Layout: split (input left, stacked output right)
UI:
- Input toolbar: Clipboard, Sample, Clear, Gear, algorithm dropdown (HS256), Copy
- Output sections: Header + Copy, Payload + Copy
- Signature section: formula, secret input
- Status bar: Signature Verified
Behavior: stub parsing OK; header/payload can be placeholders if needed.

## regexp_tester
Layout: main text + bottom output + right matches list
UI:
- RegExp row: input + Clipboard, Sample, Clear, Gear
- Text row: Clipboard
- Match navigation: count + arrows
- Cheat Sheet button
- Output row: format input, Copy, search matches input
Behavior: highlight matches; stub list OK.

## url_encode_decode
Layout: vertical editors
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Mode radios: Encode / Decode
- Output toolbar: Copy, Use as input
Behavior: encode/decode.

## url_parser
Layout: split (input left, outputs right)
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Field/Value table
- Query string output + Copy
Behavior: parse URL; stub table OK.

## html_entity_encode_decode
Layout: vertical editors
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Mode radios: Encode / Decode
- Output toolbar: Copy, Use as input
Behavior: encode/decode.

## backslash_escape_unescape
Layout: vertical editors
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Mode radios: Escape / Unescape
- Output toolbar: Copy, Use as input
Behavior: escape/unescape.

## uuid_ulid_generate_decode
Layout: split (details left, generator right)
UI:
- Input toolbar: Clipboard, Sample, Clear, Gear
- Left fields with labels + copy buttons
- Right: version dropdown (UUID v1), count field, Generate, Copy, Clear, lowercased checkbox, output list
Behavior: stub OK; generation can be placeholder.

## html_preview
Layout: split (code left, preview right)
UI:
- Input toolbar: Clipboard, Sample, Clear, Gear, Format... dropdown
- Output toolbar: Open in Browser, Reload
Behavior: preview can be stubbed.

## text_diff_checker
Layout: split inputs + bottom diff output
UI:
- Input 1: Clipboard, Sample, Clear
- Input 2: Clipboard, Clear, Swap Inputs
- Diff mode radios: Characters / Words / Lines
- Output toolbar: format dropdown (Formatted Text), Copy, nav arrows with count
Behavior: diff can be stubbed.

## yaml_to_json
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: parse YAML to JSON.

## json_to_yaml
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: Copy
Behavior: parse JSON to YAML.

## number_base_converter
Layout: multi-row form
UI:
- Rows for Base 2/8/10/16: text field, Clipboard, Clear, Copy
- Select base row: dropdown (36), Clipboard, Sample, Clear, text field, Copy
Behavior: auto-calc across rows.

## html_beautify_minify
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: stub OK.

## css_beautify_minify
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: stub OK.

## js_beautify_minify
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: stub OK.

## erb_beautify_minify
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: stub OK.

## less_beautify_minify
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: stub OK.

## scss_beautify_minify
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: stub OK.

## xml_beautify_minify
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: Include Comments dropdown, indent dropdown (2 spaces), Copy
Behavior: stub OK.

## lorem_ipsum_generator
Layout: left presets + right editor
UI:
- Preset buttons: Paragraph, Sentence, Word, Title, First name, Last name, Full name, Email, URL, Short tweet, Long tweet
- Right toolbar: count dropdown (x1), Append dropdown, Clear, Copy
Behavior: stub OK; can output sample text.

## qr_code_reader_generator
Layout: split (content left, QR right)
UI:
- Content toolbar: Clipboard, Sample, Clear, Select Template dropdown
- Read QR Code: File..., Clipboard
- Add Watermark..., Add Icon...
- QR preview, Error Correction dropdown, Save, Copy image
Behavior: stub OK; QR preview can be placeholder.

## string_inspector
Layout: split (input left, stats right)
UI:
- Input toolbar: Clipboard, Sample, Clear
- Stats sections: Count, Character, Selection
- Filter button, Case sensitive checkbox, word distribution list
Behavior: live stats; stub OK.

## mime_types
Layout: searchable table
UI:
- Search field (name/type/extension/details)
- Sortable columns: Name, MIME Type / Internet Media Type, File Extension, More Details
- Row count label
Behavior: filter and sort table entries.

## json_to_csv
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: Copy
Behavior: stub OK.

## csv_to_json
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: indent dropdown (2 spaces), Copy
Behavior: CSV to JSON (core tool).

## hash_generator
Layout: split (input left, hash list right)
UI:
- Input toolbar: Clipboard, Sample, Load file..., Clear
- Byte count label
- Lowercased checkbox
- Hash fields with copy buttons: MD2, MD4, MD5, SHA1, SHA224, SHA256, SHA384, SHA512, Keccak-256
Behavior: stub OK.

## html_to_jsx
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: Copy
Behavior: stub OK.

## markdown_preview
Layout: split
UI:
- Input toolbar: Clipboard, Sample, Clear, Cheatsheet
- Output toolbar: Open in Browser, Preview dropdown
Behavior: stub OK.

## sql_formatter
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, dialect dropdown (General SQL)
- Output toolbar: case dropdown (Uppercase), indent dropdown (2 spaces), Copy
Behavior: stub OK.

## string_case_converter
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: case dropdown (camelCase), Copy
Behavior: stub OK.

## cron_job_parser
Layout: single form
UI:
- Toolbar: Clipboard, Sample, Clear, Copy
- Cron input field
- Examples dropdown (Pick an example...)
- Parsed fields list + next executions list
Behavior: stub OK.

## color_converter
Layout: split (inputs left, presets right)
UI:
- Input toolbar: Clipboard, Sample, Clear
- Color swatch
- Fields with Copy: Hex, Hex with alpha, RGB, RGBA, HSL, HSLA, HSB/HSV, HWB, CMYK
- Right tabs: Code Presets, View Source, Variables
Behavior: stub OK.

## php_to_json
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: Copy
- Output message: Scripts Runtime for this tool is missing (php)
Behavior: show runtime missing state until scripting config is set.

## json_to_php
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: Copy
- Output message: Scripts Runtime for this tool is missing (php)
Behavior: show runtime missing state.

## php_serializer
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: Copy
- Output message: Scripts Runtime for this tool is missing (php)
Behavior: show runtime missing state.

## php_unserializer
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: Copy
- Output message: Scripts Runtime for this tool is missing (php)
Behavior: show runtime missing state.

## random_string_generator
Layout: split (controls left, output right)
UI:
- Presets dropdown + Sample
- Seed field + refresh
- Sliders + numeric fields: uppercased, lowercased, symbols, digits, words
- Separator dropdown, Separating Group Size slider + field
- Custom Character Set slider + textarea
- Output toolbar: Colors toggle, count dropdown (x10), Copy
Behavior: stub OK.

## svg_to_css
Layout: split + preview
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: format dropdown (URL Encoded), Copy
- Preview pane
Behavior: stub OK.

## curl_to_code
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: language dropdown (NodeJS / Fetch), Copy
Behavior: stub OK.

## json_to_code
Layout: 3-column (input, output, options)
UI:
- Input toolbar: Clipboard, Sample, Clear
- Input format dropdown (JSON)
- Output toolbar: language dropdown (Swift), Copy
- Options panel: tabs (Language/Other), checkboxes, Reset to Defaults
Behavior: stub OK.

## certificate_decoder_x509
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear, Gear
- Output toolbar: Copy
- Output error block
Behavior: stub OK.

## hex_to_ascii
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: Copy
Behavior: hex to ASCII (core tool).

## ascii_to_hex
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: Copy
Behavior: ASCII to hex (core tool).

## line_sort_dedupe
Layout: split
UI:
- Input toolbar: Run, Clipboard, Sample, Clear
- Output toolbar: sort dropdown (A -> Z (Text)), duplicate mode dropdown (With Duplicates), Copy
Behavior: stub OK.

## preferences_general
Layout: preferences tabs + list
UI:
- Tabs: General, Hotkeys, Appearance, Integrations, Scripting, Updates, License
- Checkboxes: hide main window at launch, confirm quit, share analytics, write debug logs
- Buttons: Open logs directory, Stored preferences location + Open
Behavior: persist toggles.

## preferences_appearance
Layout: preferences tabs + list
UI:
- Tabs: General, Hotkeys, Appearance, Integrations, Scripting, Updates, License
- Checkboxes: Show Status Bar icon, Show Dock icon
- Theme dropdown (System)
Behavior: persist toggles.

## preferences_scripting
Layout: preferences tabs + segmented control
UI:
- Tabs: General, Hotkeys, Appearance, Integrations, Scripting, Updates, License
- Segmented control: PHP | Open SSL | Others
- PHP panel: Default command path dropdown (No Usable PHP Runtime), Add New Path..., Remove
- Text block explaining safe mode
- Multiline whitelist field with default values
Behavior: persist settings; file picker for Add New Path.

## auth_totp
Layout: card grid + add dialog
UI:
- Card grid with TOTP code, next code, label, menu icon
- Add card with plus icon
- Add dialog: Secret key, Application name, color swatches, Add button, Scan QR link
Behavior: generate TOTP codes in realtime (30s step), allow adding entries.
