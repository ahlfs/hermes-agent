# Wiki Schema — how the LLM wiki is structured

This file defines the conventions for the `04-Wiki/` layer of this vault. It
follows Andrej Karpathy's "LLM wiki" pattern: raw notes in `03-Notes/` are
the immutable source of truth; `04-Wiki/` is a synthesized, interlinked
layer the AI maintains on top of them. The AI reads this schema every time
it ingests a note, so the wiki stays consistent.

## The two page kinds

- **Entities** (`04-Wiki/Entities/`) — concrete, nameable things: a person,
  a project, a company, a tool, a place, a specific system. "Proyek Elang
  Biru", "PostgreSQL", "Budi".
- **Concepts** (`04-Wiki/Concepts/`) — ideas, topics, techniques, recurring
  themes: "Deployment", "Rate Limiting", "Second Brain". Not a specific
  named thing, but a subject that shows up across sources.

If unsure, ask: *"is this a proper noun / specific instance?"* → Entity.
*"is this a general topic that many notes could touch?"* → Concept.

## Page naming

- One file per entity/concept: `Entities/<Title>.md` or `Concepts/<Title>.md`.
- Filenames may contain only letters, numbers, spaces, and hyphens, ending
  in `.md`. No slashes beyond the `Entities/` or `Concepts/` prefix, no `..`,
  no other punctuation.
- The filename (minus `.md`) IS the page title and IS what `[[wikilinks]]`
  point to. So `[[Deployment]]` resolves to `Concepts/Deployment.md`.

## Page format (assembled by the script, not written by hand)

Each page is: YAML frontmatter (`type`, `category`, `summary`, `sources`,
`updated`) + a `# Title` heading + a markdown body. The **script** assembles
the frontmatter and heading — the AI only supplies the semantic fields and
the body text as JSON. The body should:

- Start directly with prose (no repeated `# Title`, no frontmatter).
- Link generously to related pages with `[[Title]]` — this is what turns the
  vault's Graph View from disconnected dots into a real graph. Only link to
  things that exist or plausibly *should* exist as their own page.
- Cite where a claim came from by linking the source note, e.g.
  `[[meeting-2026-07-22]]` (source notes live in `03-Notes/` and resolve by
  filename).
- Stay concise and factual. Synthesize across sources; don't dump the raw
  transcript.

## Maintenance rules

- **Prefer updating an existing page over creating a near-duplicate.** Check
  the index first. "PostgreSQL" and "Postgres" should be one page, not two.
- When a new note adds to an existing entity/concept, produce the full merged
  page body — don't drop what was already there.
- Flag contradictions (a note that conflicts with an existing page) rather
  than silently overwriting — the script records these in `log.md`.
- If a note is a test, empty, or has no durable content, create no pages.

## Operational Boundary (Agent-OS)

- **The wiki (`04-Wiki`) is for permanent, distilled knowledge.**
- **It is NOT for operational state.** If a note contains a to-do list, a project specification, or a daily log of what an agent accomplished, do NOT synthesize that into the Wiki.
- Agents tracking work should use `05-Projects/`, `06-Tasks/`, or `07-Daily/`. Keep the Wiki graph pure.

## Files the script owns (do not hand-edit)

- `04-Wiki/index.md` — regenerated from every page's `summary` after each
  ingest. Read this first to know what already exists.
- `04-Wiki/log.md` — append-only chronological record of ingests.
- `.wiki-state.json` — tracks which notes have already been ingested.
