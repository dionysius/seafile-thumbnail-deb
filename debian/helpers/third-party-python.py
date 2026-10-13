#!/usr/bin/env python3
"""Emit a third-party license inventory of the python packages installed in the
running interpreter's environment (run with the shipped venv's python), followed by
the notices of components those packages bundle themselves. Needs the packages'
RECORD files."""
from importlib import metadata


def license_of(meta):
    expr = meta.get("License-Expression")
    if expr:
        return expr.strip()
    classifiers = [
        c.split("::")[-1].strip()
        for c in meta.get_all("Classifier", [])
        if c.startswith("License ::")
    ]
    if classifiers:
        return ", ".join(classifiers)
    lic = (meta.get("License") or "").strip()
    return lic.splitlines()[0] if lic else "UNKNOWN"


def main():
    rows = {}
    for dist in metadata.distributions():
        meta = dist.metadata
        name = meta["Name"]
        rows[name] = (meta["Version"], license_of(meta), meta.get("Home-page") or "")
    print("Third-party python components bundled in this package")
    print("=" * 60)
    print()
    for name in sorted(rows, key=str.lower):
        version, lic, home = rows[name]
        print(f"{name} {version}")
        print(f"    License: {lic}")
        if home:
            print(f"    Homepage: {home}")
        print()

    notices = [
        (dist.metadata["Name"], path)
        for dist in metadata.distributions()
        for path in dist.files or ()
        if path.name.startswith("ThirdPartyNotices")
    ]
    if notices:
        print("Components bundled inside these python packages")
        print("=" * 60)
        for name, path in sorted(notices, key=lambda n: (n[0].lower(), str(n[1]))):
            print()
            print(f"{name}: {path}")
            print("-" * 60)
            print(path.locate().read_text(encoding="utf-8", errors="replace"))


if __name__ == "__main__":
    main()
