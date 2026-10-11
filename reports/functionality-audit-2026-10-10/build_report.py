"""Extract reproducible per-tool evidence from the final test logs."""
import csv
import json
from pathlib import Path
root = Path(__file__).parent
markers = ['FUNCTIONALITY_AUDIT', 'CONTROL_AUDIT', 'DROPDOWN_MENU_AUDIT', 'CUSTOM_AUDIT']
data = {m:{} for m in markers}
for line in (root/'final-tests.log').read_text().splitlines():
    for marker in markers:
        if line.startswith(marker+' '):
            record=json.loads(line[len(marker)+1:])
            data[marker][record['tool']]=record
native={}
for line in (root/'final-native.log').read_text().splitlines():
    if line.startswith('FUNCTIONALITY_AUDIT '):
        record=json.loads(line[len('FUNCTIONALITY_AUDIT '):]);native[record['tool']]=record
rows=[]
for tool,sample in data['FUNCTIONALITY_AUDIT'].items():
    control=data['CONTROL_AUDIT'].get(tool,{})
    menus=data['DROPDOWN_MENU_AUDIT'].get(tool,{})
    records=control.get('records',[])
    rows.append({'tool':tool,'sample_present':sample.get('samplePresent',False),
       'sample_errors':sample.get('errors',[]),'native_sample_checked':tool in native,
       'control_records':len(records),
       'buttons_tapped':sum(r.get('status')=='button tapped' for r in records),
       'dropdown_selections':sum(len(m['selected']) for m in menus.get('menus',[])),
       'deferred_in_generic_sweep':[r['control'] for r in records if 'deferred' in r.get('status','')],
       'control_errors':control.get('errors',[]),
       'scope':'Sample smoke, actual dropdown menus, control/input robustness; detailed correctness tests are listed in README.'})
(root/'tool-matrix.json').write_text(json.dumps(rows,indent=2)+'\n')
with (root/'tool-matrix.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
(root/'evidence.json').write_text(json.dumps({'headless':data,'native_samples':native},indent=2)+'\n')
print(f'{len(rows)} tools; {sum(r["dropdown_selections"] for r in rows)} menu selections; {len(native)} native sample checks')
