# Product Requirements Document (PRD): Hermes Agent (Backend Engine)

## 1. Project Overview
**Hermes Agent** adalah mesin utama (*backend engine*) dan orkestrator yang bertindak sebagai "otak" di balik ekosistem pusat komando AI personal. Proyek ini beroperasi sebagai *API Gateway* dan *Swarm Manager* yang melayani berbagai antarmuka klien (seperti `lam-cyberlab` *workspace*, Terminal CLI, hingga Telegram Bot).

Fokus utama proyek ini adalah menyediakan pendelegasian LLM yang tangguh, manajemen agen multi-peran (*swarm workers*), dan bertindak sebagai **Eksekutor Mutlak** untuk integrasi otomatis *Knowledge Base* lokal (Obsidian Second Brain).

## 2. Core Objectives
1. **Centralized Intelligence (Omnichannel Gateway)**: Bertindak sebagai titik pusat tunggal (Single Point of Truth). Klien mana pun (Web UI, Bot Telegram) akan mendapatkan kecerdasan, akses alat, dan kemampuan *Second Brain* yang sama persis tanpa degradasi fitur.
2. **Headless & Daemon-Ready**: Dirancang untuk hidup di latar belakang peladen secara terus-menerus (24/7) tanpa membutuhkan antarmuka grafis.
3. **Autonomous Swarm Management**: Mengelola siklus hidup berbagai spesialis AI (*orchestrator, builder, researcher*) melalui `swarm.yaml` dan profil di `~/.hermes/profiles/`.
4. **Adaptive & Self-Healing Skills**: Agen harus memiliki kemampuan untuk menulis, mempelajari, dan menginstal *skill* baru secara mandiri jika dihadapkan pada tugas yang belum dikenalnya (menyimpannya di `~/.hermes/skills/`).

## 3. Functional Requirements

### 3.1. Konfigurasi Kredensial Tersentralisasi
- **Manajemen Model**: Konfigurasi kunci API LLM diatur eksklusif di dalam `~/.hermes/config.yaml` atau `.env` gateway.
- **Lokasi Klien Frontend**: Mengenali variabel `WORKSPACE_DIR` atau `LAM_CYBERLAB_DIR` untuk mengetahui jalur fisik (path absolut) letak repositori UI berada. Hal ini memungkinkan agen latar belakang memanipulasi file-file konfigurasi UI bila diperlukan.
- **API Server & Keamanan**: Menyediakan *endpoint* REST API (port `8642`). Wajib menggunakan otentikasi `API_SERVER_KEY` jika diekspos di luar *localhost*.
- **Portabilitas Data**: Seluruh data agen (Sesi, Memori, *Skill*) terisolasi rapi di dalam direktori `HERMES_HOME` (default: `~/.hermes`).

### 3.2. Eksekusi Multi-Agen (Swarm Engine)
- **Isolasi Memori Agen**: Setiap *worker* memiliki direktori profil yang berisi identitas (`SOUL.md`, `USER.md`) dan memori lokal (`MEMORY.md`).
- **Tool Execution**: Mampu mengeksekusi *tools* bawaan dan menjalankan proses latar belakang (*background daemon*).

### 3.3. Orkestrasi Mutlak "Second Brain" (LLM Wiki)
**Hermes Agent adalah PEMILIK TUNGGAL (Absolute Owner) dari skrip pengelolaan pengetahuan (Python Venv, faster-whisper, wiki_ingest).**
Saat menerima instruksi ingesti dari klien (baik itu unggahan via Telegram atau Workspace), agen bertanggung jawab penuh untuk:
1. Mentranskripsi rekaman audio.
2. Mengekstrak teks dari dokumen/PDF.
3. Menulis, merangkum, dan menautkan halaman *Markdown* ke dalam direktori Wiki.
4. Melakukan pembaruan pemetaan graf (*Graphify*).

## 4. Filosofi Pengetahuan: LLM Wiki Pattern
Logika operasi dan struktur *Second Brain* (di dalam `OBSIDIAN_VAULT_DIR`) sangat terinspirasi dari pola **LLM Wiki** (Andrej Karpathy). Pilar utamanya yang **diemban oleh Hermes Agent**:
1. **Evolusi Alur Ingesti (Full-AI Automation)**: AI (*Hermes Agent*) mengambil alih seluruh peran pengumpulan data. Manusia (via klien apa pun) cukup melempar file mentah (teks, tautan YouTube, PDF) dan membiarkan Agen mengeksekusi penyimpanannya. Manusia tidak perlu menyentuh *vault* Obsidian secara manual.
2. **Siklus Operasi Agen (Ingest, Query, Lint)**: Agen secara otonom mencerna (*Ingest*), mencari dan mensintesis jawaban (*Query*), serta merapikan tautan rusak atau usang (*Lint*) di dalam Wiki.
3. **Katalog (index.md)**: Direktori di-*index* secara deterministik untuk navigasi termurah bagi agen pengganti sistem RAG tradisional yang berat.

## 5. Struktur Integrasi Second Brain (Obsidian Vault)
Hermes Agent akan mematuhi struktur hirarki kaku berikut pada saat mengeksekusi manipulasi file di Obsidian:
- **01-Audio/** & **02-Documents/**: Hulu (*Raw Ingestion*).
- **03-Notes/**: Hasil ekstraksi mentah (Transkrip & Ekstraksi PDF).
- **04-Wiki/**: Pengetahuan Permanen (Entities, Concepts, index.md). **Dilarang mencampur ini dengan state pekerjaan.**
- **05-Projects/**, **06-Tasks/**, **07-Daily/**: Status Pekerjaan operasional, tiket, dan *log* aktivitas *swarm*.

## 6. Target Pengguna
- **Power Users & Developer**: Pengguna *Headless VPS* yang membangun arsitektur *omnichannel* untuk asisten AI otonom mereka sendiri.
