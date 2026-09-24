# Architecture Review Checklist

- Does this change improve or preserve locality of behavior?
- Is the code grouped by user flow or use case rather than by technical concern?
- Did we keep related UI, state, and behavior close together?
- Was a new abstraction introduced because it represents a real feature boundary rather than generic reuse pressure?
- Should this code remain feature-local instead of moving to `Shared/`?
- Did we avoid creating or expanding vague buckets such as `Services`, `Managers`, `Helpers`, or `Utilities`?
- If a large file was touched, did we consider extracting one or more small named collaborators instead of extending the file?
- Are the names concrete and role-based, such as `Workflow`, `Coordinator`, `Navigator`, `Store`, `Factory`, `Resolver`, or `Builder`?
- If code was promoted upward, does at least one other distinct flow clearly need it?
- Does the resulting structure make the feature easier to understand by reading a small nearby cluster of files?
