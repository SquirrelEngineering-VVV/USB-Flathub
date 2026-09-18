# 📦 Flatpak Portable OSTree Manager (`menu.sh`)

An interactive, zero-dependency Bash utility designed to manage offline Flatpak application bundles on external storage (USB drives). It simplifies exporting applications from a host system into a portable `.ostree/repo` structure and provides a fuzzy-search interface (`fzf`) to sideload or prune applications directly from the drive.

---

## ✨ Features

- **Interactive TUI:** Built with `fzf` for intuitive, multi-select installation and deletion of Flatpaks.
- **Dependency Self-Healing:** Automatically detects missing binaries (`fzf`, `ostree`, `flatpak`) and installs them using your distro's native package manager (`apt`, `dnf`, `pacman`, or `zypper`).
- **Scope & Collection-ID Setup:** Ensures Flathub collection IDs are correctly configured (`org.flathub.Stable`) to prevent P2P sideloading failures.
- **Live Progress & Repository Metrics:** Real-time feedback spinner showing active operations alongside overall USB repository size disk usage.
- **Interactive Export Guide:** Built-in cheat sheet addressing common `flatpak create-usb` syntax errors, scope mismatches, and runtime requirements.

---

## 🚀 Quick Start

### 1. Installation

Place `menu.sh` at the root of your external drive or target directory.

```bash
# Make the script executable
chmod +x menu.sh

# Launch the manager
./menu.sh
```

---

## 🛠️ Usage Guide

### Sideload / Install Applications from USB
1. Launch `./menu.sh` and select **Option 2** (`Sideload/Install Flatpaks FROM this USB`).
2. The interactive `fzf` menu will display all applications present in `.ostree/repo`.
   - `[AVAILABLE]` — App is ready to be installed.
   - `[INSTALLED]` — App already exists on the local machine (will be skipped).
3. Navigation:
   - Use **Up / Down** arrow keys to navigate.
   - Press **TAB** to select multiple applications.
   - Press **ENTER** to start sideloading into the user scope.

---

### Exporting Applications TO the USB

Flatpak requires exporting both the **Application** and its underlying **Runtime**.

#### Step 1: Ensure Flathub Collection ID is set
```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify --user --collection-id=org.flathub.Stable flathub
```

#### Step 2: Identify App ID and Runtime
```bash
# List installed applications
flatpak list --app

# Find the associated runtime ID
flatpak info --show-runtime <APP_ID>
```

#### Step 3: Export Runtime & Application
```bash
# 1. Export Runtime (CRITICAL: Required for offline execution on target systems)
flatpak create-usb --user . runtime/<RUNTIME_ID>

# Example:
# flatpak create-usb --user . runtime/org.freedesktop.Platform/x86_64/23.08

# 2. Export Application
flatpak create-usb --user . <APP_ID>
```

---

## ⚠️ Common Pitfalls & Troubleshooting

| Error Message | Cause | Resolution |
| :--- | :--- | :--- |
| `Invalid id / Name can't start with [` | Shell bracket expansion issue when copying placeholders literally. | Remove square brackets `[...]` when specifying runtime strings. |
| `... not installed` / Scope Mismatch | Mixing system-wide (`sudo`) and user-installed (`--user`) scopes. | Ensure `--user` flag is matched across `flatpak list`, `flatpak install`, and `create-usb`. |
| `Collection ID not set` | Remote is missing P2P metadata. | Run `flatpak remote-modify --user --collection-id=org.flathub.Stable flathub`. |

---

## 📄 License

Distributed under the MIT License. Feel free to modify and distribute.