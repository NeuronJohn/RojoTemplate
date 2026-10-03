# AI Rules

Keep this workflow simple and deterministic.

## 1. Know which repository you are editing

### If this is the TEMPLATE repository
This means the repository is `NeuronJohn/RojoTemplate` and the reusable project lives inside `RojoTemplateV1_GitHub/`.

- `RojoTemplateV1_GitHub/version.txt` is starter content for NEW games.
- Keep it at `0.0.0_Foundation`.
- Do NOT bump it when maintaining the template itself.
- Template revisions are tracked by Git history/releases, not by the starter game's `version.txt`.

### If this is an ACTUAL GAME made from the template
- The user's local project is canonical.
- When GitHub `ai-sync` exists, refresh and read the latest `ai-sync` before editing.
- Every delivered code update must bump that game's `version.txt`.

## 2. Before every coding update

Re-read:
- this file;
- `version.txt`;
- `default.project.json`;
- the relevant current files under `src/`.

Check the real current paths before deciding a file is new, renamed, moved, or deleted. Do not rely only on earlier chat context.

Never edit/package generated data:
- `.build/`
- `.tools/`
- `_versions/`
- `.git/`
- `.rojo-template/STATE.json`

## 3. Game update ZIPs

For an ACTUAL GAME, deliver a ZIP containing only:

```text
version.txt
<changed/new files at exact project-relative paths>
```

If files were deleted or renamed, also include:

```text
_AI_DELETE.txt
```

Each line in `_AI_DELETE.txt` is one OLD path under `src/`, for example:

```text
src/client/OldController.client.lua
```

For a rename/move:
- put the old path in `_AI_DELETE.txt`;
- include the new file at its new path.

No wildcards, absolute paths, or `..` traversal.

The launcher validates and consumes this manifest before hashing/building.

## 4. Versioning for ACTUAL GAMES

Format:

`0.0.0_UpdateName`

- `0.X.0` = major system / notable milestone.
- `0.0.X` = normal feature, fix, tuning, or hotfix.
- Keep `UpdateName` short.
- Do not reuse one version for different game contents.

## 5. Final response after changing game code

Keep it concise:
- new version;
- short summary of what changed;
- mention deleted/renamed files only if there were any;
- provide the finished update ZIP.

Do not dump large replacement code unless asked.
Do not claim testing or verification that did not actually happen.

Planning/discussion-only replies do not need a ZIP or version bump.
