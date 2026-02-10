# Flatpak Build

## Prerequisites

Install flatpak and flatpak-builder:

```bash
sudo dnf install flatpak flatpak-builder
```

Add Flathub and install the SDK:

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08
```

## Building

From the repository root (with `baserom.us.z64` in place):

```bash
flatpak-builder --user --install --force-clean builddir flatpak/com.github.MorsGames.sm64plus.yml
```

## Running

```bash
flatpak run com.github.MorsGames.sm64plus
```

## Creating a distributable bundle

```bash
flatpak-builder --force-clean --repo=repo builddir flatpak/com.github.MorsGames.sm64plus.yml
flatpak build-bundle repo sm64plus.flatpak com.github.MorsGames.sm64plus
```

Users can then install with:

```bash
flatpak install sm64plus.flatpak
```
