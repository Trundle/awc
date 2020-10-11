import Wlroots

protocol Layout {
    func doLayout<View>(stack: Stack<View>, box: wlr_box) -> [(View, wlr_box)]
}

/// The simplest of all layouts: renders the focused surface fullscreen.
class Full<View> : Layout {
    func doLayout<View>(stack: Stack<View>, box: wlr_box) -> [(View, wlr_box)] {
        [(stack.focus, box)]
    }
}
