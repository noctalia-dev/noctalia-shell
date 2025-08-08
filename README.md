# Noctalia

**_quiet by design_**

<p align="center">
  <a href="https://github.com/Ly-sec/Noctalia/commits">
    <img src="https://img.shields.io/github/last-commit/Ly-sec/Noctalia?style=for-the-badge&labelColor=0C0D11&color=A8AEFF" alt="Last commit" />
  </a>
  <a href="https://github.com/Ly-sec/Noctalia/stargazers">
    <img src="https://img.shields.io/github/stars/Ly-sec/Noctalia?style=for-the-badge&labelColor=0C0D11&color=A8AEFF" alt="GitHub stars" />
  </a>
  <a href="https://github.com/Ly-sec/Noctalia/graphs/contributors">
    <img src="https://img.shields.io/github/contributors/Ly-sec/Noctalia?style=for-the-badge&labelColor=0C0D11&color=A8AEFF" alt="GitHub contributors" />
  </a>
  <a href="https://discord.gg/7JFFYWzWRn">
    <img src="https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&labelColor=0C0D11&color=A8AEFF&logo=discord&logoColor=white" alt="Discord" />
  </a>



</p>

A sleek, minimal, and thoughtfully crafted setup for Wayland using **Quickshell**. This setup includes a status bar, notification system, control panel, wifi & bluetooth support, power profiles, lockscreen, tray, workspaces, and more — all styled with a warm lavender palette.

## Preview

<details>
<summary>Click to expand preview images</summary>

![Main](https://i.imgur.com/5mOIGD2.jpeg)  
</br>

![Control Panel](https://i.imgur.com/fJmCV6m.jpeg)  
</br>

![Applauncher](https://i.imgur.com/9OPV30q.jpeg)

</details>
<br>

---

> ⚠️ **Note:**  
> This setup currently only supports **Niri** and **Hyprland** (for the most part), mostly due to the workspace integration. For anything else you will have to add your own workspace logic.

---

## Features

- **Status Bar:** Modular and informative with smooth animations.
- **Notifications:** Non-intrusive alerts styled to blend naturally.
- **Control Panel:** Centralized system controls for quick adjustments.
- **Connectivity:** Easy management of WiFi and Bluetooth devices.
- **Power Profiles:** Quick toggles for CPU performance.
- **Lockscreen:** Secure and visually consistent lock experience.
- **Tray & Workspaces:** Efficient workspace switching and tray icons.
- **Applauncher:** Stylized Applauncher to fit into the setup.

---

<details>
<summary><strong>Theme Colors</strong></summary>

| Color Role           | Color       | Description                |
| -------------------- | ----------- | -------------------------- |
| Background Primary   | `#0C0D11`   | Deep indigo-black          |
| Background Secondary | `#151720`   | Slightly lifted dark       |
| Background Tertiary  | `#1D202B`   | Soft contrast surface      |
| Surface              | `#1A1C26`   | Material-like base layer   |
| Surface Variant      | `#2A2D3A`   | Lightly elevated           |
| Text Primary         | `#CACEE2`   | Gentle off-white           |
| Text Secondary       | `#B7BBD0`   | Muted lavender-blue        |
| Text Disabled        | `#6B718A`   | Dimmed blue-gray           |
| Accent Primary       | `#A8AEFF`   | Light enchanted lavender   |
| Accent Secondary     | `#9EA0FF`   | Softer lavender hue        |
| Accent Tertiary      | `#8EABFF`   | Warm golden glow           |
| Error                | `#FF6B81`   | Soft rose red              |
| Warning              | `#FFBB66`   | Candlelight amber-orange   |
| Highlight            | `#E3C2FF`   | Bright magical lavender    |
| Ripple Effect        | `#F3DEFF`   | Gentle soft splash         |
| On Accent            | `#1A1A1A`   | Text on accent background  |
| Outline              | `#44485A`   | Subtle bluish-gray line    |
| Shadow               | `#000000B3` | Standard soft black shadow |
| Overlay              | `#11121ACC` | Deep bluish overlay        |

</details>

---

## Installation & Usage

<details>
<summary><strong>Installation</strong></summary>

Install quickshell:

```
yay -S quickshell-git
```

or use any other way of installing quickshell-git (flake, paru etc).

_Download and install the latest release:_

```
mkdir -p ~/.config/quickshell && curl -sL https://github.com/Ly-sec/Noctalia/releases/latest/download/noctalia-latest.tar.gz | tar -xz --strip-components=1 -C ~/.config/quickshell/
```

Or download manually from [releases](https://github.com/Ly-sec/Noctalia/releases) and extract:

```
mkdir -p ~/.config/quickshell && tar -xzf noctalia-*.tar.gz --strip-components=1 -C ~/.config/quickshell/
```

### _niri only_

Add this to your `layout` section:

`background-color "transparent"`

That is to make swww work properly.

</details>
</br>

<details>
<summary><strong>Usage</strong></summary>

### Start quickshell:

```
qs
```

(If you want to autostart it, just add it to your niri configuration.)

It is recommended to set the following in your Niri configuration (hyprland equivalent):

```
window-rule {
    geometry-corner-radius 20
    clip-to-geometry true
}
```

### Settings:

To make the weather widget, wallpaper manager and record button work you will have to open up the settings menu in to right panel (top right button to open panel) and edit said things accordingly.

### Launcher:

The launcher supports special commands for math calculation and clipboard history.
Once the launcher open you can invoke those special command by typing ">"
* \>calc : lets you do simple math
* \>clip : shows clipboard history

</details>

</br>
<details>
<summary><strong>Keybinds</strong></summary>

### Toggle Applauncher:

```
 qs ipc call globalIPC toggleLauncher
```

### Toggle Lockscreen:

```
 qs ipc call globalIPC toggleLock
```

### Toggle Notification Popup:

```
qs ipc call globalIPC toggleNotificationPopup
```

### Toggle Idle Inhibitor:

```
qs ipc call globalIPC toggleIdleInhibitor
```
</details>

---

## Dependencies

You will need to install a few things to get everything working:

- `cava` so the audio visualizer works
- `gpu-screen-recorder` so that the record button works
- `xdg-desktop-portal-gnome` or any other xdg-desktop-portal (for `gpu-screen-recorder`)
- `material-symbols-git` so the icons properly show up
- `swww` to add fancy wallpaper animations (optional)
- `wallust` to theme the setup based on wallpaper (optional)

## zigstat and zigbrightness

The zigstat and zigbrightness utilities are automatically built from source during release creation. Source code can be found [here](https://git.pika-os.com/wm-packages/pikabar/src/branch/main/src).

## Known issues

It is perfect now

---

## 💜 Credits

Huge thanks to [**@ferrreo**](https://github.com/ferrreo) and [**@quadbyte**](https://github.com/quadbyte) for all the changes they did and all the cool features they added!

---

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

#### Donation

---
While I actually didn't want to accept donations, more and more people are asking to donate so... I don't know, if you really feel like donating then I obviously highly appreciate it but **PLEASE** never feel forced to donate or anything. It won't change how I work on Noctalia, it's a project that I work on for fun in the end.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/R6R01IX85B)

---

#### Special Thanks

Thank you to everyone who supports me and this project 💜!
* Gohma

---

## License

This project is licensed under the terms of the [MIT License](./LICENSE).
