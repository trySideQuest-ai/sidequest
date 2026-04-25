# Security Policy

## Reporting a Vulnerability

If you find a security issue in the SideQuest plugin or native app, please **do not open a public GitHub issue**. Instead, email:

**tomer.shavit5@gmail.com** — subject line: `SECURITY: SideQuest`

Include:

- A description of the issue and its impact.
- The affected version(s) (`plugin/VERSION` and the macOS app `CFBundleShortVersionString`).
- Steps to reproduce.
- A proof-of-concept if one exists.
- Whether you would like credit in the disclosure (and how to attribute).

## Disclosure Window

We aim to:

- Acknowledge reports within **3 business days**.
- Triage and assign severity within **7 days**.
- Ship a fix or document a mitigation within **90 days**.

If we cannot meet the 90-day window, we will tell you why and propose a new timeline.

## Scope

Security reports are accepted for code in this repository:

- The Claude Code plugin under `plugin/` (Bash + Python hooks, skills).
- The native macOS app under `macOS/` (Swift sources, Xcode project, scripts).
- Build + release scripts under `scripts/` and `.github/workflows/`.

Out of scope (please report to the relevant project instead):

- Vulnerabilities in third-party dependencies (please report to the upstream maintainer; we will accept a heads-up so we can pin a fix).
- Issues in the SideQuest API or landing pages — those live in the private monorepo and have their own disclosure path; you can report them to the same email.

## Bug Bounty

There is no formal bug bounty program. We may credit responsible disclosures in release notes if you want.

## Contact

- **Primary:** tomer.shavit5@gmail.com
- **Public:** [GitHub Issues](https://github.com/tomer-shavit/sidequest/issues) — please use this only for non-security reports.
