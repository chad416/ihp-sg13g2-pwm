"""Render a GDS to PNG with KLayout in batch mode, using the IHP layer colours.

Run:  klayout -b -r scripts/render_gds.py -rd gds=<in.gds> -rd png=<out.png> \
              -rd lyp=<layers.lyp> [-rd width=2000] [-rd box=x1,y1,x2,y2 (um)]
"""

import pya

gds = globals()["gds"]
png = globals()["png"]
lyp = globals().get("lyp", "")
width = int(globals().get("width", "2000"))
box = globals().get("box", "")

view = pya.LayoutView()
view.load_layout(gds, True)
if lyp:
    view.load_layer_props(lyp)
view.set_config("background-color", "#ffffff")
view.set_config("grid-visible", "false")
view.set_config("text-visible", "false")
view.max_hier()
if box:
    x1, y1, x2, y2 = (float(v) for v in box.split(","))
    view.zoom_box(pya.DBox(x1, y1, x2, y2))
else:
    view.zoom_fit()

bbox = view.box()
height = max(1, int(width * bbox.height() / bbox.width()))
view.save_image_with_options(png, width, height, 0, 0, 0, bbox, False)
print(f"wrote {png} ({width}x{height}) from {gds}")
