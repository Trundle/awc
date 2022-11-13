import Wlroots

struct SceneLayers {
    let scene: UnsafeMutablePointer<wlr_scene>
    let background: UnsafeMutablePointer<wlr_scene_tree>
    let tiling: UnsafeMutablePointer<wlr_scene_tree>
    let floating: UnsafeMutablePointer<wlr_scene_tree>
    let overlay: UnsafeMutablePointer<wlr_scene_tree>

    init?(scene: UnsafeMutablePointer<wlr_scene>) {
        self.scene = scene
        guard let tree = wlr_scene_tree_create(&scene.pointee.tree) else {
            return nil
        }
        self.background = tree
        guard let tree = wlr_scene_tree_create(tree) else {
            wlr_scene_node_destroy(&tree.pointee.node)
            return nil
        }
        self.tiling = tree
        guard let tree = wlr_scene_tree_create(tree) else {
            wlr_scene_node_destroy(&tree.pointee.node)
            return nil
        }
        self.floating = tree 
        guard let tree = wlr_scene_tree_create(tree) else {
            wlr_scene_node_destroy(&tree.pointee.node)
            return nil
        }
        self.overlay = tree
    }
}
