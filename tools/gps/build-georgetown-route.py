#!/usr/bin/env python3
"""Regenerate the QA route from GeorgetownGPS's checked-in coordinates."""
import json
import math
from pathlib import Path
import re

folder = Path(__file__).resolve().parent
source = folder.parents[1] / 'Pinpoint/Models/CourseGPS.swift'
text = source.read_text()
point = r'GeoPoint\(latitude: ([\d.-]+), longitude: ([\d.-]+)\)'
layouts = {}
for number in (1, 2, 3):
    block = text.split(f'        {number}: HoleLayout(', 1)[1].split(f'        {number + 1}: HoleLayout(', 1)[0]
    def field(name):
        return list(map(float, re.search(name + r': ' + point, block).groups()))
    path_text = block.split('path: [', 1)[1].split(']', 1)[0]
    layouts[number] = dict(tee=field('tee'), pin=field('pin'), front=field('greenFront'), path=[list(map(float, pair)) for pair in re.findall(point, path_text)])


def offset(p, north=0, east=0):
    return [round(p[0] + north / 111320, 7), round(p[1] + east / (111320 * math.cos(math.radians(p[0]))), 7)]


phases = []
def stop(name, p, seconds=35):
    phases.append(dict(kind='stop', name=name, seconds=seconds, coordinate=p))


def move(name, points, speed=5):
    phases.append(dict(kind='move', name=name, speed_mps=speed, coordinates=points))


one, two, three = [layouts[i] for i in (1, 2, 3)]
stop('Hole 1 — mapped tee / driver', one['tee'], 45)
move('Hole 1 — cart to fairway', one['path'][:2])
stop('Hole 1 — fairway / approach', one['path'][1], 35)
near1 = offset(one['front'], north=12)
move('Hole 1 — cart to greenside', [one['path'][1], near1])
stop('Hole 1 — greenside / chip', near1, 30)
move('Hole 1 — walk to putting position', [near1, one['front']], 1.1)
stop('Hole 1 — first putt', one['front'], 30)
move('Hole 1 — walk to cup', [one['front'], one['pin']], 0.9)
stop('Hole 1 — finish putting', one['pin'], 25)
move('Transition — hole 1 green to hole 2 tee', [one['pin'], two['tee']], 2.5)
stop('Hole 2 — mapped tee / driver', two['tee'], 40)
# A synthetic miss 25m north of the mapped landing centerline (rough scenario).
rough = offset(two['path'][1], north=25)
move('Hole 2 — cart to rough', [two['tee'], offset(two['path'][1], north=55, east=40), rough])
stop('Hole 2 — rough / recovery', rough, 40)
near2 = offset(two['front'], north=12, east=10)
move('Hole 2 — cart toward green', [rough, near2], 4)
stop('Hole 2 — greenside / wedge', near2, 35)
move('Hole 2 — walk to first putt', [near2, two['front']], 1.1)
stop('Hole 2 — first putt', two['front'], 30)
move('Hole 2 — walk to cup', [two['front'], two['pin']], 0.9)
stop('Hole 2 — finish putting', two['pin'], 25)
move('Transition — hole 2 green to hole 3 tee', [two['pin'], three['tee']], 2)
stop('Hole 3 — par-three mapped tee / iron', three['tee'], 40)
near3 = offset(three['front'], north=12, east=8)
move('Hole 3 — cart toward green', [three['tee'], near3], 4.5)
stop('Hole 3 — greenside / chip', near3, 30)
move('Hole 3 — walk onto green', [near3, three['front']], 1.1)
stop('Hole 3 — first putt', three['front'], 30)
move('Hole 3 — walk to cup', [three['front'], three['pin']], 0.9)
stop('Hole 3 — finish putting', three['pin'], 25)
route = dict(name='Georgetown Country Club — holes 1–3',
    description='Synthetic golf-cart route based on the exact GeorgetownGPS tees, hole corridors, green fronts and pins used by Pinpoint. Rough/greenside stops and drive paths are approximate QA scenarios, not surveyed cart paths.',
    source='Pinpoint/Models/CourseGPS.swift (GeorgetownGPS); underlying map coordinates © OpenStreetMap contributors, ODbL 1.0: https://www.openstreetmap.org/copyright',
    phases=phases)
(folder / 'georgetown-country-club.json').write_text(json.dumps(route, indent=2) + '\n')
print('Generated Georgetown route from', source)
