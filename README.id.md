<p align="center">
  <img src="assets/banner.png" alt="Hermes Agent" width="100%">
</p>

# Hermes Agent - Edisi Second Brain
<p align="center">
  <a href="https://hermes-agent.nousresearch.com/">Hermes Agent</a> | <a href="https://hermes-agent.nousresearch.com/">Hermes Desktop</a>
</p>
<p align="center">
  <a href="https://github.com/ahlfs/hermes-agent"><img src="https://img.shields.io/badge/Modified%20by-Ahlfs-blueviolet?style=for-the-badge" alt="Modified by Ahlfs"></a>
  <a href="https://github.com/NousResearch/hermes-agent/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License: MIT"></a>
  <a href="README.md"><img src="https://img.shields.io/badge/Lang-English-lightgrey?style=for-the-badge" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/Lang-中文-red?style=for-the-badge" alt="中文"></a>
  <a href="README.ur-pk.md"><img src="https://img.shields.io/badge/Lang-اردو-green?style=for-the-badge" alt="اردو"></a>
  <a href="README.es.md"><img src="https://img.shields.io/badge/Lang-Español-orange?style=for-the-badge" alt="Español"></a>
</p>

> **⚠️ FORK KUSTOM UNTUK LAM-CYBERLAB**
>
> Repositori ini adalah versi Hermes Agent yang telah dimodifikasi secara ekstensif oleh **Ahlfs**. Ini dirancang khusus agar kompatibel penuh sebagai mesin kecerdasan backend untuk **[LAM-Cyberlab](https://github.com/ahlfs/LAM-Cyberlab)**. Lihat bagian [Edisi Second Brain](#-edisi-second-brain-fork-kustom) di bawah ini untuk rincian tentang fitur kustom.

**Agen AI yang dapat memperbaiki diri sendiri, dibangun oleh [Nous Research](https://nousresearch.com).** Ini adalah satu-satunya agen dengan putaran pembelajaran bawaan — ia menciptakan keterampilan dari pengalaman, meningkatkannya selama penggunaan, mendorong dirinya untuk mempertahankan pengetahuan, mencari percakapan masa lalunya sendiri, dan membangun pemodelan yang mendalam tentang siapa Anda di seluruh sesi. Jalankan di VPS $5, klaster GPU, atau infrastruktur tanpa server yang hampir tidak memerlukan biaya saat diam. Ini tidak terikat pada laptop Anda — bicaralah dengannya dari Telegram saat ia bekerja di cloud VM.

Gunakan model apa pun yang Anda inginkan — [Nous Portal](https://portal.nousresearch.com), OpenRouter, OpenAI, endpoint Anda sendiri, dan [banyak lagi](https://hermes-agent.nousresearch.com/docs/integrations/providers). Ganti dengan `hermes model` — tanpa mengubah kode, tanpa keterikatan.

<table>
<tr><td><b>Antarmuka terminal sungguhan</b></td><td>TUI penuh dengan pengeditan multi-baris, penyelesaian otomatis perintah slash, riwayat percakapan, interupsi-dan-arah-ulang, serta output alat streaming.</td></tr>
<tr><td><b>Hidup di mana Anda berada</b></td><td>Telegram, Discord, Slack, WhatsApp, Signal, dan CLI — semuanya dari satu proses gateway tunggal. Transkripsi memo suara, kesinambungan percakapan lintas platform.</td></tr>
<tr><td><b>Putaran pembelajaran tertutup</b></td><td>Memori yang dikuratori agen dengan dorongan berkala. Penciptaan keterampilan otonom setelah tugas kompleks. Keterampilan meningkat secara mandiri selama penggunaan. Pencarian sesi FTS5 dengan peringkasan LLM untuk mengingat lintas sesi. Pemodelan pengguna dialektis <a href="https://github.com/plastic-labs/honcho">Honcho</a>. Kompatibel dengan standar terbuka <a href="https://agentskills.io">agentskills.io</a>.</td></tr>
<tr><td><b>Otomatisasi terjadwal</b></td><td>Penjadwal cron bawaan dengan pengiriman ke platform apa pun. Laporan harian, pencadangan malam, audit mingguan — semuanya dalam bahasa alami, berjalan tanpa pengawasan.</td></tr>
<tr><td><b>Mendelegasikan dan memparalelkan</b></td><td>Munculkan sub-agen terisolasi untuk alur kerja paralel. Tulis skrip Python yang memanggil alat melalui RPC, meruntuhkan jalur multi-langkah menjadi giliran biaya nol-konteks.</td></tr>
<tr><td><b>Berjalan di mana saja</b></td><td>Enam backend terminal — lokal, Docker, SSH, Singularity, Modal, dan Daytona. Daytona dan Modal menawarkan persistensi tanpa server — lingkungan agen Anda berhibernasi saat diam dan bangun sesuai permintaan. Jalankan di VPS $5 atau klaster GPU.</td></tr>
<tr><td><b>Siap untuk penelitian</b></td><td>Pembuatan lintasan secara batch, kompresi lintasan untuk melatih model pemanggil-alat generasi berikutnya.</td></tr>
</table>

---

## 🧠 Edisi Second Brain (Fork Kustom)

Ini adalah fork kustom dari Hermes Agent yang **dimodifikasi dan dikelola oleh Ahlfs**, menampilkan pipeline **Second Brain** otonom dan pencadangan konfigurasi GitHub otomatis.

### Fitur
1. **Pipeline Second Brain Otomatis**
   - **Transkripsi Audio**: Masukkan `.mp3` ke `01-Audio` dan Hermes secara otomatis mentranskripsinya menggunakan Whisper.
   - **Parsing Dokumen**: Mem-parsing `.pdf` dan melakukan OCR pada gambar yang dijatuhkan ke `02-Documents`.
   - **Generasi Wiki**: Mensintesis transkrip dan dokumen menjadi file markdown bergaya Wikipedia yang saling terhubung di `04-Wiki`.
   - **Pencadangan Git**: Secara otomatis melakukan commit dan push pengetahuan baru ke repositori GitHub pribadi.
   - **Kaskade Pembersihan Sumber Penuh**: Menghapus file sumber mentah (`.mp3`, `.pdf`, dll.) dari `01-Audio` dan `02-Documents` secara aman *hanya setelah* pengetahuan akhir berhasil dicadangkan ke GitHub, menjaga brankas Anda tetap ringan.
2. **Pencadangan Konfigurasi Otomatis**
   - Mencadangkan konfigurasi `~/.hermes` Anda, keterampilan kustom, dan memori ke repositori GitHub pribadi yang terpisah melalui tugas cron terjadwal (default: setiap 24 jam).
3. **Router Swarm Dinamis (Perutean Berbasis Niat)**
   - Secara otomatis mencegat dan merutekan pesan masuk ke sub-agen spesialis yang paling mampu (`builder`, `researcher`, `writer`).
   - Menggunakan klasifikasi kata kunci tanpa latensi untuk menyimpulkan niat pengguna, memberikan pengalaman swarm tanpa gesekan tanpa beralih profil secara manual.
4. **Integrasi Asli LAM-Cyberlab**
   - **Streaming Waktu Nyata**: Dukungan penuh untuk streaming token progresif melalui SSE/WebSockets (`stream_events.py`), menjadikannya backend kecerdasan plug-and-play tanpa hambatan untuk UI LAM-Cyberlab.
   - **Pembelajaran Putaran Tertutup**: Bersinergi tanpa cela dengan Generator Keterampilan Penyembuhan Diri asli. Saat dihadapkan pada tugas yang kompleks dari UI Cyberlab, agen dapat secara otonom menulis, menguji, dan menyimpan keterampilan `.md` barunya sendiri untuk penggunaan di masa mendatang.

## Instalasi & Pengaturan Cepat

Ikuti langkah-langkah ini untuk menginstal versi Hermes Agent yang kompatibel dengan LAM-Cyberlab.

> **⚠️ PENGGUNA WINDOWS**: Proyek ini sangat bergantung pada paket Linux (seperti `apt install ffmpeg`) dan skrip Bash. Git Bash atau PowerShell asli **tidak** akan berfungsi untuk pipeline Second Brain. Anda **harus** menginstal dan menggunakan **[WSL2 (Windows Subsystem for Linux)](https://learn.microsoft.com/en-us/windows/wsl/install)** untuk mengikuti langkah-langkah ini.

### Prasyarat

Sebelum memulai, pastikan Anda telah menginstal hal-hal berikut di sistem Anda:

| Kebutuhan | Wajib? | Kegunaan | Cara Instal |
|---|---|---|---|
| **[Git](https://git-scm.com/downloads)** | ✅ Wajib | Clone repo, sistem backup | [Panduan Instal](https://git-scm.com/downloads) |
| **[Python 3.10+](https://www.python.org/downloads/)** | ✅ Wajib | Menjalankan skrip Second Brain | [Panduan Instal](https://www.python.org/downloads/) |
| **[curl](https://curl.se/)** | ✅ Wajib | Mengunduh installer Hermes | Sudah terinstal di kebanyakan sistem |
| **[FFmpeg](https://ffmpeg.org/download.html)** | ✅ Wajib | Transkripsi audio (Whisper) | [Panduan Instal](https://ffmpeg.org/download.html) |
| **[Tesseract OCR](https://github.com/tesseract-ocr/tesseract)** | ✅ Wajib | Ekstraksi teks gambar/PDF | [Panduan Instal](https://github.com/tesseract-ocr/tesseract#installing-tesseract) |
| **[Obsidian](https://obsidian.md/)** | ⭐ Opsional | Penampil markdown visual untuk Second Brain Anda | [Unduh](https://obsidian.md/download) |
| **Akun GitHub + Kunci SSH** | ⭐ Opsional | Pencadangan cloud otomatis | [Panduan](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) |

> **Catatan:** Anda **tidak** perlu menginstal Obsidian untuk menggunakan pipeline Second Brain. "Vault" hanyalah sebuah folder berisi file `.md` di disk Anda. Editor teks apa pun (VS Code, Notepad, dll.) dapat membacanya. Obsidian direkomendasikan untuk pengalaman menjelajah terbaik dengan catatan yang saling terhubung dan tampilan graf.

### 1. Instal Dependensi OS
Pipeline Second Brain membutuhkan `ffmpeg` (untuk audio) dan `tesseract-ocr` (untuk gambar). Jalankan perintah yang sesuai untuk sistem Anda:

**Ubuntu / Debian / WSL2 (Default):**
```bash
sudo apt update && sudo apt install ffmpeg tesseract-ocr
```

**macOS (via Homebrew):**
```bash
brew install ffmpeg tesseract
```

**Fedora / RHEL:**
```bash
sudo dnf install ffmpeg tesseract
```

**Arch Linux:**
```bash
sudo pacman -S ffmpeg tesseract
```

### 2. Instal Dasar Hermes & Ganti ke Fork Kustom
Pertama, gunakan penginstal resmi untuk mengatur runtime yang diperlukan (Node.js, uv, PATH wrapper), lalu ganti kode sumber dengan repositori kustom ini.

**Linux / macOS / WSL2:**
```bash
# Instal lingkungan dasar
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# Ganti repo resmi dengan fork kustom Ahlfs
rm -rf ~/.hermes/hermes-agent
git clone https://github.com/ahlfs/hermes-agent.git ~/.hermes/hermes-agent

# Sinkronisasi ulang dependensi
cd ~/.hermes/hermes-agent
~/.hermes/bin/uv venv venv
~/.hermes/bin/uv pip install --python venv -e ".[all]"
```

### 3. Inisialisasi Lingkungan Second Brain
Jalankan skrip pengaturan untuk membuat lingkungan virtual terisolasi khusus untuk alat Second Brain:
```bash
cd ~/.hermes/hermes-agent
bash scripts/second-brain/setup-venv.sh
```

### 4. Konfigurasi Variabel Lingkungan
Buka file `~/.hermes/.env` Anda dan tambahkan pengaturan berikut di bagian bawah:
```ini
# Direktori Vault Obsidian Anda (Second Brain)
OBSIDIAN_VAULT_DIR=/home/user/obsidian/memo

# Pengaturan Pencadangan GitHub
GITHUB_USERNAME=username_github_anda
GITHUB_REPO_CONFIG=hermes-config
GITHUB_REPO_SECONDBRAIN=second-brain
```

### 5. Inisialisasi Struktur Vault
Untuk membiarkan Hermes membangun kerangka folder kosong Anda secara otomatis dan memverifikasi lingkungan Anda, jalankan skrip sinkronisasi secara manual untuk pertama kalinya:
```bash
cd ~/.hermes/hermes-agent
bash scripts/second-brain/sync-second-brain.sh
```
*(Setelah ini selesai, Anda akan menemukan folder `01-Audio`, `02-Documents`, dan `04-Wiki` telah siap di dalam Vault Anda.)*

### 6. Hubungkan GitHub via SSH (Opsional)
Jika Anda mengkonfigurasi Pengaturan Pencadangan GitHub di atas, pastikan mesin Anda terhubung ke GitHub melalui SSH. Pencadangan otomatis mengandalkan kunci SSH untuk mendorong perubahan tanpa memerlukan kata sandi.
```bash
ssh-keygen -t ed25519
# Tambahkan kunci publik (~/.ssh/id_ed25519.pub) ke akun GitHub Anda
```

### 7. Mulai Gunakan!
Muat ulang shell Anda dan mulai agen:
```bash
source ~/.bashrc    # muat ulang shell (atau: source ~/.zshrc)
hermes              # mulai mengobrol!
```
### 8. Mengajarkan Second Brain Anda (Mengonsumsi Pengetahuan)
Untuk memberi agen Anda pengetahuan baru (rekaman rapat, buku, makalah penelitian, dll.), cukup letakkan file mentah ke dalam direktori Vault Obsidian yang Anda tentukan (`OBSIDIAN_VAULT_DIR`):

1. **File Audio (`.mp3`, `.m4a`, `.wav`)**: Pindahkan ke dalam folder `01-Audio/`.
2. **Dokumen & Gambar (`.pdf`, `.png`, `.jpg`)**: Pindahkan ke dalam folder `02-Documents/`.

**Apa yang terjadi selanjutnya?**
- Agen secara otomatis mendeteksi file baru dan menjalankan pipeline konsumsi di latar belakang. Anda juga dapat memaksanya secara manual dengan memberi tahu agen: *"Pelajari file baru saya di vault."*
- Audio ditranskripsikan melalui Whisper; Dokumen dan Gambar diuraikan dan di-OCR.
- Informasi yang diekstraksi disintesis menjadi halaman `.md` yang saling terhubung bergaya Wikipedia di folder `04-Wiki/` Anda.
- **Pembersihan Otomatis**: Setelah pengetahuan berhasil diubah menjadi halaman Wiki dan dengan aman dicadangkan ke repositori GitHub Anda, **Kaskade Pembersihan Sumber Penuh** agen akan bekerja. Ini akan secara otomatis menghapus file sumber mentah besar (`.mp3`, `.pdf`, dll.) dari folder `01-Audio` dan `02-Documents` Anda untuk menjaga server Anda tetap ringan.

---

## 📦 Sistem Pencadangan & Pencadangan Otomatis

Edisi kustom Hermes Agent ini memiliki sistem Pencadangan Otomatis (sepenuhnya disinkronkan ke cloud/GitHub) untuk memastikan konfigurasi, memori agen, keterampilan kustom, dan basis pengetahuan Anda aman bahkan jika server/VPS Anda mati.

### 1. Apa yang Dicadangkan?
Sistem memisahkan cadangan menjadi dua repositori agar semuanya tetap teratur:
- **`second-brain` (Basis Pengetahuan):** Menyimpan seluruh struktur Vault Obsidian Anda (catatan yang diekstraksi, transkrip, halaman wiki `.md`).
- **`hermes-config` (Otak Agen):** Menyimpan identitas inti agen Anda. Ini termasuk direktori `~/.hermes/` (file `config.yaml`, folder `skills/`, folder `profiles/`, `MEMORY.md`, `SOUL.md`).

### 2. Persiapan Repositori & Akses
Untuk memungkinkan fitur otomatis berjalan tanpa campur tangan, atur akses SSH untuk Git:
1. Buat 2 repositori **Pribadi** kosong di GitHub (misalnya, `second-brain` dan `hermes-config`).
2. Buat Kunci SSH di mesin Anda (jika belum):
   ```bash
   ssh-keygen -t ed25519 -C "email_anda@example.com"
   ```
3. Salin kunci publik Anda (`cat ~/.ssh/id_ed25519.pub`) dan tambahkan ke akun GitHub Anda (**Pengaturan > Kunci SSH dan GPG > Kunci SSH Baru**).

### 3. Konfigurasi Variabel Lingkungan
Untuk memberi tahu Hermes di mana harus mencadangkan data Anda, Anda harus menambahkan variabel berikut ke file `~/.hermes/.env` Anda:
```ini
# Pengaturan Pencadangan GitHub
GITHUB_USERNAME=username_github_anda
GITHUB_REPO_CONFIG=hermes-config
GITHUB_REPO_SECONDBRAIN=second-brain
```

### 4. Cara Kerja Pencadangan Otomatis
- **Sinkronisasi Otomatis Second Brain:** Dikelola melalui skrip Bash (`sync-second-brain.sh`). Skrip ini dapat dijalankan secara manual, atau akan dieksekusi secara otomatis sesuai jadwal (cron) / setiap kali agen menerima perintah *konsumsi*. Selama **Pass 6**, agen secara otomatis menjalankan `git add`, `git commit`, dan `git push` ke repositori `second-brain`.
- **Pencadangan Konfigurasi Otomatis:** Berjalan secara otomatis di latar belakang melalui tugas cron setiap 24 jam. Agen memeriksa perubahan dalam keterampilan kustom, memori yang baru ditambahkan, atau profil yang dimodifikasi, dan menyinkronkannya ke repositori `hermes-config`.

### 5. Pencadangan Manual
Jika Anda ingin memaksakan pencadangan segera, Anda dapat memerintahkan agen secara langsung dalam obrolan:
> *"Sinkronkan Second Brain saya ke GitHub sekarang"* atau *"Cadangkan konfigurasi dan keterampilan Anda ke GitHub segera."*

### 6. Memulihkan dari Pencadangan (Mesin Baru / Instal Ulang)
Jika Anda menyiapkan Hermes di server baru atau menginstal ulang, Anda dapat secara otomatis mengunduh semua data yang telah dicadangkan (konfigurasi, keterampilan, memori, dan seluruh Second Brain Anda) dari GitHub dengan satu perintah:
```bash
cd ~/.hermes/hermes-agent
bash scripts/second-brain/restore-from-cloud.sh
```

**Apa yang dilakukan skrip ini:**
1. Membaca `GITHUB_USERNAME`, `GITHUB_REPO_CONFIG`, `GITHUB_REPO_SECONDBRAIN`, dan `OBSIDIAN_VAULT_DIR` dari file `~/.hermes/.env` Anda.
2. Memverifikasi konektivitas SSH ke GitHub.
3. Meng-*clone* repositori `hermes-config` Anda dan memulihkan `skills/`, `profiles/`, `config.yaml`, `MEMORY.md`, dan `SOUL.md` kembali ke `~/.hermes/`.
4. Meng-*clone* repositori `second-brain` Anda langsung ke `OBSIDIAN_VAULT_DIR` Anda. Jika vault sudah ada sebagai repo Git, skrip akan melakukan `git pull` saja.
5. Membersihkan file sementara.

> **Prasyarat:** Pastikan Anda telah menyelesaikan Langkah 1–4 dari [Instalasi & Pengaturan Cepat](#instalasi--pengaturan-cepat) (dependensi OS, instalasi dasar Hermes, pengaturan venv, dan konfigurasi `.env`) sebelum menjalankan skrip pemulihan ini.

---

Silakan laporkan masalah (issues) di GitHub jika Anda menemukan bug.
