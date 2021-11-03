import Libawc

extension ViewSet where L.OutputData == OutputDetails {
    func findOutputBy(name: String) -> Output<L>? {
        self.outputs().first(where: { toString(array: $0.data.output.pointee.name) == name })
    }
}
