import os
# dmgbuild settings: defines.app is the app, defines.bg the background. Icon spots match make-dmg-background.py
app = defines["app"]
format = "UDZO"
compression_level = 9
files = [app]
symlinks = {"Applications": "/Applications"}
background = defines["bg"]
default_view = "icon-view"
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
window_rect = ((200, 160), (660, 400))
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {os.path.basename(app): (165, 212), "Applications": (495, 212)}
