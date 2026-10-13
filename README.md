# Seafile thumbnail server deb packages

Easy to install and highly configurable debian packages for running [Seafile Community Edition](https://www.seafile.com) on your system natively without docker.

## Installation

Head over to [seafile-deb](https://github.com/dionysius/seafile-deb) for installation instructions as this repository contains the debian source for building the optional thumbnail server extension. It takes over thumbnail generation from Seahub and adds thumbnails for more file types.

Alternatively, download prebuilt packages from the [releases section](https://github.com/dionysius/seafile-thumbnail-deb/releases) and verify signatures with the [signing-key](signing-key.pub). Packages are automatically built in [Github Actions](https://github.com/dionysius/seafile-thumbnail-deb/actions).

## Configuration

See the [Configuration Wiki](https://github.com/dionysius/seafile-deb/wiki/Configuration) of seafile-deb. The thumbnail server's own options live in `/etc/seafile/thumbnail-server.env`.

## Release schedule

This project packages the thumbnail server for [seafile-deb](https://github.com/dionysius/seafile-deb) and aims to closely match the releases of upstream, whose versions follow the Seafile server's major series without being tied to its releases. The first release in each minor version series starts as a prerelease with a 3-day waiting period to allow upstream to fix oversights in new features or changes. Subsequent releases follow the same waiting period. After the waiting period has passed, all prereleases are automatically promoted to normal releases including new releases. Important releases may skip the waiting period.

## Build source package

This debian source package builds the [Seafile thumbnail server](https://github.com/haiwen/seafile-thumbnail-server) natively on your build environment. No annoying docker! It is managed with [git-buildpackage](https://wiki.debian.org/PackagingWithGit). You can find the maintaining command summary in [debian/gbp.conf](debian/gbp.conf).

### Requirements

Installed `git-buildpackage` from your apt, clone with it and switch to the folder:

```bash
gbp clone https://github.com/dionysius/seafile-thumbnail-deb.git
cd seafile-thumbnail-deb
```

Installed build dependencies as defined in [debian/control `Build-Depends`](debian/control) (will notify you in the build process otherwise). [`mk-build-deps`](https://manpages.debian.org/testing/devscripts/mk-build-deps.1.en.html) can help you automate the installation, for example:

```bash
mk-build-deps -i -r debian/control -t "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes"
```

### Build package

There are many arguments to fine-tune the build (see `gbp buildpackage --help` and `dpkg-buildpackage --help`), notable options: `-b` (binary-only, no source files), `-us` (unsigned source package), `-uc` (unsigned .buildinfo and .changes file), `--git-export-dir=<somedir>` (before building the package export the source there), for example:

```bash
gbp buildpackage -b -us -uc
```

On successful build packages can now be found in the parent directory `ls ../*.deb`.
