#!/usr/bin/env python3
"""Module Map scope rules, shared by self-check.sh and the pstack-guard.sh / handoff.sh hooks.

Usage:
  module_scope.py check <status.md> <module-dir> <repo-relative-path>
      exit 0  the path is inside the module's write scope
      exit 1  outside it (reason on stdout)
      exit 2  the module has no Module Map row
      exit 3  the Module Map has no Source Path column (older project) — caller decides
  module_scope.py paths <status.md> <module-dir>
      prints the module's Source Paths (and project files, if it owns them), one per line
  module_scope.py changed <project-root> <module-dir>
      every file this module's Engineer changed since its base — committed, uncommitted and
      untracked — checked against its scope; prints each one outside it with the reason.
      The base is recorded by handoff.sh (see BASE LOG below), so commit messages are not
      trusted. Renames count as a delete and an add. Files changed only by "human: ..." or
      "coordinator(...)" commits are not counted. Untracked files that are in no module's path,
      or older than the base, are printed as "note:" lines and do not fail the check.
      Exit 0 = all in scope, 1 = not, 2 = no Module Map row, 3 = no Source Path column.
  module_scope.py dependents <project-root> <module-dir>
      prints the modules whose spec.md "## Dependencies" section names this module's MOD-ID

Write scope of an Engineer = its Source Paths + the project files it owns + its own planning
files (modules/<dir>/ except spec.md, project-planning/status.md, integration-review.md).
A Source Path is a file or folder (src/login/) or a filename pattern (supabase/migrations/*_mod_003_*).
When paths overlap, the most specific one (longest literal part) decides the owner.

BASE LOG: handoff.sh appends "<sha> <epoch> <agent>" to <git-dir>/framework-handoff-log at every
handoff and every coordinator stop that moved HEAD. The base for engineer-<dir> is the latest
entry written by anyone other than engineer-<dir>. Without a log (older setups), the last commit
whose message does not start with engineer-<dir> is used.
"""
import fnmatch
import os
import posixpath
import re
import subprocess
import sys

MOD_IDS = {}  # module dir -> MOD-ID, filled by parse()
EXCLUDED_PREFIXES = ("human:", "coordinator(", "pstack(")


def clean(cell):
    """Drop backticks and **bold** markers; single * stays (filename patterns use it)."""
    return re.sub(r"`|\*\*", "", cell).strip()


def norm_dir(cell):
    d = clean(cell)
    d = re.sub(r"^(project-planning/)?modules/", "", d)
    return d.rstrip("/")


def norm_path(p):
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
        s = re.sub(r"^[-*\s]+(?=\S)", "", clean(line)) if not line.strip().startswith("|") else line.strip()
        pf = re.match(r"^Project files:\s*([^|]+)\|\s*(.*)$", s, re.I)
        if pf:
            project = (norm_dir(pf.group(1)), [norm_path(x) for x in pf.group(2).split(",") if norm_path(x)])
            continue
        if not s.startswith("|"):
            continue
        cols = [c.strip() for c in s.strip("|").split("|")]
        if len(cols) < 2:
            continue
        if clean(cols[1]).lower() == "directory":
            has_source_col = len(cols) >= 4 and "source" in cols[3].lower()
            continue
        if re.fullmatch(r"[-: ]*", cols[1]):
            continue
        d = norm_dir(cols[1])
        paths = [norm_path(x) for x in cols[3].split(",") if norm_path(x)] if len(cols) >= 4 else []
        if d:
            modules[d] = paths
            MOD_IDS[d] = clean(cols[0])
    return has_source_col, modules, project


def matches(rel, pattern):
    """(matched, specificity). A pattern without wildcards matches the path or anything below it."""
    if any(c in pattern for c in "*?["):
        if fnmatch.fnmatchcase(rel, pattern) or fnmatch.fnmatchcase(rel, pattern + "/*"):
            return True, len(re.split(r"[*?\[]", pattern, maxsplit=1)[0])
        return False, -1
    if rel == pattern or rel.startswith(pattern + "/"):
        return True, len(pattern)
    return False, -1


def owner_of(rel, modules, project):
    """Module that owns rel by the most specific matching path, or None."""
    best, best_len = None, -1
    entries = [(d, p) for d, ps in modules.items() for p in ps]
    if project:
        entries += [(project[0], p) for p in project[1]]
    for d, p in entries:
        ok, spec = matches(rel, p)
        if ok and spec > best_len:
            best, best_len = d, spec
    return best


def git(root, *args):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def base_for(root, mod):
    """(sha, epoch) of the latest handoff not made by engineer-<mod>."""
    git_dir = (git(root, "rev-parse", "--absolute-git-dir") or "").strip()
    log_path = os.path.join(git_dir, "framework-handoff-log") if git_dir else ""
    if log_path and os.path.exists(log_path):
        for line in reversed(open(log_path, encoding="utf-8").read().splitlines()):
            parts = line.split()
            if len(parts) >= 3 and parts[2] != f"engineer-{mod}":
                if git(root, "cat-file", "-e", parts[0] + "^{commit}") is not None:
                    return parts[0], int(parts[1]) if parts[1].isdigit() else 0
    # Fallback (no log yet): last commit whose message is not this Engineer's
    for line in (git(root, "log", "--format=%H%x00%ct%x00%s") or "").splitlines():
        sha, ct, subject = (line.split("\0") + ["", ""])[:3]
        if not (subject.startswith(f"engineer-{mod}(") or subject.startswith(f"engineer-{mod}:")):
            return sha, int(ct) if ct.isdigit() else 0
    if git(root, "rev-parse", "-q", "--verify", "HEAD"):
        return (git(root, "hash-object", "-t", "tree", "/dev/null") or "").strip(), 0
    return None, 0


def excluded_files(root, base):
    """Files changed in base..HEAD only by human:/coordinator( commits."""
    if not base or len(base) != 40:
        return set()
    out = git(root, "log", "--format=%x00%s", "--name-only", "--no-renames", "--relative", f"{base}..HEAD") or ""
    touched_by = {}
    subject = ""
    for line in out.splitlines():
        if line.startswith("\0"):
            subject = line[1:]
            continue
        if line:
            touched_by.setdefault(line, set()).add(subject.startswith(EXCLUDED_PREFIXES))
    return {f for f, kinds in touched_by.items() if kinds == {True}}


def changed_files(root, mod):
    """(files, untracked, base_epoch) — working tree vs the module's base."""
    base, epoch = base_for(root, mod)
    files = set()
    if base:
        out = git(root, "-c", "core.quotePath=false", "diff", "--name-only", "-z", "--no-renames",
                  "--relative", base) or ""
        files.update(x for x in out.split("\0") if x)
        files -= excluded_files(root, base)
    out = git(root, "-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard", "-z") or ""
    untracked = {x for x in out.split("\0") if x}
    return sorted(files | untracked), untracked, epoch


def dependents(root, mod):
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
    cmd = sys.argv[1]
    if cmd == "dependents":
        print(", ".join(dependents(sys.argv[2], norm_dir(sys.argv[3]))))
        return 0
    if cmd == "changed":
        root, mod = sys.argv[2], norm_dir(sys.argv[3])
        has_source_col, modules, project = parse(os.path.join(root, "project-planning", "status.md"))
        if not has_source_col:
            print("Module Map has no Source Path column")
            return 3
        if mod not in modules:
            print(f"{mod} has no row in the Module Map")
            return 2
        files, untracked, base_epoch = changed_files(root, mod)
        bad, notes = [], []
        for f in files:
            code, reason = in_scope(f, mod, has_source_col, modules, project)
            if code != 1:
                continue
            if f in untracked:
                try:
                    older = base_epoch and os.path.getmtime(os.path.join(root, f)) < base_epoch
                except OSError:
                    older = False
                if owner_of(norm_path(f), modules, project) is None or older:
                    notes.append(f"note: untracked {f} was not created in this Engineer's session or is in no module's path — not counted against {mod}; whoever created it should add it to .gitignore or remove it")
                    continue
            bad.append(reason or f)
        for line in bad + notes:
            print(line)
        return 1 if bad else 0
    status_path, mod = sys.argv[2], norm_dir(sys.argv[3])
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
