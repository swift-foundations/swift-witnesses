# Audit: swift-witnesses

## Legacy — Consolidated 2026-04-08

### From: swift-institute/Research/audit-foundations.md (2026-04-03)

**Pre-publication audit — P0/P1/P2 checks**

#### P1: Multi-type Files [API-IMPL-005]

**Severe (5+ types in one file)**:

| File | Types | Lines |
|------|-------|-------|
| `Sources/Witnesses Macros Implementation/WitnessMacro.swift` | 13 | 1494 |
| `Sources/Witnesses Macros Implementation/EnumExpansion.swift` | 5 | 360 |

**Note on WitnessMacro.swift**: This is a macro implementation file containing `WitnessMacro`, `DeriveOptions`, `ClosureProperty`, `ClosureParameter`, `NonClosureProperty`, plus generated type templates (`Calls`, `Prisms`, `Outcome`, `Case`, `Result`). The generated templates are source-generation output embedded in the macro, not independent API types. The helper structs are private/internal to the macro implementation. Severity is structural rather than API-surface.

**Minor (2 types in one file)**:

| File | Nature |
|------|--------|
| `Witness.Context.swift` | `Context` struct + `_ContextKey` internal |
| `Witness.Key.swift` | `__WitnessKeyTest` protocol + `Key` protocol |
| `WitnessAccessorsMacro.swift` | 4 types (macro + 2 helpers + diagnostic) |

#### P1: Compound Type Names [API-NAME-001] — Macro Types (exempt)

| Type | Reason |
|------|--------|
| `WitnessAccessorsMacro` | SwiftSyntax macro naming convention requires `*Macro` suffix |
| `WitnessScopeMacro` | Same — required by `@_CompilerPlugin` |
| `WitnessMacro` | Same |

These are exempt from [API-NAME-001] because SwiftSyntax requires compound `*Macro` suffix names.

#### P1: Untyped Throws — Not Violations

Macro implementations use untyped `throws` because the `MemberMacro`, `PeerMacro`, `MemberAttributeMacro`, and `ExtensionMacro` protocols from SwiftSyntax require `throws -> [DeclSyntax]`. These cannot use typed throws.

#### P2: Methods in Type Bodies [API-IMPL-008]

| File:Line | Type | Members |
|-----------|------|---------|
| `WitnessMacro.swift:498` | `ClosureProperty` | 10 |
| `WitnessAccessorsMacro.swift:70` | `AccessorClosureProperty` | 6 |
| `WitnessMacro.swift:653` | `ClosureParameter` | 5 |

#### Recommended Action (Consider)

`WitnessMacro.swift` (1494 lines, 13 types) could benefit from extracting helper types into separate files. Not blocking since these are `private`/`internal` macro-implementation types, not public API.

---

### From: swift-institute/Research/modularization-audit-foundations-batch-B.md (2026-03-20)

**Modularization audit — MOD-001 through MOD-014**

2 products: Witnesses, Witnesses Macros. 3 source targets: Witnesses, Witnesses Macros, Witnesses Macros Implementation.

| Rule | Status | Notes |
|------|--------|-------|
| MOD-001 | N/A | Main + Macros pattern |
| MOD-002 | REVIEW | `Witness Primitives` declared in both Witnesses and Witnesses Macros target deps. Witnesses depends on Macros, so it could receive Witness Primitives transitively if Macros re-exports it. |
| MOD-003 | N/A | Not a variant package |
| MOD-004 | N/A | No ~Copyable concerns |
| MOD-005 | N/A | Two products but vertical (Witnesses depends on Macros) |
| MOD-006 | PASS | Each target declares deps it needs |
| MOD-007 | PASS | Depth 2 (Witnesses → Macros → Implementation) |
| MOD-008 | PASS | Main: 21 files, Macros: 1 file, Implementation: 5 files |
| MOD-009 | N/A | No inline variants |
| MOD-010 | N/A | No stdlib extensions |
| MOD-011 | **FAIL** | No Test Support product |
| MOD-012 | PASS | `Witnesses`, `Witnesses Macros` — correct L3 naming |
| MOD-013 | N/A | 4 targets, threshold is 5 |
| MOD-014 | N/A | No cross-package optional integration |

**Findings**: 1 FAIL (MOD-011). 1 REVIEW (MOD-002): `Witness Primitives` appears in both Witnesses and Witnesses Macros deps. Since Witnesses already depends on Witnesses Macros, this is a duplicate if Macros re-exports it. Verify whether `MemberImportVisibility` requires the explicit dependency declaration (see primitives delta audit section 5 — this is a systemic ecosystem pattern where MemberImportVisibility forces explicit dep declarations even when transitive access exists).
