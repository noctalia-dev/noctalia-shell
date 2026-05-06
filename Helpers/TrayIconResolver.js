function resolveCandidates(icon) {
    if (!icon)
        return [""];
    if (!icon.includes("?path="))
        return [icon];

    const chunks = icon.split("?path=");
    const name = chunks[0];
    const path = chunks[1];
    const fileName = name.substring(name.lastIndexOf("/") + 1);

    return [
        `file://${path}/${fileName}`,
        `file://${path}/${fileName}.svg`,
        `file://${path}/${fileName}.png`,
        `file://${path}/hicolor/scalable/status/${fileName}.svg`,
        `file://${path}/hicolor/scalable/apps/${fileName}.svg`,
        `file://${path}/hicolor/scalable/categories/${fileName}.svg`,
        `file://${path}/hicolor/scalable/devices/${fileName}.svg`,
        `file://${path}/hicolor/scalable/actions/${fileName}.svg`,
        `file://${path}/hicolor/scalable/${fileName}.svg`,
        `file://${path}/hicolor/32x32/status/${fileName}.png`,
        `file://${path}/hicolor/32x32/apps/${fileName}.png`,
        `file://${path}/hicolor/48x48/status/${fileName}.png`,
        `file://${path}/hicolor/48x48/apps/${fileName}.png`,
        `file://${path}/hicolor/64x64/status/${fileName}.png`,
        `file://${path}/hicolor/64x64/apps/${fileName}.png`,
    ];
}
