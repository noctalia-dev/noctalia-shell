# Noctalia Shell

**_quiet by design_**

<p align="center">
  <img src="https://assets.noctalia.dev/noctalia-logo.svg?v=2" alt="Noctalia Logo" style="width: 192px" />
</p>

<p align="center">
  <a href="https://docs.noctalia.dev/getting-started/installation">
    <img
      src="https://img.shields.io/badge/🌙_Install_Noctalia-A8AEFF?style=for-the-badge&labelColor=0C0D11"
      alt="Install Noctalia"
      style="height: 50px"
    />
  </a>
</p>

<p><br/></p>

<p align="center">
  <a href="https://github.com/noctalia-dev/noctalia-shell/commits">
    <img src="https://img.shields.io/github/last-commit/noctalia-dev/noctalia-shell?style=for-the-badge&labelColor=0C0D11&color=A8AEFF&logo=git&logoColor=FFFFFF&label=commit" alt="Last commit" />
  </a>
  <a href="https://github.com/noctalia-dev/noctalia-shell/stargazers">
    <img src="https://img.shields.io/github/stars/noctalia-dev/noctalia-shell?style=for-the-badge&labelColor=0C0D11&color=A8AEFF&logo=github&logoColor=FFFFFF" alt="GitHub stars" />
  </a>
  <a href="https://docs.noctalia.dev">
    <img src="https://img.shields.io/badge/docs-A8AEFF?style=for-the-badge&logo=gitbook&logoColor=FFFFFF&labelColor=0C0D11" alt="Documentation" />
  </a>
  <a href="https://discord.noctalia.dev">
    <img src="https://img.shields.io/badge/discord-A8AEFF?style=for-the-badge&labelColor=0C0D11&logo=discord&logoColor=FFFFFF" alt="Discord" />
  </a>
</p>

---

## What is Noctalia?

A beautiful, minimal desktop shell for Wayland that actually gets out of your way. Built on [Quickshell](https://quickshell.outfoxxed.me/) (Qt/QML) with a warm lavender aesthetic that you can easily customize to match your vibe.

**✨ Key Features:**
- 🪟 Native support for Niri, Hyprland, Sway, Scroll, Labwc and MangoWC
- 🎨 Extensive theming with predefined color schemes and automatic color generation from your wallpaper
- 🖼️ Wallpaper management with Wallhaven integration
- 🔔 Notification system with history and Do Not Disturb
- 🖥️ Multi-monitor support
- 🔒 Lock screen
- 🧩 Desktop widgets (clock, media player and more)
- 💡 OSD for volume and brightness
- 🔌 30+ plugins available ([explore plugins](https://noctalia.dev/plugins/))
- 🪄 Setup wizard for first-time users
- ⚡ Built on Quickshell for performance

---

## Preview

https://github.com/user-attachments/assets/bf46f233-8d66-439a-a1ae-ab0446270f2d

<details>
<summary>Screenshots</summary>

![Dark 1](/Assets/Screenshots/noctalia-dark-1.png)
![Dark 2](/Assets/Screenshots/noctalia-dark-2.png)
![Dark 3](/Assets/Screenshots/noctalia-dark-3.png)

![Light 1](/Assets/Screenshots/noctalia-light-1.png)
![Light 2](/Assets/Screenshots/noctalia-light-2.png)
![Light 3](/Assets/Screenshots/noctalia-light-3.png)

</details>

---

## 📋 Requirements

- Wayland compositor (see supported compositors below)
- Quickshell: [noctalia-qs](https://github.com/noctalia-dev/noctalia-qs)
- Additional dependencies are listed in our [documentation](https://docs.noctalia.dev)

---

## 🚀 Getting Started

**New to Noctalia?**
Check out our comprehensive documentation and installation guide to get up and running!

<p align="center">
  <a href="https://docs.noctalia.dev/getting-started/installation">
    <img src="https://img.shields.io/badge/📖_Installation_Guide-A8AEFF?style=for-the-badge&logoColor=FFFFFF&labelColor=0C0D11" alt="Installation Guide" />
  </a>
  <a href="https://docs.noctalia.dev/getting-started/faq/">
    <img src="https://img.shields.io/badge/❓_FAQ-A8AEFF?style=for-the-badge&logoColor=FFFFFF&labelColor=0C0D11" alt="FAQ" />
  </a>
  <a href="https://discord.noctalia.dev">
    <img src="https://img.shields.io/badge/💬_Get_Help-A8AEFF?style=for-the-badge&logo=discord&logoColor=FFFFFF&labelColor=0C0D11" alt="Discord" />
  </a>
</p>

---

## 🖥️ Wayland Compositors

Noctalia provides native support for **Niri**, **Hyprland**, **Sway**, **Scroll**, **Labwc** and **MangoWC**. Other Wayland compositors may work but could require additional configuration for compositor-specific features like workspaces and window management.

---

## Scope

Noctalia is a **desktop shell**, not a full desktop environment. It provides the visual layer that sits on top of your Wayland compositor (bars, panels, notifications, a dock, and widgets) but it intentionally stays within that boundary. Understanding this helps set the right expectations for feature requests.

### What Noctalia does

Noctalia focuses on the things a shell is responsible for: status bar, panels, application launcher, notifications, lock screen, idle management, OSD, theming, wallpapers, desktop widgets, dock, and multi-monitor support.

### What belongs in a plugin

If a feature is useful to some users but not essential to the core shell experience, it's a great candidate for a [plugin](https://noctalia.dev/plugins/). The plugin system is designed to make this easy: plugins can add bar widgets, panels, launcher providers, desktop widgets, and more.

Some examples of features that are better suited as plugins:
- Compositor-specific extras (e.g., Steam overlay for Hyprland)
- Hardware-specific controls (e.g., laptop fan profiles, battery thresholds)
- Third-party service integrations (e.g., smart home controls, Tailscale)
- Niche productivity tools (e.g., Pomodoro timer, RSS reader, Docker manager)
- Alternative visualizations or widgets

If you have an idea that fits this category, consider [building a plugin](https://docs.noctalia.dev/development/guideline) for it!

### What falls outside our scope

Some features go beyond what a desktop shell can or should do. These are typically responsibilities of the compositor, a dedicated application, or the system itself:

- **File management**: use a file manager application
- **Display/login greeter**: this runs before the shell and is managed separately
- **Window management and overview**: workspace switching and window tiling are compositor responsibilities
- **Removable drive mounting**: handled by system services like udisks and desktop applications
- **Screen mirroring/casting**: managed by the compositor or dedicated tools

We appreciate feature suggestions, but if a request falls into this category, it's likely outside what Noctalia can provide. When in doubt, feel free to ask in our [Discord](https://discord.noctalia.dev).

---

## 🤝 Contributing

We welcome contributions of any size - bug fixes, new features, documentation improvements, or custom themes and configs.

**Get involved:**
- **Found a bug?** [Open an issue](https://github.com/noctalia-dev/noctalia-shell/issues/new)
- **Want to code?** Check out our [development guidelines](https://docs.noctalia.dev/development/guideline)
- **Need help?** Join our [Discord](https://discord.noctalia.dev)

---

## 💜 Credits

A heartfelt thank you to our incredible community of [**contributors**](https://github.com/noctalia-dev/noctalia-shell/graphs/contributors). We are immensely grateful for your dedicated participation and the constructive feedback you've provided, which continue to shape and improve our project for everyone.

---

## ☕ Donations

While all donations are greatly appreciated, they are completely voluntary.
Thank you to everyone who supports the project! 💜

<p>
  <a href="https://www.buymeacoffee.com/noctalia">
    <img src="https://img.shields.io/badge/Buy_Me_a_Coffee-A8AEFF?style=for-the-badge&logo=buymeacoffee&logoColor=FFFFFF&labelColor=0C0D11" alt="Buy Me a Coffee">
  </a>
  <a href="https://ko-fi.com/noctaliadev">
    <img src="https://img.shields.io/badge/Ko--fi-A8AEFF?style=for-the-badge&logo=kofi&logoColor=FFFFFF&labelColor=0C0D11" alt="Ko-fi">
  </a>
</p>

---

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.

---

## ⭐ Star History

<p align="center">
  <a href="https://github.com/noctalia-dev/noctalia-shell/stargazers">
    <img src="https://api.noctalia.dev/stars" alt="Star History" />
  </a>
</p>