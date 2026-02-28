# Documentation Snippet Extraction

This directory contains scripts to keep documentation snippets synchronized with tested code.

## Overview

Documentation snippets in `Sources/Statoscope/Documentation.docc/Tutorials/` are automatically extracted from test files in `Tests/StatoscopeTests/Examples/` using annotation markers.

## Usage

Run the extraction script to update all documentation snippets:

```bash
./Scripts/extract-doc-snippets.swift
```

## Annotation Syntax

Use `@extract:begin` and `@extract:end` markers in test files to define extractable snippets:

```swift
// @extract:begin MySnippet-01
import Statoscope

final class Counter: Statostore {
    var count: Int = 0
}
// @extract:end MySnippet-01
```

### Multiple Begin/End Pairs (Progressive Disclosure)

You can use multiple begin/end pairs for the same snippet to create "windows" showing progressive code building:

```swift
// @extract:begin Counter-01
// @extract:begin Counter-02
import Statoscope
// @extract:end Counter-01

final class Counter: Statostore {
    var count: Int = 0
    // @extract:end Counter-02
    
    func increment() {
        count += 1
    }
    // @extract:begin Counter-02
}
// @extract:end Counter-02
```

This creates:
- **Counter-01**: Just the import
- **Counter-02**: Import + class with state + increment method (excludes the increment implementation details)

## Benefits

✅ **Single Source of Truth**: Docs always match tested, working code  
✅ **No Drift**: Documentation can't become outdated  
✅ **Compile-Time Verification**: Doc snippets are validated by tests  
✅ **Progressive Tutorials**: Show code building up step-by-step  

## Workflow

1. Write/update tests in `Tests/StatoscopeTests/Examples/Tutorial*.swift`
2. Add `@extract:begin/end` markers for documentation snippets
3. Run `./Scripts/extract-doc-snippets.swift`
4. Generated snippets appear in `Documentation.docc/Tutorials/.../`
5. Commit both test files and generated snippets

## CI Integration

Add to your CI pipeline to verify docs are up-to-date:

```bash
./Scripts/extract-doc-snippets.swift
git diff --exit-code Sources/Statoscope/Documentation.docc/
```

