# TopCTL 🛡️

**Automated Linux Security Hardening Tool**

TopCTL audits and hardens Linux systems based on CIS Benchmark recommendations. Built as a modular, extensible Bash toolkit that gives you a clear security score and actionable fixes.

> 🎓 Built by a cybersecurity student learning by doing. Contributions welcome.

---

## What It Does

TopCTL scans your Linux system across 6 security domains and either reports issues (**audit mode**) or fixes them automatically (**fix mode**):

| Module | Checks |
|--------|--------|
| **SSH** | Root login, password auth, protocol version, ciphers, timeouts |
| **Firewall** | UFW/iptables status, default policies, logging, SSH access |
| **Services** | Unnecessary running services, open ports, init script permissions |
| **Filesystem** | File permissions, SUID/SGID binaries, world-writable files, ownership |
| **Users** | UID 0 accounts, empty passwords, password policies, sudo config |
| **Updates** | Pending patches, automatic updates, kernel status |

Each run produces a timestamped report and a **security score** (0–100).

## Quick Start

```bash
# Clone the repo
git clone https://github.com/toppos2/topctl.git
cd topctl

# Make it executable
chmod +x topctl.sh

# Run an audit (scan only, no changes)
sudo ./topctl.sh --audit

# Run specific modules
sudo ./topctl.sh --ssh --firewall

# Apply fixes (creates backups first)
sudo ./topctl.sh --fix
```

## Example Output

```
    ████████╗ ██████╗ ██████╗  ██████╗████████╗██╗
    ╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝╚══██╔══╝██║
       ██║   ██║   ██║██████╔╝██║        ██║   ██║
       ██║   ██║   ██║██╔═══╝ ██║        ██║   ██║
       ██║   ╚██████╔╝██║     ╚██████╗   ██║   ███████╗
       ╚═╝    ╚═════╝ ╚═╝      ╚═════╝   ╚═╝   ╚══════╝
       Linux Security Hardening Tool

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SSH Configuration Hardening
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [✓ PASS] Root login disabled (PermitRootLogin = no)
  [✗ FAIL] Password authentication enabled (should be no)
  [✓ PASS] SSH Protocol 2 enforced
  [✓ PASS] Empty passwords disabled

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Passed:   18
  Failed:   4
  Warnings: 3

  Security Score: 82/100
  Rating: GOOD
```

## Project Structure

```
topctl/
├── topctl.sh               # Main entry point
├── modules/
│   ├── ssh.sh              # SSH hardening checks
│   ├── firewall.sh         # Firewall configuration
│   ├── services.sh         # Unnecessary services
│   ├── filesystem.sh       # File permissions & integrity
│   ├── users.sh            # User account security
│   └── updates.sh          # System update status
├── configs/
│   └── topctl.conf         # Configuration file
├── reports/                 # Generated reports (gitignored)
├── LICENSE
└── README.md
```

## Tested On

- Ubuntu 22.04 / 24.04 LTS
- Debian 12
- More distros coming (CentOS, Rocky Linux)

## Roadmap

- [ ] JSON report output for integration with dashboards
- [ ] HTML report with visual security score
- [ ] Network security module (open ports, listening services deep scan)
- [ ] Logging & monitoring module (auditd, syslog config)
- [ ] Docker/container hardening module
- [ ] Compliance mapping (CIS Benchmark ID references)
- [ ] Pre/post hardening comparison snapshots

## Why I Built This

I'm a cybersecurity student with the goal of becoming a Security Architect. Instead of just studying theory, I decided to build tools that solve real problems. TopCTL is my way of learning Linux security from the inside out — every check in this tool represents something I researched, understood, and implemented.

## Contributing

Found a bug? Want to add a check? PRs are welcome.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/new-check`)
3. Commit your changes
4. Push and open a PR

## License

MIT License — see [LICENSE](LICENSE) for details.

---

**⭐ If this helped you, star the repo — it helps other students find it.**
