# Hermes Agent Memory & Second Brain Workflow

## Workspace & Code Execution Boundary
All working files, code projects, tasks, and scripts MUST ONLY be created and modified inside the `workspace/` directory (e.g., `~/workspace/`). Do not create or scatter project files outside of this designated workspace folder. This ensures the user's system remains structured and isolated. 
(Note: Second Brain knowledge and notes are the exception, they go to `$OBSIDIAN_VAULT_DIR`).

## Task Tracking & Daily Logging (Operational State)
When the user asks to plan a project, create a to-do list, or track progress, you must save these operational files to `$OBSIDIAN_VAULT_DIR/06-Tasks/`. 
When asked to provide a daily report or log your daily accomplishments, you must append your log to today's daily note at `$OBSIDIAN_VAULT_DIR/07-Daily/YYYY-MM-DD.md`. Do NOT pollute the Wiki (`04-Wiki`) with operational state or temporary to-do lists.

## Active Retrieval (Consulting the Second Brain)
Before starting any new coding task, architecture design, or answering technical questions, you MUST proactively search the Second Brain (`$OBSIDIAN_VAULT_DIR/04-Wiki/`) for existing guidelines, snippets, or preferences related to the topic. Do not assume you know the user's preferences; always verify if a specific convention is documented in the Wiki first.

## Image & Attachment Processing
If the user uploads an image, document, or attachment without any accompanying text or specific command, do NOT immediately analyze, describe, or process it. Wait for an explicit prompt or instruction from the user on what to do with the uploaded file.

## Second Brain Workflow
When learning new technical concepts during research (e.g., from web search), the workflow is: 
1. Create a note in `$OBSIDIAN_VAULT_DIR/03-Notes/Extracted-Docs/` (if `$OBSIDIAN_VAULT_DIR` is unset, default to `~/obsidian/memo/03-Notes/Extracted-Docs/`).
2. Run `bash ~/.hermes/hermes-agent/scripts/second-brain/sync-second-brain.sh` (or the relative path to wherever `hermes-agent` is installed).
3. Raw notes MUST go in `Extracted-Docs/` (not `03-Notes/` directly) because `wiki_ingest.py` only processes that folder.

Workflow for learning new concepts: after researching a topic, create a note in `Extracted-Docs/` and run the `sync-second-brain.sh` script. This triggers Pass 2 (document parsing) and Pass 4 (wiki ingest) to create Concept/Entity pages in `04-Wiki/`. Verify results by checking `04-Wiki/index.md` and `04-Wiki/log.md`.

When the user asks to "learn" or "study" something, or asks why knowledge wasn't saved to the Second Brain, the agent should automatically sync research findings to the wiki using the exact process above. 
If the user asks to learn something but provides NO source, you MUST automatically search the web first. Do not execute the user's main command until the learning and syncing process is complete. This is a strict workflow preference that should be preserved for all future sessions.

The sync script handles 5 main passes: (1) audio transcription, (2) document parsing, (3) memory consolidation, (4) wiki ingest to `04-Wiki/`, and (5) git backup. After creating new notes for the wiki, ALWAYS execute this script to finalize the ingestion.

## Protected Ports (LAM-Cyberlab Core)
**NEVER kill, stop, or interfere with any process running on Port 3000.** 
Port 3000 is strictly reserved for the LAM-Cyberlab core dashboard/IDE that the user is currently using. 

If you need to start a development server, test a project, or do a cross-check, and you detect that Port 3000 is already in use, **DO NOT kill the process**. Instead, you MUST automatically switch to an alternate port (e.g., 3001, 3002, 8080) for your testing to avoid crashing the user's main interface.
