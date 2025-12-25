# 12-Issue Tracker

## How we use this tracker
- One PR per issue (reference the ID in the PR title, e.g., `fix(#ID): ...`).
- After merge, update Status to DONE and fill PR Link.
- If an issue is already solved by recent PRs (auto-merge workflow, SC2016, etc.), mark it DONE and put the PR number/link if it exists in the repo history; otherwise keep PR Link as TBD but still mark DONE.

| ID | Title | Area/File | Current Behavior | Expected Behavior | Fix Plan | Status | PR Link |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 01 | Document default install paths with placeholders | docs/README.md | Paths are inconsistent across docs | Paths use placeholders like `/var/www/your-site/html` | Audit docs for path examples and standardize | DONE | TBD (this PR) |
| 02 | Clarify domain examples are placeholders | docs/README.md | Domain examples are inconsistent | All domain examples use `abc.yourdomain.com` | Update examples and add a short note | TODO | TBD |
| 03 | Add explicit backup prerequisites | docs/backup.md | Backup steps assume tools are installed | Prerequisites list required tools | Add a short prerequisites section | TODO | TBD |
| 04 | Consolidate service restart instructions | docs/README.md | Restart steps vary by section | Single canonical restart guidance | Create a shared snippet and reference it | TODO | TBD |
| 05 | Explain required file permissions | docs/permissions.md | Permissions guidance is scattered | Clear ownership/permissions table | Add a concise permissions table | TODO | TBD |
| 06 | Document configuration file locations | docs/config.md | Config file locations are unclear | Exact locations with placeholders | Add a table of config paths | TODO | TBD |
| 07 | Add troubleshooting entry for common startup failure | docs/troubleshooting.md | Missing startup failure guidance | Common causes + fixes listed | Add a new troubleshooting item | TODO | TBD |
| 08 | Summarize log locations | docs/logging.md | Log paths are not centralized | Single list of log locations | Add a logging locations section | TODO | TBD |
| 09 | Describe required environment variables | docs/config.md | Env var usage is implicit | Explicit list and purpose | Add env var list with examples | TODO | TBD |
| 10 | Clarify upgrade workflow steps | docs/upgrade.md | Upgrade steps are ambiguous | Step-by-step upgrade flow | Rewrite upgrade section for clarity | TODO | TBD |
| 11 | Note supported OS prerequisites | docs/README.md | OS requirements not explicit | Clear supported OS list | Add a supported OS section | TODO | TBD |
| 12 | Add glossary for key terms | docs/glossary.md | No shared terminology | Quick glossary of key terms | Create glossary file and link it | TODO | TBD |
