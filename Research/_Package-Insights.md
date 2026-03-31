# swift-witnesses Insights

<!--
---
title: swift-witnesses Insights
version: 1.0.0
last_updated: 2026-03-31
applies_to: [swift-witnesses]
normative: false
---
-->

Design decisions, implementation patterns, and lessons learned specific to this package.

## Overview

This document captures insights that emerged during development of swift-witnesses.
These are not API requirements — they are recorded decisions and patterns that inform
future work on this package.

**Document type**: Non-normative (recorded decisions, not requirements).

**Consolidation source**: Reflection entries tagged with `[package: swift-witnesses]`.

---

## nonisolated(nonsending) Closures Skip Observation (2026-03-29)

**Date**: 2026-03-29

**Context**: The `observe` passthrough for `nonisolated(nonsending)` closures in the `@Witness` macro silently skips observation. This is the only correct behavior given the compiler constraint — `nonisolated(nonsending)` closures cannot be wrapped in an observation closure without changing their isolation semantics.

Users should know that `nonisolated(nonsending)` closure properties are not observable via the `observe` API. This is a known limitation, not a bug.

**Applies to**: @Witness macro, observe() API, nonisolated(nonsending) closure properties
