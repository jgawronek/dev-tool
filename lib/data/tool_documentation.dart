/// Plain-language guides. Tool names and categories come from ToolRegistry.
/// Keep each guide beside its stable tool ID so renamed tools keep their help.
const toolDocumentation = <String, String>{
  'getting_started':
      r'''DevUtils is a toolbox. Pick a tool, give it some text or a file, and use the result. You do not need to write a program to use it.
## Find and open a tool
Use the search box in the main sidebar to find a tool by name. Click a tool to open it in a tab. Click another tab to return to your work. The star beside a page title adds or removes that tool from Favorites. An empty star means it is not a favorite; a filled star means it is.
## Common controls
Input is the information you give the tool. Output is the answer. Most text tools update while you type; tools with Run, Generate, Scan, or Send wait for that action.
Click an input box and press Command+V to paste copied text. The two overlapping pages copy text. Load sample, at the top right when available, fills in an example. It may replace your current input.
Use as input moves the answer back into the input box. Pick the opposite mode if you want to reverse a conversion. File icons open a file chooser. Some tools also accept a file dragged into their input box. Export and Save let you choose a place for a result.
## Arrange your workspace
Drag a divider between panels to give one more room. Smaller windows may stack panels vertically. Drag the sidebar edge to change its width. Use the plus button in the tab bar to choose another tool. Close a tab with its x.
Command+N opens another copy of the current tool. Command+W closes the current tab. Command+1 through Command+9 select those tabs. Command+Shift+[ or ] moves between tabs. These tab shortcuts apply while you are working in the workspace.
## Offline and network tools
Offline tool means the main operation runs on your Mac. Network means the tool can contact another computer. URL Parser only sends a request when you press Send. Scanners need a target and a start action. Use network checks on systems you own or have permission to check.
Encoding changes how data is written. It does not hide a secret. Encryption locks data with a key. A hash is a fingerprint of data; it is not a way to recover the original text.
## Use this handbook
Open Help → Documentation, or press Command+Shift+D. The menu on the left groups all tools by category. Search looks inside the guides as well as their titles. Click a result to read it. Open tool closes the guide and takes you to that tool.
Command+F focuses the guide search. Clear search restores the full menu. Escape or the close button closes the handbook without changing your tool input.
## When something goes wrong
Start with Load sample if it is available. Compare your input with the example. Check the direction, format, and selected options. An error usually means the text does not match the expected format. Copy a useful result before clearing or closing your tool.''',
  'glossary': r'''These are words you will see in the tools.
## Text and data
JSON: text that stores named values, such as {"name":"Alex","age":13}. Names use double quotes. CSV: a table written as text, with commas between cells. YAML: another way to write named values, often using spaces and new lines. XML and HTML: text with tags, such as <title>Hello</title>.
Encode: rewrite information in another form. Decode: change it back. Base64: a way to write bytes using ordinary letters and numbers. Hex: numbers written with 0–9 and A–F. Byte: a small unit of stored data. UTF-8: a common way computers store text as bytes.
## Web and network
URL: a web address. Scheme: the first part, such as https. Host: the computer or website name. Path: the part after the host. Query parameters: named values after ?, such as page=2. Fragment: the part after #.
HTTP request: a message sent to a server. Response: its reply. Header: extra information sent with a request or reply. Body: the main content. GET asks for information; POST usually submits information; PUT replaces it; PATCH changes part of it; DELETE asks to remove it. The server decides what each request does.
IP address: a computer's network address. Port: a numbered doorway for a service. CIDR: a short way to describe a range of IP addresses, such as 192.168.1.0/24. DNS: the system that connects names to addresses. TLS: the protection used by HTTPS.
## Security
Key or secret: information used to lock, unlock, or verify data. Hash or digest: a fingerprint calculated from data. HMAC: a fingerprint calculated with a secret key. Salt: extra random data added before password hashing. Signature: a check that data was made by someone with the right key.
JWT: a token with a header, payload, and signature. TOTP: a short sign-in code that changes with time. Certificate: a document that connects a name with a public key. WAF: a web firewall that filters requests. A scanner's guess or confidence score is evidence to review, not proof.
## Code and time
Beautify: add spacing to make code easier to read. Minify: remove unneeded space to make it smaller. Regex: a pattern that searches text. Cron: a short schedule with fields for minutes, hours, and days. Unix time: time counted from January 1, 1970 in UTC. UTC: a shared time reference. Semver: a version number like 2.4.1; its parts are major, minor, and patch.''',
  'unix_time_converter':
      r'''Turn a timestamp into a date, or a date into a timestamp. A timestamp is a number that counts time from January 1, 1970.
## How to use
1. Choose whether your number uses seconds, milliseconds, or nanoseconds.
2. Enter the number, or use the date/time fields. Now fills in the current time.
3. Read the date, time, and converted values. Use the copy controls for the value you need.
## Options and results
Timezone 1 and Timezone 2 show the same moment in two places. Offset shows the difference from UTC. UTC ISO, RFC 3339, and RFC 1123 are different ways to write a date. Relative describes how far away the date is. Unix sec, ms, and ns give the same moment in different units. Day, Week, and Leap show calendar facts.
## Try it
Choose seconds and enter 0. The UTC date is January 1, 1970.
## If the date looks wrong
Check the unit first. A millisecond timestamp is much larger than a seconds timestamp. Also check the timezone before comparing clock times.''',
  'json_format_validate':
      r'''Make JSON easy to read and check whether it is valid.
## How to use
1. Paste JSON into Input, or load a JSON file or sample.
2. Read the formatted result and any error message.
3. Copy or export the result you want to keep.
## Options
Choose indentation with 2 spaces, 4 spaces, or Tabs. Wrap lets long lines fit the panel; No wrap keeps them on one line. Operation offers Prettify for readable spacing, Minify for compact JSON, Stringify for a JSON string containing the JSON text, JSON → XML for tag-based output, Escape for escaped text, Sort keys for ordering object names, and Sort arrays for ordering supported array values. Validation checks the structure, not whether the information is true. The status area reports size, counts, and validation errors. Sorting arrays can change their meaning when order matters.
## Try it
Paste {"name":"Alex","scores":[8,9]}. The tool puts the values on readable lines.
## Fix an error
JSON needs double quotes around names and text. Check commas, closing brackets, and braces. A comma after the last item is not valid JSON.''',
  'base64_string_encode_decode':
      r'''Turn ordinary text into Base64, or turn Base64 back into text. Base64 is a different spelling of data, not encryption.
## How to use
1. Choose Encode for normal text or Decode for Base64 text.
2. Paste into Input and read Output.
3. Copy the result. Use as input lets you run another conversion on it.
## Try it
Encode Hello to get SGVsbG8=. Select Decode and paste that value to get Hello again.
## If decoding fails
Make sure you copied the whole value. Text decoding expects text bytes; Base64 for an image belongs in the image tool.''',
  'base64_image_encode_decode':
      r'''Write an image as Base64 text and preview an image stored in Base64.
## How to use
1. Choose image… or drop a supported image file into String to encode it, or paste Base64 text to decode it.
2. Look at the Image preview to check the result.
3. Copy the text, or use Copy image to copy the picture.
## What the text means
An image data URL may start with data:image/png;base64,. That prefix tells an app the image type and encoding. The long text after it holds the picture's bytes.
## If there is no preview
Choose PNG, JPEG, GIF, WebP, or BMP files under 20 MB. Check that pasted Base64 contains a complete supported image; ordinary encoded words are not an image.''',
  'compression_codecs':
      r'''Make text smaller, or unpack compressed text. The packed result is shown as Base64 so you can copy it.
## How to use
1. Choose Compress or Decompress.
2. Choose a codec, which is the packing method.
3. Paste your text. Copy the result, or use Use as input to move it back for the next step.
## Options
The codec menu offers GZip, Zlib, Raw Deflate, BZip2, Zip, and Tar. Use the same codec to unpack a value as was used to pack it. Compress expects plain text; Decompress expects the Base64 packed result.
## Try it
Compress a few repeated sentences with GZip. Move the result to Input, switch to Decompress, and compare it with the original.
## If unpacking fails
Check the codec and Base64 text. Very short text may become larger after packing because the format adds extra information.''',
  'base_encodings':
      r'''Convert text using Base32, Base58, Base62, Base85, or Bech32. These formats use different sets of characters.
## How to use
1. Pick a format from the encoding menu.
2. Select Encode or Decode.
3. Paste Input. Read the result and summary, then copy it.
## Options
Use as input moves the result back for another operation. Load sample gives an example for the current format and direction. These are conversions, not passwords or secret protection.
## If decoding fails
Select the format that was used to create the value. Each format allows different characters. Bech32 also includes a check value, so changing one character can make it invalid.''',
  'jwt_debugger':
      r'''Read a JSON Web Token, called a JWT, and check its signature when you know its secret.
## How to use
1. Paste the whole token into Token, or load the sample.
2. Read Header and Payload. The header describes the token; the payload holds its claims, or named values.
3. In Token details, choose the supported signature algorithm. Enter Secret and press Verify signature if you want to check it.
## Options and results
The algorithm menu supports HS256, HS384, and HS512. Type and Segments describe the token. Signature status tells you whether the check has run and whether it matched. Copy controls copy the token or decoded panels.
## Understand the secret
Reading Header and Payload does not need a secret. Verifying needs the same secret that signed the token. The tool does not find the secret for you. Reading a token does not prove its claims are trusted, and a matching signature does not automatically mean the token is still allowed or unexpired.
## If verification fails
Check the full token, algorithm, and exact secret, including spaces. Unsupported algorithms cannot be verified here.''',
  'auth_totp':
      r'''Make the short, changing codes used by authenticator apps for two-step sign-in.
## How to use
1. Click the add-application card and enter the Base32 setup secret from the account.
2. Give it a name so you know which account it belongs to.
3. Read its Current code and enter it on the sign-in page before the timer runs out.
## Manage accounts
The edit icon opens Edit application, where you can change the secret, optional name, and card color, then Save. Close leaves the editor. Cards show Current and Next codes and seconds remaining. Codes use six digits and 30-second periods. There is no remove-entry button in this screen. The first example account is a demo, not a connection to a real account. Entries and secrets are saved locally in app preferences, not in an encrypted vault.
## If a code is rejected
Check the secret and account settings. Make sure your Mac's time is correct. Wait for the next code if the current one is about to expire. Treat setup secrets like passwords: they let someone else make your codes.''',
  'regexp_tester':
      r'''Try a regular expression: a pattern that finds matching pieces of text.
## How to use
1. Enter a pattern in the expression field.
2. Paste the text to search in Text.
3. Read the Matches list and matched groups. Copy Formatted matches if you need the matched pieces as text.
## Options
Output format controls the copied report: $0 is the whole match, $1 is the first group in parentheses, and \n adds a new line. Search matches filters the visible list; it does not change the formatted output. The pattern uses the app's default regex settings; there are no flag switches.
## Try it
Use the pattern [0-9]+ with I have 13 apples and 2 pears. It finds 13 and 2. Try Output format $0\n to put each match on its own line.
## If nothing matches
Check the pattern and letter case. Special characters like . and * have special meanings. An invalid pattern shows an error; simplify it and add parts one at a time.''',
  'url_encode_decode':
      r'''Make text safe to put inside a URL, or read percent-encoded text.
## How to use
1. Choose Encode or Decode.
2. Paste text into Input.
3. Copy Output. Use as input moves Output back for another conversion.
## Try it
Encode a value containing a space or an ampersand. Decode the result to see the original text.
## If the result surprises you
Encoding a whole address and encoding one parameter value are different jobs. Use URL Query Editor to change named parameters in an address. Do not keep encoding the same text unless you intend to encode it twice.''',
  'url_parser':
      r'''Break a web address into readable parts. You can also send an HTTP request and read the server's reply.
## Read an address
1. Paste a URL into the short URL panel, or load the sample.
2. URL details shows Scheme, Host, Port, Path, and Fragment.
3. Parameters shows values after the question mark as JSON. Repeated parameter names can have several values. Parsing stays on your Mac.
## Send a request
1. Choose GET, POST, PUT, PATCH, DELETE, HEAD, or OPTIONS.
2. In Request → Headers, enter one header per line, such as Content-Type: application/json.
3. For methods that accept a body, choose Request → Body and type the content.
4. Press Send. No request is sent just by typing or loading a sample.
## Read the reply
Response → Body shows the returned text; JSON is spaced out for reading. Response → Headers shows the extra reply information. The header reports status, time in milliseconds, and size in bytes. GET and HEAD do not send the Body field. HEAD replies usually have no body. Redirects are shown as replies rather than followed automatically.
## If a request fails
Use a full http:// or https:// address with a host. Send stays disabled otherwise. Check header spelling and use Name: value on each line. Cancel stops waiting. Requests time out after 30 seconds; replies larger than 2 MB are not displayed. Check the server and connection before trying again. POST, PUT, PATCH, and DELETE can change a server's data.''',
  'subdomain_finder':
      r'''Find public records of names below a domain, such as shop.example.com.
## How to use
1. Choose Domain or Organization and enter what to search for.
2. Press Find known to search the public certificate records.
3. Read Public subdomains and copy the names you need.
## What this tells you
These are names found in public records. A listed name may be old, offline, or no longer controlled by the same owner. Finding a name does not prove it is running now. Organization searches look for matching organization information in records.
## If the list is empty
Check spelling and internet access. Public records do not contain every private or unlisted name.''',
  'subdomain_takeover':
      r'''Check whether a subdomain points at a service that may no longer be set up. That can sometimes allow someone else to claim the service.
## How to use
1. Enter the target names in Scan options and choose the available check settings.
2. Press Scan and wait for Results.
3. Select a result to read its evidence in Details. Use JSON or CSV for a copyable report.
## Read results carefully
A possible match is a clue based on DNS and reply signatures. It is not proof that a takeover is possible. Review the named provider and the evidence. This tool checks; it does not claim services or take over accounts.
## If a check fails
Check the hostname, DNS, and connection. Scan only names you own or have permission to assess.''',
  'subnet_calculator': r'''Work out the addresses in a network range.
## How to use
1. Enter an IP address with a prefix, such as 192.168.1.10/24.
2. Read the calculated network, range, mask, and host counts.
3. Copy the report if you need to share the network plan.
## What the results mean
The prefix after / says how much of the address identifies the network. A smaller prefix usually leaves more room for devices. Network and broadcast addresses have special roles in IPv4. Labels such as private, loopback, multicast, and link-local describe special address ranges.
## If input is rejected
Check the dots and numbers in an IPv4 address, or the colons in IPv6, and use a valid prefix length. This is a calculator; it does not scan the network.''',
  'port_scanner':
      r'''Check which numbered network ports accept a connection on a target computer.
## How to use
1. Enter a hostname or IP address in Target.
2. Pick a scan profile or enter Custom Ports, such as 22,80,443 or 8000-8010.
3. Press Scan. Select an open port to read Details. Recon collects extra host information. Stop stops the active operation.
## Options
Timeout is how long each check waits. Concurrency is how many checks run together. Banners reads service greeting text; TLS details checks secure-connection evidence; HTTP HEAD asks web services for headers. More probes can take longer.
## Results
Details shows service evidence, security grading, and recommendations. Recon can include DNS, location, Whois, TLS, technologies, and available external-service information. Report exports JSON or CSV. History keeps recent scan information in the current tool session.
## Limits and errors
An open port is not automatically unsafe. A closed or silent port does not prove there is no service. Some extra information needs working external services. Check the target and timeout if a scan fails. Only scan systems you own or have permission to check.''',
  'network_scanner': r'''Find devices that respond in a network range.
## How to use
1. Enter a CIDR network, such as 192.168.1.0/24, or use Detect LAN to find your current local range.
2. Choose a profile or custom ports. Enable Ping, TCP ports, or both.
3. Press Scan. Select a device to read Device details. Stop stops the scan.
## Options
Timeout is the wait for each check. Concurrency is the number of checks at once. Custom ports accepts lists and ranges. Ping looks for a ping reply; TCP ports checks chosen service ports. A device may respond to one and ignore the other.
## Results
Devices lists responsive addresses. Evidence shows hostname, latency, open ports, services, and warnings. Report gives JSON or CSV to copy.
## If a device is missing
It may be asleep or may block your chosen probes. No response is not proof that a device does not exist. Use a range you are allowed to scan, and try a suitable profile or longer timeout.''',
  'local_server':
      r'''Serve files from a folder on your Mac using a small HTTP server.
## How to use
1. Press Choose Folder and pick the folder to share.
2. Set the port and Local only option.
3. Start the server. Copy URL and open that address to view the files.
4. Stop the server when you are finished.
## Options and results
Local only keeps access on your Mac. Turning it off can let other computers reach the server, depending on your network and firewall. The server serves the selected folder, not a full web application backend.
## If it will not start
The port may already be in use. Choose another port and check folder permissions. Choose a folder containing only the files you intend to serve.''',
  'firewall_fingerprint':
      r'''Look for signs of a web application firewall, or WAF, in a website's replies.
## How to use
1. Enter a target URL in Probe options.
2. Set Timeout. Choose Find all to look beyond the first match, and Redirects if you want redirects followed.
3. Press Fingerprint.
4. Open a probe in Details to read its full request URL, response headers, and saved body snippet. Select text to copy it, or copy the JSON/Text Report.
## Understand results
Signatures and unusual replies can suggest a firewall product. Confidence is a strength of evidence, not a promise. Generic behavior means the site acted like a firewall without a clear product match. No detected WAF means no tested signature matched. HTTP 200 means the server replied successfully; it does not prove an attack worked. HTTP 403 means the request was refused. The body is a saved snippet, not the entire page.
## If probes fail
Check the URL, network, and timeout. Servers may block or rate-limit these checks. Use targets you own or have permission to test.''',
  'html_entity_encode_decode':
      r'''Change characters into HTML entities, or change entities back into readable text.
## How to use
1. Select Encode or Decode.
2. Paste Input and read Output.
3. Copy the result, or use Use as input for another conversion.
## Try it
Encode text containing <, >, or &. Entities let those characters be written as text instead of being confused with HTML tags.
## If text still looks encoded
It may have been encoded more than once. Decode one layer at a time and check the result. This tool changes text; it does not render a webpage.''',
  'backslash_escape_unescape':
      r'''Add or remove backslash escapes used to write special characters inside text values.
## How to use
1. Choose Escape or Unescape.
2. Paste the text and read the result.
3. Copy it, or use Use as input to work on the next layer.
## Try it
Escape text containing a quote, a backslash, or a new line. An escape such as \n writes a new line using two visible characters.
## If it looks wrong
Different languages have different string rules. Check the result before inserting it into code. Unescape only text that actually contains the escape sequences you intend to remove.''',
  'uuid_ulid_generate_decode':
      r'''Generate unique-looking IDs, or inspect a UUID or ULID you already have.
## How to use
1. Paste an existing ID into Input to inspect it.
2. To make IDs, choose UUID v4, UUID v1, or ULID and set the generation count.
3. Press Generate and copy Generated IDs.
Load sample generates IDs using the selected type, count, and letter case, then puts the first ID into Input and shows its details.
## Options
The lowercase checkbox changes the letter case of newly generated IDs. Inspection shows Standard and Raw forms, Version, Variant, and any stored Time, Clock, or Node values. UUID v4 uses random values. UUID v1 includes time-related information. ULID is another ID format with a time part. Inspection reports details the format actually stores; a random UUID does not hold a creation time.
## If an ID is rejected
Check its length and allowed characters. UUIDs usually contain hyphens. Copy the full ID without extra surrounding words.''',
  'html_preview': r'''Preview HTML source without leaving the toolbox.
## How to use
1. Paste HTML into Input or load the sample.
2. Read Preview as you change the source.
3.
## Limits
This is a built-in preview, not a full browser. Complex styling, scripts, and browser features may not behave like a real webpage. Use it for a quick view of supported text and elements.
## Try it
Paste <h1>Hello</h1><p>This is a paragraph.</p> and compare the tags with the visible result.''',
  'text_diff_checker': r'''Compare two pieces of text and find what changed.
## How to use
1. Put the old text in Input 1 and the new text in Input 2.
2. Choose Characters, Words, or Lines to decide how changes are grouped.
3. Read Differences and copy the result if needed.
## Options
Comparison preserves order and duplicate occurrences. Swap Inputs reverses the comparison. Very large changed spans are reported in full rather than minimized, to keep the app responsive.
## Try it
Compare Hello Alex with Hello Sam using Words.
## If there are unexpected changes
Spaces and new lines can count as differences. Try Lines for large files and Characters for tiny spelling changes.''',
  'yaml_json_converter': r'''Change structured data between YAML and JSON.
## How to use
1. Choose YAML → JSON or JSON → YAML.
2. Paste input in that format.
3. Read Output and copy it.
## Options
Select 2 spaces, 4 spaces, or Tabs for available output formatting. Use indentation that fits the target format. Conversion keeps values, not the original comments and layout.
## Try it
Convert the JSON {"name":"Alex","age":13} to YAML, then choose the other direction to convert it back.
## Fix an error
Check brackets and quotes in JSON. YAML is sensitive to indentation, so keep related lines aligned and avoid mixing indentation styles.''',
  'number_base_converter':
      r'''Write a whole number in decimal, binary, hexadecimal, and other supported bases.
## How to use
1. Enter a whole number and select its input base if needed. Auto recognises prefixes such as 0b for binary, 0o for octal, and 0x for hex. Custom base controls an additional base conversion.
2. Read Converted bases and Number details.
3. Right-click a converted value to copy the plain value, a prefix, or grouped digits.
## Options
Bit width can be Auto or a fixed size from 8 to 256. Signed reserves a bit for negative numbers; Unsigned uses all bits for nonnegative values. Number details helps show how the value fits the chosen width.
## Try it
Enter decimal 15. Its binary value is 1111 and its hex value is F.
## If a value is rejected
Check that every digit belongs to the selected base. A fixed width can only hold a limited range. Use a wider width or Auto for larger values.''',
  'html_beautify_minify': r'''Make HTML source easier to read or more compact.
## How to use
1. Paste HTML or load the sample.
2. Select Beautify, Minify, or Preview.
3. Read the result and any message, then copy it.
## Options
Beautify adds readable line breaks and indentation. Minify removes unnecessary spacing. Preview renders HTML in the built-in web view with JavaScript turned off. Choose 2 spaces, 4 spaces, or Tabs for indentation in Beautify. Preview does not run scripts. HTML minification keeps spacing between inline words and preserves preformatted text, script contents, and style contents.
## If output is unexpected
Review it before replacing a real file. HTML can contain scripts and styles whose whitespace has special meaning. Use HTML Preview for a quick visual check.''',
  'css_beautify_minify': r'''Make CSS styles easier to read or smaller to copy.
## How to use
1. Paste CSS or choose a source file.
2. Pick Beautify or Minify.
3. Read Output and copy it.
## Options
Beautify spaces rules out; Minify packs them together. Neither operation checks whether a browser will apply the style as intended. The indentation menu offers 2 spaces, 4 spaces, and Tabs.
## Try it
Use body{color:red;background:white;} and choose Beautify.
## If it looks wrong
Check braces and semicolons. Review complicated or newer CSS syntax in your normal development tools.''',
  'js_beautify_minify':
      r'''Change the layout of JavaScript or TypeScript source.
## How to use
1. Paste code or choose a source file.
2. Choose Beautify, Minify, Obfuscate, or Verify.
3. Inspect and copy Output.
## Options
Beautify formats the syntax tree with consistent spacing and your chosen indentation. It keeps loop headers together and preserves comments and literal text. Minify removes comments and unnecessary spaces and line breaks, while keeping strings and required word separators intact. Long output may still wrap visually in the editor. Obfuscate creates a reversible Base64 wrapper for standalone scripts; it is not encryption. TypeScript type annotations are removed first. Bundle imports/exports and compile JSX before using this option. Verify reports syntax errors with line and column numbers using an offline JavaScript/TypeScript parser; it does not check types or whether the program gives the right answer. Select 2 spaces, 4 spaces, or Tabs for indentation. This does not run the code or prove it is safe.
## If code behaves differently
Keep a copy of your original and review complex strings, comments, or language features. A formatting tool is not a complete compiler or test runner.''',
  'rb_beautify_minify': r'''Adjust the layout of Ruby source code.
## How to use
1. Paste Ruby or choose a Ruby file.
2. Select Beautify or Minify.
3. Read and copy the result.
## Options
Beautify re-indents ordinary Ruby blocks. Minify removes indentation and blank lines outside strings; Ruby still needs its line breaks. Both preserve multiline strings, heredocs, and data after __END__. Minify lets you keep or strip comments. Special lines that tell Ruby how to run, such as #! and frozen_string_literal, are kept. The indentation choices are 2 spaces, 4 spaces, and Tabs. The tool does not execute Ruby.
## If output is unexpected
Ruby has syntax where spacing matters. Review the output before using it, especially strings, blocks, and uncommon syntax. Keep the original file.''',
  'xml_beautify_minify':
      r'''Make XML easier to read or remove extra layout space.
## How to use
1. Paste XML into Input.
2. Pick Beautify or Minify. Beautify offers 2 spaces, 4 spaces, or Tabs. Minify offers Keep comments or Strip comments.
3. Read Output and copy it.
## Try it
Use <person><name>Alex</name><age>13</age></person> and choose readable formatting.
## If XML is invalid
Every opening tag needs the right closing tag. Attribute values need quotes. Keep the original when working with XML whose text spaces matter.''',
  'lorem_ipsum_generator':
      r'''Create filler content for a design or a test. The names and contact details are example data, not a list of real people.
## How to use
1. Choose Count: x1, x5, or x10.
2. Select Replace to replace the output, or Append to add to it.
3. Click the kind of content you want. Read and copy Generated text.
## Content buttons
Text offers Paragraph, Sentence, Word, and Title. Identity offers First name, Last name, Full name, Email, and URL. Social offers Short tweet and Long tweet. You can combine them by using Append.
## Try it
Choose x5 and Paragraph for a page mock-up. Switch to Append and add a Title.
## If there is too much text
Choose a smaller count and Replace, then generate again.''',
  'password_generator':
      r'''Make a password or word-based passphrase with the choices you select.
## How to use
1. Choose Style: Random characters, Wordlist passphrase, Numeric PIN, or UUID / token.
2. Select character groups such as letters, digits, and symbols, or choose word options.
3. Set Count from 1 to 500. Each password appears on its own line. Regenerate replaces the entire list. Copy copies one password; Copy all copies the full list.
## Options
Random characters always includes lowercase letters; A-Z, 0-9, and Symbols add other groups. Length sets the character count. Wordlist passphrase uses Words for the count, a separator between words, and optional Capitalise. Numeric PIN uses Digits for the count. UUID / token makes a 128-bit random token and has no extra options. Count works with every style. For a list, strength and guess-time figures describe each password, not the whole list. The summary includes an estimated strength and guess-time figures; these are rough estimates, not guarantees.
## If a website rejects it
Check that the site's length and character rules match your options. Do not reuse a password across accounts. This generator does not save a password in a password manager for you.''',
  'qr_code_reader_generator':
      r'''Make a QR picture that another device can scan to read your content.
## How to use
1. Choose Plain text, URL, vCard, Wi-Fi, Email, or SMS.
2. Enter content in the form that matches that type. The sample gives a starting example.
3. Read the QR preview. Save PNG exports it as a picture.
## Appearance options
Choose the error-correction level, module shape, and eye shape. Modules are the little squares; eyes are the large corner shapes. Add Logo, Change Logo, and Remove Logo manage an image in the center.
## Limits
The current screen creates QR codes. It does not provide an image-scanning reader flow despite its tool name. A long message or large logo can make a code harder to scan. Higher error correction can help with a logo but leaves less room for data.
## If the preview fails
Shorten the content or choose another error-correction level. Scan the saved code with your intended device before sharing it.''',
  'semver_calculator':
      r'''Compare software versions and check whether a version fits a range.
## How to use
1. Enter versions in A and B, such as 1.2.3 and 1.3.0.
2. Enter a range if you want to check which versions fit it.
3. Read Comparison and copy the report. Swap exchanges A and B.
## What versions mean
The three main parts are major.minor.patch. A higher major part wins even if the other parts are smaller. Labels like -beta mark a prerelease, not a final release. A range describes acceptable versions rather than one exact version.
## If parsing fails
Use a version in the expected format. Try a simple exact version or range before adding more complex range notation.''',
  'string_inspector': r'''Count and inspect the text you paste.
## How to use
1. Enter text in Input.
2. Read Text analysis for Characters, Bytes, Words, Lines, and Unique.
3. Move the cursor or select text to see Cursor and Selected details.
## Why counts differ
A visible symbol may use more than one byte, especially emoji and letters from other writing systems. Characters and bytes are different measurements. Unique counts distinct characters rather than every repeated copy.
## Try it
Compare hello with hello 👋 and watch the byte count.
## If a count surprises you
Check for extra spaces and final new lines. A selection is only the part highlighted in the input.''',
  'string_case_converter':
      r'''Change the capitalization and word separators in text.
## How to use
1. Paste text into Input.
2. Choose a case style from the available controls.
3. Copy the converted result.
## Common styles
UPPERCASE and lowercase change letters. camelCase joins words and starts later words with capitals. PascalCase also capitalizes the first word. snake_case uses underscores, and kebab-case uses hyphens. CONSTANT_CASE combines uppercase letters and underscores. Title Case capitalizes each word; Sentence case capitalizes the start. Use these styles for names, labels, or code.
## Try it
Convert hello world to camelCase to get helloWorld.
## If word breaks look wrong
Names with unusual capitals, numbers, or punctuation may need a quick manual check.''',
  'json_csv_converter':
      r'''Turn JSON rows into a CSV table, or turn CSV into JSON.
## How to use
1. Choose CSV → JSON or JSON → CSV.
2. Paste the correct input format, or load a sample for that direction.
3. Read Output. Copy it or use Export JSON when that option is shown.
## Options
Wrap or No wrap changes how long JSON lines are displayed. Choose 2 spaces, 4 spaces, or Tabs for JSON spacing. CSV's first row names the columns. JSON-to-CSV works best with a list of objects using the same fields.
## Try it
Use a CSV with the header name,age and a row Alex,13.
## If conversion fails
Check quotes around CSV cells that contain commas. Check JSON brackets and double quotes. A flat table cannot represent every kind of deeply nested JSON.''',
  'file_checksum':
      r'''Calculate a file's fingerprint and compare it with an expected fingerprint.
## How to use
1. Choose file, or use the supported file input.
2. Read the MD5, SHA-1, SHA-256, and SHA-512 checksums.
3. Paste an expected checksum and press Verify to compare it.
## Results
Copy copies the report. Copy manifest copies checksum-and-filename lines. An expected digest is compared against all supported algorithms, so you do not have to choose one manually. The file's actual bytes are hashed, not just its filename.
## If verification fails
Check that the expected checksum uses the same algorithm. A changed file or an incomplete download gives a different result. A matching checksum proves the bytes match the expected fingerprint, not that a file is harmless.''',
  'hash_generator':
      r'''Make fingerprints of text, or investigate hash values you already have.
## Generate
1. Choose Generate and paste text.
2. Read MD2, MD4, MD5, SHA1, SHA224, SHA256, SHA384, SHA512, and the other displayed algorithms.
3. Copy the hash you need. Even one extra space changes a hash.
## Lookup
Choose Lookup and paste a hash or text containing hashes. Analyze finds supported hex hashes and their possible formats. Local crack tries a small built-in wordlist or your one-candidate-per-line list. Online lookup asks external hash databases for known matches.
## Understand a match
A hash is not encryption and has no simple Decode button. Lookup finds a known input with that fingerprint, if one is available. It cannot promise to recover an unknown password. Online lookup sends the lookup hash to outside services.
## If there is no result
Check the hash length and hex characters. Try the expected algorithm. A wordlist only finds candidates it actually tries.''',
  'text_encryption':
      r'''Lock text with a key, or unlock text using the matching key and settings.
## How to use
1. Choose a category and algorithm.
2. Choose Encrypt or Decrypt and Base64 or Hex output.
3. Enter Password/Key and the input text.
4. Read and copy the result. Swap & toggle mode moves the result back and reverses the direction.
## Algorithms
Modern includes AES sizes and modes and ChaCha20. Other groups include legacy ciphers such as 3DES and RC2, stream ciphers such as Salsa20 and RC4, lightweight TEA/XTEA/XOR, and classical Vigenere/Caesar/ROT13/Atbash. Pick from the actual menu. Different modes and formats need matching settings to decrypt.
## Limits
Classical and legacy methods are useful for learning or compatibility; they are not a good way to protect important new secrets. Encryption output may include random setup data, so encrypting twice can give different results.
## If decryption fails
Use the exact same key, algorithm, mode, and input format. Copy the complete encrypted result. The tool cannot recover a forgotten key.''',
  'password_hashing':
      r'''Make a stored password hash, or check whether a password matches one. Password hashing is one-way; it does not decrypt a password.
## How to use
1. Choose Hash and enter the password.
2. Select bcrypt, PBKDF2-HMAC-SHA256, PBKDF2-HMAC-SHA512, scrypt, Argon2d, Argon2i, or Argon2id and its settings, then run the operation.
3. Copy the generated hash. To check it, choose Verify, enter the password and Hash to check, and run again.
## Options
Salt can be left empty to generate one randomly. Cost factor controls bcrypt work. Iterations controls repeated work. Scrypt uses N, r, and p. Argon2 settings include iterations, Memory in KiB, and Parallelism. Larger work settings can take more time and memory.
## Verification
Supported bcrypt or PHC-style hashes carry information about their algorithm and settings. The tool detects supported formats from the hash prefix. Back to hash returns to creation mode.
## If it fails
Check parameter ranges, especially a power-of-two N for scrypt. Paste the whole stored hash. A new random salt means two hashes of the same password can look different.''',
  'payload_embedder':
      r'''Store an encrypted file inside a PNG, JPG, or PDF carrier, check for it, or extract it.
## Embed a file
1. Choose Embed. Select a Carrier file and a Payload file.
2. Set Output file, or leave it empty for the suggested *.embedded.* name.
3. Enter a Passphrase and press Embed encrypted.
## Check or decode
Check looks for this app's embedded format in a Stego file; it does not extract the secret. Decode needs the Stego file, matching Passphrase, and a Decoded output location. An empty output uses the embedded filename. Choose file/folder buttons help set paths.
## Options and limits
Example paths only fills example paths; it does not create files. Results reports what happened and the output path. PNG uses a private chunk, JPG uses metadata segments, and PDF uses a comment block. This is not guaranteed to survive image editing or PDF rewriting.
## If it fails
Check that both files exist, the carrier format is supported, and the output is writable. You need the original passphrase to decode.''',
  'user_agent_tool':
      r'''Read or create a user-agent string: text a browser or app uses to describe itself to a website.
## How to use
1. Paste a user agent to read its Analysis.
2. To create one, choose a browser/app and platform from the controls, then press Generate.
3. Copy the generated string or analysis.
## Options
The choices include common browsers, mobile apps, operating systems, and random standard or WebView styles. Analysis reports the browser, platform, device, engine, WebView/app details, and any detected issues.
## Limits
A user agent is only a claim made by the sender. It does not prove which device or person sent a request. Generated version numbers are examples, not a live list of the newest releases.
## If validation warns
Check for missing brackets, invalid characters, or a browser/platform combination that does not make sense.''',
  'antibot_detection':
      r'''Fetch a web page and look for signs of anti-bot protection.
## How to use
1. Enter a website URL, such as https://example.com, or load the sample.
2. Press Run or submit the URL to fetch and analyse the page.
3. Read Report and copy the evidence.
## What results mean
The tool looks for recognizable words, scripts, headers, or response patterns. A match suggests a product or challenge; it does not bypass it. Missing a signature does not prove there is no protection.
## If nothing is found
Check the URL and internet connection. The tool reads the fetched page, headers, cookies, and script text; it does not run a full browser challenge. Some protection only appears to an interactive browser. The fetch contacts the supplied website.''',
  'offline_llm':
      r'''Download and run a language model on your Mac, then chat with it.
## Set up
1. Choose Download in Download Presets. Downloads need internet access and disk space.
2. Use Refresh to update Installed Models.
3. Press Start on an installed model. Wait for it to be running.
## Chat
Enter a message and press Send or Enter. Tokens limits how much text can be generated. Temp controls variation: smaller values tend to be more predictable. Stop stops generation or the running model using the matching control.
## Manage models
Delete removes an installed model file, so you would need to download it again. Generation uses the running local model. Downloads are online even though the tool is named Offline LLM.
## If it fails
Check the download, available memory, and local model/server setup. Start a model before sending. A model can invent facts, so check important answers yourself.''',
  'html_to_jsx': r'''Convert HTML markup into a starting point for React JSX.
## How to use
1. Paste HTML into Input or load the sample.
2. Read the converted JSX and copy it.
3.
## What changes
JSX has different rules from HTML, such as className in place of class and expressions for some values. The converter handles supported syntax; it does not build or run a React app.
## If it is not ready to use
Review attributes, styles, and component names before putting the result into your project. Complex templates may need manual changes.''',
  'js_to_ts_converter':
      r'''Create a TypeScript starting point from JavaScript, or strip supported types from TypeScript.
## How to use
1. Choose JS → TS or TS → JS.
2. Paste source or choose a matching source file.
3. Review and copy the output and summary.
## Options
For JS → TS, class fields can add field declarations; JSDoc uses supported type hints from comments; CommonJS adjusts supported module syntax; : any adds broad types where a specific type is not known. TS → JS removes supported type syntax.
## Limits
This is a helper based on supported patterns, not a complete TypeScript compiler. Complex generics, decorators, and unusual syntax need review. Loose any types allow values without strict checking.
## If output is wrong
Try a smaller example and check it in your project's compiler. Keep the original source.''',
  'markdown_preview': r'''See how Markdown text looks when rendered.
## How to use
1. Type Markdown, paste it, or choose/drop a .md file.
2. Read Preview while you edit.
3.
## Try it
Use # My title for a heading, **bold** for bold text, and a line starting with - for a list.
## Limits
The preview supports the app's built-in Markdown rendering. It may not match every website's extra Markdown features. Check your final publishing system if you use special extensions.''',
  'sql_formatter':
      r'''Space out SQL queries, or get a simple English description of supported SQL.
## How to use
1. Paste SQL into Input.
2. Choose Format or SQL to English.
3. Read and copy Output.
## Options
Formatting uses General SQL rules. Uppercase or Lowercase changes keyword case while preserving quoted values, quoted names, and comments. Choose 2 spaces, 4 spaces, or Tabs for indentation. SQL to English describes supported structure in words.
## Try it
Use SELECT name FROM people WHERE age > 12;.
## Limits
This tool does not connect to a database or execute a query. An English explanation is a reading aid, not proof the query is correct. Review database-specific syntax in your normal SQL tools.''',
  'cron_job_parser': r'''Explain a cron schedule and list its next run times.
## How to use
1. Enter a cron expression, paste one, or load the sample.
2. Read Schedule for the plain-language explanation.
3. Read Next executions in local time. Copy expression copies the schedule text.
## Understand the fields
A usual five-field cron has minute, hour, day of month, month, and day of week. A star means every allowed value in that field. A slash such as */5 means a step of five.
## Try it
Use */5 * * * * for every five minutes.
## If it is rejected
Check the number of fields and their ranges. Cron formats can vary between systems; use the format supported here. This screen calculates times; it does not schedule a task on your Mac.''',
  'color_converter':
      r'''Describe the same color in several formats and adjust it visually.
## How to use
1. Enter a supported color, such as #5CC07F or rgb(92, 192, 127).
2. Read Color values and right-click a value to copy it.
3. Use Palette, the color picker, or Presets to choose another color.
## Controls
Hue chooses the color family. Saturation chooses how vivid it is. Value chooses brightness. Alpha controls transparency. Results include Hex, Hex alpha, RGB/RGBA, HSL/HSLA, HSB/HSV, HWB, and CMYK.
## If a color fails
Check syntax and number ranges. A screen preview is not a guarantee of the same printed color; print color also depends on paper and printer settings.''',
  'php_to_js':
      r'''Convert supported PHP-style values or code patterns into JavaScript text.
## How to use
1. Paste the PHP input the screen expects or load its sample.
2. Read the JavaScript output and copy it.
3. Review the result before using it in a project.
## Limits
This is a conversion helper, not a full PHP application translator. Language features, libraries, and runtime behavior do not all have matching JavaScript forms.
## If conversion fails
Start with a small valid example. Check quotes, brackets, and supported syntax. Use a real runtime or project checks to confirm the final code.''',
  'php_serializer':
      r'''Turn supported data into PHP's serialized text format, which records values and their types.
## How to use
1. Paste JSON, such as {"name":"Alex","age":13}, or use Load sample.
2. Run the conversion if needed.
3. Copy the serialized result.
## Understand the result
PHP serialization has its own punctuation and length markers. It is not the same as JSON and is not encryption.
## If it fails
Check that the input is valid JSON. This serializer runs inside the app and does not require an installed PHP runtime. It handles ordinary values and arrays, not every PHP object format.''',
  'php_unserializer':
      r'''Read supported PHP serialized text as a more readable value.
## How to use
1. Paste the complete serialized value or load the sample.
2. Read and copy the decoded JSON output.
3. Use PHP Serializer for the opposite direction.
## If it fails
A serialized string's length markers must match its contents. Copy the original value without changing quotes or punctuation. This is a data-inspection tool, not a way to execute a full PHP application.''',
  'random_string_generator':
      r'''Make batches of strings using characters or words you choose.
## How to use
1. Choose a preset, then adjust uppercase, lowercase, symbol, digit, and word counts.
2. Choose x10 or x20 and press Generate. Load sample also generates from the current options.
3. Copy Generated strings.
## Options
Character categories are shuffled within each string. A Custom Character Set replaces the character alphabet while retaining the total requested character count. Separator joins character groups and words; Separating Group Size of 0 leaves characters ungrouped. An empty separator uses spaces between words.
Seed is optional: leave it empty for secure randomness, or enter an integer for repeatable output. Changing batch size generates immediately.
## Limits
Each item supports up to 4096 characters and 100 words. Seeded strings are predictable; use Password Generator for security-focused secrets. An API key preset does not create a working service key.
## If generation fails
Use whole-number counts within the displayed limits and request at least one character or word. Correct the options and press Generate.''',
  'svg_to_css': r'''Put SVG image source into CSS as an embedded image value.
## How to use
1. Paste SVG into Source or choose/drop an .svg file.
2. Choose URL Encoded or Raw output.
3. Read and copy CSS.
## Options
URL Encoded escapes characters that have special meanings in a URL. Raw keeps source closer to the original. Use the mode required by the place you will paste the CSS.
## If it does not display
Check that the SVG is complete and valid. Review quotes and escaping in the surrounding CSS. Embedded image conversion does not repair a broken drawing.''',
  'curl_to_code':
      r'''Turn a cURL command into request code for another language or library. It does not send the request here.
## How to use
1. Paste a cURL command, or load the example.
2. Select an output language/library.
3. Read and copy the generated code. Review it before running it.
## Output choices
Options include Fetch, axios, node:http, Python Requests, PHP cURL/Guzzle, Go net/http, Rust reqwest, C# and Java HttpClient, Ruby Net::HTTP/Faraday, Swift URLSession, Dart http/dio, and wget. Choose the one used in your project.
## If parsing fails
Check shell quotes and supported cURL flags. Commands can include passwords, authorization headers, or cookies; those values will also appear in the generated code.''',
  'json_to_code':
      r'''Generate model types from a JSON example. A model describes the kinds of values your code expects.
## How to use
1. Paste JSON, choose a JSON file, or drag it into Input.
2. Choose Swift, TypeScript, or Kotlin in Output.
3. Review and copy the generated types.
## Options
Swift offers Plain types only (no Codable), Generate memberwise initializers, and Explicit CodingKeys. Codable adds support for converting values to and from encoded data. Initializers help construct objects. CodingKeys spell out field names. Reset to Defaults restores these options. Other output languages may have no extra options.
## Try it
Use {"name":"Alex","age":13} to make a type with text and number fields.
## Limits
The tool guesses types from the example. Null, empty lists, and mixed values can create loose types. Provide a realistic sample and review optional fields. The current output can be copied; its placeholder mentions a right-click save action that is not connected on this screen.''',
  'cipher_decoder':
      r'''Explore simple ciphers that hide letters using substitutions or shifts.
## How to use
1. Paste ciphertext, which is the hidden message.
2. Choose Identify, Decode, or Brute force and the available cipher.
3. Set Shift, Key, or Rails when the selected method needs it.
4. Read the candidates, summary, and output. Copy or Use as input for another step.
## Modes
Identify tries to suggest a likely method. Decode applies the selected method. Brute force tries supported small key choices and ranks readable-looking results. These include simple rotations and supported Vigenere/XOR candidates; it is not a universal key finder.
## Try it
Decode uryyb using ROT13 to get hello.
## If no candidate looks right
The input may use another cipher, several layers, or modern encryption. A readability score is only a guess.''',
  'certificate_decoder_x509':
      r'''Read the information in an X.509 certificate, often used for HTTPS.
## How to use
1. Paste a complete certificate in a supported form, or load the sample.
2. Read the decoded report.
3. Copy the result for inspection.
## What to look for
The subject describes who the certificate is for. The issuer describes who issued it. Validity dates show the intended time range. Public-key and signature information describe the cryptographic format.
## Limits
Decoding is not the same as checking a website's whole trust chain or proving ownership. This screen reads supplied data; it does not replace a browser's certificate checks.
## If it fails
Keep PEM BEGIN/END lines when copying PEM text. Make sure the certificate is complete and not a private key.''',
  'hex_ascii_converter':
      r'''Change text to hexadecimal byte values, or hexadecimal values back to text.
## How to use
1. Choose Hex → ASCII or ASCII → Hex.
2. Paste the correct type into Input.
3. Read and copy Output.
## Try it
Hex 48656c6c6f represents Hello.
## If it fails
Hex bytes normally use two hex digits each. Check for missing digits or characters outside 0–9 and A–F. Arbitrary binary bytes may not make readable text.''',
  'line_sort_dedupe': r'''Sort lines and optionally remove repeated lines.
## How to use
1. Paste one item per line.
2. Choose A → Z or Z → A text ordering.
3. Choose With Duplicates or Without Duplicates.
4. Read and copy Output.
## Try it
Paste pear, apple, and pear on separate lines. Sort A → Z and remove duplicates to keep one apple and one pear.
## If order is unexpected
This is text ordering, not a spreadsheet's number sorting. Spaces and letter case can affect comparisons. Clean unwanted spaces before using the result.''',
  'uml_class_diagram':
      r'''Create a diagram from supported PlantUML text and edit its layout visually.
## How to use
1. Paste PlantUML, load the sample, or drop a .puml file into PlantUML.
2. Read Diagram. Select a node, then drag it to arrange it. Nodes can move in any direction, including left or above the starting position. Drag empty space to pan, or use Fit to bring the whole diagram into view.
3. Tidy arranges the diagram; Snap aligns dragging to a grid. Zoom controls and Fit help you see it all.
## Diagram controls
The first menu chooses how the diagram is drawn: App, Sketch, Digital, or Chalkboard. The second menu chooses node colors. Sketch uses handwriting-style text and rough outlines. Digital uses a dark canvas, thin colored outlines, and code-style text. Chalkboard has rough chalk outlines on a board surface. Use the add-element palette for classes, interfaces, rectangles, components, servers, databases, queues, clouds, actors, notes, and supported related shapes. Select and edit element labels. Right-click a node to rename, change background color, wrap/move it into a package, remove it from a package, or delete it. Package menus rename or color the package or move its contents out.
## Save and share
Export opens Save .puml, Export PNG, Export PDF, and Print. Source saves editable text; PNG/PDF save a picture of the diagram. Packages group related nodes.
## Limits
The renderer supports the syntax and shapes implemented in this app, not every feature of the full PlantUML program. If a diagram is incomplete, start with the sample and add one element at a time.''',
  'chmod_calculator':
      r'''Calculate Unix file permissions using checkboxes or a number.
## How to use
1. Select read, write, and execute for owner, group, and others, or enter a supported mode.
2. Read the numeric and text permission values and Details.
3. Copy chmod copies a command; Copy report copies the explanation. Common modes fills familiar choices.
## Special bits
setuid, setgid, and sticky have special operating-system meanings beyond normal read/write/execute. They are advanced settings; leave them off unless you need them.
## Try it
Mode 644 means the owner can read and write, while the group and others can read.
## Limits
This is a calculator. It does not change a file's permissions. Review a copied command and its target path before running it.''',
  'mime_types':
      r'''Look up the type name used to describe a file's contents, such as image/png.
## How to use
1. Type a type name, extension, or related text in search.
2. Read the matching rows in MIME types.
3. Clear search to restore the list.
## Understand the table
A MIME type often has a main group and a subtype, such as text/plain or application/json. Extensions are common filename endings for that format. Reference information identifies the listed definition.
## Limits
A filename extension is a clue, not proof of what a file contains. This is a reference table; it does not inspect a file's bytes.''',
  'preferences':
      r'''Choose the app's appearance and inspect saved general and scripting settings.
## Appearance
Show status bar icon adds a menu-bar shortcut for showing or quitting the app. Show Dock icon controls whether the app appears in the Dock. If you hide the Dock icon, the status bar icon stays on so you can reach the app. Light and Dark change the current display. Color theme changes accents and selections.
## General
The screen stores choices for hiding at launch, confirming Command+Q, analytics, and debug logs. These switches currently save preferences; the app does not yet connect all of them to launch, quit, reporting, or logging behavior. Do not assume changing one starts reporting or enables a quit prompt.
## Scripting
PHP, OpenSSL, and Other select a settings segment. Runtime shows the stored PHP runtime information. Allowed PHP functions stores a comma-separated list. These are settings fields, not an installer or a complete runtime manager.
## Limits
System mode is a stored choice; Light and Dark directly change the current app state. Only the General, Appearance, and Scripting sections are part of this main Preferences screen. A disabled setting cannot be changed until its related condition is met.''',
  'leetspeak_converter':
      r'''Change normal letters into leetspeak, or turn leetspeak back into words. Leetspeak replaces letters with shapes like 3 for E.
## How to use
1. Enter text in Input on the right. Output is on the left.
2. Choose Leet → Text or Text → Leet.
3. Pick Basic, Common, or Aggressive and copy the result.
## Options
The profile controls how many replacements are used or recognised. Text → Leet shows Intensity, which controls how strongly replacements are applied. The summary reports the conversion.
## Try it
Decode H3ll0 W0rld to read Hello World.
## Limits
Different letters can look like the same leet character, so decoding can be a guess rather than a perfect reversal.''',
  'timestamp_extractor':
      r'''Find dates and times inside a larger block of text, such as a log.
## How to use
1. Paste text into Input.
2. Choose All or a format: ISO, Apache, nginx, Syslog, or Epoch.
3. Read and copy the extracted timestamp report.
## Options
All searches the supported patterns. A specific format narrows the search when other numbers or text would be confusing. Epoch means Unix-style numeric timestamps.
## If a date is missing
Check the selected format. Some log timestamps leave out a year or timezone, so read the report's interpretation before using it. The tool finds supported patterns, not every possible way people write dates.''',
  'access_log_parser':
      r'''Read supported web-server access logs as entries and a summary.
## How to use
1. Paste log lines into Input.
2. Choose Entries to see individual requests or Summary to see grouped totals.
3. Copy the report.
## What to look for
Supported entries can include address, time, request, response status, and byte count. The summary helps you see patterns across the parsed lines. It only counts what the parser could read.
## If lines are skipped or rejected
Check that they match a supported access-log format. Custom server formats may need adjustment before parsing. A log's address or user-agent text does not prove a person's identity.''',
  'session_cookie_decoder': r'''Inspect supported encoded session-cookie values.
## How to use
1. Paste the cookie value into Input, or load the example.
2. Read the decoded report and copy it.
3.
## Limits
The tool identifies supported Flask, JWT, JWE, PHP serialized, Rails, and ASP.NET/.NET cookie forms and reports readable parts when available. JWE and other encrypted forms can only expose format information without their keys. Reading encoded data does not verify a signature, decrypt a protected cookie, or log you into a website. Some cookies are just random IDs with no readable content.
## If it cannot decode
Copy the value completely and check the expected input. A server may keep the actual session information elsewhere. Treat a live sign-in cookie like a password.''',
  'asn1_tlv_decoder':
      r'''Read binary-style data made from tags, lengths, and values.
## How to use
1. Select ASN.1 (DER) or Generic TLV.
2. Choose Input: PEM/Base64/hex to accept those encodings, or Input: hex only to force hex interpretation. Paste the bytes or load the sample.
3. Read the nested decoded report and copy it.
## Understand the parts
Tag says what kind of item it is. Length says how many bytes belong to it. Value is the data. ASN.1 DER follows strict rules often used by certificates. Generic TLV follows the simpler format supported here.
## If it fails
Check the selected format, byte encoding, and complete length. Random bytes are not necessarily valid DER or TLV.''',
  'js_obfuscator':
      r'''Make supported JavaScript/TypeScript source harder for a person to read.
## How to use
1. Paste source code.
2. Choose the transformations you want.
3. Read and copy the output, then check it in your project.
## Options
Rename identifiers changes names. Hoist strings moves text into shared storage. Inject dead code adds unused code. Self-defending and Debug protection add supported protection patterns. Disable console changes console behavior.
## Limits
Obfuscation is not encryption. A determined reader can still inspect or run the program. Some transformations can change behavior or interfere with debugging. Do not rely on this to protect a secret placed in client-side code.
## If code breaks
Turn off options one at a time and compare with the original. Keep an unobfuscated copy for development.''',
  'hash_verifier':
      r'''Check whether text has an expected hash or HMAC fingerprint.
## How to use
1. Choose SHA-256, SHA-512, SHA-1, MD5, HMAC-SHA-256, or HMAC-SHA-512.
2. Enter the original text and Expected hex digest.
3. For an HMAC method, also enter HMAC key.
4. Read Computed and Match or No match, then copy the report.
## If it does not match
Check the algorithm, exact text, spaces, new lines, and HMAC key. The expected value must be hexadecimal and have the correct length. This compares text as UTF-8 bytes; use File Checksum to compare a file's actual bytes.''',
  'query_editor': r'''Inspect or change named values in a URL's query string.
## How to use
1. Paste a whole URL or just its query string, or use Load sample for an example.
2. Choose Inspect, Add, Replace, Remove, or Sort.
3. For editing, enter Parameter name and, when needed, Value.
4. Read and copy the edited URL or query.
## Options
Inspect reads existing values. Add adds a parameter. Replace changes the chosen name's value. Remove deletes that name. Sort orders the parameters. The status shows the parameter count.
## Try it
Load sample fills a URL with a search term, page number, repeated tags, and a fragment. It also sets Parameter name to page and Value to 2. Choose Replace to change the page number.
## Limits
This changes text on your Mac. It does not send a web request or change the website.''',
  'csv_inspector': r'''Filter and sort a CSV table without using a spreadsheet.
## How to use
1. Paste CSV with a header row into Input, or use Load sample to try a small table. Load sample resets filtering and sorting so all four example rows appear.
2. Enter Filter contains to keep matching rows.
3. Choose All columns or a specific column for the filter.
4. Choose a Sort column and optionally Descending. Read and copy Filtered CSV.
## Results
The count shows how many rows matched out of the parsed total. Sort None keeps the current input order.
## If parsing fails
Use a header row and consistent columns. Put quotes around cells with commas or new lines. Check extra quotes and missing separators.''',
  'date_difference': r'''Find the elapsed time between two dates or times.
## How to use
1. Enter Start and End as ISO 8601 dates with a timezone, such as 2024-03-08T09:00:00Z or 2024-03-09T10:30:00+01:00.
2. Read Difference and the UTC instants used in the calculation.
3. Copy the result.
## Understand the result
Elapsed time is the actual gap between two moments. Timezone offsets affect which moments a written clock time represents. UTC instants show the shared reference used for comparison.
## If the gap looks wrong
Use complete dates and check their timezone or offset. Daylight-saving changes can make elapsed hours different from simply counting calendar days.''',
};
