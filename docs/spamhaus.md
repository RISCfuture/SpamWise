# Spamhaus fit for SpamWise

Research checked on 2026-10-17. No account was registered, terms accepted, key
requested, paid service purchased or live message/domain lookup performed.

## What it adds

Spamhaus supplies reputation observations about domains, IPs and other resources.
For SpamWise, the Domain Blocklist (DBL) is the relevant starting point: its return
codes distinguish low-reputation, phishing, malware and compromised legitimate
domains. See the [official response-code definitions](https://docs.spamhaus.com/datasets/docs/source/10-data-type-documentation/datasets/040-zones.html).

Our assessment: this complements general spam/phishing detection but cannot
decide whether an otherwise legitimate newsletter is personally wanted. An absent
listing is not proof of safety, and a listed shared/compromised domain requires
context. SpamWise keeps observations separate from actions and preserves explicit
rules. It does not treat lookup errors as spam evidence.

## Access and cost

| Route | Current published conditions |
| --- | --- |
| Public DNS mirrors | Non-commercial use with reasonable volume; the originating network must be attributable through an appropriate recursive resolver or ECS-capable service. Ordinary shared public DNS is not a reliable drop-in configuration. |
| Free keyed DNS service, formerly DQS | Non-commercial individuals/small organizations; queries must not consistently exceed 100,000 per day, and contact details must remain current. Eligibility is conditional. |
| Commercial service | Quote based on users and query volume; a 30-day trial is available. No fixed price was established by this research. |

Sources: [public-mirror terms](https://www.spamhaus.org/blocklists/dnsbl-fair-use-policy/),
[free keyed-service terms](https://www.spamhaus.com/terms-of-use-fair-use-policy-for-free-data-query-service/),
and [commercial access and pricing](https://www.spamhaus.com/data-access/real-time-dns-blocklists/).

Your personal use may qualify for free access. That does not establish permission
to distribute a shared key with SpamWise or operate a common service for every
installation. Before offering built-in access broadly, obtain a written answer
covering a free desktop app, user-owned credentials, commercial users and any
developer-operated proxy. The app's zero price alone does not resolve those cases.

## Privacy and existing implementation

The current adapter sends sender/link domains in DNS questions, not full messages,
email addresses or URL paths. The resolver and service can therefore observe the
queried domains. Keyed DNS also puts the service key into the query name, as shown
in the [authentication protocol](https://docs.spamhaus.com/datasets/docs/source/70-access-methods/data-query-service/020-dqs-auth.html).

The app currently implements public DBL lookup through bounded `dig` execution,
with a user-selected resolver and terms acknowledgement. It has no DQS-key UI or
keyed-query transport. Signed shipping acceptance and a reliable sandbox-compatible
DNS transport remain engineering work. Lookup evidence stays disabled by default
and is blocked by local-only mode.

Spamhaus also maintains [Rspamd integration configuration](https://github.com/spamhaus/rspamd-dqs).
That is an alternative deployment path once its compatibility and service settings
are validated. Our Rspamd HTTP transport sends raw mail to the local scanner;
the scanner's own plugins determine which data leaves the Mac. Successful local
HTTP transport tests do not establish a tested Spamhaus-enabled scanner.

## Suggested next step

Keep Spamhaus optional. For personal testing, first establish free-account
eligibility, then implement and test the chosen transport without processing real
mail. For public distribution, request a licensing answer before designing shared
access or bundling credentials. No immediate account action is needed while this
feature remains disabled.
