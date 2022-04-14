import Libawc

fileprivate let scratchpadTag = "scratchpad"

fileprivate class ScratchpadData {
    /// The scratchpad view
    var scratchpadSurface: Surface? = nil
}


extension Awc {
    func assignFocusAsScratchpad() {
        let data = self.getScratchpadData()
        let currentScratchpad = data.scratchpadSurface
        self.withFocused {
            data.scratchpadSurface = $0
        }
        if let currentScratchpad = currentScratchpad,
            let workspace = self.viewSet.findWorkspace(view: currentScratchpad),
            workspace.tag == scratchpadTag
        {
            // There is currently a surface on the scratchpad workspacee.
            // Be nice and bring it to the current workspace so it's not lost
            self.modifyAndUpdate {
                $0.focus(view: currentScratchpad)
                    .shift(tag: $0.current.workspace.tag)
                    .view(tag: $0.current.workspace.tag)
            }
        }
    }

    func toggleScratchpad() {
        let data = self.getScratchpadData()
        if let scratchpadSurface = data.scratchpadSurface {
            self.modifyAndUpdate { viewSet in
                let focus = viewSet.peek()
                if scratchpadSurface == focus {
                    return viewSet.shift(tag: scratchpadTag)
                } else {
                    return viewSet
                        .focus(view: scratchpadSurface)
                        .shift(tag: viewSet.current.workspace.tag)
                        .view(tag: viewSet.current.workspace.tag)
                }
            }
        }
    }

    fileprivate func getScratchpadData() -> ScratchpadData {
        if let data: ScratchpadData = self.getExtensionData() {
            return data
        } else {
            let data = ScratchpadData()
            self.addExtensionData(data)
            return data
        }
    }
}
