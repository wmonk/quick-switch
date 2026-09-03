# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability. Use [GitHub's private vulnerability reporting](https://github.com/wmonk/quick-switch/security/advisories/new) and include:

- the affected commit or version;
- reproduction steps or a proof of concept;
- the security impact; and
- any suggested mitigation.

Avoid including real window titles, passwords, signing credentials, or other sensitive data. Reports will be acknowledged as soon as practical, then assessed and coordinated privately before any public disclosure.

## Supported versions

Until Quick Switch has a tagged stable release, security fixes are made on the latest commit of the default branch.

## Expected privileged behavior

Quick Switch requires macOS Accessibility permission, installs a session-level keyboard event tap, and uses a dynamically loaded private macOS symbol to replace Command-Tab. App Sandbox is disabled because the app must inspect and focus windows owned by other applications. These behaviors are core to the app and are not vulnerabilities by themselves.

Quick Switch should never transmit window metadata, capture screen contents, or persist window titles. A report showing that it does any of those things is in scope.
