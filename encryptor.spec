Name:           encryptor
Version:        2.1.0
Release:        1%{?dist}
Summary:        Advanced CLI encryption tool with AES-256-GCM, S/MIME, and PKI management

License:        MIT
URL:            https://github.com/mpgamer75/encryptor
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
Requires:       bash >= 4.0
Requires:       openssl >= 1.1.1
Recommends:     git
Recommends:     less
Recommends:     coreutils

%description
Encryptor is an advanced command-line encryption tool built on OpenSSL.

Features:
  - AES-256-GCM (default, true AEAD), AES-256-CBC/CTR, ChaCha20,
    Camellia-256-CBC, ARIA-256-CBC symmetric encryption
  - S/MIME asymmetric encryption using X.509 certificates
  - PBKDF2-HMAC-SHA256 key derivation (600,000 iterations)
  - SHA-256 integrity sidecar files for tamper detection
  - Full X.509 PKI management: Root CA, CSR, signing, PKCS#12 export
  - Security audit (local checks + optional remote SSL/TLS scan)
  - Batch/non-interactive mode for CI/CD pipelines (--encrypt, --decrypt, --json)
  - Interactive color-coded TUI
  - Cross-platform: Linux, macOS, WSL

%prep
%setup -q

%install
# Main script
install -Dm755 encryptor.sh %{buildroot}%{_bindir}/encryptor

# Library modules
install -dm755 %{buildroot}%{_libdir}/encryptor
install -Dm644 lib/ui.sh     %{buildroot}%{_libdir}/encryptor/ui.sh
install -Dm644 lib/crypto.sh %{buildroot}%{_libdir}/encryptor/crypto.sh
install -Dm644 lib/certs.sh  %{buildroot}%{_libdir}/encryptor/certs.sh
install -Dm644 lib/audit.sh  %{buildroot}%{_libdir}/encryptor/audit.sh

# Patch LIB_DIR to point to the installed location
sed -i 's|LIB_DIR="$SCRIPT_DIR/lib"|LIB_DIR="%{_libdir}/encryptor"|' \
    %{buildroot}%{_bindir}/encryptor

# Documentation
install -Dm644 README.md            %{buildroot}%{_docdir}/%{name}/README.md
install -Dm644 CHANGELOG.md         %{buildroot}%{_docdir}/%{name}/CHANGELOG.md
install -Dm644 docs/ALGORITHMS.md   %{buildroot}%{_docdir}/%{name}/ALGORITHMS.md
install -Dm644 docs/USAGE.md        %{buildroot}%{_docdir}/%{name}/USAGE.md
install -Dm644 LICENSE              %{buildroot}%{_docdir}/%{name}/LICENSE

# Man page
install -dm755 %{buildroot}%{_mandir}/man1
gzip -c debian/encryptor.1 > %{buildroot}%{_mandir}/man1/encryptor.1.gz

%files
%license LICENSE
%doc %{_docdir}/%{name}/
%{_bindir}/encryptor
%{_libdir}/encryptor/
%{_mandir}/man1/encryptor.1.gz

%post
# Update man database if available
if command -v mandb >/dev/null 2>&1; then
    mandb -q 2>/dev/null || true
fi

%postun
# Update man database after removal
if command -v mandb >/dev/null 2>&1; then
    mandb -q 2>/dev/null || true
fi

%changelog
* Sat Mar 22 2026 mpgamer75 <mpgamer75@github.com> - 2.1.0-1
- Critical security fix: password no longer exposed in process args (ps aux)
- Critical security fix: false AEAD claim corrected for CBC/CTR modes
- Critical security fix: PKCS#12 export password leak fixed
- Added AES-256-GCM as new default recommended algorithm (true AEAD)
- Raised PBKDF2 iterations from 100,000 to 600,000 (OWASP 2024)
- Added SHA-256 integrity sidecar files for tamper detection
- Refactored monolithic script into lib/ modules (ui, crypto, certs, audit)
- Added batch/non-interactive mode with JSON output
- Added built-in --help (no .deb installation required)
- Added ASCII spinner for long operations
- Added status bar in main menu
- Improved uninstall.sh with full cleanup and user prompts
- Added ShellCheck to CI and upgraded actions/checkout to v4
- Added functional smoke tests in CI
- Fixed ALGORITHMS.md to accurately reflect implemented algorithms

* Mon Jan 01 2024 mpgamer75 <mpgamer75@github.com> - 2.0.0-1
- Initial RPM package
