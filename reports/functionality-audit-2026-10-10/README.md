# DevUtils functionality audit — 2026-10-10

This audit distinguishes interaction coverage from output correctness. A button callback completing without an exception is **not** evidence that the result is correct.

## Results

**1,212 headless tests passed, with zero failures or skips.** Static analysis is clean. The registry contains **76 tools**. **87 native tests passed** (85 core audit checks, one real-model service workflow, and one real-model UI workflow). The macOS release build succeeded: `build/macos/Build/Products/Release/DevUtils.app` (85.3 MB).

- Every tool: fresh opening, available Load sample clicked twice, control/input robustness, actual dropdown menu selections, and empty/sample layout at the native minimum **1040 × 700**.
- **344 dropdown choices** selected through menus, with selected values checked. Dynamic menus and scrolling lists are included.
- Headless tests use the actual vendored formatter engines. Native tests use macOS JavaScriptCore and real Flutter image decoding.
- Computational samples must produce output. Visual tools have separate image/diagram/preview tests. Network samples prepare targets; samples alone are not counted as successful network operations.

Browse [tool-matrix.csv](tool-matrix.csv) or [tool-matrix.json](tool-matrix.json) for all 76 tools. [evidence.json](evidence.json) contains control-level records, selected menu choices, sample output, and deferred actions.

## Defects fixed

| Area | Finding and correction | Stronger evidence |
|---|---|---|
| Encoders / YAML | Several sample and Use as input actions set text without recomputing output; stale output remained after errors. Actions now run the conversion and clear invalid output. | Repeated samples, encoder/converter tests, input/error recovery |
| Encryption | ChaCha20 nonce mismatch; CFB/OFB used bits where the engine requires bytes; partial blocks were mishandled. | 29 algorithms × Hex/Base64 = 58 UI round trips with Unicode, whitespace, and multiple blocks; 32 AES/ChaCha cases independently decrypted with Node/OpenSSL |
| Compression | Leading/trailing whitespace was removed before compression. | Six codecs round-trip exact Unicode/whitespace, including whitespace-only input; invalid data and recovery |
| Text diff | Membership comparisons missed order changes and duplicate changes; Output dropdown was inert. | Ordered sequence tests, duplicates, Unicode graphemes, meaningful spaces, whitespace-only word input, empty inputs, swap, formatted/plain presentation; bounded large-input handling |
| Random String | Words, separators, grouping and custom alphabet were inert; default seed made generation predictable; counts were emitted in fixed category order. | Optional deterministic seed, secure default, exact preset counts, Unicode alphabet, group lengths, word counts, x10/x20, invalid input and recovery |
| Base64 Image | Sample PNG was corrupt. Copy image copied text; no image-file encoding path. | Valid 32×32 pixel fixture; exact file bytes encoded, actual image dimensions rendered, cancellation and invalid-file recovery; native NSPasteboard image object test |
| Firewall Fingerprint | Ordinary 404 or server-header differences could be reported as generic firewall blocking; cookie values could falsely match F5. | Cloudflare fixtures, anchored cookie names, benign 404/server change and blanket outage cases |
| Layout / controls | JWT algorithm label overflow, Sketch stereotype header overflow, SemVer output overflow, and Subdomain Takeover detail pane squeezed to zero at minimum size. Legacy Clear/Sample actions could reappear in editor headers. | Every tool at native minimum window size; actual menus; widget/diagram/control tests |
| Offline LLM | HTTP error pages or interrupted downloads could appear as models; SSE parsing assumed network chunks aligned with complete events. Downloads now check status, GGUF signature and length, preserve existing files, clean partial files and prevent duplicate downloads; streaming decodes complete UTF-8 lines. | Error/truncation/recovery fixtures; every byte split across Unicode SSE events; all four official model URLs return HTTP 200 |
| Documentation | Guide list used ListTile without a Material ancestor. | Search/open/close documentation and every tool has a guide |

Formatter-specific fixes and 69 correctness cases are detailed in [the formatter audit](../formatter-audit-2026-10-10/README.md): JSON, HTML, CSS, JavaScript/TypeScript, Ruby, XML and SQL. They include all available modes/indentation, valid syntax, malformed syntax, comments, literals and recovery.

## End-to-end checks

- File Checksum: streaming known digests, expected digest/manifest, missing-file/picker error, duplicate selection, cancellation and disposal. **Native GUI**: opened macOS file chooser, selected a three-byte `abc` fixture, checked displayed MD5/SHA-1/SHA-256/SHA-512, verified SHA-256 MATCH, reopened and cancelled without losing the selection. No crash in this flow.
- Password Generator: all four styles, 500-item batches, copy all, invalid count/recovery. UUID/ULID: generation types, counts, decoding and copy.
- JWT: HMAC algorithms, valid/mismatched signatures, recovery. Hash/HMAC: known results including the legitimate digest of empty input. Password hashing: supported hash/verify options.
- URL Parser: Send for GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS against a real loopback HTTP server, exact methods/headers/body and response checks; error responses, redirects, display limits.
- Port Scanner and Network Scanner: actual loopback socket, Scan finds the fixture port and exports JSON/CSV. Network service also has fixture discovery tests.
- AntiBot: real loopback Cloudflare-style fixture produces detection output. Firewall and takeover detection: controlled HTTP evidence/negative cases. Subdomain discovery: certificate transparency/subfinder fixtures.
- Local Server: Choose Folder, missing-folder/invalid-port recovery, Start, actual GET response bytes, log, Stop; service tests also cover HEAD, missing files and unsupported methods.
- Payload Embedder: Embed encrypted, Check output and Decode produce exact original UTF-8 bytes; service round trips cover PNG/JPEG/PDF and wrong passphrase. Previously skipped inspection test is now enabled and passes; its hang came from async fixture I/O in the test clock.
- Offline LLM: Download, Refresh, Start, Send, cancel response while keeping the server ready, Stop server, Delete, and empty/disabled states. A real SmolLM2 model and the bundled server were used. Controlled response delivery latency makes the cancel state observable; native test prompt values are set through the text controller, with real button taps.
- TOTP: add/edit fixture account, persistence and current/next codes. Navigation: search, favorites and tabs. Diagrams: parsing, dragging, pan, resize, styles, arrows and export tests.

## Coverage limits

The generic control sweep records deferred external actions explicitly. Separate local/service tests cover many of them; they are not silently treated as passes.

- Offline LLM download failure/recovery, streamed event boundaries, and all four preset URLs are tested. A native test downloaded the 386 MB SmolLM2 fixture into temporary storage, started the bundled server, generated a streamed response, stopped the server and deleted the fixture successfully. Other model weights were not downloaded; their official URLs returned HTTP 200.
- Public DNS/WHOIS/geolocation/Shodan/recon providers, real LAN discovery and third-party firewall behavior are tested with local or controlled fixtures where available. This does not establish live availability or detection accuracy across arbitrary public hosts.
- Native checksum file selection/cancellation and image clipboard are verified. Other native picker/export branches use mocked dialog paths or service tests. Actual Finder drag-and-drop has not been manually exercised across every drop target.
- Minimum-size tests detect layout exceptions and overflows; they are not a pixel-level visual review of every state.
- These results establish the tested cases. They do not prove that every possible input is bug-free.

## Reproduce

Run from the repository root with its configured Flutter SDK:

```sh
flutter test --no-pub --reporter expanded
flutter test integration_test/full_audit_test.dart -d macos --no-pub --reporter expanded
flutter test integration_test/local_llm_test.dart -d macos --no-pub --reporter expanded
flutter test integration_test/local_llm_ui_test.dart -d macos --no-pub --reporter expanded
flutter analyze --no-pub
flutter build macos --release --no-pub
python3 reports/functionality-audit-2026-10-10/build_report.py
```

Native runner note: earlier long-run frame stalls and accessibility inspection interference are retained in their own logs. The final native harness keeps frame delivery live and brings its test window forward through a DEBUG-only channel before opening screens; native results are counted from the completed final run.

Final logs: [headless tests](final-tests.log), [native tests](final-native.log), [real-model service](native-llm.log), [real-model UI](native-llm-ui.log), [analysis](final-analyze.log), [build](final-build.log). Earlier failure logs are retained as debugging history; the final logs are the result of the corrected implementation.
