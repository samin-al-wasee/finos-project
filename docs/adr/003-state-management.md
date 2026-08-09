# ADR-003: State Management Approach

**Status:** Accepted
**Date:** 2026-08-09

## Context

FinOS uses a layered architecture (Presentation → Application → Domain →
Data) as defined in `docs/ARCHITECTURE.md` §4 and §23.

The state-management layer is responsible for:

* Coordinating UI state with domain use cases and repositories.
* Supporting dependency injection for testability.
* Managing asynchronous operations and loading/error/success states.
* Integrating with Drift's stream-based query API for reactive UI updates.

Business rules must not leak into the state-management layer (see
`docs/ARCHITECTURE.md` §23 and `docs/DEVELOPMENT.md` §4–§5).

## Decision

Use **Riverpod** (the `flutter_riverpod` package, without code generation) as
the application-state coordination layer.

Selected conventions:

* **Providers as dependency containers:** `Provider` exposes infrastructure
  singletons (e.g. the Drift `AppDatabase` instance) with lifecycle disposal
  via `ref.onDispose`.
* **Domain-specific state:** feature-specific state (streams from Drift,
  controller state, loading/error) is expressed with `StreamProvider`,
  `NotifierProvider`, and related Riverpod primitives as appropriate.
* **Testing:** providers are overridden at the widget/provider level with
  in-memory or fake implementations for unit and widget tests.
* **No code generation in V1:** plain Riverpod providers are preferred over
  `riverpod_generator` to reduce build infrastructure while the provider graph
  remains small.

## Consequences

### Positive

* Strong compile-time safety and explicit dependency graphs without framework
  magic.
* Reactive integration with Drift's `watch*` stream queries, keeping UI state
  in sync with local database changes.
* Testable at the provider level: individual providers or the full provider
  graph can be overridden for widget and unit tests.
* Well-established in the Flutter ecosystem and consistent with the
  "explicit before magical" principle in `docs/DEVELOPMENT.md` §3.

### Negative / Trade-offs

* Provider composition can grow large if features are added without discipline;
  the provider graph must be kept small and feature-scoped.
* Code-generation-based alternatives (e.g. `riverpod_generator`) are not
  adopted in V1; if the provider graph later justifies generated providers,
  this decision should be revisited.
* Riverpod does not replace the need for clear use-case / controller boundaries;
  discipline in layering remains essential.

## Alternatives Considered

* **Provider** — simpler ChangeNotifier-based DI; lighter but less structured
  for the layered architecture and less tightly integrated with reactive Drift
  streams.
* **Bloc** — strict event/state pattern with more boilerplate; heavier for a
  small personal-use project while providing no unique benefit at V1 scale.
* **Riverpod + code generation** — deferred to reduce build infrastructure
  complexity; revisitable if the provider graph grows.

## References

* `docs/ARCHITECTURE.md` §23 (State Management), §25 (Dependency Injection)
* `docs/DEVELOPMENT.md` §13 (State Management), §4–§5 (Architecture, Dependency Direction)
* `docs/AGENTS.md` §19 (Flutter Rules), §33 (AI-Specific Anti-Patterns)
