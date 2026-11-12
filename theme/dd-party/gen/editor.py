"""Kate / KWrite / KDevelop editor colours (a KSyntaxHighlighting theme)."""
import os, sys, json
from palette import *


def st(color, **kw):
    d = {"text-color": color, "selected-text-color": TEXT}
    d.update({k.replace("_", "-"): v for k, v in kw.items()})
    return d


theme = {
    "metadata": {"name": "DD Party", "revision": 1, "license": "MIT", "copyright": ["DeskDroid"]},
    "text-styles": {
        "Normal": st(TEXT), "Keyword": st(PINK, bold=True), "Function": st(CYAN), "Variable": st("#FF8FB8"),
        "ControlFlow": st(PINK, bold=True), "Operator": st(SOFT), "BuiltIn": st(PURPLE), "Extension": st(CYAN, bold=True),
        "Preprocessor": st(ORANGE), "Attribute": st(YELLOW), "Char": st(GREEN), "SpecialChar": st("#7DFFB0"),
        "String": st(GREEN), "VerbatimString": st(GREEN), "SpecialString": st("#7DFFB0"), "Import": st(PURPLE),
        "DataType": st(YELLOW), "DecVal": st(ORANGE), "BaseN": st(ORANGE), "Float": st(ORANGE), "Constant": st(ORANGE, bold=True),
        "Comment": st(DIM, italic=True), "Documentation": st("#B08AC0", italic=True), "Annotation": st(PURPLE),
        "CommentVar": st(MAGENTA_TEXT), "RegionMarker": st(CYAN, **{"background-color": "#14142A"}),
        "Information": st(CYAN), "Warning": st(ORANGE), "Alert": st(RED, bold=True, **{"background-color": "#2A0F18"}),
        "Others": st(GREEN), "Error": st(RED, underline=True),
    },
    "editor-colors": {
        "BackgroundColor": BG, "CodeFolding": "#1A0F22", "BracketMatching": "#3A1028", "CurrentLine": "#11111C",
        "IconBorder": HEADER, "IndentationLine": "#22223A", "LineNumbers": "#4A4A66", "CurrentLineNumber": MAGENTA_TEXT,
        "MarkBookmark": CYAN, "MarkBreakpointActive": RED, "MarkBreakpointReached": YELLOW, "MarkBreakpointDisabled": PURPLE,
        "MarkExecution": GREEN, "MarkWarning": ORANGE, "MarkError": RED, "ModifiedLines": ORANGE, "SavedLines": GREEN,
        "ReplaceHighlight": "#1F5A3A", "SearchHighlight": "#5A4A10", "TextSelection": MAGENTA, "Separator": BORDER,
        "SpellChecking": RED, "TabMarker": "#2A2A3D", "TemplateBackground": "#12121E", "TemplatePlaceholder": "#1A0F22",
        "TemplateFocusedPlaceholder": "#3A1028", "TemplateReadOnlyPlaceholder": "#12121E", "WordWrapMarker": "#22223A",
    },
}

if __name__ == "__main__":
    out = sys.argv[1] + "/org.kde.syntax-highlighting/themes"
    os.makedirs(out, exist_ok=True)
    json.dump(theme, open(out + "/dd-party.theme", "w"), indent=2)
