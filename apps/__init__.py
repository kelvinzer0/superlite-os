"""SuperLite Apps - Built-in Applications"""

# Lazy imports — GTK4 only needed on desktop
def get_terminal():
    from .terminal import TerminalWindow
    return TerminalWindow

def get_filemanager():
    from .filemanager import FileManagerWindow
    return FileManagerWindow

def get_texteditor():
    from .texteditor import TextEditorWindow
    return TextEditorWindow

def get_browser():
    from .browser import BrowserLauncher
    return BrowserLauncher

__all__ = ["get_terminal", "get_filemanager", "get_texteditor", "get_browser"]
