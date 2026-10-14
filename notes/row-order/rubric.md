# Rubric: order-free, chunkable data-frame consumers

Research question:
which functions that accept a data frame (directly, via `data=` + formula, via `newdata=`, or via an `x` that is
coerced from a data frame) do not care about row order, and could be rewritten to consume the rows chunk by chunk
(streaming / out-of-core: read chunk, update state, discard chunk, finish)?

## ORDER class (pick one)

- `I` invariant: the result depends only on the multiset of rows
  (identical up to floating-point summation order).
- `E` row-local / equivariant: each output row (or kept/dropped decision) depends only on its own input row
  plus parameters fixed in advance; permuting the input permutes the output the same way.
  Filters, transforms, `predict(newdata=)`, `model.matrix` given fixed levels, writing rows.
- `S` invariant up to presentation: the set of results is invariant,
  but output order, row names, or first-appearance-based labels/levels follow input order
  (e.g. `unique()`, `merge(sort = FALSE)`, levels built from `unique()` instead of `sort(unique())`).
- `R` invariant only in distribution: RNG draws are indexed by row position
  (bootstrap, CV fold assignment, random starts, subsampling, random tie-breaking);
  with a fixed seed the result changes under row permutation.
- `D` order-dependent: semantics use row order
  (time series, lags, cumulative ops, first/last, `duplicated()`, ordered ties, AR/MA correlation without a time covariate).
  Report `D` only for notable traps (functions that look order-free but are not), not for obvious time-series code.

## CHUNK class (how a chunk-wise rewrite would work; pick the cheapest that is exact)

- `M` map: chunk-local and stateless (possibly with parameters fixed by a pre-pass).
- `A` single pass, fixed-size mergeable state:
  counts, sums, moments (Welford/Chan), cross-products X'X / X'y or incremental (Givens) QR, min/max,
  fixed-grid bins or histograms, linear binning onto a fixed grid, convex hulls, etc.
- `K` single pass, keyed mergeable state whose size grows with the number of distinct keys:
  groups, factor-level cells, unique x values, unique event times
  (e.g. `table()`, `xtabs()`, `rowsum()`, `aggregate()` with decomposable FUN, Kaplan–Meier counts).
- `P` multiple passes, each pass of type M/A/K:
  iterative estimation (IRLS, Newton, Fisher scoring, EM, Lloyd's k-means, `optim()` over a log-likelihood that is a sum of row contributions),
  or a pre-pass to fix global quantities (factor levels, ranges, centering/scaling, `poly()`/`ns()`/`bs()` knots, breaks).
  Say how many passes and what the per-pass state is.
- `H` holistic: order-invariant, but needs all rows at once, no bounded exact mergeable state
  (exact quantiles/medians/MAD/ranks, sorting, pairwise distances, nearest neighbours, kernel matrices, exact permutation tests,
  local regression, tree growing with arbitrary split points).
  Mention the realistic escape hatch:
  approximation (t-digest/KLL quantile sketches, reservoir sampling, pre-binning),
  degeneration to `K` when the number of distinct values is small,
  or "chunkable over the *prediction/test* rows only".

## Global-information traps to flag in notes

- factor level sets and `drop.unused.levels` (model-matrix columns depend on levels seen; needs a pre-pass or declared levels/`xlev`)
- data-dependent bases: `poly()`, `scale()`, `ns()`/`bs()` knots at quantiles, `mgcv::s()` knots/eigenbases, `cut(breaks = n)`
- `na.action`, `subset`, `weights`, `offset` are row-local (fine)
- convergence tests, starting values, or tuning computed on all rows
- integer overflow / precision of naive sums; algorithms needing the exact rank or sort
- RNG consumed per row (makes the result `R`)
- grouped data: invariance often holds only *between* groups, not *within* groups (e.g. `nlme` `corAR1()` without a covariate)

## Output format

Write findings as Markdown to the file named in your task, using exactly this per-function line shape
so results can be merged mechanically:

```
- `pkg::fun` — ORDER=X; CHUNK=Y; state: <what is accumulated per chunk / per pass>; notes: <caveats, traps, prior art>
```

Group the lines under `##` headings by package, and within a package put the most interesting ones first.
Methods can be grouped on one line (`stats::t.test.formula`, `stats::wilcox.test.formula` → split them only if they differ).
Skip pure plumbing (print/format/summary-of-a-fitted-object methods, coercion helpers, getters) unless they genuinely aggregate rows.
For each package also add one line `- **verdict**: ...` naming the 1–3 most valuable chunking targets,
and mention any function that is *already* chunk-capable (e.g. `mgcv::bam(chunk.size=)`, `biglm::update()`, `bigglm(data = function)`).

Ground claims in the source code you read (cite `file:line` for non-obvious claims),
not in memory of the documentation.
