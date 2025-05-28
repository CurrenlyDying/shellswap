# 🐚 shellswap 🔄

A simple and safe command-line utility to quickly swap the root user's default login shell between `/bin/bash` and `/bin/zsh` on Linux systems, particularly useful for Proxmox VE.

It directly modifies the root user's entry in `/etc/passwd`.

## ✨ Features

* **Easy Switching:** Toggle between Bash and Zsh for root with a single command.
* **Safe Operation:** Uses a temporary file to ensure `/etc/passwd` is not corrupted during the update.
* **Minimalist:** A single C program with no external runtime dependencies beyond libc.
* **Multiple Installation Options:** Install directly as a binary or via a `.deb` package.

## ⚠️ Prerequisites

* **Root Access:** You must run `shellswap` and its installers as root (e.g., using `sudo`).
* **`curl` or `wget`:** Required by the one-liner installation scripts to download assets.
* **Supported Shells:** `/bin/bash` and `/bin/zsh` must be installed on the system.
* **Debian-based System (for .deb):** `apt` and `dpkg` are used for the `.deb` package installation. So sworks with PVE.

## 🚀 Installation

You can install `shellswap` using one of the following methods.

### Method 1: Install via .deb Package (Recommended for Debian-based systems) 📦

This method downloads the latest `.deb` package and installs it using `apt` (with a fallback to `dpkg`). This is generally the preferred method for systems that use `.deb` packages as it allows for easier updates and removal via the package manager.

```bash
curl -fsSL [https://raw.githubusercontent.com/CurrenlyDying/shellswap/refs/heads/main/install-deb.sh](https://raw.githubusercontent.com/CurrenlyDying/shellswap/refs/heads/main/install-deb.sh) | sudo bash
```

*(Alternatively, using `wget`):*

```bash
wget -qO- [https://raw.githubusercontent.com/CurrenlyDying/shellswap/refs/heads/main/install-deb.sh](https://raw.githubusercontent.com/CurrenlyDying/shellswap/refs/heads/main/install-deb.sh) | sudo bash
```

This script will:

1.  Detect your system's architecture.
2.  Download the corresponding `shellswap_VERSION_ARCH.deb` package from the latest GitHub release.
3.  Attempt to install it using `sudo apt install ./package.deb`.
4.  If `apt` fails or is not available, it will try `sudo dpkg -i ./package.deb` and advise running `sudo apt --fix-broken install` if dependencies are missing.


### Method 2: Install Latest Binary Directly 💨

This method downloads the latest pre-compiled binary for your architecture and places it in `/bin`.

```bash
curl -fsSL [https://raw.githubusercontent.com/CurrenlyDying/shellswap/refs/heads/main/install-binary.sh](https://raw.githubusercontent.com/CurrenlyDying/shellswap/refs/heads/main/install-binary.sh) | sudo bash
````

This script will:

1.  Detect your system's architecture (amd64, arm64).
2.  Download the corresponding `shellswap-<arch>` binary from the latest GitHub release.
3.  Move it to `/bin/shellswap`.
4.  Set appropriate permissions (`root:root`, `755`).

## 🛠️ Usage

Once installed, simply run the command as root (sudo not needed if executing as root in PVE):

```bash
sudo shellswap
```

  * If the root shell is `/bin/bash`, it will be changed to `/bin/zsh`.
  * If the root shell is `/bin/zsh`, it will be changed to `/bin/bash`.
  * If the root shell is neither, it will report an error and make no changes.

You will need to log out and log back (or just open a new shell in PVE) in for the new shell to take effect.

## ⚙️ How It Works

`shellswap` carefully performs the following steps:

1.  Reads the `/etc/passwd` file.
2.  Checks the first line (expected to be the root user's entry).
3.  If the shell is `/bin/bash` or `/bin/zsh`, it prepares to swap it.
4.  Writes all changes to a temporary file (`/etc/passwd.tmp`).
5.  If all operations are successful, it atomically renames the temporary file to `/etc/passwd`.
6.  Permissions on `/etc/passwd` are maintained (0644).

This ensures that the critical `/etc/passwd` file is not left in a corrupted state.

## 🧑‍💻 Building from Source

If you prefer to build `shellswap` from source:

1.  **Prerequisites:**

      * A C compiler (e.g., `gcc`)
      * `git` (to clone the repository)

2.  **Clone the repository:**

    ```bash
    git clone [https://github.com/CurrenlyDying/shellswap.git](https://github.com/CurrenlyDying/shellswap.git)
    cd shellswap
    ```

3.  **Compile:**

    ```bash
    gcc -o shellswap shellswap.c
    ```

4.  **Install manually (optional):**

    ```bash
    sudo mv shellswap /bin/shellswap
    sudo chown root:root /bin/shellswap
    sudo chmod 755 /bin/shellswap
    ```


-----

Made with ❤️ by CurrenlyDying (loputo)

```
```
