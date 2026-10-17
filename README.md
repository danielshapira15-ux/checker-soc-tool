# CHECKER — Automated SOC Attack Simulation Tool

A Bash tool for SOC (Security Operations Center) training labs. It discovers live
hosts on the local network, lets the operator pick an attack type and a target
(manually or at random), runs the attack, and logs every execution for later
review — the kind of controlled, repeatable "red team" activity a SOC analyst
needs to practice detecting.

## What it does

1. **Network discovery** — scans the local subnet with `nmap -sn` and lists every
   live host it finds.
2. **Attack menu** — presents three independent attack types, each with its own
   description, and lets the operator choose one by number or let the script
   pick at random:
   - **Nmap Port Scan** — service/version scan of the target
   - **Hydra SSH Brute-force** — credential brute-force attempt against SSH
   - **Hping3 SYN Flood** — a short, bounded burst of TCP SYN packets to
     simulate a flood/DoS pattern
3. **Target selection** — manual IP entry, selection by list number, or random
   pick from the discovered hosts.
4. **Input validation** — any invalid menu choice prints an error and exits
   immediately rather than guessing.
5. **Logging** — every executed attack is appended to `/var/log/checker_project.log`
   with its type, timestamp, and target IP, so results can be reviewed afterward.

## Requirements

- Linux (tested on Ubuntu Server)
- `nmap`, `hydra`, `hping3` installed and on `PATH`
- `sudo` privileges (needed for `hping3` and for writing to `/var/log`)

Install the dependencies on Debian/Ubuntu:

```bash
sudo apt update && sudo apt install nmap hydra hping3 -y
```

For the Hydra attack, create simple wordlists (adjust to your own lab's test
accounts — never point this at anything you don't own or have explicit
permission to test):

```bash
mkdir -p ~/wordlists
printf "web\nadmin\nroot\n" > ~/wordlists/users.txt
printf "123456\npassword\n" > ~/wordlists/passwords.txt
```

## Usage

```bash
chmod +x checker.sh
./checker.sh
```

Follow the on-screen menu: choose an attack by number (or `random`), then a
target IP (by address, by list number, or `random`).

## ⚠️ Scope and intended use

This tool is built **for isolated lab environments only** — a local VM network
you control, with no real external targets. The Hydra and Hping3 attacks are
real, functioning offensive techniques; running them against any system you do
not own or do not have explicit written permission to test is illegal in most
jurisdictions. This project exists purely to help SOC trainees generate
realistic attack traffic they can then learn to detect and respond to.

## Background

Built as a hands-on project for a SOC Analyst training course, to practice
both the offensive side (what an attack actually looks like on the wire) and
the logging/detection side (how a SOC would record and later audit it).
