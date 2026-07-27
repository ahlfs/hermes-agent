# Hermes Agent Memory & Second Brain Workflow

When learning new technical concepts during research (e.g., from web search), the workflow is: 
1. Create a note in `$OBSIDIAN_VAULT_DIR/03-Notes/Extracted-Docs/` (if `$OBSIDIAN_VAULT_DIR` is unset, default to `~/obsidian/memo/03-Notes/Extracted-Docs/`).
2. Run `bash ~/.hermes/hermes-agent/scripts/second-brain/sync-second-brain.sh` (or the relative path to wherever `hermes-agent` is installed).
3. Raw notes MUST go in `Extracted-Docs/` (not `03-Notes/` directly) because `wiki_ingest.py` only processes that folder.

Workflow for learning new concepts: after researching a topic, create a note in `Extracted-Docs/` and run the `sync-second-brain.sh` script. This triggers Pass 2 (document parsing) and Pass 4 (wiki ingest) to create Concept/Entity pages in `04-Wiki/`. Verify results by checking `04-Wiki/index.md` and `04-Wiki/log.md`.

When the user asks to "learn" or "study" something, or asks why knowledge wasn't saved to the Second Brain, the agent should automatically sync research findings to the wiki using the exact process above. This is a strict workflow preference that should be preserved for all future sessions.

The sync script handles 5 main passes: (1) audio transcription, (2) document parsing, (3) memory consolidation, (4) wiki ingest to `04-Wiki/`, and (5) git backup. After creating new notes for the wiki, ALWAYS execute this script to finalize the ingestion.
