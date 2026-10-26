"""Event naming convention: camelCase, no 'on' prefix, every triggered name declared in its resource."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "resources" / "[scavengesurvive]"

NAME_RE = re.compile(r"^[a-z][A-Za-z0-9]*$")
ADD_EVENT_RE = re.compile(r'addEvent\(\s*"([^"]+)"')
# First argument of triggerServerEvent / net.handler, second argument of triggerClientEvent,
# first argument of triggerEvent. Captured as raw text so ternaries like `a and "x" or "y"` are covered.
SERVER_ARG_RE = re.compile(r"(?:triggerServerEvent|triggerEvent)\(([^,]*),")
CLIENT_ARG_RE = re.compile(r"triggerClientEvent\([^,]*,([^,]*),")
HANDLER_RE = re.compile(r'net\.handler\(\s*"([^"]+)"')
LITERAL_RE = re.compile(r'"([^"]+)"')
COMPARE_RE = re.compile(r'[=~]=\s*"[^"]*"')  # `mode == "login"` is a comparison, not an event name

# MTA built-in events are global names that start with "on"; they are never ours.
MTA_BUILTIN_PREFIX = "on"
# Third-party resource events that we handle or register locally
THIRD_PARTY_EVENTS = {"onDiscordPacket"}



def _lua_files():
    return sorted(RESOURCES.rglob("*.lua"))


def _resource_of(path):
    return path.relative_to(RESOURCES).parts[0]


def _declared_events():
    """Names declared by addEvent in each resource's shared/events.lua (models: client/main.lua)."""
    declared = {}
    for path in _lua_files():
        rel = path.relative_to(RESOURCES).parts
        resource = rel[0]
        is_decl = rel[1:] == ("shared", "events.lua") or (resource == "models" and rel[1:] == ("client", "main.lua"))
        if is_decl:
            declared.setdefault(resource, set()).update(ADD_EVENT_RE.findall(path.read_text(encoding="utf-8")))
    return declared


def test_addevent_names_are_camel_case_without_on_prefix():
    bad = []
    for path in _lua_files():
        for name in ADD_EVENT_RE.findall(path.read_text(encoding="utf-8")):
            if name in THIRD_PARTY_EVENTS:
                continue
            if not NAME_RE.match(name) or name.startswith(MTA_BUILTIN_PREFIX):
                bad.append(f"{path.relative_to(ROOT)}: {name}")
    assert not bad, "\n".join(bad)


def test_triggered_and_handled_events_are_declared_in_their_resource():
    declared = _declared_events()
    undeclared = []
    for path in _lua_files():
        text = path.read_text(encoding="utf-8")
        resource = _resource_of(path)
        names = set()
        for m in SERVER_ARG_RE.finditer(text):
            names.update(LITERAL_RE.findall(COMPARE_RE.sub("", m.group(1))))
        for m in CLIENT_ARG_RE.finditer(text):
            names.update(LITERAL_RE.findall(COMPARE_RE.sub("", m.group(1))))
        names.update(HANDLER_RE.findall(text))
        for name in sorted(names):
            if name.startswith(MTA_BUILTIN_PREFIX):
                continue
            if name not in declared.get(resource, set()):
                undeclared.append(f"{path.relative_to(ROOT)}: {name}")
    assert not undeclared, "\n".join(undeclared)
