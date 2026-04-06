pragma Singleton

import Quickshell
import QtQuick

// built from pci database @ https://pci-ids.ucw.cz/
//
Singleton {
  // Known AMD APU/iGPU device IDs (Ryzen integrated graphics)
  // Covers Vega, RDNA2, RDNA3 APUs - dGPUs have different IDs
  readonly property var amdIgpuDeviceIds: [
    "0x1636", "0x1638", "0x164c", "0x1506",  // Renoir/Cezanne/Lucienne/Mendocino
    "0x15d8", "0x15dd", "0x15e7",             // Picasso/Raven Ridge/Barcelo (Vega)
    "0x163f", "0x1681",                       // VanGogh (Steam Deck) / Rembrandt
    "0x13c0",                                 // Granite Ridge (Ryzen AI 300)
    "0x15bf", "0x1900", "0x1901"              // Phoenix/HawkPoint (Ryzen 7040/8040)
  ]

  // AMD GPU device ID to marketing name mapping (partial list of common GPUs)
  readonly property var amdGpuNames: ({
    // APU/iGPU (RDNA3)
    "0x13c0": "Radeon Graphics (Granite Ridge)",
    // APU/iGPU (RDNA2/Zen3+)
    "0x1636": "Radeon Graphics (Renoir)",
    "0x1638": "Radeon Graphics (Cezanne)",
    "0x164c": "Radeon Graphics (Lucienne)",
    "0x1506": "Radeon 610M (Mendocino)",
    "0x15bf": "Radeon Graphics (Phoenix1)",
    "0x1900": "Radeon Graphics (HawkPoint1)",
    "0x1901": "Radeon Graphics (HawkPoint2)",
    "0x1681": "Radeon 680M (Rembrandt)",
    // APU/iGPU (Vega)
    "0x15d8": "Radeon Vega (Picasso/Raven 2)",
    "0x15dd": "Radeon Vega (Raven Ridge)",
    "0x15e7": "Radeon Graphics (Barcelo)",
    "0x163f": "Radeon Graphics (VanGogh)",
    // dGPU (RDNA3)
    "0x744c": "Radeon RX 7900 XT/XTX",
    "0x747e": "Radeon RX 7700 XT/7800 XT",
    "0x7480": "Radeon RX 7600/7600 XT",
    // dGPU (RDNA2)
    "0x73bf": "Radeon RX 6800/6800 XT/6900 XT",
    "0x73df": "Radeon RX 6700/6700 XT/6750 XT",
    "0x73ff": "Radeon RX 6600/6600 XT"
  })

  // NVIDIA GPU device ID to marketing name mapping (partial list of common GPUs)
  readonly property var nvidiaGpuNames: ({
    // RTX 50 series (Blackwell)
    "0x2b85": "GeForce RTX 5090",
    "0x2b87": "GeForce RTX 5090 D",
    "0x2c02": "GeForce RTX 5080",
    "0x2c05": "GeForce RTX 5070 Ti",
    "0x2f04": "GeForce RTX 5070",
    "0x2d04": "GeForce RTX 5060 Ti",
    "0x2d05": "GeForce RTX 5060",
    // RTX 40 series (Ada Lovelace)
    "0x2684": "GeForce RTX 4090",
    "0x2704": "GeForce RTX 4080",
    "0x2782": "GeForce RTX 4070 Ti",
    "0x2786": "GeForce RTX 4070",
    "0x2803": "GeForce RTX 4060 Ti",
    "0x2882": "GeForce RTX 4060",
    "0x28a1": "GeForce RTX 4050 Laptop GPU",
    // RTX 30 series (Ampere)
    "0x2204": "GeForce RTX 3090",
    "0x2206": "GeForce RTX 3080",
    "0x2484": "GeForce RTX 3070",
    "0x2487": "GeForce RTX 3060",
    "0x2503": "GeForce RTX 3060"
  })

  // Intel iGPU device ID to marketing name mapping (common integrated graphics)
  readonly property var intelGpuNames: ({
    // 13th Gen (Raptor Lake) - 2022-2023
    "0xa780": "UHD Graphics 770",
    "0xa720": "UHD Graphics",
    "0xa721": "UHD Graphics",
    "0xa7a0": "Iris Xe Graphics",
    "0xa7a1": "Iris Xe Graphics",
    "0xa7a8": "UHD Graphics",
    // 12th Gen (Alder Lake) - 2021-2022
    "0x4680": "UHD Graphics 770",
    "0x4682": "UHD Graphics 730",
    "0x4688": "UHD Graphics 770",
    "0x4690": "UHD Graphics 770",
    "0x4692": "UHD Graphics 730",
    "0x4693": "UHD Graphics 710",
    "0x46a6": "Iris Xe Graphics",
    "0x46a8": "Iris Xe Graphics",
    "0x46aa": "Iris Xe Graphics",
    "0x46a3": "UHD Graphics",
    "0x46d0": "UHD Graphics",
    // 11th Gen (Tiger Lake) - 2020-2021
    "0x9a40": "Iris Xe Graphics",
    "0x9a49": "Iris Xe Graphics",
    "0x9a60": "UHD Graphics",
    "0x9a68": "UHD Graphics",
    "0x9a70": "UHD Graphics",
    "0x9a78": "UHD Graphics",
    // 11th Gen (Rocket Lake) - 2021
    "0x4c8a": "UHD Graphics 750",
    "0x4c8b": "UHD Graphics 730",
    "0x4c90": "UHD Graphics P750",
    // 10th Gen (Comet Lake) - 2019-2020
    "0x9ba4": "UHD Graphics 610",
    "0x9ba8": "UHD Graphics 610",
    "0x9b21": "UHD Graphics 620",
    "0x9bc5": "UHD Graphics 630",
    "0x9bc8": "UHD Graphics 630",
    "0x9bc4": "UHD Graphics",
    // 10th Gen (Ice Lake) - 2019
    "0x8a51": "Iris Plus Graphics G7",
    "0x8a52": "Iris Plus Graphics G7",
    "0x8a53": "Iris Plus Graphics G7",
    "0x8a5a": "Iris Plus Graphics G4",
    "0x8a5c": "Iris Plus Graphics G4",
    "0x8a56": "Iris Plus Graphics G1",
    "0x8a58": "UHD Graphics G1",
    // 8th/9th Gen (Coffee/Whiskey Lake) - 2017-2019
    "0x3e90": "UHD Graphics 610",
    "0x3e93": "UHD Graphics 610",
    "0x3ea1": "UHD Graphics 610",
    "0x3ea0": "UHD Graphics 620",
    "0x3ea9": "UHD Graphics 620",
    "0x3e91": "UHD Graphics 630",
    "0x3e92": "UHD Graphics 630",
    "0x3e98": "UHD Graphics 630",
    "0x3e9b": "UHD Graphics 630",
    "0x3ea5": "Iris Plus Graphics 655",
    "0x3ea6": "Iris Plus Graphics 645",
    "0x3ea8": "Iris Plus Graphics 655",
    // 7th Gen (Kaby Lake) - 2016-2017
    "0x5902": "HD Graphics 610",
    "0x5906": "HD Graphics 610",
    "0x591e": "HD Graphics 615",
    "0x5916": "HD Graphics 620",
    "0x5917": "UHD Graphics 620",
    "0x5912": "HD Graphics 630",
    "0x591b": "HD Graphics 630",
    "0x5926": "Iris Plus Graphics 640",
    "0x5927": "Iris Plus Graphics 650"
  })
}
