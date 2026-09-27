import Testing

struct FetchOptionsTests {
    @Test(arguments: [
        (FetchOptions(), [String](), "Fetch"),
        (FetchOptions(prunes: true), ["--prune"], "Fetch (Prune)"),
        (FetchOptions(fetchesTags: true), ["--tags"], "Fetch (Tags)"),
        (FetchOptions(prunes: true, fetchesTags: true), ["--prune", "--tags"], "Fetch (Prune, Tags)"),
    ])
    func fetchSaysWhatItAdds(_ options: FetchOptions, _ arguments: [String], _ title: String) {
        // Act
        let added = options.arguments
        let fetchTitle = options.fetchTitle

        // Assert
        #expect(added == arguments)
        #expect(fetchTitle == title)
    }
}
