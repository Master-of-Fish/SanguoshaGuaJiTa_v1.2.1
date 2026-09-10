#!/usr/bin/env python3
from pathlib import Path
import json
R=Path(__file__).resolve().parents[1];h=(R/'index.html').read_text()
def ck(v,n):
 if not v: raise SystemExit('FAIL: '+n)
ck((R/'VERSION.txt').read_text().strip()=='1.2.1','version')
ck("version:'1.2.1'" in h and 'sgs_idle_v1210' in h and 'SGST121-' in h,'save')
ck('skins:200' in h and 'feature-unlock-toast' in h and 'showUnlockNotice' in h,'unlock flow')
ck("titles.length<5" in h and '⌄ 点击展开' in h and '⌃ 点击收起' in h,'reduced collapse')
ck(".term-help,.help-dot" in h and 'stopImmediatePropagation' in h,'left click help')
ck(".notice:not([id])" in h and 'id="equipped"' in h,'preserve functional notice nodes')
ck((R/'index.html').read_bytes()==(R/'web/index.html').read_bytes()==(R/'三国杀挂机塔_双击运行.html').read_bytes(),'entrypoints')
r=json.loads((R/'docs/LOGIC_TEST_V121.json').read_text());ck(r['failed']==0 and r['passed']>=18,'logic tests')
ck(json.loads((R/'BUTTON_TEST_V121.json').read_text())['overall']=='PASS','button report')
print('OK: v1.2.1 validated')
