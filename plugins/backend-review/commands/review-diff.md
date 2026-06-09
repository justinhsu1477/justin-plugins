---
description: Independently review the working-tree diff against a requirement, using the java-backend-reviewer.
argument-hint: "<requirement description>"
allowed-tools: Read, Grep, Bash
---

## Requirement
$ARGUMENTS

## Diff under review
!`git diff HEAD`

## Task
Review the diff above against the requirement using the **java-backend-reviewer** subagent and the **code-review** skill. Judge the change on its own merits — do not assume the author's intent was correct (separate generation from verification).

Output exactly:
- **Summary**
- **Issues** — Blocking / Non-blocking
- **Security concerns**
- **Suggested patches** (if applicable)
