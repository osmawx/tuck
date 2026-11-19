"""Place the installer contents over Tuck's Finder background."""

from unicodedata import normalize

format = "UDZO"
filesystem = "HFS+"
applications_name = "Программы"
# Match the on-disk HFS+ spelling so Finder finds the icon position.
shortcut_name = normalize("NFD", "Настройки безопасности")
files = [defines["app"]]
symlinks = {
    applications_name: "/Applications",
    shortcut_name: "/System/Library/PreferencePanes/Security.prefPane",
}
background = defines["background"]

window_rect = ((180, 140), (660, 530))
icon_size = 72
text_size = 13
icon_locations = {
    "Tuck.app": (190, 145),
    applications_name: (470, 145),
    shortcut_name: (330, 372),
    # Finder can show hidden files globally. Keep the artwork outside the initial view.
    ".background.tiff": (330, 650),
}
