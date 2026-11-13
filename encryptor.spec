Name:           encryptor
Version:        3.0.0
Release:        1%{?dist}
Summary:        Authenticated file encryption and X.509 toolkit built on OpenSSL

License:        MIT
URL:            https://github.com/mpgamer75/encryptor
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
Requires:       bash >= 4.4
Requires:       openssl >= 1.1.1
Requires:       coreutils
Recommends:     less
Suggests:       git

%description
Encryptor encrypts files with a password or for X.509 certificate holders,
using only Bash and the OpenSSL command line.

 - Self-describing ENCRYPTOR/3 container: cipher + HMAC-SHA256
   (encrypt-then-MAC), verified before any plaintext is written
 - Password mode (PBKDF2-HMAC-SHA256) and certificate recipients (CMS key wrap)
 - Secrets are never placed in process arguments or written to disk
 - Small PKI, certificate expiry report, local security audit, JSON output
 - Interactive terminal UI and a scriptable command-line interface

%prep
%setup -q

%install
install -Dm755 encryptor.sh %{buildroot}%{_bindir}/encryptor
# noarch shell modules live under /usr/lib (not %%{_libdir}, which is lib64 on 64-bit).
install -dm755 %{buildroot}%{_prefix}/lib/encryptor
for m in core ui crypto certs audit tui cli; do
    install -m644 lib/$m.sh %{buildroot}%{_prefix}/lib/encryptor/$m.sh
done
install -Dm644 man/encryptor.1 %{buildroot}%{_mandir}/man1/encryptor.1
install -dm755 %{buildroot}%{_datadir}/bash-completion/completions
bash encryptor.sh completion bash > %{buildroot}%{_datadir}/bash-completion/completions/encryptor

%check
bash tests/run.sh

%files
%license LICENSE
%doc README.md CHANGELOG.md SECURITY.md docs/USAGE.md docs/ALGORITHMS.md docs/FORMAT.md
%{_bindir}/encryptor
%{_prefix}/lib/encryptor/
%{_mandir}/man1/encryptor.1*
%{_datadir}/bash-completion/completions/encryptor

%changelog
* Fri Nov 13 2026 mpgamer75 <mpgamer75@github.com> - 3.0.0-1
- New authenticated container format ENCRYPTOR/3 (encrypt-then-MAC)
- Secrets passed to openssl over pipes; nothing on disk or in argv
- Certificate recipients via CMS key wrap, multiple recipients
- New command-line interface, terminal UI, PKI profiles, audit and test suite
- Modules installed under /usr/lib/encryptor; no path patching

* Sun Mar 22 2026 mpgamer75 <mpgamer75@github.com> - 2.1.0-1
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
