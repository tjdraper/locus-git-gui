/// A file's changes to open in a window of their own, with the rest of the commit's files for the
/// window's Previous File and Next File.
struct FileWindowRequest {
    let commit: Commit
    let file: DiffFile
    let files: [ChangedFile]
}
