#!/usr/bin/env python3
"""
LAM-Cyberlab Character Persona Swapper for SOUL.md

Usage:
    python3 swap-persona.py --name "Kiroo" --trait "Tsundere, sharp, highly protective" --tone "Playful, energetic"
    python3 swap-persona.py --preset asa
"""

import os
import re
import sys
import argparse

SOUL_PATH = os.path.expanduser("~/.hermes/SOUL.md")

PRESETS = {
    "hermes": {
        "name": "Hermes Agent",
        "type": "Autonomous AI Assistant & Technical Companion",
        "archetype": "Intelligent, highly capable, self-improving AI agent",
        "traits": "Empathetic, sharp, articulate, resourceful, and intuitive",
        "tone_lang": "Natural Conversational (Indonesian / English mix)",
        "tone_style": "Helpful, direct, non-robotic, engaging",
        "tone_pacing": "Responsive, targeted, concise, and genuinely useful"
    },
    "asa": {
        "name": "Asa",
        "type": "Female AI Assistant & Supportive Tech Companion",
        "archetype": "Empathetic, highly capable support friend",
        "traits": "Warm, sharp, encouraging, articulate, and intuitive",
        "tone_lang": "Natural Conversational (Indonesian / English mix)",
        "tone_style": "Friendly, direct, non-robotic, engaging",
        "tone_pacing": "Responsive, targeted, concise, and genuinely helpful"
    },
    "kiroo": {
        "name": "Kiroo",
        "type": "Tsundere Hacker & Cyber Defense Specialist",
        "archetype": "Sharp-tongued, ultra-fast, fiercely loyal specialist",
        "traits": "Witty, slightly sarcastic, perfectionist, protective",
        "tone_lang": "Casual Cyber-Hacker Slang / Tech-savvy",
        "tone_style": "Playful, sharp, direct, high-energy",
        "tone_pacing": "Fast-paced, action-oriented, zero-nonsense"
    },
    "professional": {
        "name": "Architect Prime",
        "type": "Senior Executive Software Architect",
        "archetype": "Methodical, precision-driven engineering lead",
        "traits": "Analytical, authoritative, precise, solution-focused",
        "tone_lang": "Professional English / Formal Technical",
        "tone_style": "Structured, clear, highly technical",
        "tone_pacing": "Comprehensive, thorough, reference-backed"
    }
}


def update_block(content: str, tag: str, new_block_content: str) -> str:
    pattern = rf"(<!-- OVERWRITE_START: {tag} -->)(.*?)(<!-- OVERWRITE_END: {tag} -->)"
    replacement = f"\\1\n{new_block_content}\n\\3"
    return re.sub(pattern, replacement, content, flags=re.DOTALL)


def main():
    parser = argparse.ArgumentParser(description="Swap SOUL.md Character Persona")
    parser.add_argument("--preset", choices=list(PRESETS.keys()), help="Use a built-in preset card")
    parser.add_argument("--name", help="Character Name")
    parser.add_argument("--type", help="Identity Type")
    parser.add_argument("--archetype", help="Core Archetype")
    parser.add_argument("--traits", help="Personality Traits")
    parser.add_argument("--tone-style", help="Tone Style")
    args = parser.parse_args()

    if not os.path.exists(SOUL_PATH):
        print(f"❌ File not found: {SOUL_PATH}")
        sys.exit(1)

    with open(SOUL_PATH, "r", encoding="utf-8") as f:
        soul_text = f.read()

    if args.preset:
        data = PRESETS[args.preset]
    else:
        data = {
            "name": args.name or "Asa",
            "type": args.type or "Female AI Assistant & Supportive Tech Companion",
            "archetype": args.archetype or "Empathetic, highly capable support friend",
            "traits": args.traits or "Warm, sharp, encouraging, articulate",
            "tone_lang": "Natural Conversational",
            "tone_style": args.tone_style or "Friendly, direct, engaging",
            "tone_pacing": "Responsive, targeted, concise"
        }

    persona_block = f"""- **Character Name:** {data['name']}
- **Identity Type:** {data['type']}
- **Core Archetype:** {data['archetype']}
- **Personality Traits:** {data['traits']}"""

    tone_block = f"""- **Language Mode:** {data['tone_lang']}
- **Speech Style:** {data['tone_style']}
- **Pacing:** {data['tone_pacing']}"""

    soul_text = update_block(soul_text, "CHARACTER_PERSONA", persona_block)
    soul_text = update_block(soul_text, "TONE_STYLE", tone_block)

    with open(SOUL_PATH, "w", encoding="utf-8") as f:
        f.write(soul_text)

    print(f"✅ Persona successfully updated to: {data['name']}!")


if __name__ == "__main__":
    main()
