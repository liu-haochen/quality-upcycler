"""Build the distributable mod only, keeping development and probe files out."""
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parent
source = root / "mod"
info = json.loads((source / "info.json").read_text(encoding="utf-8-sig"))
prefix = f"{info['name']}_{info['version']}"
files = sorted(path for path in source.rglob("*") if path.is_file())
before = {path: (path.stat().st_size, path.stat().st_mtime_ns) for path in files}
payload = {path.relative_to(source).as_posix(): path.read_bytes() for path in files}
if any(before[path] != (path.stat().st_size, path.stat().st_mtime_ns) for path in files):
    raise RuntimeError("Source changed while taking the release snapshot; run packaging again.")
destination = root / "dist"
destination.mkdir(exist_ok=True)
archive = destination / f"{prefix}.zip"
with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=6) as bundle:
    for name, content in payload.items():
        bundle.writestr(f"{prefix}/{name}", content)
with ZipFile(archive) as bundle:
    bad = bundle.testzip()
    if bad:
        raise RuntimeError(f"Invalid archive entry: {bad}")
manifest = {
    "name": info["name"], "version": info["version"], "archive": archive.name,
    "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
    "files": {name: hashlib.sha256(content).hexdigest() for name, content in payload.items()},
}
(destination / f"{prefix}.manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(json.dumps({"archive": str(archive), "files": len(payload), "bytes": archive.stat().st_size,
                  "sha256": manifest["sha256"]}, indent=2))
