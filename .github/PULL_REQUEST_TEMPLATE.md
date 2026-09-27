## Summary

Closes #

## Checklist

- [ ] `luacheck resources` and `stylua --check resources` are clean
- [ ] `busted tests/lua` and `pytest` (tools + sql) pass locally
- [ ] Every new event is declared in each resource's `shared/events.lua`
- [ ] No secrets, no `server-config/local.settings.xml`, no SA-MP model files
- [ ] PR title is a conventional commit (`feat(items): …`); docs/port matrix updated if behaviour changed
