# Experiments Index

| Directory | Purpose | Date | Toolchain | Status |
|-----------|---------|------|-----------|--------|
| [borrow-consume-extract](borrow-consume-extract/) | Validate borrow-then-consume-extract pattern for ~Copyable Outcome | 2026-03-04 | Swift 6.2.4 | CONFIRMED |
| [borrowing-observe-pattern](borrowing-observe-pattern/) | Isolate ~Escapable Outcome compiler crash; find workaround for @_lifetime(borrow) | 2026-03-04 | Swift 6.2.4 | CONFIRMED |
| [calls-result-sibling](calls-result-sibling/) | Calls/Result/Outcome sibling placement: validate that Result and Outcome as sibling types of Calls (instead of nested) cause no naming collisions with Standard_Library_Extensions.Result. 7 variants all compile and execute. | 2026-03-16 | Swift 6.2.4 | CONFIRMED |
| [witness-property-method-collision](witness-property-method-collision/) | Does the @Witness underscore convention mechanically matter? V1 (labeled coexistence), V2 (unlabeled-call resolution), V3 (self. prefix), V6 (@Witness non-underscored storage) all CONFIRMED. V4 (same-signature: property wins, no collision). V5 (zero-arg collision) REFUTED with `invalid redeclaration of 'now()'`. V7 added after the 2026-04-17 macro change: underscored storage still emits deprecation pointing to stripped-name method (backwards-compat preserved). Underscore is mechanically required ONLY for zero-arg closures where both property and method share the same Swift name; for labeled closures it is purely cosmetic. Macro updated to only emit deprecation for underscored storage. | 2026-04-17 | Swift 6.3 | CONFIRMED |
