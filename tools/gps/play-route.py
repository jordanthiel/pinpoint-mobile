#!/usr/bin/env python3
"""Timed CoreSimulator location playback; no app data or motion events are injected."""
import argparse
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET

DEFAULT = Path(__file__).with_name('georgetown-country-club.json')


def distance(a, b):
    a1, a2 = map(math.radians, (a[0], b[0]))
    da, dl = a2 - a1, math.radians(b[1] - a[1])
    return 6371000 * 2 * math.asin(min(1, math.sqrt(math.sin(da / 2)**2 + math.cos(a1) * math.cos(a2) * math.sin(dl / 2)**2)))


def duration(phase):
    if phase['kind'] == 'stop':
        return phase['seconds']
    return sum(distance(a, b) for a, b in zip(phase['coordinates'], phase['coordinates'][1:])) / phase['speed_mps']


def point_at(phase, elapsed):
    if phase['kind'] == 'stop':
        return phase['coordinate']
    remaining = elapsed * phase['speed_mps']
    for a, b in zip(phase['coordinates'], phase['coordinates'][1:]):
        length = distance(a, b)
        if remaining <= length:
            fraction = remaining / length if length else 0
            return [a[i] + fraction * (b[i] - a[i]) for i in (0, 1)]
        remaining -= length
    return phase['coordinates'][-1]


def validate(route):
    previous = None
    for phase in route['phases']:
        assert phase['kind'] in ('stop', 'move')
        points = [phase['coordinate']] if phase['kind'] == 'stop' else phase['coordinates']
        assert points and all(len(p) == 2 and all(math.isfinite(v) for v in p) and -90 <= p[0] <= 90 and -180 <= p[1] <= 180 for p in points)
        if phase['kind'] == 'stop':
            assert phase['seconds'] >= 8, 'Stops must exceed detector dwell threshold'
        else:
            assert len(points) >= 2 and 0 < phase['speed_mps'] <= 7
        assert previous is None or distance(previous, points[0]) < 0.1, 'Route teleports between phases'
        previous = points[-1]


def export_gpx(route, path):
    # Xcode uses wpt elements. One-second samples plus timestamped identical points retain stops.
    root = ET.Element('gpx', version='1.1', creator='Pinpoint GPS QA', xmlns='http://www.topografix.com/GPX/1/1')
    metadata = ET.SubElement(root, 'metadata')
    ET.SubElement(metadata, 'name').text = route['name']
    ET.SubElement(metadata, 'desc').text = route['description'] + ' ' + route['source']
    offset = 0.0
    epoch = datetime(2026, 9, 14, 15, tzinfo=timezone.utc)
    last_time = -1.0
    for phase in route['phases']:
        seconds = duration(phase)
        ticks = [float(i) for i in range(math.ceil(seconds))] + [seconds]
        for tick in ticks:
            timestamp = offset + tick
            if timestamp <= last_time + 0.0001:
                continue
            last_time = timestamp
            lat, lon = point_at(phase, tick)
            node = ET.SubElement(root, 'wpt', lat=f'{lat:.7f}', lon=f'{lon:.7f}')
            ET.SubElement(node, 'time').text = (epoch + timedelta(seconds=timestamp)).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
            ET.SubElement(node, 'name').text = phase['name']
        offset += seconds
    ET.indent(root)
    ET.ElementTree(root).write(path, encoding='utf-8', xml_declaration=True)


def dwell_point(point, tick):
    # CoreSimulator can suppress identical coordinate updates. Sub-meter jitter
    # supplies fresh fixes throughout a pause without resembling a moving golfer.
    angle = tick * math.pi / 2
    return [point[0] + math.sin(angle) * 0.4 / 111_320,
            point[1] + math.cos(angle) * 0.4 / (111_320 * math.cos(math.radians(point[0])))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--route', type=Path, default=DEFAULT)
    parser.add_argument('--device', action='append', default=[], help='Booted simulator UDID; repeat for a paired Watch')
    parser.add_argument('--dry-run', action='store_true', help='Print timeline without changing a simulator')
    parser.add_argument('--export-gpx', type=Path)
    parser.add_argument('--from-phase', type=int, default=1, help='Start at a numbered phase (1-based)')
    parser.add_argument('--limit-seconds', type=float, help='Stop early for a smoke test')
    args = parser.parse_args()
    if args.limit_seconds is not None and args.limit_seconds <= 0:
        parser.error('--limit-seconds must be positive')
    route = json.loads(args.route.read_text())
    validate(route)
    if not 1 <= args.from_phase <= len(route['phases']):
        parser.error('--from-phase is out of range')
    if args.export_gpx:
        export_gpx(route, args.export_gpx)
        print('Exported', args.export_gpx.resolve())
    total = 0.0
    for phase in route['phases']:
        seconds = duration(phase)
        label = 'STOP' if phase['kind'] == 'stop' else f"{phase['speed_mps']:.1f} m/s"
        print(f"{int(total)//60:02}:{int(total)%60:02}  {seconds:5.1f}s  {label:9} {phase['name']}")
        total += seconds
    print(f'Total: {total/60:.1f} minutes. GPS only; no synthetic IMU swings.', flush=True)
    if args.dry_run or (args.export_gpx and not args.device):
        return
    if not args.device:
        parser.error('Choose --device UDID explicitly, or use --dry-run')
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '-j']))
    booted = {d['udid'] for devices in inventory['devices'].values() for d in devices if d['state'] == 'Booted'}
    devices = list(dict.fromkeys(args.device))
    if any(d not in booted for d in devices):
        parser.error('Every requested simulator must be booted; use xcrun simctl list devices booted')

    def send(*action):
        for device in devices:
            subprocess.run(['xcrun', 'simctl', 'location', device, *action], check=True, stdout=subprocess.DEVNULL, timeout=15)

    def coordinate(p):
        return f'{p[0]:.7f},{p[1]:.7f}'

    began = time.monotonic()
    deadline = began + args.limit_seconds if args.limit_seconds else math.inf
    try:
        for phase in route['phases'][args.from_phase - 1:]:
            if time.monotonic() >= deadline:
                break
            print('Playing:', phase['name'], flush=True)
            if phase['kind'] == 'move':
                send('start', f"--speed={phase['speed_mps']}", '--interval=1', *map(coordinate, phase['coordinates']))
            else:
                send('set', coordinate(phase['coordinate']))
            dwell_tick = 0
            end = min(time.monotonic() + duration(phase), deadline)
            while time.monotonic() < end:
                time.sleep(min(1, max(0, end - time.monotonic())))
                if phase['kind'] == 'stop' and time.monotonic() < end:
                    dwell_tick += 1
                    send('set', coordinate(dwell_point(phase['coordinate'], dwell_tick)))
    except KeyboardInterrupt:
        print('\nStopped by user.')
    finally:
        for device in devices:
            subprocess.run(['xcrun', 'simctl', 'location', device, 'clear'], check=False, timeout=15)
        print('GPS simulation cleared.')


if __name__ == '__main__':
    main()
