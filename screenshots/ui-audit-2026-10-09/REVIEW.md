# DevUtils screenshot review — 9 October 2026

## Capture coverage

- 76 of 76 registered tools captured and visually reviewed.
- App overview and Documentation captured: 78 original PNG screenshots total.
- Release app at commit `225ea38`, existing light appearance, one consistent 2560 × 1640 pixel window.
- Current/initial tool states captured. Some pages contain examples or placeholder text; this is not a controlled comparison of successful output.
- No network requests, scans, downloads, or local-server starts were triggered for the review.
- This review covers the visible state of each page. It does not prove keyboard accessibility, calculations, every mode, loading/error behavior, scrolling content, dark appearance, or narrow-window layout.
- The purple sharing indicator at the top is macOS screen-sharing chrome, not a DevUtils design issue.

Open [index.html](index.html) for the searchable gallery, full-size images, priorities, and findings. All original images remain unedited. Review sheets are cropped comparison aids.

## Priorities

P1 = misleading capability/state or a clipped important control. P2 = substantial consistency or layout problem. P3 = smaller polish or clarity improvement. OK = no material page-specific visual inconsistency observed in the captured state; shared issues may still apply.

## What is working

The page heading, favorite star on the left, subtitle, tool badge, panel surface, and top-right Load sample location are mostly consistent. Paste icons, Clear controls, and editor overflow menus are absent in the captured pages. JWT, Base64 String, HTML Entity, Backslash Escape, String Case, HTML to JSX, PHP Serializer/Unserializer, and preview pages are useful visual references.

## Fix these first

1. **Keep primary header actions visible:** JS to TS clips Copy; PlantUML clips Fit and hides Export. Shared header sizing also truncates Format and Generated strings unnecessarily.
2. **Make capability labels truthful:** AntiBot Detection fetches URLs but says Offline tool. QR says Reader/Generator without a visible reader. Offline LLM needs to distinguish local inference from online downloads.
3. **Repair Random String Generator's interaction model:** align result/options panels, replace the generation-as-Load-sample action with an explicit Generate action, and implement/remove unwired controls. Source confirms the permanent disabled Colors checkbox and unwired settings.
4. **Flatten repeated panel structures:** UUID repeats Generated IDs and nests Input; Subdomain Takeover nests Takeover details inside Details. Preserve one header per logical panel.
5. **Standardize form controls:** choose one label style, height, spacing, and placement. CSV, Password Generator, Semver, Hash Verifier, and Date Difference demonstrate the current differences.
6. **Give empty states a common meaning:** clearly distinguish guidance, example placeholders, waiting for input, successful empty results, and no matches. Do not display measured scores before scans.
7. **Keep the active workspace tab visible:** the capture set shows many selected tools whose tab is outside the visible strip.

## Suggested design rules

- Use JWT's framed header/body treatment; avoid another framed editor inside a panel for the same job.
- Keep result headers level on side-by-side pages; put settings above both panels when they affect both.
- Use shared compact controls with persistent labels. Placeholder text is an example, not a field label.
- Reserve space for Copy/Export before placing secondary settings into a header. Wrap secondary settings into a named toolbar when space is insufficient.
- Keep input on the left by default. Leetspeak is currently reversed by explicit user request, so changing it requires a deliberate decision.
- Keep mode controls in one consistent location per tool family, and keep Load sample in the page heading when present.
- Use content-sized metadata/forms, spacious editors for actual text, and compact readable tables for repeated result values.
- Keep settings and result language understandable: replace jargon-only labels and move implementation attribution into docs.

## Every tool

Tool counts: 6 P1, 36 P2, 20 P3, 14 OK.

### App overview — P2

[View screenshot](00-app-overview.png)

**Observed:** The wide sidebar occupies about one fifth of the window. The tab strip shows a fixed set of earlier tabs while the active Date/Time tool is not visibly identified in it. The right edge cuts off a tab title.

**Suggested change:** Ensure the active tab scrolls into view; make overflow discoverable and keep sidebar sizing deliberate.

### Unix Time Converter — P2

[View screenshot](01-unix_time_converter.png)

**Observed:** The input label, Now button, format selector, and actual input occupy separate rows; the label is distant from its field. The two output cards stop well above the page bottom.

**Suggested change:** Group timestamp input and format in one labeled panel; use the same output sizing rule as other tools.

### JSON Format/Validate — P2

[View screenshot](02-json_format_validate.png)

**Observed:** A separate instruction banner and an unframed Operation row add two layers above otherwise aligned editors. Other formatter pages put these controls in a panel header.

**Suggested change:** Use one consistent formatter toolbar and keep guidance in the input empty state.

### Base64 String Encode/Decode — OK

[View screenshot](03-base64_string_encode_decode.png)

**Observed:** Aligned input and output panels; mode controls and output reuse/copy actions follow the shared pattern.

**Suggested change:** Keep this layout as a reference for simple text converters.

### Base64 Image Encode/Decode — P2

[View screenshot](04-base64_image_encode_decode.png)

**Observed:** The empty string editor has no visible hint; the image panel says only Image preview (base64 only). The next action for an image file is unclear.

**Suggested change:** Add concise input guidance and a labeled Choose image action if file input is supported.

### Compress / Decompress — P3

[View screenshot](05-compression_codecs.png)

**Observed:** Panels and controls align. The subtitle uses the vague phrase gzip and friends; compression mode is in a separate toolbar unlike neighboring encoders.

**Suggested change:** Name supported formats clearly and standardize mode-control placement across converters.

### Base32/58/62/85/Bech32 — P2

[View screenshot](06-base_encodings.png)

**Observed:** The encoding format selector is in the output header while Encode/Decode is in the input header. The title includes Base85 but the subtitle omits it.

**Suggested change:** Keep conversion settings together and make the subtitle match the supported formats.

### JWT Debugger — OK

[View screenshot](07-jwt_debugger.png)

**Observed:** Token, Header, Payload, and Token details use aligned framed headers. The empty verification state explains the secret requirement.

**Suggested change:** Use this as the panel styling reference. Empty-token status could say No token loaded before saying Not verified.

### Auth TOTP — P2

[View screenshot](08-auth_totp.png)

**Observed:** Accounts use raised cards inside a large panel, unlike the flatter tool surfaces. The add-account tile contains only a plus. Current, Next, and countdown text are very small.

**Suggested change:** Label Add account and use clear code/countdown hierarchy with the shared surface treatment.

### RegExp Tester — P3

[View screenshot](09-regexp_tester.png)

**Observed:** Expression and output format controls align. The matches panel has a centered empty state, while formatted output uses editor placeholder text. The output format has no visible syntax help.

**Suggested change:** Add a short example for $0, capture groups, and newline formatting; make the two output empty states explain the same next step.

### URL Encode/Decode — OK

[View screenshot](10-url_encode_decode.png)

**Observed:** Aligned editors, mode toggle, output reuse, and copy follow the shared converter pattern.

**Suggested change:** Keep the layout; consider showing which kind of URL content is encoded in the mode help.

### URL Parser — OK

[View screenshot](11-url_parser.png)

**Observed:** Compact URL panel and aligned details/parameters and request/response rows make good use of space. The response empty state points to Send.

**Suggested change:** Keep this layout as a reference for request tools.

### Subdomain Finder — P2

[View screenshot](12-subdomain_finder.png)

**Observed:** Target appears in the settings row while the domain entry sits below it. Find known is vague for a primary action.

**Suggested change:** Attach Domain or Organization directly to the input and use Find subdomains as the action label.

### Subdomain Takeover Check — P2

[View screenshot](13-subdomain_takeover.png)

**Observed:** Details contains another Takeover details panel plus a separate Result details label; repeated frames and headings reduce useful space.

**Suggested change:** Use one Details header with view tabs and one content surface.

### Subnet Calculator — P3

[View screenshot](14-subnet_calculator.png)

**Observed:** Aligned editor pair. IPv4 and IPv6 appears as a disabled-looking header chip while the subtitle describes only IPv4.

**Suggested change:** Present supported input types as help text and update the subtitle to include IPv6.

### Port Scanner — P2

[View screenshot](15-port_scanner.png)

**Observed:** Stop wraps onto a row alone. Summary badges push the left result area below Port details; the two result content starts do not line up. Score 100 / A is already shown with zero scanned ports.

**Suggested change:** Keep Scan/Recon/Stop together, put summary above both results, and show an unmeasured score before a scan.

### Network Scanner — P2

[View screenshot](16-network_scanner.png)

**Observed:** Network target, port list, scan actions, timeout, concurrency, and scan types span multiple rows without clear grouping. The port field has no visible label.

**Suggested change:** Group Target, Ports, and Scan options with persistent labels and stable action placement.

### Local Server — P2

[View screenshot](17-local_server.png)

**Observed:** Choose Folder and Start sit far right, separated from the folder status and port on the left. Start appears available while No folder selected is shown.

**Suggested change:** Keep folder selection beside its status and make the required first step clear before Start.

### Firewall Fingerprint — P3

[View screenshot](18-firewall_fingerprint.png)

**Observed:** Result and detail panels align. The settings row mixes bold Target with smaller Timeout labels and small action buttons.

**Suggested change:** Reuse a consistent settings-label weight and field height.

### HTML Entity Encode/Decode — OK

[View screenshot](19-html_entity_encode_decode.png)

**Observed:** Aligned editors, shared mode toggle, and output reuse/copy pattern.

**Suggested change:** Keep as a simple converter reference.

### Backslash Escape/Unescape — OK

[View screenshot](20-backslash_escape_unescape.png)

**Observed:** Aligned editor pair and a clear Escape/Unescape toggle.

**Suggested change:** Keep the shared converter pattern.

### UUID/ULID Generate/Decode — P2

[View screenshot](21-uuid_ulid_generate_decode.png)

**Observed:** Input is nested inside Inspect and generate, producing two headers on the left. Generated IDs is repeated above and inside the output panel. Output begins lower than the left panel. Count is unlabeled.

**Suggested change:** Use separate aligned Inspect and Generate sections, remove duplicate headings, and label Count.

### HTML Preview — OK

[View screenshot](22-html_preview.png)

**Observed:** Input and Preview headers align and the empty preview says what to do next.

**Suggested change:** Keep the shared preview structure.

### Text Diff Checker — P2

[View screenshot](23-text_diff_checker.png)

**Observed:** Diff controls form a centered strip between panels with a bare zero between arrows. Empty inputs lack visible prompts.

**Suggested change:** Label change navigation and add guidance to both empty inputs; put diff settings in a clearly named toolbar.

### YAML ↔ JSON — P3

[View screenshot](24-yaml_json_converter.png)

**Observed:** Editors align. The example-like input hint and [] output can look like a conversion has already happened.

**Suggested change:** Use instructional input guidance and an explicit waiting-for-input output state.

### Number Base Converter — P2

[View screenshot](25-number_base_converter.png)

**Observed:** Input controls show Auto, 32, and Unsigned without labels for the bit width and signedness. Results use many individually bordered rows. No Load sample action is shown.

**Suggested change:** Label Base, Bit width, and Signedness; use a compact result table and a consistent example action.

### HTML Beautify/Minify — P3

[View screenshot](26-html_beautify_minify.png)

**Observed:** Aligned panels. Format controls occupy the output header while JSON uses a page-level Operation row.

**Suggested change:** Unify the formatter control location and naming across languages.

### CSS Beautify/Minify — P3

[View screenshot](27-css_beautify_minify.png)

**Observed:** Aligned panels and a compact source-file icon. A Format label is shown here but omitted in RB/XML formatting pages.

**Suggested change:** Use the same formatter labels and control placement across languages.

### JS/TS Beautify/Minify — P2

[View screenshot](28-js_beautify_minify.png)

**Observed:** The output header truncates its Format label despite a large overall window. Formatting options compete with the panel title.

**Suggested change:** Move options to a shared toolbar or preserve enough header width for full labels and Copy.

### RB Beautify/Minify — P3

[View screenshot](29-rb_beautify_minify.png)

**Observed:** Aligned panels. The input hint says RB although the subtitle says Ruby; output formatting controls have no Format label.

**Suggested change:** Use Ruby in user-facing copy and unify formatter labels.

### XML Beautify/Minify — P3

[View screenshot](30-xml_beautify_minify.png)

**Observed:** Aligned panels; output formatting controls use values alone, unlike the HTML/CSS pages.

**Suggested change:** Use the same formatter settings layout and labels across languages.

### Lorem Ipsum Generator — P3

[View screenshot](31-lorem_ipsum_generator.png)

**Observed:** Panel headers are now aligned. Count and Mode labels are lighter/smaller than the group headings; the generator has no page-level sample action.

**Suggested change:** Keep aligned panels and clarify that category buttons generate content; use a consistent Count label style.

### Password Generator — P2

[View screenshot](32-password_generator.png)

**Observed:** The options use floating Count and Length labels beside an inline Style label. Result Copy is a text button while other tool outputs use an icon. Large blank area follows the short form.

**Suggested change:** Use the shared field labeling and output-copy pattern; retain content-sized panels rather than stretching them.

### QR Code Reader/Generator — P1

[View screenshot](33-qr_code_reader_generator.png)

**Observed:** The title and subtitle promise a QR reader, but only content generation is visible. Visual options sit below the preview without a section title and High (30%) has no explanatory label.

**Suggested change:** Rename the tool to QR Code Generator unless a reader is provided; label Error correction and group QR appearance settings. The missing reader is also documented in the current guide.

### Semver Calculator — P2

[View screenshot](34-semver_calculator.png)

**Observed:** A, B, and Range are tiny floating labels. The comparison is a long monospaced report with a second summary line below it; Copy sits with inputs.

**Suggested change:** Use Version A/Version B and a structured comparison summary; put Copy in the result header.

### String Inspector — P3

[View screenshot](35-string_inspector.png)

**Observed:** Headers align. Several boxed statistics and a bordered Word distribution area are nested inside Text analysis, making the result side heavier than the input.

**Suggested change:** Reduce redundant borders while retaining the useful summary metrics.

### String Case Converter — OK

[View screenshot](36-string_case_converter.png)

**Observed:** Aligned editors with a compact case selector and output copy.

**Suggested change:** Keep the shared converter layout.

### JSON ↔ CSV — P2

[View screenshot](37-json_csv_converter.png)

**Observed:** Input/output remain stacked at the same wide window where most converter tools are side by side. Input hint id,name,note plus [] output looks more like loaded data than an empty state.

**Suggested change:** Adopt the shared wide-window split rule and make the empty state explicit.

### File Checksum — P2

[View screenshot](38-file_checksum.png)

**Observed:** Expected digest is separated from its label by a large gap. File metadata occupies an entire tall editor-like panel even before selecting a file. Copy manifest and Copy are adjacent actions with unclear distinction.

**Suggested change:** Use a compact file summary, group digest verification controls, and clarify manifest versus digest copying.

### Hash Generator — P2

[View screenshot](39-hash_generator.png)

**Observed:** Generate/Lookup and the lowercase checkbox are inside the Hashes body rather than a shared settings toolbar. Empty digests resemble editable fields and every row repeats Copy/Lookup controls.

**Suggested change:** Use a read-only digest table, central settings, and consistent row actions with an empty-state explanation.

### Text Encryption/Decryption — P2

[View screenshot](40-text_encryption.png)

**Observed:** A mode toolbar is followed by an unframed Password/Key row. Its input height differs from several other form controls. The key requirement is separated from algorithm settings.

**Suggested change:** Group algorithm, mode, and key into one consistent settings panel.

### Password Hashing — P2

[View screenshot](41-password_hashing.png)

**Observed:** Password uses a framed editor while Algorithm/Salt/Cost use an untitled options surface, so Hash begins lower than Password. There is no double input border in this capture.

**Suggested change:** Add an Options header and use a compact password form to align the main hash result with the other panels.

### Payload Embed/Extract — P2

[View screenshot](42-payload_embedder.png)

**Observed:** File chooser actions are bare file/folder icons, and the output row has two adjacent icons without text. Format support is another framed box within Options.

**Suggested change:** Label file-selection actions, distinguish output-file and output-folder choices, and simplify the support note.

### User Agent Generator/Validator — P2

[View screenshot](43-user_agent_tool.png)

**Observed:** Generate and two dropdowns crowd the input header. Chrome and Any do not have persistent labels indicating browser and platform.

**Suggested change:** Move generation settings to a labeled toolbar: Browser, Platform, and Generate.

### AntiBot Detection — P1

[View screenshot](44-antibot_detection.png)

**Observed:** The page shows an Offline tool badge while asking for a URL and offering Run. The URL row lacks the framed options treatment used by Firewall Fingerprint.

**Suggested change:** Use the Network badge and shared request toolbar. Source confirms Run calls _fetchPage through HttpClient; this is a confirmed metadata mismatch.

### Offline LLM — P2

[View screenshot](45-offline_llm.png)

**Observed:** Offline tool is displayed alongside Download actions, with no visible distinction between local inference and online model setup. The green send arrow looks available while Start a model first is shown. Temp is abbreviated.

**Suggested change:** Explain Offline inference / downloads require internet, use Temperature, and make the disabled composer state visually clear.

### HTML to JSX — OK

[View screenshot](46-html_to_jsx.png)

**Observed:** Aligned input/output panels and shared sample/copy placement.

**Suggested change:** Keep the common converter layout.

### JS to TS Converter — P1

[View screenshot](47-js_to_ts_converter.png)

**Observed:** The four-checkbox options group consumes the output header and the rightmost Copy icon is visibly clipped. The options group has a separate white border inside the header.

**Suggested change:** Put migration options in a shared settings panel and reserve the header end for a fully visible Copy action.

### Markdown Preview — OK

[View screenshot](48-markdown_preview.png)

**Observed:** Aligned input/preview panels and clear empty-state guidance; the source-file action uses the compact icon.

**Suggested change:** Keep the common preview layout.

### SQL Formatter — P2

[View screenshot](49-sql_formatter.png)

**Observed:** Dialect selection is in Input and three format settings are in Output. There is no visible Copy action at the output header end in this capture.

**Suggested change:** Group SQL options into a toolbar and keep Copy visible in the output header.

### Cron Job Parser — P3

[View screenshot](50-cron_job_parser.png)

**Observed:** Expression, Schedule, and Next executions follow the framed panel style. Wide schedule rows leave labels and values far apart.

**Suggested change:** Use a compact key/value grid and keep the local-time indication visible.

### Color Converter — P2

[View screenshot](51-color_converter.png)

**Observed:** Each converted color has a bordered row without a visible copy affordance; palette swatches are unlabeled. The input and rows fill one panel while sliders form a separate dense column.

**Suggested change:** Use a compact conversion table with consistent copy actions and identifiable color preset labels/tooltips.

### PHP to JS — P3

[View screenshot](52-php_to_js.png)

**Observed:** Aligned editors; a long footer includes token state machine and a library attribution, which is implementation detail in the main workflow.

**Suggested change:** Shorten the footer to a plain-language limitation and move technical detail into documentation.

### PHP Serializer — OK

[View screenshot](53-php_serializer.png)

**Observed:** Aligned editors and clear input/output guidance with shared sample and copy placement.

**Suggested change:** Keep the shared converter layout.

### PHP Unserializer — OK

[View screenshot](54-php_unserializer.png)

**Observed:** Matches PHP Serializer in editor sizing, headers, sample, and copy placement.

**Suggested change:** Keep the paired-tool consistency.

### Random String Generator — P1

[View screenshot](55-random_string_generator.png)

**Observed:** Output begins below Options because Colors and count occupy an unframed row above it. Generated strings is truncated despite spare header space. Colors is permanently checked and disabled. Load sample is the only prominent generation action.

**Suggested change:** Align the panels, show the full title, move Count into labeled options, and use a clear Generate action. Source confirms Colors has onChanged:null and several visible settings are not wired to generation.

### SVG to CSS — OK

[View screenshot](56-svg_to_css.png)

**Observed:** Source and Preview align; CSS is logically below Source. Empty preview explains the next step.

**Suggested change:** Keep the layout; consider making the output encoding selector label explicit.

### cURL to Code — P3

[View screenshot](57-curl_to_code.png)

**Observed:** Aligned panels; GET, Options, and NodeJS / Fetch expose different classes of settings through different affordances. Input hint Enter text does not mention a cURL command.

**Suggested change:** Use an explicit cURL input hint and label request method versus target language/library.

### JSON to Code — P1

[View screenshot](58-json_to_code.png)

**Observed:** The output empty state tells the user Right click -> Save to file instead of explaining generated code. Options form a large lower panel with sparse checkboxes.

**Suggested change:** Replace the output hint with Generated code will appear here and provide an explicit export action only when implemented; keep language options compact.

### Cipher Decoder — P2

[View screenshot](59-cipher_decoder.png)

**Observed:** A full-width strip contains only Tries every single-step cipher while mode choices live in the input header. The next action is not obvious from the empty input.

**Suggested change:** Place mode-specific guidance beside the mode selector and explain whether typing runs identification automatically.

### Certificate Decoder (X.509) — P3

[View screenshot](60-certificate_decoder_x509.png)

**Observed:** Aligned editor pair. The input hint mentions PEM while the subtitle promises PEM or DER and no file chooser is visible.

**Suggested change:** Make accepted input formats and how to provide DER clear in the input guidance.

### Hex ↔ ASCII — OK

[View screenshot](61-hex_ascii_converter.png)

**Observed:** Aligned editor pair with clear conversion direction and shared sample/copy placement.

**Suggested change:** Keep the converter pattern.

### Line Sort/Dedupe — P3

[View screenshot](62-line_sort_dedupe.png)

**Observed:** Editors and controls align. The two output dropdowns have values but no persistent Sort and Duplicates labels.

**Suggested change:** Add clear setting labels; this screenshot alone does not establish sample or sorting behavior.

### PlantUML Class Diagram — P1

[View screenshot](63-uml_class_diagram.png)

**Observed:** The diagram toolbar clips the Fit control at its right edge and Export is not visible, even at this large window size. Source and diagram headers otherwise align.

**Suggested change:** Keep Fit and Export always visible; move secondary controls into a wrapped settings row. The code-first versus preview-first ordering should remain an explicit tool choice.

### Chmod Calculator — P2

[View screenshot](64-chmod_calculator.png)

**Observed:** Permissions combine large outlined checkbox rows, colored output chips, tiny None/All actions, and standard checkboxes below. The same result is repeated in Permissions and Details.

**Suggested change:** Use a uniform permission grid and a single primary result summary; keep All/None controls comparable in size.

### MIME Types — P2

[View screenshot](65-mime_types.png)

**Observed:** Search uses a tall field and the table uses tall, strongly separated rows, giving this reference tool a different density. Search placeholder truncates the accepted search types.

**Suggested change:** Match the compact control height and table density; give persistent guidance for name, extension, and MIME searches.

### Preferences — P2

[View screenshot](66-preferences.png)

**Observed:** General options are widely spaced checkboxes with no descriptions; the entire options panel is stretched across the page. The same Preferences label is treated as an offline utility.

**Suggested change:** Use a restrained settings-form width, group related options, and explain analytics/debug options and availability in place.

### Leetspeak Converter — P2

[View screenshot](67-leetspeak_converter.png)

**Observed:** Output is on the left and Input on the right, unlike nearly every converter. Input mode/strength controls are crowded across its header.

**Suggested change:** Preserve the user-requested reversed order unless changed deliberately; make input/output direction explicit and move options into a labeled toolbar.

### Timestamp Extractor — P2

[View screenshot](68-timestamp_extractor.png)

**Observed:** Six timestamp-type segments occupy most of the input header. No timestamps detected appears below the panels even when the input is empty.

**Suggested change:** Move type selection to settings and distinguish Waiting for input from No timestamps found.

### Access Log Parser — P3

[View screenshot](69-access_log_parser.png)

**Observed:** Panels align; Entries/Summary is an output presentation choice placed in the input header.

**Suggested change:** Use the output header or shared settings row for result presentation controls.

### Session Cookie Decoder — P3

[View screenshot](70-session_cookie_decoder.png)

**Observed:** Aligned editors; both the output placeholder and the footer Nothing to decode yet communicate the same empty state.

**Suggested change:** Use one concise, consistent result empty state.

### ASN.1 / TLV Decoder — P2

[View screenshot](71-asn1_tlv_decoder.png)

**Observed:** The input header combines a parser mode toggle with an Input: PEM/Base64/hex chip, crowding the panel title. Input guidance lists a slightly different set of formats.

**Suggested change:** Separate parser mode from accepted format guidance and make supported formats consistent.

### JS/TS Obfuscator — P2

[View screenshot](72-js_obfuscator.png)

**Observed:** Options occupy two unframed rows below the editors, unlike tools with top settings panels. Name style uses a separate segmented group.

**Suggested change:** Use a labeled options toolbar before the editors and group naming options with it.

### Hash/HMAC Verifier — P3

[View screenshot](73-hash_verifier.png)

**Observed:** Dropdown and expected digest are now the same height. Expected hex digest is only a placeholder and will disappear when a value is entered; there is no sample action.

**Suggested change:** Keep the corrected sizing and add a persistent Expected digest label plus a working example action if useful.

### URL Query Editor — P3

[View screenshot](74-query_editor.png)

**Observed:** Aligned editors with Load sample in the shared location. A large settings strip contains only the Action dropdown in Inspect mode.

**Suggested change:** Use a compact settings row, expanding it only when an action needs key/value fields.

### CSV Inspector — P2

[View screenshot](75-csv_inspector.png)

**Observed:** The filter field is visibly taller than the compact controls used on other tools. Filter contains is only a placeholder, and 0 of 0 rows is the only empty-data indication.

**Suggested change:** Use the shared compact field and a persistent Filter label; explain that CSV with a header is needed.

### Date/Time Difference — P2

[View screenshot](76-date_difference.png)

**Observed:** Start and End are placeholder-only labels in wide inputs. The large Difference panel has only generic guidance and no date/time example or timezone cue beyond ISO 8601 + zone.

**Suggested change:** Add persistent Start/End labels, a concrete example, and a page-level Load sample action.

### Documentation — P3

[View screenshot](77-documentation.png)

**Observed:** Search, navigation, and reading content are clearly separated. The text column is very wide and dense paragraphs run across most of the dialog. The next section is cut at the bottom without a visible scrollbar.

**Suggested change:** Limit reading line length and make vertical scrolling more discoverable; keep the search and guide navigation.
