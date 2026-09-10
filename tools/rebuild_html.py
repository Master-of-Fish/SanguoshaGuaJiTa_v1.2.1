#!/usr/bin/env python3
from pathlib import Path
import json,re,shutil
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'data'; P=ROOT/'index.html'
html=P.read_text(encoding='utf-8')
modules='// BEGIN V121 MODULES\n'+'\n'.join((ROOT/'src'/name).read_text(encoding='utf-8') for name in ['ascension_v121.js','ux_v121.js','support_v121.js','button_guard_v121.js'])+'\n// END V121 MODULES'
html=re.sub(r'// BEGIN (?:V111|V120|V121) MODULES\n.*?// END (?:V111|V120|V121) MODULES',lambda m:modules,html,count=1,flags=re.S)
def compact(name):
    return json.dumps(json.loads((DATA/name).read_text(encoding='utf-8')),ensure_ascii=False,separators=(',',':')).replace('\u2028','\\u2028').replace('\u2029','\\u2029')
def sub_once(pattern,replacement,text,flags=0):
    return re.sub(pattern,lambda m:replacement,text,count=1,flags=flags)
html=sub_once(r'const GENERALS=.*?; const WEAPONS=.*?; const PETS=.*?; const SKINS=.*?;\n','const GENERALS='+compact('generals.json')+'; const WEAPONS='+compact('weapons.json')+'; const PETS='+compact('pets.json')+'; const SKINS='+compact('skins.json')+';\n',html,re.S)
adv=json.loads((DATA/'adventure.json').read_text(encoding='utf-8'))
adv_s=json.dumps(adv,ensure_ascii=False,separators=(',',':')).replace('\u2028','\\u2028').replace('\u2029','\\u2029')
html=sub_once(r'const ADVENTURE_DATA=.*?;\nconst TECH_QUALITIES=', 'const ADVENTURE_DATA='+adv_s+';\nconst TECH_QUALITIES=', html, re.S)
cards=json.loads((DATA/'cards.json').read_text(encoding='utf-8'))
tricks=json.dumps(cards['tricks'],ensure_ascii=False,separators=(',',':')).replace('\u2028','\\u2028').replace('\u2029','\\u2029')
html=sub_once(r'const TRICKS=.*?;','const TRICKS='+tricks+';',html)
cards_s=json.dumps(cards,ensure_ascii=False,separators=(',',':')).replace('\u2028','\\u2028').replace('\u2029','\\u2029')
html=sub_once(r'const CARD_CATALOG=.*?;\nconst GID_BY_NAME=','const CARD_CATALOG='+cards_s+';\nconst GID_BY_NAME=',html,re.S)
P.write_text(html,encoding='utf-8')
shutil.copy2(P,ROOT/'web/index.html'); shutil.copy2(P,ROOT/'三国杀挂机塔_双击运行.html')
# Keep all entrypoint bytes identical; web assets are copied for file:// use.
shutil.copytree(ROOT/'assets',ROOT/'web/assets',dirs_exist_ok=True)
print('[+] HTML 内嵌数据已安全重建')
