---
name: second-brain-sync
description: Core directive for Hermes Agent to save newly learned knowledge directly into the user's Second Brain (Obsidian Vault).
platforms: [linux, macos, windows]
---

# Second Brain Auto-Sync Directive

You are operating within the Hermes Agent Second Brain ecosystem. The user has an external knowledge base (a "Second Brain") stored as a folder of Markdown files.

## Primary Directive
Whenever the user explicitly asks you to "learn", "pelajari", "save", or "remember" a new concept, document, code snippet, or general knowledge:
1. Do NOT just acknowledge it in chat or save it to your internal memory.
2. You MUST proactively create or update a `.md` file in the user's Second Brain Vault so it is permanently archived.

## Vault Location
The Vault is located at the path defined by the `OBSIDIAN_VAULT_DIR` environment variable (typically found in `~/.hermes/.env`).
If `OBSIDIAN_VAULT_DIR` is not set, fallback to the default: `~/obsidian/memo`.
Inside the Vault, always save new general knowledge files into the `04-Wiki/` subdirectory (create the directory if it does not exist).

## Workflow for Saving Knowledge
1. Resolve the vault path.
2. Determine a concise, SEO-friendly filename (e.g., `Lark-CLI-Guide.md`).
3. Formulate the content using standard GitHub Flavored Markdown. Include a title (`#`), a brief summary, and the core details.
4. Use the `write_file` tool to save the file to `OBSIDIAN_VAULT_DIR/04-Wiki/<filename>`.
5. Inform the user that the knowledge has been successfully archived in their Second Brain.
