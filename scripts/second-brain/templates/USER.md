User communicates in [Insert preferred language here, e.g., English / Indonesian].
§
User's tech stack: [Insert your tech stack here, e.g., React, Python, Docker, etc.]
§
User's workspace is located at [Insert your workspace path here].
§
User's Second Brain (vault) is located at the path defined by `$OBSIDIAN_VAULT_DIR` (or `~/obsidian/memo/` if unset).
When syncing to Second Brain, ALWAYS execute the `sync-second-brain.sh` script located in the `scripts/second-brain/` directory of the hermes-agent installation.
Extracted files should ALWAYS be saved to `$OBSIDIAN_VAULT_DIR/03-Notes/Extracted-Docs/`.
§
User expects automatic Second Brain integration with auto-didactic learning: 
1) When asked to "learn" or "study" something without a source OR given an unknown command → automatically search web first.
2) Save learned material to `$OBSIDIAN_VAULT_DIR/03-Notes/Extracted-Docs/<Topic>.md`.
3) Run `sync-second-brain.sh`.
4) Execute command only AFTER learning is complete.
5) Source auto-deleted after ingest.
6) This is permanent for all future conversations regardless of session. Triggered for: "learn/study" requests, unknown knowledge commands, ambiguous topics without clear source.
