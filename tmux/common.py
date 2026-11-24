"""Small helpers the monitor's panes and data sources share (no curses, no tmux): one copy here
instead of one per file, so a fix reaches all of them.
    tilde(path)     /home/you/x → ~/x
    human(bytes)    1536 → 2K · 5 GiB → 5.0G · None → ""
    start_of(pid)   when a process started (to tell a reused pid from the original) · None: gone
    state_of(pid)   R, S, T (stopped)…
"""
import os
import subprocess

HOME = os.path.expanduser("~")


def tilde(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + "/") else path


def human(n):
    if n is None:
        return ""
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.0f}{unit}" if unit in ("B", "K") else f"{n:.1f}{unit}"
        n /= 1024


def start_of(pid):
    """When a process started (/proc/PID/stat field 22, in ticks since boot; macOS: ps's start
    time) · None when gone."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as f:
            stat = f.read().decode("utf-8", "replace")
        return int(stat[stat.rindex(")") + 2:].split()[19])
    except FileNotFoundError:
        if os.path.isdir("/proc/self"):
            return None                          # Linux: the process is gone
    except (OSError, ValueError, IndexError):
        return None
    # no /proc (macOS): ps's start time, to the second ("Tue Nov  4 10:12:33 2026")
    try:
        out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                             timeout=3, stdin=subprocess.DEVNULL).stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        return None
    return out or None


def state_of(pid):
    """R, S, T (stopped)… · macOS (no /proc): what ps says."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as f:
            stat = f.read().decode("utf-8", "replace")
        return stat[stat.rindex(")") + 2:].split()[0]
    except (OSError, ValueError, IndexError):
        pass
    try:
        return subprocess.run(["ps", "-o", "state=", "-p", str(pid)], capture_output=True, text=True,
                              timeout=3, stdin=subprocess.DEVNULL).stdout.strip()[:1]
    except (subprocess.TimeoutExpired, OSError):
        return ""
