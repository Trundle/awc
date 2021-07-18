public protocol ExtensionDataProvider {
    func getExtensionData<D>() -> D?
}
