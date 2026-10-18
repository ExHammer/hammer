# CLAUDE.md

Claude Code guidance for this repository. The canonical agent instructions live in AGENTS.md.

@AGENTS.md

## Plugin Setup

```bash
claude plugin install elixir@claude-code-elixir
claude plugin install superpowers@claude-plugins-official
claude plugin install code-review@claude-plugins-official
```

## Claude-specific notes

- `.claude/settings.local.json` pre-approves `mise exec *`, `git checkout *`, `git add *`, `git commit *`. Do not widen it without being asked.
- Use `superpowers:test-driven-development` for algorithm fixes (write the failing ETS and Atomic tests first) and `superpowers:systematic-debugging` for race conditions or flaky timing tests.
- Run `code-review` before opening a PR; the library is public on Hex, so API and return-shape changes need extra care.
- `superpowers:verification-before-completion`: run the full gate in AGENTS.md "Essential Commands" before claiming done.
- The sibling backend repos (`../hammer-backend-redis`, `../hammer-backend-mnesia`) are separate projects; read them to check contract impact, do not edit them from this repo.
