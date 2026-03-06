[한국어](SECURITY.md) | **English**

# Security Policy

## Supported Versions

| Version | Support |
|------|------|
| Latest release | Supported |
| Previous versions | Not supported |

## Reporting a Vulnerability

If you discover a security vulnerability, **please do not open a public issue**. Instead, report it through one of the following methods:

1. GitHub Security Advisory: [Report a vulnerability](https://github.com/DinN0000/DotBrain/security/advisories/new)
2. Or contact us via private email

### What to Include in Your Report

- Vulnerability type (e.g., path traversal, injection)
- Steps to reproduce
- Scope of impact
- Suggested fix, if possible

### Response Process

1. Acknowledgment within 72 hours of receiving the report
2. Severity assessment followed by a shared fix timeline
3. Release and credit given after the fix is complete

## Security Design

### API Key Storage
- AES-GCM encrypted file, key derived from hardware UUID + HKDF (device-bound)
- Stored file permissions: `0o600` (owner read/write only)
- Automatic migration from legacy macOS Keychain to encrypted file (V1 SHA256 → V2 HKDF)
- No API key required when using Claude CLI (subscription-based authentication)

### Network
- HTTPS only (NSAppTransportSecurity)
- API keys are transmitted only via HTTP headers (never in URL parameters)

### File System
- Path traversal prevention: `URL.resolvingSymlinksInPath()` followed by `hasPrefix` check
- Folder name validation: `sanitizeFolderName()` — max 3 depth, 255 character limit, `..` forbidden, null bytes removed
- Wiki-link injection prevention: `sanitizeWikilink()` — `[[`, `]]`, `/`, `\\`, `..` removed

### Data Protection
- YAML: tags are always stored as double-quoted arrays (`tags: ["tag1", "tag2"]`)
- File deletion: uses `trashItem` (recoverable deletion)
- File writing: atomic writes via `atomically: true` option
