import Libawc

extension ViewSet where L.OutputData == OutputDetails {
    func findOutputBy(name: String) -> Output<L>? {
        self.outputs().first(where: { $0.data.output.name == name })
    }
}
