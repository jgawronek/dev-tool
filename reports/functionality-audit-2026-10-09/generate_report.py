from pathlib import Path
import json, csv, collections, html

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent

def events(file):
    result=[]
    for line in (ROOT / (file+'.jsonl')).read_text().splitlines():
        try: result.append(json.loads(line))
        except json.JSONDecodeError: pass
    return result

def cases(file, prefix=None):
    ev=events(file)
    starts={x['test']['id']:x['test'] for x in ev if x.get('type')=='testStart'}
    result=[]
    for x in ev:
        if x.get('type')!='testDone': continue
        t=starts.get(x['testID'],{})
        name=t.get('name','')
        if name.startswith('loading ') or (prefix and not name.startswith(prefix)): continue
        result.append({'name':name,'result':x['result'],'file':t.get('root_url',t.get('url')),
                       'evidenceLog':file+'.jsonl',
                       'messages':[y.get('message',y.get('error','')) for y in ev
                                   if y.get('testID')==x['testID'] and y.get('type') in ('print','error')]})
    return result

def records(file,prefix):
    return [json.loads(x['message'][len(prefix):]) for x in events(file)
            if x.get('type')=='print' and x.get('message','').startswith(prefix)]

samples=records('samples-final','FUNCTIONALITY_AUDIT ')
controls=records('fresh-final','CONTROL_AUDIT ')
custom=records('fresh-final','CUSTOM_AUDIT ')
fresh=cases('samples-final','sample audit:')
fresh += [c for c in cases('fresh-final') if not c['name'].startswith('sample audit:')]
baseline=cases('flutter-test')
manifest=json.loads((PROJECT/'screenshots/ui-audit-2026-10-09/manifest.json').read_text())
names={x['id']:x['name'] for x in manifest}
status_counts=collections.Counter(x['status'] for t in controls for x in t['records'])
findings=[]
for id in ['base64_string_encode_decode','url_encode_decode','html_entity_encode_decode','backslash_escape_unescape','yaml_json_converter']:
    findings.append({'priority':'P2','tool':id,'issue':'Load sample fills input but leaves output empty',
                     'reproduce':'Open a fresh tool, click Load sample, wait; output controller remains empty. Repeated sample clicks do not calculate the result.',
                     'expected':'The loaded sample should immediately produce the matching conversion result.',
                     'evidence':'samples-final.jsonl',
                     'nativeEvidence':'native-base64-sample.png' if id=='base64_string_encode_decode' else None})
findings += [
 {'priority':'P1','tool':'text_encryption','issue':'AES CFB/OFB fail on short plaintext',
  'reproduce':'Modern → AES-128/192/256-CFB or OFB; key KEY; Encrypt; plaintext HELLO WORLD. Both Base64 and Hex fail.',
  'expected':'Valid 11-byte text should encrypt and decrypt successfully.',
  'observed':'Error: Invalid argument(s): Input buffer too short; empty ciphertext.',
  'evidence':'encryption-matrix.jsonl','nativeEvidence':'native-aes-cfb-failure.png'},
 {'priority':'P1','tool':'text_encryption','issue':'ChaCha20 fails with IV length error',
  'reproduce':'Modern → ChaCha20; key KEY; Encrypt; plaintext HELLO WORLD; either output format.',
  'expected':'Encryption should produce ciphertext that decrypts back to the input.',
  'observed':'Error: Invalid argument(s): ChaCha20 requires exactly 8 bytes of IV.',
  'evidence':'encryption-errors.jsonl'},
 {'priority':'P2','tool':'random_string_generator','issue':'Words field is ignored',
  'reproduce':'Set upper/lower/symbol/digit counts to 0, Words to 3, then click Load sample (the generation action).',
  'expected':'Generate nonempty strings containing the requested words.',
  'observed':'Only blank lines are generated. Source also leaves Seed, Separator, Separating Group Size and Custom Character Set disconnected from generation.',
  'evidence':'journeys-final.jsonl'},
 {'priority':'P2','tool':'jwt_debugger','issue':'Algorithm row overflows by 46 pixels',
  'reproduce':'Open JWT Debugger at the 2560×1640 test viewport.',
  'expected':'The dropdown and label should fit within Token details.',
  'observed':'RenderFlex overflowed by 46 pixels on the right. HS256/384/512 signature correctness checks passed.',
  'evidence':'controls-final.jsonl'},
 {'priority':'P2','tool':'documentation','issue':'Documentation ListTiles trigger Flutter assertions',
  'reproduce':'Open Documentation and search CSV Inspector.',
  'expected':'Menu selection and ink effects should render without assertions.',
  'observed':'ListTile background color or ink splashes may be invisible: ColoredBox hides the Material painting. Search and closing work, but the debug assertion causes the test to fail.',
  'evidence':'journeys-final.jsonl'},
]
summary={
 'commit':'225ea38','date':'2026-10-09','tools':76,
 'baseline':dict(collections.Counter(x['result'] for x in baseline)),
 'fresh':dict(collections.Counter(x['result'] for x in fresh)),
 'freshCases':len(fresh),'baselineCases':len(baseline),
 'sampleAvailable':sum(x['samplePresent'] for x in samples),
 'sampleUnavailable':[x['tool'] for x in samples if not x['samplePresent']],
 'controlStatuses':dict(status_counts),
 'dropdownOptionsExercised':sum(len(x.get('options',[])) for t in controls for x in t['records']),
 'findings':findings,
 'coverageLimits':[
  'Fresh sweeps cover controls discovered in the visited states; they are not proof of every possible combination, dynamic branch, or output value.',
  'Some dropdowns/toggles, editor inputs and offscreen controls were exercised through callbacks. 213 visible buttons were hit-tested and tapped; 10 button checks used callbacks.',
  'Subdomain Find known; takeover Scan; port Scan/Recon; network Detect LAN/Scan; firewall Fingerprint were not invoked through the widget UI. Existing service tests use controlled fixtures for these services.',
  'Local server Start is verified at service level with loopback HTTP; the native folder picker/Start combination is not end-to-end verified.',
  'Offline LLM refresh/download/installed-model generation remain unverified. A local model path was requested; no model was supplied during this run.',
  'Native file picker save/open, print dialog, actual Finder interactions, and OS-specific delivery paths are not exhaustively verified. Automated file/dialog tests use mocked or cancelled channels.',
  'Samples are checked twice in their default states, with output snapshots. Most sample outputs have not been independently checked against a full known-answer oracle.',
  'The 126 baseline failures include obsolete Clear/Paste/Sample menu expectations, copy-icon names and old field selectors; do not interpret them as 126 confirmed app defects.',
 ],
 'passedChecks':[
  'All 76 registered tool pages opened in the current shell; all 58 available Load sample actions were clicked twice.',
  'Password batches: all 4 styles, 500 entries, Copy all exact clipboard content, invalid counts 0/501/-1/abc/1.5/empty and recovery to 1.',
  'UUID sample populates generated IDs; every listed generation type produces 10 unique IDs.',
  'Line sorting produces output immediately from its sample; ascending/descending and duplicate-removal results match expected values.',
  'All 6 compression formats roundtrip through the UI; malformed input, clearing through text editing, and recovery were checked.',
  'JWT HS256/HS384/HS512: decoded header/payload, valid signature, wrong-key mismatch and correction.',
  '44 of 58 encryption algorithm/format roundtrip checks passed; 14 failed across the 6 AES CFB/OFB options and ChaCha20.',
  'HTTP GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS tested through URL Parser Send against loopback; service tests also check body/header forwarding, non-JSON/error responses, redirects and the 2 MB limit.',
  'AntiBot Run identifies a synthetic Cloudflare response served locally.',
  'Local server serves index/static files, handles HEAD/404/405, logs requests and stops cleanly.',
  'TOTP add/edit, generated code display and mocked preference persistence; favorites toggle, tool search/navigation and documentation guide presence.',
  'Static analysis of all 9 new audit test files: no issues.',
 ],
}
(ROOT/'summary.json').write_text(json.dumps(summary,indent=2))
(ROOT/'test-cases.json').write_text(json.dumps({'baseline':baseline,'fresh':fresh},indent=2))
(ROOT/'control-evidence.json').write_text(json.dumps({'samples':samples,'controls':controls,'custom':custom},indent=2))
with (ROOT/'findings.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,lineterminator='\n',fieldnames=['priority','tool','issue','reproduce','expected','observed','evidence','nativeEvidence'])
    writer.writeheader();writer.writerows(findings)
with (ROOT/'coverage.csv').open('w',newline='') as f:
    writer=csv.writer(f,lineterminator='\n');writer.writerow(['Tool','Sample','Sample errors','Control records','Control errors','Deferred buttons'])
    for tool in manifest[:76]:
        s=next(x for x in samples if x['tool']==tool['id']);c=next(x for x in controls if x['tool']==tool['id'])
        writer.writerow([tool['name'],s['samplePresent'],'; '.join(s['errors']),len(c['records']),'; '.join(c['errors']),'; '.join(x['control'] for x in c['records'] if x['status'].startswith('deferred'))])

def esc(value): return html.escape(str(value))
def list_html(items): return '<ul>'+''.join('<li>'+esc(i)+'</li>' for i in items)+'</ul>'
rows=[]
for tool in manifest[:76]:
    id=tool['id'];s=next(x for x in samples if x['tool']==id);c=next(x for x in controls if x['tool']==id)
    detail=next(x for x in custom if x['tool']==id)
    sample_status='Unavailable' if not s['samplePresent'] else 'Failed' if s['errors'] else 'Clicked twice; snapshot checked'
    issues=[x['issue'] for x in findings if x['tool']==id]
    deferred=[x['control'] for x in c['records'] if x['status'].startswith('deferred')]
    if id in ['url_parser','antibot_detection']: deferred=[]
    panel='<details><summary>Inspect controls and sample snapshots</summary><pre>'+esc(json.dumps({'sample':s,'controls':c,'custom':detail},indent=2))+'</pre></details>'
    rows.append('<tr data-search="'+esc(tool['name']+' '+id+' '+' '.join(issues))+'"><td><strong>'+esc(tool['name'])+'</strong><br><a href="../../screenshots/ui-audit-2026-10-09/'+esc(tool['file'])+'">Screen</a></td><td>'+esc(sample_status)+'</td><td>'+str(len(c['records']))+' records'+panel+'</td><td>'+list_html(issues or ['No defect found by these checks'])+list_html(['Unverified action: '+x for x in deferred])+'</td></tr>')
findings_html=''
for item in sorted(findings,key=lambda x:x['priority']):
    evidence='<a href="'+item['evidence']+'">Test log</a>'
    if item.get('nativeEvidence'):evidence+=' · <a href="'+item['nativeEvidence']+'">Native screenshot</a>'
    findings_html+='<article><h3>'+item['priority']+' · '+esc(names.get(item['tool'],item['tool']))+' · '+esc(item['issue'])+'</h3><p><b>Reproduce:</b> '+esc(item['reproduce'])+'</p><p><b>Expected:</b> '+esc(item['expected'])+'</p><p><b>Observed:</b> '+esc(item.get('observed','Output stays empty.'))+'</p><p>'+evidence+'</p></article>'
failed_rows=''.join('<tr><td>'+esc(x['name'])+'</td><td><a href="'+x['evidenceLog']+'">Log</a></td></tr>' for x in baseline if x['result']=='error')
html_doc='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>DevUtils functionality audit</title><style>
:root{font:15px/1.55 system-ui,sans-serif;color:#24242c;background:#faf9f6}body{max-width:1440px;margin:32px auto;padding:0 24px}h1{font-size:32px}h2{margin-top:40px}a{color:#914728}nav{display:flex;gap:22px;flex-wrap:wrap}article{border:1px solid #dedbd5;background:white;border-radius:8px;padding:10px 20px;margin:16px 0}table{width:100%;border-collapse:collapse;background:white}th,td{border-bottom:1px solid #dedbd5;text-align:left;vertical-align:top;padding:12px}th{background:#eeeae3}pre{white-space:pre-wrap;overflow-wrap:anywhere;max-height:480px;overflow:auto;font-size:12px}input{width:min(600px,90%);padding:12px;border:1px solid #aaa;border-radius:6px;margin:16px 0}.banner{padding:16px;background:#efe8de;border-left:4px solid #9a4b30}summary{cursor:pointer}li{margin-bottom:6px}.small{font-size:13px;color:#555}td:nth-child(1){width:20%}td:nth-child(2){width:15%}td:nth-child(3){width:25%}</style><h1>DevUtils functionality audit</h1><p>2026-10-09 · app source commit 225ea38 · Flutter widget/service checks plus native confirmation</p><nav><a href="#results">Results</a><a href="#bugs">Confirmed failures</a><a href="#tools">All 76 tools</a><a href="#limits">Coverage limits</a><a href="#baseline">Existing suite</a><a href="summary.json">JSON summary</a><a href="findings.csv">Findings CSV</a><a href="coverage.csv">Coverage CSV</a></nav>
<div class="banner"><b>Testing is not fully green.</b> Every registered tool page was covered, but every functionality path has not been fully verified. External scan/model actions and native dialogs have remaining gaps. A callback that does not crash is not evidence that its output is correct.</div>
<h2 id="results">Results</h2>'''
html_doc+=f'<p><b>{len(fresh)} fresh test cases: {summary["fresh"].get("success",0)} passed, {summary["fresh"].get("error",0)} failed.</b> Latest results per case are shown; loading events and repeated diagnostic runs are excluded. A concurrent sample check initially completed before password hashing finished; a bounded real-time wait was added and all samples were rerun. Failures include repeated checks of the same defect.</p>'
html_doc+='<p>76 tool pages; 58 sample actions clicked twice; 213 visible buttons tapped; 10 button callbacks used because the controls were not hit-testable; 289 dropdown option callbacks; 57 editor input and 57 form field robustness checks. Disabled and deferred controls are recorded separately.</p>'+list_html(summary['passedChecks'])
html_doc+='<h2 id="bugs">Confirmed failures — 10 issue groups</h2>'+findings_html
html_doc+='<h2 id="tools">Per-tool evidence</h2><p>“No defect found” describes the checks performed, not complete correctness certification. Search a tool, then expand its evidence for exact input/output snapshots and control statuses.</p><input id="search" placeholder="Search tools or issues" aria-label="Search tool coverage"><table id="coverage"><thead><tr><th>Tool</th><th>Load sample</th><th>Controls</th><th>Findings / remaining actions</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table>'
html_doc+='<h2 id="limits">Coverage limits</h2>'+list_html(summary['coverageLimits'])
html_doc+='<h2 id="baseline">Existing test suite</h2><p>690 existing test cases: 564 passed and 126 failed. Many failures refer to removed UI controls or old selectors. These are preserved as test failures rather than counted as confirmed app defects. Existing green tests also cover serializers, formatters, parsers, encryption helpers, file processing, networking services and diagram operations.</p><details><summary>Show all existing failures</summary><table><tr><th>Test</th><th>Evidence</th></tr>'+failed_rows+'</table></details>'
html_doc+='<h2>Repeat the checks</h2><pre>flutter test test/ui/functionality_audit_test.dart test/ui/control_audit_test.dart test/ui/additional_controls_audit_test.dart test/ui/generation_regression_audit_test.dart test/ui/output_contract_audit_test.dart test/ui/dialog_journeys_audit_test.dart test/ui/local_network_journeys_audit_test.dart test/ui/encryption_matrix_audit_test.dart test/local_http_audit_test.dart\npython3 reports/functionality-audit-2026-10-09/generate_report.py</pre><p class="small">Application implementation was not changed during this audit. Failing regression tests remain visible so the defects can be fixed and rechecked.</p><script>document.querySelector("#search").addEventListener("input",e=>{const q=e.target.value.toLowerCase();document.querySelectorAll("#coverage tbody tr").forEach(r=>r.hidden=!r.dataset.search.toLowerCase().includes(q))})</script></html>'
(ROOT/'REPORT.html').write_text(html_doc)
print(json.dumps({'freshCases':len(fresh),'freshResults':summary['fresh'],'findings':len(findings),'report':str(ROOT/'REPORT.html')},indent=2))
