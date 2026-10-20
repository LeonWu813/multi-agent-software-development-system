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
  module_scope.py changed <project-root> <module-dir>
      compares the working tree (committed + uncommitted + untracked) with the last commit made by
      another agent, and prints each changed file outside the module's scope with the reason.
      Renames count as a delete and an add. Untracked files in no module's path are printed as
      "note:" lines (they may be another session's leftovers) and do not fail the check.
      Exit 0 = all in scope, 1 = not, 2 = the module has no Module Map row,
      3 = no Source Path column (older project). Shell writes are caught here, not by the guard.
  module_scope.py dependents <project-root> <module-dir>
      prints the modules whose spec.md "## Dependencies" section names this module's MOD-ID

Write scope of an Engineer = its Source Paths + the project files it owns + its own planning
files (modules/<dir>/ except spec.md, project-planning/status.md, integration-review.md).
When Source Paths nest, the longest matching path decides the owner.
"""
import os
import re
import subprocess
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
    MOD_IDS.clear()
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
            MOD_IDS[d] = clean(cols[0])
    return has_source_col, modules, project


MOD_IDS = {}  # module dir -> MOD-ID, filled by parse()

# Commit prefixes of every agent except Engineers; the base for an Engineer's changes is the
# last such commit (or another module's engineer commit). Anything else counts as this Engineer's.
OTHER_AGENT_PREFIXES = ("pm(", "pm:", "tech-lead(", "tech-lead:", "doc-sync(", "doc-sync:",
                        "qa-", "pstack(", "retrospective:", "retrospective(", "human:")   # the human prefixes manual commits "human: ..."


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


def git(root, *args):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def changed_files(root, mod):
    """(files, untracked) — working tree vs the last other-agent commit, renames split."""
    log = git(root, "log", "--format=%H%x00%s") or ""
    base = None
    for line in log.splitlines():
        sha, _, subject = line.partition("\0")
        own = subject.startswith(f"engineer-{mod}(") or subject.startswith(f"engineer-{mod}:")
        other_engineer = subject.startswith("engineer-") and not own
        if subject.startswith(OTHER_AGENT_PREFIXES) or other_engineer:
            base = sha
            break
    if base is None:
        base = (git(root, "hash-object", "-t", "tree", "/dev/null") or "").strip() if log else None
    files = set()
    if base:
        out = git(root, "-c", "core.quotePath=false", "diff", "--name-only", "-z", "--no-renames", base) or ""
        files.update(x for x in out.split("\0") if x)
    out = git(root, "-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard", "-z") or ""
    untracked = {x for x in out.split("\0") if x}
    return sorted(files | untracked), untracked


def dependents(root, mod):
    """Modules whose spec Dependencies section names mod's MOD-ID."""
    parse(os.path.join(root, "project-planning", "status.md"))
    mid = MOD_IDS.get(mod)
    if not mid:
        return []
    out = []
    for d in MOD_IDS:
        if d == mod:
            continue
        try:
            spec = open(os.path.join(root, "project-planning", "modules", d, "spec.md"), encoding="utf-8").read()
        except OSError:
            continue
        dep = re.search(r"^## Dependencies\s*\n(.*?)(?=^## |\Z)", spec, re.S | re.M)
        if dep and re.search(re.escape(mid) + r"\b", re.sub(r"<!--.*?-->", "", dep.group(1), flags=re.S)):
            out.append(d)
    return out


def in_scope(rel, mod, has_source_col, modules, project):
    """(code, reason) — code 0 in scope, 1 outside, 2 no row, 3 no Source Path column."""
    rel = norm_path(rel)
    if rel.startswith("project-planning/modules/") and rel.endswith("/spec.md"):
        return 1, f"{rel} is Doc-Sync's spec — Engineers never edit it"
    if not has_source_col:
        return 3, "Module Map has no Source Path column"
    if mod not in modules:
        return 2, f"{mod} has no row in the Module Map"
    if rel.startswith(f"project-planning/modules/{mod}/") or rel in (
        "project-planning/status.md",
        "project-planning/integration-review.md",
    ):
        return 0, ""
    owner = owner_of(rel, modules, project)
    if owner == mod:
        return 0, ""
    allowed = ", ".join(modules.get(mod, [])) or "none"
    if owner:
        return 1, f"{rel} belongs to {owner}, not {mod} (Source Path: {allowed})"
    return 1, f"{rel} is outside every module's Source Path and the project files (yours: {allowed})"


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 64
    if sys.argv[1] == "dependents":
        print(", ".join(dependents(sys.argv[2], norm_dir(sys.argv[3]))))
        return 0
    if sys.argv[1] == "changed":
        root, mod = sys.argv[2], norm_dir(sys.argv[3])
        has_source_col, modules, project = parse(os.path.join(root, "project-planning", "status.md"))
        if not has_source_col:
            print("Module Map has no Source Path column")
            return 3
        if mod not in modules:
            print(f"{mod} has no row in the Module Map")
            return 2
        files, untracked = changed_files(root, mod)
        bad, notes = [], []
        for f in files:
            code, reason = in_scope(f, mod, has_source_col, modules, project)
            if code != 1:
                continue
            if f in untracked and owner_of(norm_path(f), modules, project) is None:
                notes.append(f"note: untracked {f} is in no module's path — not counted against {mod}; whoever created it should add it to .gitignore or remove it")
            else:
                bad.append(reason or f)
        for line in bad + notes:
            print(line)
        return 1 if bad else 0
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
    code, reason = in_scope(sys.argv[4], mod, has_source_col, modules, project)
    if reason:
        print(reason)
    return code

if __name__ == "__main__":
    sys.exit(main())
