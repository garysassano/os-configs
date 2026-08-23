import pathlib, sys
sys.path.insert(0, "/home/user/.agents/skills/cloudflare-diagrams/assets")
from cfdiagram import Diagram, Node

theme = sys.argv[1] if len(sys.argv) > 1 else "light"
nodes = [
    Node("upload", "r2", "R2", "upload-bucket"),
    Node("queue", "queues", "Queues", "event-notification-queue"),
    Node("worker", "workers", "Workers", "event-notification-writer"),
    Node("log", "r2", "R2", "log-bucket"),
]
d = Diagram(nodes, theme)
d.render()
d.arrow(None, 0, "PutObject")
d.arrow(0, 1, ["event", "notification"])
d.arrow(1, 2, "consumes", "100 / 5s")
d.arrow(2, 3, "writes", "1 per batch")
suffix = "" if theme == "light" else "-dark"
out = pathlib.Path(f"/home/user/git/cdktn-cloudflare-upload-events-logger/src/assets/arch-diagram{suffix}.svg")
out.write_text(d.finish())
print(f"  {out.name}: {d.W:.0f}x{d.H:.0f} aspect {d.W/d.H:.2f} node {d.nw:.0f}px")
