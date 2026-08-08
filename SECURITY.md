# Security Policy

## Supported versions

Mutinynet is continuously deployed and does not maintain security fixes for
older releases or commits. Only the latest version of the `main` branch is
supported.

| Version | Supported |
| --- | --- |
| Latest `main` | Yes |
| Tagged releases and older commits | No |

## Reporting a vulnerability

Please do not open a public issue or discussion for a suspected vulnerability.
Instead, email `benthecarman@live.com` with the subject prefix
`[mutiny-net security]`.

Include as much of the following as possible:

- The affected component and commit or deployment
- A description of the vulnerability and its potential impact
- Steps to reproduce or a minimal proof of concept
- Any suggested mitigation

Do not include credentials, private keys, or other secrets in the report. We
will acknowledge the report, investigate it, and coordinate disclosure with
you. Please allow a reasonable amount of time for a fix before publishing any
details.

## Testing guidelines

Test against a local deployment whenever possible. Do not disrupt the public
Mutinynet service, access data that is not your own, degrade service for other
users, or perform denial-of-service testing.

Mutinynet is a public Bitcoin signet environment. Its coins have no monetary
value and it must not be used with mainnet funds or production secrets.

Vulnerabilities in an upstream project should be reported to that project. If
the issue is caused by Mutinynet's configuration or integration of an upstream
project, report it here.

This project does not currently offer a bug bounty or promise compensation for
reports.
