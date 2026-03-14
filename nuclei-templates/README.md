# Custom Nuclei Templates for reNgine-ng

Direktori ini berisi custom Nuclei templates untuk deteksi berbagai kerentanan.

## Struktur Direktori

```
nuclei-templates/
├── cves/                              # CVE-specific templates
│   ├── cve-2021-44228-log4shell.yaml  # Log4Shell RCE
│   ├── cve-2021-41773-apache-rce.yaml # Apache 2.4.49 RCE
│   ├── cve-2022-22965-spring4shell.yaml # Spring4Shell RCE
│   ├── cve-2023-44487-http2-rapid-reset.yaml # HTTP/2 DoS
│   ├── cve-2020-14882-weblogic-rce.yaml # WebLogic RCE
│   └── cve-2019-11510-pulse-vpn-lfi.yaml # Pulse VPN LFI
│
├── exposures/                         # Information disclosure
│   ├── env-file-exposure.yaml         # .env file exposure
│   ├── git-exposure.yaml              # .git directory exposure
│   ├── wordpress-debug-log.yaml       # WordPress debug log
│   ├── aws-credentials-exposure.yaml  # AWS credentials
│   ├── docker-registry-exposure.yaml  # Docker registry
│   ├── kubernetes-api-exposure.yaml   # Kubernetes API
│   ├── firebase-exposure.yaml         # Firebase DB
│   └── server-version-disclosure.yaml # Server version info
│
├── misconfigurations/                 # Misconfigurations
│   ├── cors-misconfiguration.yaml     # CORS misconfiguration
│   ├── springboot-actuator.yaml       # Spring Boot actuator
│   ├── security-txt-missing.yaml      # security.txt missing
│   ├── debug-mode-enabled.yaml        # Debug mode enabled
│   └── http-methods-enabled.yaml      # Dangerous HTTP methods
│
├── vulnerabilities/                   # Vulnerability templates
│   ├── open-redirect.yaml             # Open redirect
│   ├── xss-reflected.yaml             # Reflected XSS
│   ├── ssrf-detection.yaml            # SSRF detection
│   ├── sqli-error-based.yaml          # SQL injection (error)
│   ├── sql-injection-error.yaml       # SQL injection
│   ├── path-traversal.yaml            # Path traversal / LFI
│   └── command-injection.yaml         # OS command injection
│
├── takeovers/                         # Subdomain takeovers
│   ├── subdomain-takeover-github.yaml # GitHub Pages takeover
│   ├── subdomain-takeover-cloud.yaml  # Generic cloud takeover
│   ├── subdomain-takeover-aws-s3.yaml # AWS S3 takeover
│   └── subdomain-takeover-azure.yaml  # Azure takeover
│
└── custom/                            # Custom/miscellaneous
    ├── api-key-exposure.yaml          # API key in responses
    ├── graphql-introspection.yaml     # GraphQL introspection
    ├── jwt-none-algorithm.yaml        # JWT none algorithm
    └── missing-security-headers.yaml  # Missing security headers
```

## Penggunaan

Templates ini otomatis dimuat ke container saat startup via `init-wordlists.sh`.
Path di dalam container: `/home/rengine/nuclei-templates/custom/`

### Menjalankan semua custom templates
```bash
nuclei -l targets.txt -t /home/rengine/nuclei-templates/custom/ -severity critical,high,medium
```

### Menjalankan kategori tertentu
```bash
# Hanya CVE templates
nuclei -l targets.txt -t /home/rengine/nuclei-templates/custom/cves/

# Hanya exposure templates
nuclei -l targets.txt -t /home/rengine/nuclei-templates/custom/exposures/

# Hanya vulnerability templates
nuclei -l targets.txt -t /home/rengine/nuclei-templates/custom/vulnerabilities/
```

### Menjalankan template tertentu
```bash
nuclei -l targets.txt -t /home/rengine/nuclei-templates/custom/cves/cve-2021-44228-log4shell.yaml
```

## Membuat Template Baru

Ikuti [Nuclei Template Guide](https://docs.projectdiscovery.io/templates/introduction):

```yaml
id: my-template

info:
  name: My Custom Template
  author: your-name
  severity: medium
  description: Description of what this template detects
  tags: custom,tag1,tag2

http:
  - method: GET
    path:
      - "{{BaseURL}}/path-to-test"
    
    matchers:
      - type: word
        words:
          - "pattern to match"
```

## Integrasi dengan reNgine-ng

Di reNgine-ng, template ini tersedia di:
- **Nuclei Template Path**: `/home/rengine/nuclei-templates/custom/`
- **Dikonfigurasi di**: `reNgine/definitions.py` → `NUCLEI_DEFAULT_TEMPLATES_PATH`

Untuk menggunakan template ini dalam scan engine:
1. Buka **Scan Engines** di dashboard reNgine-ng
2. Edit scan engine configuration
3. Tambahkan path template: `/home/rengine/nuclei-templates/custom/`

## Referensi
- [Nuclei Templates Docs](https://docs.projectdiscovery.io/templates/introduction)
- [ProjectDiscovery Nuclei Templates](https://github.com/projectdiscovery/nuclei-templates)
- [Nuclei Template Community](https://github.com/projectdiscovery/nuclei-templates/discussions)
