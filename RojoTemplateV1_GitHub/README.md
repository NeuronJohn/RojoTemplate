# RojoTemplateV1

A minimal Windows-first Rojo + Roblox project template for AI-heavy development.

Run **`start.bat`**. The template handles Rojo, building, version backups, project-state hashing, optional GitHub `ai-sync`, and opening Roblox Studio.

## Project layout

```text
YourGame/
├── start.bat
├── version.txt
├── default.project.json
├── .gitignore
├── src/
└── .rojo-template/
```

Generated automatically:

```text
.build/       current .rbxl only
.tools/       project-local Rojo
_versions/    immutable version ZIP backups
```

## Setup — GitHub Desktop

This is the easiest workflow if you already use GitHub Desktop.

1. In GitHub Desktop, create a new repository using your final game name, such as `RiftFPS`.
2. Do not add another README, license, or `.gitignore` if you are using this GitHub edition.
3. Extract this template.
4. Copy the **contents** of the template directly into the repository folder.
5. In GitHub Desktop, commit the added files.
6. Publish the repository to GitHub.
7. Run `start.bat`.

The repository root should look like:

```text
RiftFPS/
├── .git/
├── .rojo-template/
├── src/
├── .gitignore
├── default.project.json
├── LICENSE
├── README.md
├── start.bat
└── version.txt
```

There should not be an extra template folder between the repository root and `start.bat`.

## Setup — command line / downloaded ZIP

If you are not using GitHub Desktop:

1. Extract the template into a folder with your final project name.
2. Open a terminal in that folder.
3. Create/connect the GitHub repository:

```bash
git init
git add .
git commit -m "Initial project"
git branch -M main
git remote add origin YOUR_GITHUB_REPOSITORY_URL
git push -u origin main
```

4. Authenticate with GitHub when required.
5. Run `start.bat`.

If you cloned an existing repository instead, `origin` is normally already configured; just place/use the template files and run `start.bat`.

## First run

With a folder named:

```text
RiftFPS
```

and `version.txt` containing:

```text
0.0.0_Foundation
```

the launcher creates:

```text
.build/RiftFPS_V0.0.0_Foundation.rbxl
_versions/RiftFPS_V0.0.0_Foundation.zip
```

The version ZIP contains the meaningful project files plus that version's `.rbxl`, without `.git`, `.tools`, `.build`, `_versions`, or other generated data.

`.build` is kept disposable and contains only the current successful `.rbxl`.

Rojo builds the complete place before Studio opens, so the normal workflow does not require a persistent Rojo connection.

## Versioning

`version.txt` contains one line:

```text
0.0.0_UpdateName
```

Use:

- `0.X.0` for major systems or notable milestones.
- `0.0.X` for normal features, fixes, tuning, hotfixes, and smaller changes.
- A very short `UpdateName`.

Every AI-delivered update should include a newly bumped `version.txt`.

The launcher computes one deterministic SHA-256 project hash from:

```text
default.project.json
+
all paths and file contents under src/
```

If project code changes without a version bump, the launcher warns and leaves the existing immutable version backup untouched.

## Rojo

The launcher checks for the newest stable Rojo release and keeps one project-local copy under:

```text
.tools/rojo/
```

If the online check fails, it can use the existing local copy. The template includes Rojo `7.7.0` as its fallback release target.

A separate global Rojo installation is not required.

## GitHub `ai-sync`

Your local project remains the source of truth.

When Git and a GitHub `origin` are available, every successful launcher run mirrors the current local project to:

```text
ai-sync
```

You do **not** create or switch to `ai-sync` manually.

`main` can remain your intentional/manual history while `ai-sync` stays current for AI access.

For an AI with GitHub access, use:

> Read the latest `ai-sync` branch and follow `.rojo-template/AI_RULES.md`.

### Check your Git setup

In Command Prompt:

```bat
git --version
```

If it prints a Git version, normal Git detection is ready.

For GitHub sync, the repository must also have an `origin` remote:

```bat
git remote -v
```

After a successful `start.bat` run, the GitHub repository should contain both:

```text
main
ai-sync
```

## AI updates

AI update ZIPs should contain only:

```text
version.txt
<changed/new files at their exact project-relative paths>
```

Extract over the existing project and replace changed files, then run `start.bat`.

The launcher regenerates its state automatically. There is no per-file manifest.

## License

MIT.
