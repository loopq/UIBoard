#!/usr/bin/env python3
import functools, http.server, re, shutil, subprocess, sys, tempfile, threading
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BOARDS = {
    "A": ("editor-empty", "1280,820"),
    "B": ("editor-working", "1280,820"),
    "C": ("editor-working-dark", "1280,820"),
    "D": ("device-menu", "1280,820"),
    "E": ("export-sheet", "1280,820"),
    "F": ("replace-alert", "1280,820"),
    "G": ("history", "900,640"),
    "H": ("settings", "560,260"),
}
PAGE = """<!DOCTYPE html><html><head><meta charset="utf-8"><script src="./support.js"></script></head>
<body><x-dc><helmet><style>body{{margin:0;background:#FFFFFF;}}</style></helmet>
<div style="font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','PingFang SC','Helvetica Neue',sans-serif;color:rgba(0,0,0,0.85);font-size:13px;">
{window}
</div></x-dc></body></html>"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def windows(doc):
    lines = doc.splitlines()
    starts = [i for i, l in enumerate(lines) if l.startswith('<div id="')]
    end = next(i for i, l in enumerate(lines) if l.startswith("</x-dc>")) - 1
    for a, b in zip(starts, starts[1:] + [end]):
        block = lines[a:b]
        board = re.match(r'<div id="(\w+)"', block[0]).group(1)
        window = block[2:-1]
        window[0] = re.sub(r"border-radius:10px;|box-shadow:[^;]*;", "", window[0])
        yield board, "\n".join(window)


def main():
    doc = (HERE / "UIBoard Design.dc.html").read_text()
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for f in HERE.iterdir():
            if f.suffix in (".html", ".js"):
                shutil.copy(f, tmp / f.name)
        found = dict(windows(doc))
        missing = set(BOARDS) - set(found)
        if missing:
            sys.exit(f"artboards not found: {sorted(missing)}")
        for board, window in found.items():
            (tmp / f"_{board}.html").write_text(PAGE.format(window=window))
        handler = functools.partial(QuietHandler, directory=str(tmp))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        port = server.server_address[1]
        try:
            for board, (name, size) in BOARDS.items():
                png = OUT / f"{board}-{name}.png"
                subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                                "--force-device-scale-factor=2", "--virtual-time-budget=8000",
                                f"--window-size={size}", f"--screenshot={png}",
                                f"http://127.0.0.1:{port}/_{board}.html"],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print(png)
        finally:
            server.shutdown()


if __name__ == "__main__":
    main()
