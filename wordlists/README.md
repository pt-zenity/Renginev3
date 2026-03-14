# Custom Wordlists for reNgine-ng

Direktori ini berisi wordlist kustom yang digunakan untuk berbagai jenis reconnaissance dan fuzzing.

## Struktur Direktori

```
wordlists/
├── dns/                        # Subdomain enumeration
│   ├── subdomains-top5000.txt  # Top 5000 common subdomains
│   └── subdomains-common.txt   # Most common subdomains
│
├── web/                        # Web content discovery
│   ├── common-paths.txt        # Common web paths & sensitive files
│   └── extensions.txt          # Common file extensions
│
├── api/                        # API fuzzing
│   ├── api-endpoints.txt       # REST API endpoints
│   └── api-params.txt          # Common API parameters
│
├── fuzzing/                    # General fuzzing
│   └── dirsearch-custom.txt    # Custom dirsearch wordlist
│
├── passwords/                  # Password lists
│   └── common-passwords.txt    # Common passwords
│
├── usernames/                  # Username lists
│   └── common-usernames.txt    # Common usernames
│
└── backup/                     # Backup/sensitive file paths
    └── sensitive-files.txt     # Sensitive file paths
```

## Penggunaan dalam reNgine-ng

Wordlist ini otomatis dimuat ke container saat startup via `init-wordlists.sh`.
Path di dalam container: `/home/rengine/wordlists/custom/`

### FFUF / DirSearch
```bash
ffuf -w /home/rengine/wordlists/custom/fuzzing/dirsearch-custom.txt -u https://target.com/FUZZ
```

### Subfinder / Amass
```bash
subfinder -d target.com -w /home/rengine/wordlists/custom/dns/subdomains-top5000.txt
```

### Naabu / Nuclei
```bash
nuclei -l targets.txt -w /home/rengine/wordlists/custom/api/api-endpoints.txt
```

## Menambah Wordlist Baru

1. Letakkan file `.txt` di subdirektori yang sesuai
2. Rebuild container: `make build`
3. Atau restart untuk reload dari bind mount: `make restart`

## Sumber Referensi
- [SecLists](https://github.com/danielmiessler/SecLists)
- [Assetnote Wordlists](https://wordlists.assetnote.io/)
- [FuzzDB](https://github.com/fuzzdb-project/fuzzdb)
- [PayloadsAllTheThings](https://github.com/swisskyrepo/PayloadsAllTheThings)
