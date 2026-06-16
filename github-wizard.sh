#!/usr/bin/env bash
#
# github-wizard.sh — set up a persistent GitHub-over-SSH workflow on Tails.
#
# Everything (private key, SSH config, known_hosts, helper script and the repo
# itself) is stored under ~/Persistent/github so it survives a Tails reboot.
# The only non-persistent thing is the running SSH/Git process.
#
# Add a step: write a step_* function, then list it in STEPS at the bottom.
#
set -euo pipefail

bold=$'\033[1m'; yellow=$'\033[33m'; green=$'\033[32m'; reset=$'\033[0m'

# --- Configuration ---------------------------------------------------------
persistent_dir="$HOME/Persistent"
github_dir="$persistent_dir/github"
ssh_dir="$github_dir/ssh"
repos_dir="$github_dir/repos"
key_file="$ssh_dir/id_ed25519_github_tails"
pub_file="$key_file.pub"
config_file="$ssh_dir/config"
known_hosts="$ssh_dir/known_hosts"
helper_file="$github_dir/gitgh"

# Ask a yes/no question. Returns 0 for yes, 1 for no.
ask() {
    local answer
    while true; do
        read -rp "${bold}$1${reset} [y/n] " answer || return 1
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "Please answer y or n." ;;
        esac
    done
}

# Stop the wizard with a message.
abort() { echo; echo "${yellow}Stopped: $1${reset}"; exit 1; }

# Require a command to be available.
need() { command -v "$1" >/dev/null || abort "'$1' is not installed."; }

# ---------------------------------------------------------------------------

step_greeting() {
    echo "${bold}GitHub-on-Tails setup wizard.${reset}"
    echo "This sets up SSH access to GitHub that lives entirely inside your"
    echo "Persistent Storage, so it keeps working after every reboot."
    echo
    echo "Everything will be stored under:"
    echo "  $github_dir"
    echo

    need ssh-keygen; need ssh; need git

    [[ -d "$persistent_dir" ]] || \
        abort "Persistent Storage not found at $persistent_dir. Turn it on, unlock it, then run this again."

    ask "Ready to start?" || abort "come back when you are ready."
}

step_make_folders() {
    echo
    echo "${bold}Step 1 — Creating folders inside Persistent...${reset}"

    mkdir -p "$ssh_dir" "$repos_dir"
    chmod 700 "$ssh_dir"

    echo "${green}Created:${reset}"
    echo "  $ssh_dir   (key + config, mode 700)"
    echo "  $repos_dir (your cloned repos)"
}

step_generate_key() {
    echo
    echo "${bold}Step 2 — Generating the SSH key...${reset}"

    if [[ -f "$key_file" ]]; then
        echo "${green}A key already exists: $key_file${reset}"
        if ask "Keep the existing key? (choose No only to replace it)"; then
            echo "Keeping the existing key."
        else
            ask "Really DELETE and regenerate the key? The old one stops working." \
                || abort "leaving the existing key in place."
            rm -f "$key_file" "$pub_file"
        fi
    fi

    if [[ ! -f "$key_file" ]]; then
        echo "${yellow}You will be asked for a passphrase. Use a strong one — it"
        echo "encrypts the private key on disk. The wizard never sees it.${reset}"
        echo
        # Run ssh-keygen interactively so the user types the passphrase.
        ssh-keygen -t ed25519 -f "$key_file" -C "tails-github" \
            || abort "key generation failed or was cancelled."
    fi

    # Lock down permissions either way.
    chmod 600 "$key_file"
    chmod 644 "$pub_file"
    echo "${green}Key ready (private 600, public 644).${reset}"
}

step_add_to_github() {
    echo
    echo "${bold}Step 3 — Add the public key to GitHub.${reset}"
    echo "Here is your PUBLIC key (safe to share — never share the private one):"
    echo
    echo "${yellow}$(cat "$pub_file")${reset}"
    echo
    echo "Add it to GitHub one of two ways:"
    echo "  Account-wide key:  Settings > SSH and GPG keys > New SSH key"
    echo "  Per-repo deploy key (safer if you only need one private repo):"
    echo "    <repo> > Settings > Deploy keys > Add deploy key"
    echo "    (tick 'Allow write access' if you need to push)"
    echo
    echo "GitHub requires the public key on your account (or as a deploy key)"
    echo "before any SSH Git operation will work."
    echo

    ask "Have you added the public key to GitHub?" \
        || abort "add the key to GitHub, then run this wizard again."
}

step_write_config() {
    echo
    echo "${bold}Step 4 — Writing the SSH config into Persistent...${reset}"

    if [[ -f "$config_file" ]]; then
        ask "An SSH config already exists. Overwrite it?" \
            || { echo "Keeping the existing config."; return 0; }
    fi

    # Uses ssh.github.com on port 443: GitHub supports SSH over the HTTPS port,
    # which is more reliable in restricted / Tor-routed environments than the
    # normal SSH port 22. known_hosts is kept inside Persistent too.
    cat > "$config_file" <<EOF
Host github.com
    HostName ssh.github.com
    User git
    Port 443
    IdentityFile $key_file
    IdentitiesOnly yes
    UserKnownHostsFile $known_hosts
    StrictHostKeyChecking accept-new
EOF

    chmod 600 "$config_file"
    echo "${green}Wrote $config_file${reset}"
}

step_test_ssh() {
    echo
    echo "${bold}Step 5 — Testing GitHub SSH (over Tor)...${reset}"
    echo "Connecting with: ssh -F $config_file -T git@github.com"
    echo

    # GitHub closes the session with exit code 1 ("no shell access") even on
    # success, so we look at the message rather than the exit code.
    local output
    output=$(ssh -F "$config_file" -T git@github.com 2>&1) || true
    echo "$output"
    echo

    if grep -q "successfully authenticated" <<<"$output"; then
        echo "${green}Success — GitHub accepted your key.${reset}"
    else
        echo "${yellow}Authentication did not succeed.${reset}"
        echo "Check that: Tor is connected, the public key is on GitHub, and"
        echo "you can reach ssh.github.com:443."
        abort "could not authenticate to GitHub."
    fi
}

step_clone_repo() {
    echo
    echo "${bold}Step 6 — Cloning your repository into Persistent...${reset}"

    local slug
    while true; do
        read -rp "${bold}Repository (owner/repo): ${reset}" slug || abort "no repository given."
        slug="${slug#git@github.com:}"; slug="${slug%.git}"   # tolerate full SSH URLs
        [[ "$slug" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] && break
        echo "Please enter it as owner/repo (for example: octocat/Hello-World)."
    done

    local repo_name dest
    repo_name="${slug#*/}"
    dest="$repos_dir/$repo_name"

    if [[ -d "$dest" ]]; then
        echo "${green}A directory already exists: $dest${reset}"
        echo "Skipping clone. (Use the helper to 'pull' inside it instead.)"
        return 0
    fi

    echo "Cloning git@github.com:$slug.git into $dest ..."
    if ! GIT_SSH_COMMAND="ssh -F $config_file" \
            git clone "git@github.com:$slug.git" "$dest"; then
        abort "clone failed (check the repo name, your access, and Tor)."
    fi
    echo "${green}Cloned into $dest${reset}"
}

step_write_helper() {
    echo
    echo "${bold}Step 7 — Creating the 'gitgh' helper script...${reset}"

    # A tiny wrapper so you can use git against GitHub without retyping
    # GIT_SSH_COMMAND every time.
    cat > "$helper_file" <<EOF
#!/bin/sh
export GIT_SSH_COMMAND="ssh -F $config_file"
exec git "\$@"
EOF
    chmod +x "$helper_file"
    echo "${green}Wrote $helper_file${reset}"
}

step_done() {
    echo
    echo "${green}${bold}All set.${reset}"
    echo
    echo "Everything lives under: $github_dir"
    echo
    echo "Use the helper instead of plain git when talking to GitHub:"
    echo "  $helper_file pull"
    echo "  $helper_file status"
    echo "  $helper_file add ."
    echo "  $helper_file commit -m \"message\""
    echo "  $helper_file push"
    echo
    echo "Future boot routine — after unlocking Persistent Storage:"
    echo "  cd $repos_dir/<REPO>"
    echo "  $helper_file pull"
}

# ---------------------------------------------------------------------------
# Steps run in this order.
STEPS=(
    step_greeting
    step_make_folders
    step_generate_key
    step_add_to_github
    step_write_config
    step_test_ssh
    step_clone_repo
    step_write_helper
    step_done
)

for step in "${STEPS[@]}"; do "$step"; done
