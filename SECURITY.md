# Security

Stackbar runs plugins in their own sandboxed processes and enforces the
capabilities each one declares. A way around that (a plugin reaching a host,
file, secret or system action it wasn't granted, or a signed bundle or index
that verifies when it shouldn't) is a security problem.

## Reporting

Please report privately through GitHub's
[private vulnerability reporting](https://github.com/navbytes/stackbar/security/advisories/new)
rather than in a public issue. Include the Stackbar version, the steps or a
plugin that shows the problem, and `stackbarctl doctor` output.

You'll get an answer within a week. Fixes ship in a new release, and the
advisory is published once most users can update.

## Supported versions

Only the latest release gets security fixes.
