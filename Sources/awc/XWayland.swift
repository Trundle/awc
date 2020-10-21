/// Atoms describing the functional type of a window, as set by the client.
///
/// See also https://specifications.freedesktop.org/wm-spec/1.4/ar01s05.html
enum AtomWindowType: String, CaseIterable {
    /// The window is popped up by a combo box (e.g. completions window in a text field)
    case combo = "_NET_WM_WINDOW_TYPE_COMBO"
    case dialog = "_NET_WM_WINDOW_TYPE_DIALOG"
    case dropdownMenu = "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU"
    case menu = "_NET_WM_WINDOW_TYPE_MENU"
    case normal = "_NET_WM_WINDOW_TYPE_NORMAL"
    case notification = "_NET_WM_WINDOW_TYPE_NOTIFICATION"
    case popupMenu = "_NET_WM_WINDOW_TYPE_POPUP_MENU"
    /// The window is a "splash screen" (a window displayed on application startup)
    case splash = "_NET_WM_WINDOW_TYPE_SPLASH"
    case toolbar = "_NET_WM_WINDOW_TYPE_TOOLBAR"
    case tooltip = "_NET_WM_WINDOW_TYPE_TOOLTIP"

    /// A small persistent utility window, such as a palette or toolbox. It is distinct from type
    /// .toolbar because it does not correspond to a toolbar torn off from the main application.
    /// It's distinect from type DIALOG because it isn't a transient dialog, the user will
    /// probably keep it open while they're working.
    case utility = "_NET_WM_WINDOW_TYPE_UTILITY"
}
