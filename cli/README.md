# saddb: sadDatabase in your terminal

Fix broken databases in disposable local Docker boxes. No account, no server: just Docker.

```
uv tool install "git+https://github.com/SanjivKannaa/saddatabase#subdirectory=cli"   # or pipx install ...
saddb list                     # tracks & scenarios with your progress
saddb start pg-wont-start      # boot the broken box, read the task, get a shell
#   ...fix it, then exit the shell (the box keeps running)
saddb check                    # grade it: points + breakdown
saddb hint | solution | extend | shell | task | status | end | progress
```

- Boxes have **no network**, 1 CPU, a memory cap, and time out on their own after 15 min
  (`saddb extend` adds 15 min, twice). One box at a time.
- Scoring is the same as on the website (base by difficulty, speed and first-check bonuses, −15% per hint,
  0 if you viewed the solution first). Progress is in `~/.local/share/saddb/state.json`.
- Images: uses local `saddb/<slug>` images if you have them (built with `bin/sadb build` from the repo),
  otherwise pulls `ghcr.io/sanjivkannaa/saddb-<slug>` (set `SADDB_REGISTRY` to use another registry).

Local play runs on the honour system: the graders and solutions are on your own machine.
