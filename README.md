# Noctalia shell

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

A beautiful, minimal desktop shell for Wayland that actually gets out of your way. Built on Quickshell with a warm lavender aesthetic that you can easily customize to match your vibe.

**✨ Key Features:**
- 🪟 Native support for Niri, Hyprland, Sway, MangoWC and labwc
- ⚡ Built on Quickshell for performance
- 🎯 Minimalist design philosophy
- 🔌 Plugin support ([explore plugins](https://noctalia.dev/plugins/))
- 🔧 Easily customizable to match your style
- 🎨 Many color schemes available
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

- Wayland compositor (Niri, Hyprland, Sway, MangoWC or labwc recommended)
- Quickshell
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

Noctalia provides native support for **Niri**, **Hyprland** and **Sway**. Other Wayland compositors will work but may require additional workspace logic configuration.

---

## 🔔 Notification Rules

Noctalia supports file-based notification filtering via `~/.config/noctalia/notification-rules.json`. Copy the example config to get started:

```bash
cp /path/to/noctalia-shell/Assets/notification-rules-default.json ~/.config/noctalia/notification-rules.json
```

### Actions

| Action | Description |
|--------|-------------|
| `show` | Display normally (default) |
| `block` | Suppress completely (saved to history with filtered flag) |
| `mute` | Show popup but no sound |
| `notoast` | Add to history/notification center, skip popup |
| `snooze` | Delay display (requires `snooze_minutes`) |
| `modify` | Rewrite notification (requires `modify` object) |

### Match Conditions

| Field | Type | Description |
|-------|------|-------------|
| `app_name` | string | Exact match (case-insensitive) |
| `app_pattern` | regex | Regex match against app name |
| `summary_pattern` | regex | Regex match against title |
| `body_pattern` | regex | Regex match against body |
| `body_contains` | string[] | Any word matches (case-insensitive) |
| `urgency` | object | Comparison: `eq`, `lt`, `gt`, `lte`, `gte`, `in` |
| `category` | string | Exact match on notification category |

### Rule Evaluation

- All conditions within a rule must match (AND logic)
- Rules are evaluated by priority (higher first)
- First matching rule wins
- If no rule matches, `defaultAction` is used

### Urgency Values

| Value | Level |
|-------|-------|
| 0 | Low |
| 1 | Normal |
| 2 | Critical |

See `Assets/notification-rules-default.json` for comprehensive examples.

---

## 🤝 Contributing

We welcome contributions of any size - bug fixes, new features, documentation improvements, or custom themes and configs.

**Get involved:**
- **Found a bug?** [Open an issue](https://github.com/noctalia-dev/noctalia-shell/issues/new)
- **Want to code?** Check out our [development guidelines](https://docs.noctalia.dev/development/guideline)
- **Need help?** Join our [Discord](https://discord.noctalia.dev)

### ✨ Nix DevShell

Nix users can use the flake's devShell to access a development environment. Run `nix develop` in the repo root to enter the dev shell. It includes packages, utilities and environment variables needed to develop Noctalia.

---

## 💜 Credits

A heartfelt thank you to our incredible community of [**contributors**](https://github.com/noctalia-dev/noctalia-shell/graphs/contributors). We are immensely grateful for your dedicated participation and the constructive feedback you've provided, which continue to shape and improve our project for everyone.

---

## ☕ Donations

While all donations are greatly appreciated, they are completely voluntary.

<a href="https://ko-fi.com/">
  <img src="https://img.shields.io/badge/donate-ko--fi-A8AEFF?style=for-the-badge&logo=kofi&logoColor=FFFFFF&labelColor=0C0D11" alt="Ko-Fi" />
</a>

### Thank you to everyone who supports the project 💜!
* Gohma
* DiscoCevapi
* <a href="https://pika-os.com/" target="_blank">PikaOS</a>
* LionHeartP
* Nyxion ツ
* RockDuck
* Eynix
* MrDowntempo
* Tempus Thales
* Raine
* JustCurtis
* llego
* Grune
* Maitreya (Max)
* sheast
* Radu

---

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.
