#!/usr/bin/env python3
"""Module Map scope rules, shared by self-check.sh and the pstack-guard.sh hook.

Usage:
  module_scope.py check <status.md> <module-dir> <repo-relative-path>
      exit 0  the path is inside the module's write scope
      exit 1  outside it (reason on stdout)
      exit 2  the module has no Module Map row
      exit 3  the Module Map has no Source Path column (older project) — caller decides
  module_scope.py paths <status.md> <module-dir>
      prints the module's Source Paths (and project files, if it owns them), one per line

Write scope of an Engineer = its Source Paths + the project files it owns + its own planning
files (modules/<dir>/ except spec.md, project-planning/status.md, integration-review.md).
When Source Paths nest, the longest matching path decides the owner.
"""
import re
import sys


def clean(cell):
    cell = cell.replace("`", "").strip()
    return cell


def norm_dir(cell):
    d = clean(cell)
    d = re.sub(r"^(project-planning/)?modules/", "", d)
    return d.rstrip("/")


def norm_path(p):
    import posixpath
    p = clean(p)
    if not p:
        return ""
    p = posixpath.normpath(p)
    return "" if p == "." else p.rstrip("/")


def parse(status_path):
    try:
        text = open(status_path, encoding="utf-8").read()
    except OSError:
        return None, {}, None
    m = re.search(r"^## Module Map\s*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        return None, {}, None
    section = re.sub(r"<!--.*?-->", "", m.group(1), flags=re.S)
    has_source_col = False
    modules = {}
    project = None
    for line in section.splitlines():
        s = line.strip()
        pf = re.match(r"^Project files:\s*([^|]+)\|\s*(.*)$", s, re.I)
        if pf:
            owner = norm_dir(pf.group(1))
            paths = [norm_path(x) for x in pf.group(2).split(",") if norm_path(x)]
            project = (owner, paths)
            continue
        if not s.startswith("|"):
            continue
        cols = [c.strip() for c in s.strip("|").split("|")]
        if len(cols) < 2:
            continue
        if cols[1].lower() == "directory":
            has_source_col = len(cols) >= 4 and "source" in cols[3].lower()
            continue
        if re.fullmatch(r"[-: ]*", cols[1]):
            continue
        d = norm_dir(cols[1])
        paths = []
        if len(cols) >= 4:
            paths = [norm_path(x) for x in cols[3].split(",") if norm_path(x)]
        if d:
            modules[d] = paths
    return has_source_col, modules, project


def owner_of(rel, modules, project):
    """Module that owns rel by longest matching path, or None."""
    best, best_len = None, -1
    for d, paths in modules.items():
        for p in paths:
            if rel == p or rel.startswith(p + "/"):
                if len(p) > best_len:
                    best, best_len = d, len(p)
    if project:
        for p in project[1]:
            if rel == p or rel.startswith(p + "/"):
                if len(p) > best_len:
                    best, best_len = project[0], len(p)
    return best


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 64
    cmd, status_path, mod = sys.argv[1], sys.argv[2], norm_dir(sys.argv[3])
    has_source_col, modules, project = parse(status_path)
    if cmd == "paths":
        for p in modules.get(mod, []):
            print(p)
        if project and project[0] == mod:
            for p in project[1]:
                print(p)
        return 0
    if cmd != "check" or len(sys.argv) < 5:
        print(__doc__)
        return 64
    rel = norm_path(sys.argv[4])
    if rel.startswith("project-planning/modules/") and rel.endswith("/spec.md"):
        print(f"{rel} is Doc-Sync's spec — Engineers never edit it")
        return 1
    if not has_source_col:
        print("Module Map has no Source Path column")
        return 3
    if mod not in modules:
        print(f"{mod} has no row in the Module Map")
        return 2
    if rel.startswith(f"project-planning/modules/{mod}/") or rel in (
        "project-planning/status.md",
        "project-planning/integration-review.md",
    ):
        return 0
    owner = owner_of(rel, modules, project)
    if owner == mod:
        return 0
    allowed = ", ".join(modules.get(mod, [])) or "none"
    if owner:
        print(f"{rel} belongs to {owner}, not {mod} (Source Path: {allowed})")
    else:
        print(f"{rel} is outside every module's Source Path and the project files (yours: {allowed})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
