#!/usr/bin/env python3
"""Export catalog SVG paths to iOS vector PDFs and Android VectorDrawables.

Authoring only: pip install svglib reportlab. No app/build dependency on Python.
"""
import json
import pathlib
import re
import xml.etree.ElementTree as ET
from reportlab.graphics import renderPDF
from svglib.svglib import svg2rlg

root = pathlib.Path(__file__).resolve().parents[1]
catalog = json.loads((root / 'shared/stretch/catalog.json').read_text())
ns = '{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android', ns[1:-1])
for movement in catalog['movements']:
    if not movement.get('artwork'):
        continue
    name = movement['artwork']
    source = root / 'shared/stretch/illustrations' / (movement['id'] + '.svg')
    svg = ET.parse(source).getroot()
    assert not any(e.tag.endswith('image') for e in svg.iter()), source
    width, height = float(svg.attrib['width']), float(svg.attrib['height'])
    asset = root / 'ios/Outbound/Outbound/Assets.xcassets' / (name + '.imageset')
    asset.mkdir(parents=True, exist_ok=True)
    drawing = svg2rlg(str(source))
    renderPDF.drawToFile(drawing, str(asset / (name + '.pdf')))
    (asset / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': name + '.pdf', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1},
        'properties': {'preserves-vector-representation': True},
    }, indent=2) + '\n')
    vector = ET.Element('vector', {
        ns+'width': '256dp', ns+'height': f'{256*height/width:.3f}dp',
        ns+'viewportWidth': str(width), ns+'viewportHeight': str(height),
    })
    for path in svg:
        if path.tag.split('}')[-1] != 'path':
            continue
        parent = vector
        if transform := path.get('transform'):
            match = re.fullmatch(r'translate\(([-\d.]+)[, ]+([-\d.]+)\)', transform)
            assert match, (source, transform)
            parent = ET.SubElement(vector, 'group', {ns+'translateX': match[1], ns+'translateY': match[2]})
        ET.SubElement(parent, 'path', {
            ns+'fillColor': path.attrib['fill'], ns+'pathData': path.attrib['d'],
            ns+'fillType': path.get('fill-rule', 'nonZero').replace('evenodd', 'evenOdd'),
        })
    destination = root / 'android/feature/recording/src/main/res/drawable' / (name+'.xml')
    destination.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(vector)
    ET.ElementTree(vector).write(destination, encoding='utf-8', xml_declaration=True)
print('Exported vector artwork for both native clients.')
