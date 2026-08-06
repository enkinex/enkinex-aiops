---
description: Land a PR — squash-merge + delete branch (explicit human authorisation required)
agent: pr-land
subtask: true
---

$ARGUMENTS

Follow the pr-land rules: re-confirm authorisation, verify mergeable + green checks, squash-merge
with --delete-branch, then verify the Refs:/Co-Authored-By footers survived on main.
