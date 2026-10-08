#!/usr/bin/env python3
"""Converts the design prototype's levels (keystone-engine.js, 300x380 y-down box, ground at y=380)
into schema-1 level JSON (centre positions, y up, floor at y=-190).

Output files carry no annotation: LevelForge solves and annotates them (make forge-curated).
"""
import json, os, sys

FLOOR = -190.0

def conv_piece(p):
    m = {'wood': 'wood', 'stone': 'stone', 'steel': 'steel', 'key': 'brass', 'rope': 'rope'}[p['m']]
    w, h = float(p['w']), float(p['h'])
    cx = p['x'] + w / 2 - 150
    cy = 380 - (p['y'] + h / 2) - 190
    if m == 'brass':
        shape = {'type': 'polygon', 'points': [[-0.3 * w, -h / 2], [0.3 * w, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]}
    else:
        shape = {'type': 'rect', 'w': w, 'h': h}
    fixed = bool(p.get('fixed', False))
    return {
        'id': p['id'], 'material': m, 'shape': shape,
        'position': {'x': round(cx, 2), 'y': round(cy, 2)}, 'rotation': 0,
        'fixed': fixed, 'removable': (not fixed) and m != 'brass',
    }

def level(id, index, region, name, pieces, goal, supports=0, tutorial=None, goal_text=None):
    out = {
        'schema': 1, 'id': id, 'pack': 'curated', 'region': region, 'index': index,
        'gravity': -9.8, 'floorY': FLOOR, 'name': name, 'goal': goal,
        'supportsAllowed': supports, 'pieces': [conv_piece(p) for p in pieces], 'joints': [],
    }
    if tutorial: out['tutorial'] = tutorial
    if goal_text: out['goalText'] = goal_text
    return out

P = lambda id, m, x, y, w, h, fixed=False: dict(id=id, m=m, x=x, y=y, w=w, h=h, fixed=fixed)

LEVELS = [
    level('c-001', 1, 'wood_scaffold', {'en': 'First Block', 'tr': 'İlk Blok'}, [
        P('g1', 'stone', 80, 330, 140, 50, True), P('p1', 'wood', 100, 250, 24, 80), P('p2', 'wood', 176, 250, 24, 80),
        P('bm', 'wood', 86, 232, 128, 18), P('tb', 'stone', 125, 182, 50, 50)],
        {'type': 'removeTargetsKeepStanding', 'targetPieceIds': ['tb'], 'moveBudget': 2, 'starThresholds': [1, 2, 2]},
        tutorial=1),
    level('c-002', 2, 'wood_scaffold', {'en': 'Three Posts', 'tr': 'Üç Direk'}, [
        P('pl', 'wood', 60, 290, 20, 90), P('pm', 'wood', 140, 290, 20, 90), P('pr', 'wood', 220, 290, 20, 90),
        P('bm', 'wood', 40, 272, 220, 18), P('st', 'stone', 120, 222, 60, 50)],
        {'type': 'removeTargetsKeepStanding', 'targetPieceIds': ['pl', 'pm', 'pr'], 'requiredCount': 2, 'moveBudget': 3, 'starThresholds': [2, 3, 3]},
        tutorial=2),
    level('c-003', 3, 'wood_scaffold', {'en': 'One Support', 'tr': 'Tek Destek'}, [
        P('p1', 'wood', 40, 260, 24, 120), P('p2', 'wood', 236, 260, 24, 120),
        P('bm', 'wood', 20, 242, 260, 18), P('st', 'stone', 125, 192, 50, 50)],
        {'type': 'placeSupportThenRemove', 'targetPieceIds': ['p1', 'p2'], 'moveBudget': 4, 'starThresholds': [3, 4, 4]},
        supports=1, tutorial=3),
    level('c-004', 4, 'wood_scaffold', {'en': 'Clean Drop', 'tr': 'Temiz Düşüş'}, [
        P('pa', 'wood', 70, 300, 24, 80), P('pb', 'wood', 206, 300, 24, 80), P('bm', 'wood', 50, 282, 200, 18),
        P('sl', 'stone', 90, 232, 30, 50), P('sc', 'stone', 135, 232, 30, 50), P('sr', 'stone', 180, 232, 30, 50),
        P('k', 'key', 100, 192, 100, 40)],
        {'type': 'dropOnlyTarget', 'targetPieceIds': ['k'], 'moveBudget': 3, 'starThresholds': [2, 3, 3]}),
    level('c-005', 5, 'wood_scaffold', {'en': 'Pinned Lintel', 'tr': 'Sabitli Lento'}, [
        P('b1', 'stone', 30, 320, 70, 60, True), P('b2', 'stone', 200, 320, 70, 60, True),
        P('s1', 'steel', 144, 210, 12, 170), P('w1', 'wood', 48, 210, 28, 110), P('w2', 'wood', 224, 210, 28, 110),
        P('w3', 'wood', 20, 190, 260, 20), P('t1', 'stone', 62, 135, 54, 55), P('t2', 'stone', 184, 135, 54, 55),
        P('w4', 'wood', 48, 117, 204, 18), P('k', 'key', 122, 72, 56, 45), P('w5', 'wood', 182, 57, 70, 60)],
        {'type': 'removeTargetsKeepStanding', 'targetPieceIds': ['w1', 'w2', 'w3', 'w4', 'w5'], 'requiredCount': 3, 'moveBudget': 5, 'starThresholds': [3, 4, 5]}),
    level('c-006', 6, 'wood_scaffold', {'en': 'Counterweight', 'tr': 'Karşı Ağırlık'}, [
        P('sc', 'steel', 140, 260, 20, 120), P('bm', 'wood', 20, 244, 260, 16),
        P('a', 'stone', 30, 214, 30, 30), P('b', 'stone', 70, 214, 30, 30), P('c', 'stone', 200, 214, 30, 30),
        P('d', 'stone', 240, 214, 30, 30), P('pd', 'wood', 135, 214, 30, 30), P('k', 'key', 120, 174, 60, 40)],
        {'type': 'placeSupportThenRemove', 'targetPieceIds': ['a', 'b', 'c', 'd'], 'moveBudget': 6, 'starThresholds': [5, 6, 6]},
        supports=1),
    level('c-007', 7, 'wood_scaffold', {'en': 'Twin Piers', 'tr': 'İkiz Ayak'}, [
        P('bl', 'stone', 30, 330, 60, 50, True), P('br', 'stone', 210, 330, 60, 50, True),
        P('pl', 'wood', 46, 250, 28, 80), P('pr', 'wood', 226, 250, 28, 80),
        P('cl', 'stone', 36, 220, 74, 30), P('cr', 'stone', 190, 220, 74, 30),
        P('sp', 'steel', 143, 220, 14, 160), P('k', 'key', 80, 180, 140, 40)],
        {'type': 'dropOnlyTarget', 'targetPieceIds': ['k'], 'moveBudget': 3, 'starThresholds': [2, 3, 3]}),
]

def main(out_dir, fixtures_dir=None):
    os.makedirs(out_dir, exist_ok=True)
    for l in LEVELS:
        with open(os.path.join(out_dir, l['id'] + '.json'), 'w', encoding='utf-8') as f:
            json.dump(l, f, indent=2, ensure_ascii=False, sort_keys=True)
            f.write('\n')
    if fixtures_dir:
        os.makedirs(fixtures_dir, exist_ok=True)
        for l in LEVELS[:1] + LEVELS[3:4] + LEVELS[2:3]:
            with open(os.path.join(fixtures_dir, l['id'] + '.json'), 'w', encoding='utf-8') as f:
                json.dump(l, f, indent=2, ensure_ascii=False, sort_keys=True)
                f.write('\n')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
