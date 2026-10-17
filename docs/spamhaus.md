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
| DNS Blocklists via HTTPS | Separate subscribed product or trial; requires a query key authorized for HTTPS. A free DNS key does not establish HTTPS entitlement. |
| Commercial service | Quote based on users and query volume; a 30-day trial is available. No fixed price was established by this research. |

Sources: [public-mirror terms](https://www.spamhaus.org/blocklists/dnsbl-fair-use-policy/),
[free keyed-service terms](https://www.spamhaus.com/terms-of-use-fair-use-policy-for-free-data-query-service/),
[HTTPS access requirements](https://docs.spamhaus.com/datasets/docs/source/70-access-methods/web-query-service/000-intro.html),
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

The app offers two explicitly selected transports: public DNS through bounded
`dig` execution, or the native HTTPS API at `apibl.spamhaus.net`. HTTPS sends the
query key in the Authorization header and stores it only in shared Keychain under
`codes.tim.SpamWise.spamhaus`. It never embeds the key in a domain, URL, backup or
activity record. Public DNS is unavailable in the App Store build; HTTPS needs
only the existing outgoing-network entitlement. Neither transport falls back to
the other. Direct keyed DNS queries are not implemented.

Both routes require acknowledgement of the selected service's terms and remain
disabled by default and in local-only mode. Changing services clears that
acknowledgement. Lookups query at most five distinct validated domains per message,
with a three-second limit shortened by the processing deadline. HTTPS rejects
redirects, uses normal TLS validation, disables cookies, credential persistence
and response caching, and limits responses to 16 KiB. It accepts only documented
DBL codes. Matching HTTP/JSON 404 responses mean not listed; authentication,
rate limits, unknown codes, malformed responses and transport failures mean
unknown. There is no automatic service retry or mail action from a listing.
See the [HTTPS request protocol](https://docs.spamhaus.com/datasets/docs/source/70-access-methods/web-query-service/040-api-queries.html).

The request guide mentions code 2003, but the current zone table omits it.
SpamWise conservatively treats that inconsistent code as unknown; accepted codes
must also appear in the zone table.

Offline tests cover response interpretation, credential failures, consent,
domain/query bounds, cancellation, deadlines and local-only suppression. Live
Spamhaus account authorization and signed shipping queries remain unverified.

Spamhaus also maintains [Rspamd integration configuration](https://github.com/spamhaus/rspamd-dqs).
That is an alternative deployment path once its compatibility and service settings
are validated. Our Rspamd HTTP transport sends raw mail to the local scanner;
the scanner's own plugins determine which data leaves the Mac. Successful local
HTTP transport tests do not establish a tested Spamhaus-enabled scanner.

## Optional setup

In Settings → Advanced → Optional evidence, enable domain lookups and choose
the service. For HTTPS, obtain your own HTTPS-authorized subscription/trial query
key, paste it into the secure field and save it to Keychain. Saving a key does not
verify service access or send a request. Review the requirements, acknowledge
eligibility, then save evidence settings. Keep dry run enabled for initial testing;
dry run still permits explicitly authorized network lookups. To stop new queries,
disable the lookup toggle and save, or enable local-only mode.

No immediate account action is required while the feature is off. For shared
access or bundled credentials, obtain a separate licensing answer before release.
