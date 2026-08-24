"""Minimal build script. Copy this into a repo as scripts/build-diagram.py.

    python3 example-build.py [light|dark] [out.svg]
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from cfdiagram import Diagram, Flow, Node  # noqa: E402

theme = sys.argv[1] if len(sys.argv) > 1 else "light"
out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else f"arch-diagram-{theme}.svg")

nodes = [
    Node("upload", "r2", "R2", "upload-bucket"),
    Node("queue", "queues", "Queues", "event-notification-queue"),
    Node("worker", "workers", "Workers", "event-notification-writer"),
    Node("log", "r2", "R2", "log-bucket"),
]

# Flows carry node indices and go to the constructor, not to the rendered
# diagram: node width and gap are sized so every label fits at its standard
# size, which cannot happen if the labels arrive after the layout is fixed.
flows = [
    Flow(0, 1, ["event", "notification"]),
    Flow(1, 2, "consumes", "100 / 5s"),
    Flow(2, 3, "writes", "1 per batch"),
]

d = Diagram(nodes, flows, theme).render()
d.entry(0, "PutObject", "s3:ObjectCreated")
out.write_text(d.finish())
print(f"  {out.name}: {d.W:.0f}x{d.H:.0f} aspect {d.W / d.H:.2f} node {d.nw:.0f}px")
