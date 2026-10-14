# Consumers that do not need row order: approaches and prior art

Question: what would R code that *receives* data have to look like
so that a producer (duckplyr, Arrow datasets, Spark, a database cursor, a chunked file reader)
can drop the row-order requirement and hand over rows in arbitrary order, possibly chunk by chunk?

This note surveys how other systems answer that question, what R already has,
and the spectrum of approaches from documentation to patching every function.
It ends with a layered recommendation and open questions.

It builds on two earlier pieces of work in this repository:

- `notes/row-order/` on the branch `claude/ecstatic-cannon-s84vqu`:
  a catalogue of 1,223 data-frame consumers in base R, the recommended packages and CRAN packages of depth 1–3,
  classified by order class and chunk class, with the six reasons a function depends on order
  (`README.md`, `chunkable-report.md`, `order-report.md`).
- `notes/row-order-literature.md` on the branch `claude/row-order-literature`:
  the literature on row-order invariance (relational theory, mergeable summaries, sufficiency, exchangeability, metamorphic testing).
  Citations given there are not repeated here unless they are needed for the argument.

**How sources were checked.**
Most documentation hosts (duckdb.org, postgresql.org, docs.pola.rs, spark.apache.org, beam.apache.org, docs.oracle.com and others)
were unreachable from the environment that wrote this note.
For those, every quote was taken verbatim from the upstream source file that builds the page (a GitHub repository),
and the rendered URL is given as the conventional location; such URLs are marked "(page not fetched)".
R package claims were checked against the installed help pages of the current CRAN versions (October 2026) or by running code.
Items that could not be confirmed at all are marked **unverified**.

## 1. The question, made precise

### Two goals

The two goals need different things from consumers, and most approaches serve only one.

- **(a) Order-free materialisation.**
  The producer still delivers every row into one R data frame, but in whatever order is cheapest.
  The consumer must give the same answer for any permutation of the rows.
  This is the "order class" of the earlier catalogue:
  invariant (`I`), row-local (`E`), same set but presentation follows input (`S`), invariant only in distribution (`R`),
  or order-dependent (`D`).
- **(b) Chunk-wise consumption.**
  The producer delivers the rows as a sequence of chunks, possibly in parallel streams, and never all at once.
  The consumer must be written as a state that is updated by each chunk and merged across streams.
  This is the "chunk class":
  stateless map (`M`), one pass with fixed-size state (`A`), one pass with keyed state (`K`), several passes (`P`), holistic (`H`).

Goal (b) implies goal (a) only when the merge is commutative.
`iotools::chunk.apply(CH.SEQUENTIAL = TRUE)`, readr's `AccumulateCallback`, Clojure's `fold` and Algebird's `Semigroup`
consume chunks *in order* with an associative merge.
Beam, SQL aggregates and `foreach(.inorder = FALSE)` additionally require commutativity, and only those give the producer full freedom.
Conversely, a consumer can satisfy (a) and not (b): exact `quantile()` is order-invariant but holistic.

### A third, often forgotten requirement: one consistent permutation

"Unordered" does not mean "each column in its own order".
A row-local consumer such as `predict(fit, newdata = df)` returns a vector aligned with its input,
and the user then pairs it with `df$id` or `cbind()`s it back.
A data frame delivered in arbitrary order must therefore still be a *single* permutation applied to all columns,
and any side input (weights, offsets, an `id` vector held elsewhere) must be permuted with it.
For a producer that materialises columns lazily and independently,
this means all columns of one frame must come from one execution, or the execution must be deterministic.
The earlier catalogue's "side inputs aligned by position" group (`cbind()`, `Ops.data.frame`, `sweep()`, `lm(subset = <integer>)`)
is exactly the set of consumers that break when this is violated.

### What the producer can and cannot see

A producer decides about order when it builds or executes its plan.
duckplyr builds a lazy relation and executes it when a consumer first touches column data or the row count;
its prudence vignette says
"accessing column data or retrieving the number of rows will trigger a computation that is carried out by DuckDB".
At that moment the producer sees an ALTREP vector being touched, not *which function* touched it or why.
So for goal (a), information about the consumer has to reach the producer *before* the first touch, by one of three routes:

- the user says so, at the boundary (a flag, a class, a scope);
- the consumer's identity is known in advance (a registry the producer or a wrapper consults);
- the producer guesses and is checked afterwards (dynamic testing).

For goal (b) the producer cannot help at all unless the consumer accepts something other than a data frame,
because a data frame, lazy or not, is all rows.
Every approach below is one of these routes, or a way to make the consumer accept chunks.

## 2. How other systems let consumers opt out of order

### Relational engines: order is absent unless requested, and aggregates declare what they need

- **SQL.**
  PostgreSQL: "If sorting is not chosen, the rows will be returned in an unspecified order. … it must not be relied on."
  ([queries-order](https://www.postgresql.org/docs/current/queries-order.html), page not fetched; source `doc/src/sgml/queries.sgml`).
  Inside aggregates: "Ordinarily, the input rows are fed to the aggregate function in an unspecified order.
  In many cases this does not matter; for example, `min` produces the same result…"
  ([§4.2.7](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES), page not fetched; `syntax.sgml`).
  An aggregate that needs order says so at the call site, either `array_agg(x ORDER BY t)`
  or, for ordered-set aggregates, `percentile_cont(0.5) WITHIN GROUP (ORDER BY x)`.
  - This is the cleanest design in the survey: the *default contract of a consumer is order-free*,
    and order-dependent consumers carry their order requirement as an argument.
- **User-defined aggregates as a registry of properties.**
  PostgreSQL `CREATE AGGREGATE` takes `SFUNC`, `STYPE`, `FINALFUNC`, `COMBINEFUNC`, `SERIALFUNC`/`DESERIALFUNC`
  and `PARALLEL = { SAFE | RESTRICTED | UNSAFE }`:
  "the combinefunc must combine two state_data_type values, each containing the result of aggregation over some subset of the input values",
  and "the aggregate must also be marked `PARALLEL SAFE` to enable parallel aggregation"
  ([CREATE AGGREGATE](https://www.postgresql.org/docs/current/sql-createaggregate.html), page not fetched; `create_aggregate.sgml`).
  Function volatility (`IMMUTABLE`/`STABLE`/`VOLATILE`) and SQLite's `SQLITE_DETERMINISTIC` flag
  ("the new function always gives the same output when the input parameters are the same",
  [c3ref](https://www.sqlite.org/c3ref/c_deterministic.html), page not fetched; `src/sqlite.h.in`)
  are further examples of a *declared property* that the engine trusts and exploits.
  MADlib builds in-database OLS exactly this way, with `SFUNC = linregr_transition`, a merge function and `FINALFUNC = linregr_final`
  ([`linear.sql_in`](https://github.com/apache/madlib/blob/master/src/ports/postgres/modules/regress/linear.sql_in);
  Hellerstein et al., "The MADlib Analytics Library", PVLDB 5(12), 2012, <https://doi.org/10.14778/2367502.2367510>, PDF not read).
- **DuckDB.**
  The [order preservation page](https://duckdb.org/docs/current/sql/dialect/order_preservation)
  (page not fetched; `duckdb-web/docs/current/sql/dialect/order_preservation.md`) lists which operators keep insertion order
  and states that `GROUP BY` keeps "neither in- nor output order".
  The `preserve_insertion_order` setting (default `true`):
  "If set to false the system is allowed to re-order any results that do not contain ORDER BY clauses."
  The aggregate documentation says "Most aggregate functions are order-insensitive, and for them this clause is parsed and discarded",
  and names `first`, `last`, `list` and `string_agg` as order-sensitive.
  So DuckDB knows, per aggregate, whether order matters; it does not know this about R code that receives its output.
- **SQLite `PRAGMA reverse_unordered_selects`** reverses unordered `SELECT` output
  "to debug applications that are making invalid assumptions about the result order"
  ([pragma](https://www.sqlite.org/pragma.html#pragma_reverse_unordered_selects); wording seen in search snippets and mirrors only,
  the pragma itself confirmed in `tool/mkpragmatab.tcl`).
  This is dynamic checking built into a producer (section 6.6).

### Dataframe libraries: per-operator flags

- **Polars.**
  `group_by(maintain_order = False)`: "This is slower than a default group by.
  Setting this to `True` blocks the possibility to run partitioned" (2.0.0 source; older pages say "on the streaming engine").
  `unique(maintain_order = False)` and `join(maintain_order = "none")` follow the same pattern,
  the latter warning "Do not rely on any observed ordering without explicitly setting this parameter".
  The Polars 2.0 upgrade guide (`docs/source/releases/upgrade/2.md` in
  [pola-rs/polars](https://github.com/pola-rs/polars/blob/main/docs/source/releases/upgrade/2.md))
  makes the streaming engine the default for lazy queries
  and says it "does not guarantee row order for operations that don't require it (`unpivot`, `group_by`, joins, ...)".
  `LazyFrame.map_batches(..., streamable = False)` is the consumer-side declaration:
  with `streamable = True` "the function must produce the same result when it is executed in batches or … on the full dataset".
- **pandas** keeps order by default: `groupby(sort = True)` sorts keys ("Get better performance by turning this off"),
  and "Groupby preserves the order of rows within each group" (`pandas/core/frame.py`).
  The opt-outs are about group-key order only.
- **Ibis** is unordered by design:
  "SQL (and therefore Ibis) makes no guarantees about row order, which is a key assumption that numpy/pandas users are used to"
  ([coming from pandas](https://ibis-project.org/tutorials/coming-from/pandas)), and
  "you cannot 'line up' any two `Column`s" (`docs/concepts/datatypes.qmd`), which is the consistent-permutation point above.
- **Modin** pays for pandas order and says so:
  "Enforcing ordering on a parallel dataframe system like Modin requires non-trivial effort that involves decoupling of the logical and
  physical representation of the data" (`modin_vs_dask_vs_koalas` page, page not fetched).
  Petersohn et al. (PVLDB 13(11), 2020) formalise the ordered dataframe; see the literature note.
- **Dask** has the chunk contract explicitly:
  `dask.dataframe.Aggregation(name, chunk, agg, finalize = None)`
  ("specify what operation to do on each chunk of data, how to combine those chunks of data together, and then how to finalize the result",
  [docs](https://docs.dask.org/en/latest/generated/dask.dataframe.Aggregation.html)),
  `DataFrame.reduction(chunk, aggregate, combine, split_every)` for tree reductions,
  `Bag.foldby(key, binop, initial, combine, combine_initial)`,
  and `map_partitions()` for maps.
  Order exists only through sorted index "divisions".
- **Arrow.**
  Acero's `Ordering::Unordered()` is "a suborder of all other orderings", and `Ordering::Implicit()` marks
  a meaningful order that no column represents (`cpp/src/arrow/compute/ordering.h`).
  `ScanBatchesUnordered` "may allow record batches to be returned out of order. This allows for more efficient scanning"
  (`cpp/src/arrow/dataset/scanner.h`).
  The R package's NEWS for 6.0.0: "Row order of data from a Dataset query is no longer deterministic.
  If you need a stable sort order, you should explicitly `arrange()` the query result."
  `write_dataset(preserve_order = FALSE)` is the default in recent versions.

### Distributed engines: the combine-function contract

- **Spark.**
  `RDD.aggregate(zeroValue)(seqOp, combOp)`: `combOp` is "an associative operator used to combine results from different partitions";
  `fold` warns that
  "For functions that are not commutative, the result may differ from that of a fold applied to a non-distributed collection";
  `treeAggregate` is "semantically identical"; `mapPartitions` maps chunks (`core/src/main/scala/org/apache/spark/rdd/RDD.scala`).
  The typed `Aggregator` has `zero`, `reduce`, `merge`, `finish` and is "based loosely on Aggregator from Algebird".
  `collect_list` is documented as non-deterministic "as the order of collected results depends on the order of the rows,
  which possibly becomes non-deterministic after shuffle operations" (`pyspark/sql/functions/builtin.py`),
  and UDFs carry a `deterministic` flag set by `asNondeterministic()`.
  MLlib computes gradient sums with `treeAggregate` (`GradientDescent.scala`, `LBFGS.scala`),
  and `Summarizer` merges per-partition buffers.
- **sparklyr.**
  `spark_apply(x, f, ..., group_by = NULL)` with
  "`f`: A function that transforms a data frame partition into a data frame"
  ([reference](https://spark.posit.co/packages/sparklyr/latest/reference/spark_apply.html), fetched).
  `sdf_with_sequential_id()` makes position an explicit column via `zipWithIndex`, "independent of partitioning".
- **Apache Beam** states the contract most bluntly.
  "The elements in input PCollection have no guaranteed order"; `CombineFn` has
  `createAccumulator()`, `addInput()`, `mergeAccumulators()`, `extractOutput()`, and
  "Commutativity is required because any order of the input values is ignored when breaking up input values into groups"
  ([programming guide](https://beam.apache.org/documentation/programming-guide/), page not fetched; `Combine.java`).
- **Apache Flink** `AggregateFunction` has `createAccumulator`, `add`, `merge`, `getResult`
  ("Different intermediate aggregates can be merged together"), but states no algebraic laws.
- **Algebird** `Aggregator[A, B, C]` is `prepare`, `semigroup`, `present`; a `Semigroup` need only be associative,
  so `List` concatenation qualifies and order is kept
  ([algebird-core](https://github.com/twitter/algebird/tree/develop/algebird-core/src/main/scala/com/twitter/algebird)).
  `MomentsMonoid` is declared a `CommutativeMonoid`.

### Language libraries: consumer-side declarations

- **Java streams** are the closest analogue of what R would need.
  A `Collector` is `supplier()`, `accumulator()`, `combiner()`, `finisher()`, and it may declare
  `Characteristics.UNORDERED`: "the collection operation does not commit to preserving the encounter order of input elements".
  A source can be de-ordered with `BaseStream.unordered()`,
  and the package documentation says "explicitly de-ordering the stream with unordered() may improve parallel performance
  for some stateful or terminal operations" (`java/util/stream/`, OpenJDK; rendered Javadoc not fetched).
  Here the *consumer* tells the *producer* that order does not matter, through a typed property of the consumer object.
- **C++17** distinguishes `std::accumulate` (left fold) from `std::reduce`, which
  "applies `binary_op` in an unspecified order, which yields a nondeterministic result for non-associative or non-commutative `binary_op`"
  (C++ working draft, [algorithms.tex](https://github.com/cplusplus/draft/blob/main/source/algorithms.tex)).
- **Rust rayon** `reduce`: "`op` should be associative or else the results will be non-deterministic"
  (`src/iter/mod.rs`); rayon keeps element order, so commutativity is not needed.
- **Haskell `foldl`** (Gabriella Gonzalez, [Control.Foldl](https://hackage.haskell.org/package/foldl/docs/Control-Foldl.html)):
  `data Fold a b = forall x. Fold (x -> a -> x) x (x -> b)` — step, initial, extract —
  with an `Applicative` instance so that "derived folds … traverse the container only once".
  The state is hidden, so two partial folds cannot be merged; the monoid form `Fold (i -> m) (m -> o)` used in her 2016
  "Beautiful folds" talk can be ([slides](https://raw.githubusercontent.com/Gabriel439/slides/main/munihac/foldmap.md)).
  The idea goes back to Max Rabkin's "Beautiful folding" (2008), attributed in the Hackage `folds` package
  (the original post could not be opened: **unverified** text).
  The `Applicative` composition is what R lacks most: one pass computing `n`, `mean`, `X'X` and a level union together.
- **Clojure reducers**: `r/fold` takes `reducef` and `combinef`;
  "combinef must be associative … These operations may be performed in parallel, but the results will preserve order"
  (`clojure/core/reducers.clj`; Rich Hickey, [Reducers](https://clojure.org/news/2012/05/08/reducers), 2012).
- **Julia.**
  Transducers.jl `foldxt`:
  "The 'bottom' reduction function … must be associative and `init` must be its identity element" (`src/reduce.jl`).
  OnlineStats.jl separates `fit!` (consume a chunk) from `merge!` (combine two states):
  "Not every `OnlineStat` can be merged. In these cases, OnlineStats either uses an approximation or provides a warning",
  and `OnlineStatsBase` exposes `is_mergeable` (`docs/src/bigdata.md`; Day & Zhou, JOSS 5(46):1816, 2020,
  <https://doi.org/10.21105/joss.01816>).
  Tables.jl has `Tables.partitions(x)`, which by default treats "a single input as a single, non-partitioned table",
  so any consumer can ask any table for its chunks (`src/Tables.jl`).
  Julia's `Base.IteratorSize` and `Base.IteratorEltype` traits show how a property of a source can be declared and dispatched on
  ([interfaces manual](https://docs.julialang.org/en/v1/manual/interfaces/), page not fetched).
- **Guy Steele**, "Organizing Functional Code for Parallel Execution; or, foldl and foldr Considered Slightly Harmful",
  ICFP 2009 invited talk, <https://doi.org/10.1145/1596550.1596551> (DOI search-verified; slides not found).
  The argument — write reductions over associative conc-trees rather than sequential lists — is the same one,
  but no quote about Fortress reducers could be verified.
- **Formal statements.**
  Yu, Gunda and Isard (SOSP 2009, <https://doi.org/10.1145/1629575.1629600>, PDF read from Microsoft Research):
  "A function H is decomposable if there exist two functions I and C … H(x1 ⊕ x2) = C(I(x1 ⊕ x2)) = C(I(x1) ⊕ I(x2))",
  with I and C commutative, and "associative-decomposable" if C is also associative.
  Dean and Ghemawat's MapReduce combiner (OSDI 2004, §4.3), Lin's "Monoidify!" (arXiv:1304.7544),
  Gray et al.'s distributive/algebraic/holistic aggregates and Agarwal et al.'s mergeable summaries are in the literature note.
  Bismarck (Feng, Kumar, Recht, Ré, SIGMOD 2012, <https://doi.org/10.1145/2213836.2213874>) is the counterpoint:
  incremental gradient descent fits the user-defined-aggregate shape but is order-*sensitive*, which is why it shuffles the data
  (the "shuffle once" wording is from secondary sources, **unverified** in the paper).

**Pattern.**
Every system that streams or parallelises gets there by the same two moves.
The *consumer* is an object with a known shape — init, update, merge, finalize — and declared properties
(associative, commutative, parallel safe, unordered, deterministic).
The *order requirement*, when there is one, is an explicit argument (`ORDER BY` inside the aggregate, `maintain_order`, `.inorder`).
R has neither move as a general protocol, only in individual packages.

## 3. What R already has

### Producers and their order switches

- **duckplyr** (1.2.1).
  Results are lazy; "accessing column data or retrieving the number of rows will trigger a computation" (prudence vignette).
  Prudence (`"lavish"`, `"thrifty"`, `"stingy"`) controls *whether* touching materialises.
  Order: "DuckDB does not guarantee order stability for the output.
  For performance reasons, duckplyr does not enable output order stability by default" (`vignette("limits")`),
  and `DUCKPLYR_OUTPUT_ORDER=TRUE` restores it,
  at the price of "more complicated execution plans with less potential for optimization" (`?config`).
  There is no per-consumer or per-frame switch: the setting is a global environment variable read when verbs build the plan.
  The word ALTREP appears in the duckdb NEWS, not in duckplyr's documentation.
- **duckdb** offers chunked fetching: `dbFetch(res, n =)`, `duckdb_fetch_record_batch(res, chunk_size =)`,
  and `to_arrow_stream()` returning an Arrow `RecordBatchReader`.
- **arrow**: `map_batches(X, FUN, ..., .schema, .lazy = TRUE)` lets R code
  "operate on chunks of data without having to hold the entire Dataset in memory at once";
  it is "experimental and not recommended for production use. It is also single-threaded", and says nothing about batch order.
- **dbplyr** makes order explicit and warns: a window function without order
  "does not have explicit order", use "`arrange()`, `window_order()`, or `.order`" (see the literature note).
  It is the only R producer that *checks* a consumer-side order requirement, but only for window functions it translates itself.

### Consumers and drivers that accept chunks or declare order-freeness

- **`foreach(.combine, .inorder = TRUE, .multicombine = FALSE)`** — the clearest R precedent of a consumer declaring order-freeness:
  "`.inorder`: logical flag indicating whether the `.combine` function requires the task results to be combined in the same order
  that they were submitted. If the order is not important, then it setting `.inorder` to `FALSE` can give improved performance"
  (typo in the original; [foreach](https://CRAN.R-project.org/package=foreach)).
- **`iotools::chunk.apply(input, FUN, ..., CH.MERGE = rbind, CH.PARALLEL = 1L, CH.SEQUENTIAL = TRUE, CH.BINARY = FALSE)`**:
  "If `FALSE` then the chunks may be processed in any order to gain better performance";
  `CH.BINARY = TRUE` turns `CH.MERGE` into a binary fold
  (Arnold, Kane and Urbanek, "iotools: High-Performance I/O Tools for R", *The R Journal* 9(1):6–13, 2017,
  <https://doi.org/10.32614/RJ-2017-001>).
- **biglm**: `bigglm(formula, data = function(reset))`:
  "The chunks need not be the same size or in the same order when the data are reread, but the same data must be provided in total";
  and "The model formula must not contain any data-dependent terms … the levels of the factor must be the same across all data chunks".
  The contract is right; it is not enforced (the earlier catalogue reproduced silent errors with `poly()` and differing level sets).
- **speedglm** `shglm(formula, datafun, ..., all.levels = FALSE)` ("does not impose restrictions on factors"),
  **fastglm** `fastglm_streaming(chunk_callback, n_chunks, family, ...)` ("never holds more than a single chunk in memory at once,
  plus a `p x p` accumulator"; the callback is indexed `chunk_callback(k)`),
  **mgcv** `bam(chunk.size =)` and `bam.update()` ("there may be small numerical differences in fit").
- **readr** `read_csv_chunked(file, callback, chunk_size)`, with `DataFrameCallback`, `SideEffectChunkCallback`
  and `AccumulateCallback$new(f, acc)`, where `f(x, pos, acc)` — a sequential fold with an explicit row offset `pos`.
  **LaF** `process_blocks(x, fun)` is a fold as well; `fun` receives the block and "the output of the previous call".
- **chunked** (`read_chunkwise()`): dplyr verbs per chunk;
  "`summarize` and `group_by` are implemented but generate a warning:
  they operate on each chunk and **not** on the whole data set" (README).
- **disk.frame** (archived on 2026-01-30) had two-stage group-by:
  `median_df.chunk_agg.disk.frame()` and `median_df.collected_agg.disk.frame()` per summary,
  and its README states the holistic limit: "function that depend on the order a column can only be obtained using estimated methods",
  marking median, quantile and IQR as estimates.
- **ff** `chunk()`, `ffapply(..., CFUN =)`; **bigstatsr** `big_apply(X, a.FUN, a.combine, block.size)`;
  `ffbase` and `bigtabulate` are archived.
- **tdigest** `td_create()`, `td_add()`, `td_merge(from, into)`, `td_value_at()` — a mergeable quantile sketch.
- **Parallel drivers return results in order.**
  `parallel::mclapply()`, `parLapplyLB()`, `future.apply::future_lapply()` and `furrr` all return a list aligned with the input
  (`future.apply` documents that its `ordering` attribute "only affects the processing order and _not_ the order values are returned").
  They therefore never *need* order-free consumers, and they never exploit them either.
- **Sufficient-statistic front ends** — `princomp(covmat =)`, `factanal(covmat =)`, `lavaan(sample.cov =)`,
  table-based tests and `stats::free1way()` (R-devel, `src/library/stats/R/free1way.R`) —
  accept the merged state of a reducer directly; they are "finalize" functions waiting for a protocol.

### Grouping, keys and presentation order

- **data.table** separates physical order from logical access:
  `setkey()` "reorders (i.e. sorts) the rows", `setindex()` stores an order "and the dataset retains the original order of rows in memory";
  `by` keeps "the order of the groups" (first appearance) while `keyby` sorts.
  GForce optimises `j` expressions built only from
  `min, max, mean, median, var, sd, sum, prod, first, last, head, tail` (`?datatable.optimize`) —
  a hard-coded registry of reducers, which includes order-dependent ones (`first`, `head`).
- **dplyr**: `group_by()` sorts keys in the C locale "for performance and reproducibility across R sessions",
  while `.by` results "maintain the ordering of the existing data" (`?dplyr_by`).
  **vctrs** `vec_unique()` returns values in first-appearance order; `vec_proxy_order()` is a per-class hook for ordering semantics.
- **collapse** `GRP(sort = FALSE)` groups by first appearance, which "often provides a performance gain";
  it has no API for combining partial results.
  **matrixStats** has none either.
- **Base R** documents order only occasionally:
  `merge(sort = FALSE)` gives rows "in an unspecified order" (`merge.Rd`), and `sort_by()` (R 4.4.0) makes sorting explicit.
  No help page in base, stats or parallel mentions associativity (`grep -i associativ` over the Rd files),
  so `Reduce()`, `aggregate()` and `tapply()` make no promise about how `FUN` may be split.

**Summary of the R position.**
R has several consumer-side declarations (`.inorder`, `CH.SEQUENTIAL`, biglm's data function, readr's chunk callbacks),
but each is private to its package and none reaches a producer such as duckplyr.
Producers expose only global switches (`DUCKPLYR_OUTPUT_ORDER`, `options(arrow.summarise.sort)`), never per-consumer ones.

## 4. The spectrum of approaches

Each approach is described by how consumer code looks, what it guarantees, how it fails,
what it costs users and package authors, how it meets duckplyr's lazy materialisation, and which goal it serves.

### 4.1 Documentation only

Help pages gain a "Row order" section stating the function's order class and chunk class,
generated from the earlier catalogue for base R and the recommended packages.

```r
#' @section Row order:
#' The result depends only on the multiset of rows (order class I).
#' It can be computed from chunks via the cross-products X'X, X'y (chunk class A).
```

- **Guarantee:** none; it informs users who then set the producer's switch themselves.
- **Failure:** silent. A user who misreads a page, or a page that is wrong, gives a wrong answer with no warning.
  The catalogue found many functions whose order dependence is invisible from the documentation
  (`gee` clusters by contiguous runs, `aggregate()` merges keys that print the same, `kmeans()` Hartigan–Wong).
- **Cost:** low for authors, and the information already exists for about 1,200 functions.
- **duckplyr:** none directly; it supports a user decision such as `Sys.setenv(DUCKPLYR_OUTPUT_ORDER = "FALSE")`.
- **Goals:** (a) only, and only by informing.

Documentation is also where the subtle classes belong.
`S` functions (first-appearance labels) are order-free *up to presentation*, and a page should say which part of the output is affected,
for example "`by =` returns groups in order of first appearance; use `keyby =` for sorted groups".

### 4.2 A boundary declaration by the user

The user declares at the producer boundary that the downstream consumer does not need order.
In duckplyr the natural place is a verb or a `collect()` argument that applies to *this* frame, not a global environment variable.

```r
# hypothetical API
fit <- flights |>
  filter(!is.na(arr_delay)) |>
  unordered() |>                        # marks the lazy frame; nothing is executed yet
  lm(arr_delay ~ distance + carrier, data = _)
```

A local experiment confirms the mechanics are available today:
on a duckplyr frame with `prudence = "stingy"`, setting an attribute and prepending a class does not materialise it,
and both survive a later `mutate()` (`class(q2 |> mutate(z = 1))` begins with the added class).
So duckplyr can read such a mark when the first column is touched and choose the cheaper plan;
the order decision would move from "when the verb builds the plan" to "when the plan is executed".

- **Guarantee:** none beyond the user's judgement; a stronger version shuffles deliberately in development (section 4.7).
- **Failure:** silent if the consumer is in fact order-dependent.
  The mark can also leak further than intended: the materialised frame keeps its order-free plan,
  and a later `head(df)` or `df$x[1]` in the same script sees an arbitrary row.
  A conservative design would therefore drop the mark when the frame is returned to the user's workspace,
  or materialise into an ordinary `data.frame` with a stored row-number column that `arrange()` can restore.
- **Consistent permutation:** the mark must promise one permutation for all columns.
  A producer that executes the query more than once, for example once per column, must re-use one execution or be deterministic
  (whether duckplyr materialises all columns from one execution was not checked here).
- **Cost:** one call for users; small for producers.
- **Precedents:** Java's `BaseStream.unordered()`, XQuery's `unordered { }` (literature note), `foreach(.inorder = FALSE)`.
- **Goals:** (a). It does nothing for (b).

### 4.3 Annotation: a registry of consumer properties

Functions carry machine-readable properties that producers, wrappers, linters and tests can read.
There are three places to put them, in increasing order of robustness.

- **An attribute on the closure** — trivially possible (`attr(f, "row_order") <- "invariant"` works and survives),
  but lost by wrappers, `Recall`, byte-compilation of a new closure and `trace()`.
- **A roxygen tag** such as `@rowOrder invariant` and `@chunk A`, parsed by a `roxy_tag_parse()` method
  and rendered by `roxy_tag_rd()` ("Extending roxygen2" vignette), and also written to a package-level table
  (for example `inst/row-order.dcf`) at document time.
- **A central registry**, analogous to PostgreSQL's catalogue of aggregate properties or DuckDB's per-aggregate order sensitivity:

```r
row_order_register("stats::lm",     order = "I", chunk = "A", args = list(data = "rows", subset = "rows"))
row_order_register("stats::table",  order = "I", chunk = "K")
row_order_register("stats::kmeans", order = "D", when = quote(algorithm != "Lloyd"))
row_order_register("base::unique",  order = "S")
row_order_class(quote(lm(y ~ poly(x, 2), data = d)))
#> order "I", chunk "P" (poly() needs a pre-pass for its coefficients)
```

The registry would be seeded from the earlier catalogue's 1,223 entries.

- **Guarantee:** only as good as the annotations.
  The classes are *conditional* in practice: `lm()` is `I` unless `subset` is an integer vector or the formula contains `lag()`;
  `aggregate()` is `I` only if `FUN` is; `kmeans()` is order-free only for `algorithm = "Lloyd"` and a key-derived start.
  The registry needs argument-level conditions and a way to say "depends on this callback".
- **Failure:** stale or wrong entries are silent, so annotations must be backed by tests (section 4.7).
- **Cost:** a community protocol; each package maintains its entries.
- **duckplyr:** a registry is useless to duckplyr on its own, because duckplyr does not see the call.
  It becomes useful through a wrapper (section 4.5) or static analysis (section 4.6), which do see the call.
- **Goals:** (a), and for (b) it records which functions *could* consume chunks, not how.

### 4.4 Types and classes

#### An "unordered frame" class that forbids positional operations

```r
unordered <- function(df) structure(df, class = c("unordered_df", class(df)))
`[.unordered_df` <- function(x, i, j, ..., drop = TRUE) {
  if (!missing(i) && is.numeric(i)) stop("positional row index on an unordered frame")
  NextMethod()
}
head.unordered_df <- function(x, ...) stop("head() on an unordered frame")
Math.unordered_df <- function(x, ...)
  if (.Generic %in% c("cumsum", "cumprod", "cummax", "cummin")) stop(.Generic, "() on an unordered frame") else NextMethod()
```

An experiment with exactly this class (R 4.5.3) shows what such a type can and cannot do.

- **It works with the order-free consumers:**
  `lm()` (also with `na.omit`, `na.exclude`, a logical `subset`), `glm()`, `predict(newdata =)`, `t.test()`, `table()`, `xtabs()`,
  `quantile()`, `aggregate()`, `tapply()`, `merge()`, `unique()`, `rbind()`, `transform()`, `reshape()`, `plot()`.
- **It catches** `head(u)`, `u[1:3, ]` and `cumsum(u["y"])`.
- **It blocks legitimate code** (false positives): `u[order(u$x), ]`, `sort_by(u, ~x)`, `split(u, u$g)` and `by(u, u$g, f)`,
  because these use integer indices internally for order-free purposes.
- **It leaks** (false negatives), and this is the decisive problem:
  `u$y` and `u[["y"]]` return a plain vector, so `cumsum(u$y)`, `u$y[1]`, `diff(u$x)` and `ave(u$y, u$g, FUN = cumsum)` pass unchecked.
  `model.frame()` builds its frame in C, so even `lm(subset = 1:10)` bypasses `[.unordered_df`,
  and the model frame inside the fit is a plain `data.frame`.

A row-order type would have to live on the *columns* (a vctrs class, or an ALTREP wrapper whose `Elt` method refuses positional access),
and then every base function that calls `x[i]` internally for order-free reasons (sorting, tabulating, splitting) would need a method.
That is the "patch every function" end of the spectrum in disguise.
The class is useful as a development-time tripwire, not as a guarantee.

- **duckplyr:** a class on the lazy frame is a boundary declaration (4.2) with some checking attached;
  it can be read before materialisation.
- **Goals:** (a).

#### A chunk-source type that consumers dispatch on

For goal (b) the type that matters is not a data frame but a *source of chunks*.
`bigglm(data = function(reset))`, `fastglm_streaming(chunk_callback, n_chunks)`, readr callbacks, `RecordBatchReader$read_next_batch()`,
`duckdb_fetch_record_batch()`, `iotools::chunk.reader()` and `ff::chunk()` are seven incompatible spellings of the same thing.
A common type with a reset (for multi-pass consumers), optional partitioning (for parallel streams) and a schema
would let consumers dispatch on it, as Julia consumers call `Tables.partitions()`:

```r
# hypothetical generics
chunks <- function(x, ...) UseMethod("chunks")       # returns a chunk source
chunks.data.frame   <- function(x, size = 1e5, ...) ...
chunks.duckplyr_df  <- function(x, size = 1e5, ...) ...   # via duckdb_fetch_record_batch()
chunks.ArrowTabular <- function(x, ...) ...                # via as_record_batch_reader()
src <- chunks(flights |> filter(!is.na(arr_delay)))
src$schema; src$reset(); while (!is.null(ch <- src$next_chunk())) ...
src$partitions()   # independent sub-sources for parallel consumers, if the producer can provide them
```

- **Guarantee:** the consumer never sees more than a chunk, so it cannot accidentally depend on global position.
  It can still depend on the order of chunks or of rows within a chunk; that is what the reducer contract below rules out.
- **duckplyr:** the producer now *knows* the consumer is chunk-wise because it is asked for chunks, not for a data frame,
  and can run with `preserve_insertion_order = false` and stream.
  This is the one place where duckplyr's knowledge problem disappears completely.
- **Goals:** (b), and therefore (a) whenever the consumer's merge is commutative.

### 4.5 Shims and wrappers

#### A scope wrapper

```r
with_unordered(d, lm(y ~ x + g, data = d))
```

The wrapper sees the call before evaluating it, so it can consult the registry (4.3) and the static analysis (4.6),
decide whether the call is order-free, and only then mark the frame for the producer.
In development it can also run the call twice, on the producer's order and on a shuffled copy, and compare (4.7).

- **Guarantee:** as good as the registry plus the analysis; with the double run, an empirical check on this data.
- **Failure:** any consumer not in the registry is treated as order-dependent, so the wrapper degrades to the safe default.
- **duckplyr:** this is the cleanest route for goal (a): the wrapper is the one party that sees both the call and the lazy frame.
- **Cost:** low for users; no change to consumer packages.

#### Methods for a new class, and masking

For goal (b), consumers have to be *re-implemented* for chunks.
Where the consumer is an S3 generic, a shim package can add methods for the chunk-source class:
`summary()`, `quantile()` (with a sketch, marked approximate), `table()`, `xtabs()`, `predict()` (a map), `nrow()`.
Many key consumers are not generic: `lm()`, `glm()`, `cov()`, `cor()` and `tapply()` are plain functions,
and `aggregate()` dispatches on `x` but then calls `split()`.
For these the shim must either export same-named functions that mask base ones (`chunkr::lm()`)
or dispatch on `data` inside a wrapper.
Masking is legitimate in a package namespace; changing someone else's namespace is not:
the CRAN Repository Policy says "A package must not tamper with the code already loaded into R"
and "Altering the namespace of another package should only be done with the agreement of the maintainer of that package"
([policies](https://cran.r-project.org/web/packages/policies.html), fetched).

```r
lm_chunked <- function(formula, data, ...) {         # data: a chunk source
  spec <- model_spec(formula, data)                   # pass 1: factor levels, poly() coefficients, knots
  fold(data, xtx_reducer(spec)) |> lm_from_xtx(spec)  # pass 2: one A-class reducer
}
```

- **Guarantee:** exactness where the reducer is exact; the shim knows which functions it implements.
- **Failure:** silently different results whenever the shim's model frame differs from base R's
  (the biglm and speedglm traps); every shim must be tested against the in-memory function.
- **Cost:** high and ongoing for the shim author; zero for consumer packages, which is both its appeal and its fragility.
- **Precedents:** biglm, speedglm, disk.frame's `*_df.chunk_agg`/`*_df.collected_agg` pairs, chunked's dplyr methods.

#### Interception with `trace()` or mocking

`trace("head", tracer = ...)`, `trace(..., where = asNamespace("utils"))` and `testthat::local_mocked_bindings()` all work
for intercepting order-dependent calls during a test.
A tracer on a primitive such as `cumsum()` fires but cannot see its arguments.
Interception is fine for dynamic checking in tests and development mode; it must not ship in package code (CRAN policy above).

### 4.6 Static analysis

A linter or a call-graph walk flags order-dependent calls in consumer code.

```r
order_linter <- lintr::make_linter_from_xpath(
  "//SYMBOL_FUNCTION_CALL[text()='head' or text()='tail' or text()='cumsum' or text()='diff']",
  lint_message = "Row-order-dependent call; make the order explicit."
)
lintr::lint(text = "f <- function(d) { x <- head(d, 3); cumsum(d$y) + sum(d$y); diff(x$z) }\n", linters = order_linter())
#> three lints: head, cumsum, diff; sum is not flagged   (lintr 3.4.0)
```

`codetools::findGlobals(f, merge = FALSE)$functions` lists the functions a consumer calls,
so a registry lookup can propagate order classes up a call graph:
a function is `I` if every call that receives the data is `I` or `E` and the result is reduced by an `I` function.

- **Guarantee:** none in general, but a useful first filter.
- **Failure** (each shown by the codetools experiment): `do.call("head", ...)` hides the call;
  inside `with(d, diff(z))` the column `z` is reported as a global variable; dispatch is invisible (`head`, not `head.data.frame`);
  callees are not entered; compiled code is opaque.
  It cannot tell whether the data were sorted on the line before (`d <- d[order(d$t), ]; cumsum(d$y)` is fine).
  And many dependences are not calls at all but defaults: `kmeans()` without `algorithm = "Lloyd"`,
  `nlme::corAR1()` without `form = ~ t | g`, `sandwich::vcovHAC()` without `order.by`.
  A linter needs argument-level rules for these, which is where the registry's conditions come in.
- **Cost:** low; lintr has no order-related linter today (`sort_linter` concerns `order()`/`sort()` idioms only).
- **duckplyr:** none at run time; useful for authors and in CI.
- **Goals:** (a) mainly; for (b) it can flag holistic calls (`median()`, `rank()`) as "needs all rows".

### 4.7 Dynamic checking

#### Metamorphic tests

Permuting rows is a metamorphic relation, and re-chunking is another.
A helper checks both, with an equivalence chosen per order class.

```r
expect_row_order_invariant <- function(f, df, reps = 5, compare = all.equal) {
  ref <- f(df)
  for (r in seq_len(reps)) {
    p <- df[sample(nrow(df)), , drop = FALSE]; rownames(p) <- NULL
    stopifnot(isTRUE(compare(ref, f(p))))
  }
}
```

An experiment over 5 permutations of a 60-row frame:
`coef(lm())`, `table()`, `quantile()`, `aggregate(y ~ g, FUN = mean)` and `levels(factor())` agreed 5/5;
`aggregate(y ~ g, FUN = function(v) v[1])` 0/5, `kmeans()` centres with a fixed seed 0/5 (5/5 after sorting the centres),
`head()` 0/5, `unique()` 1/5.
`lm()` coefficients agreed with `all.equal()` but not with `tolerance = 0`, so the comparison must allow rounding.
And `tail(cumsum(y), 1)` passed: an order-dependent intermediate with an order-free final summary is invisible to this test, correctly so.

- **Relations by order class** (from the literature note's section 6):
  `I` — equal up to tolerance; `E` — the output is permuted the same way; `S` — equal after sorting by key or canonicalising labels;
  `R` — equal in distribution, or equal with row-keyed random numbers (section 5.3).
  For chunk classes: the merged result over any chunking equals the one-chunk result, and the merge is commutative and associative
  (check `merge(a, b) == merge(b, a)` and both bracketings).
- **Tools:** hedgehog's `gen.sample()` shrinks a permutation "towards the original list order";
  quickcheck has `any_data_frame()`; testthat has `expect_setequal()` and `expect_mapequal()` but no permutation helper.
  No CRAN package for metamorphic testing exists (the only "metamorphic" hit on CRAN is about rocks).
- **Guarantee:** empirical, for the data and seeds tried; catches every dependence that the test data exercise.
- **Cost:** low per function; this is the cheapest way to make annotations trustworthy.

#### Adversarial producers

The producer itself can perturb order in development, as SQLite's `reverse_unordered_selects` does:
a duckplyr option that shuffles every unordered result, or an arrow scan with deliberately out-of-order batches,
makes order-dependent consumers fail loudly in tests instead of silently in production.
dplyr's deprecation of `all_equal(ignore_row_order = TRUE)` ("too easy to ignore important differences") is a reminder
that the *comparison* must stay order-aware for `D` and `S` functions; it is the *input* that gets shuffled.

### 4.8 Patching each function

At the far end, every order-dependent function gets an explicit order argument,
and every order-free function gets a chunk-aware path.

- Explicit order where position is used silently: `gee(..., waves =)`, `nlme::corAR1(form = ~ t | g)`,
  `sandwich::vcovHAC(order.by =)`, `kmeans(algorithm = "Lloyd")` with keyed starts, `aggregate()` warning on keys that print the same.
  The earlier report's rule — make the order an explicit input — is the fix in every case, and dbplyr's warning
  ("does not have explicit order") is the model for what a function should say when the input is not sorted and no order is given.
- Chunk-aware paths: `lm()` and `glm()` accepting a chunk source; `xtabs()` objects adding by label; `quantile()` from a value-count table.
- **Guarantee:** the strongest, function by function.
- **Cost:** enormous across ~1,200 functions and hundreds of maintainers, and it does not compose:
  a user function calling five patched consumers is still unannotated.
  Patching pays only for the shared infrastructure (section 5) and for the handful of traps that silently give wrong answers.

## 5. The hard cases

### 5.1 Global information first: levels, knots, ranges, types

Factor level sets, `poly()` coefficients, spline knots, `scale()` centres, histogram breaks and column types
must be the same for every chunk, and none of the existing chunked fitters provides a pre-pass.
The fix is a *two-phase consumer*: phase 1 is itself a reducer that computes the global information, phase 2 uses it frozen.

```r
model_spec <- function(formula, src) {
  lev <- fold(src, reducer(
    init     = function() list(),
    update   = function(s, ch) lapply(Filter(function(v) is.character(v) || is.factor(v), ch), function(v) unique(as.character(v))),
    merge    = function(a, b) { for (n in union(names(a), names(b))) a[[n]] <- union(a[[n]], b[[n]]); a },
    finalize = function(s) lapply(s, sort)
  ))
  list(terms = terms(formula), xlev = lev)   # predvars for poly()/ns() would be frozen here as well
}
```

A prototype of this (a `reducer()` constructor, a chunk source in the style of `bigglm(data = function(reset))`,
a label-aligned table merge and an `X'X`/`X'y` reducer) reproduced `coef(lm(y ~ x + g))` with `all.equal()`
on 7 shuffled chunks, and `model.matrix(y ~ g, chunk, xlev = levels)` gives all columns even when a chunk lacks a level.
Base R already has the pieces: `xlev` in `model.frame()`, `.getXlevels()`, and `predvars` captured by `makepredictcall()`
(`attr(terms(model.frame(y ~ poly(x, 2), d)), "predvars")` stores the full-data `alpha` and `norm2`).
What is missing is a pre-pass that computes them from chunks and a fitter that refuses a formula with an unfrozen data-dependent term.

Which pre-passes are cheap:

- **Level sets** are a keyed union (`K`); the producer often knows them already (a DuckDB `ENUM`, an Arrow dictionary,
  `SELECT DISTINCT`), so a producer-provided schema can skip the pass.
  Level *order* must not come from first appearance: sort, or take the producer's declared order.
- **`poly()`, `scale()`, ranges, `hist()` breaks** come from power sums, min and max (`A`).
- **Spline knots at quantiles** are holistic; options are user-given knots, approximate quantiles from a sketch,
  or exact quantiles pushed down to the producer (5.2).
- **Types**: `type.convert()` per chunk is lossy; the producer's schema should be authoritative, or a mergeable "can still be integer" mask.

Whole-column expressions inside formulas or `subset()` (`I(x - mean(x))`, `x > mean(x)`) silently become chunk-local.
A chunked consumer must evaluate such expressions in phase 1 or reject them; static analysis (4.6) can find them in the formula.

### 5.2 Holistic functions: exact quantiles, ranks, distances

These are order-free, so goal (a) is easy; goal (b) is the problem.
Four escapes, in order of preference:

- **Push the holistic step to the producer.**
  DuckDB computes exact `quantile_cont()`/`percentile_cont() WITHIN GROUP (ORDER BY x)` and ranks itself.
  An R consumer that needs `median(x)` should ask the producer for it rather than for `x`;
  duckplyr already translates `summarise(median(x))`.
  A protocol for consumers would expose this as a "finalize needs these producer-side aggregates" step.
- **Use a value-count table** when distinct values are few: it is a keyed reducer (`K`), and the earlier catalogue shows that
  all nine `quantile()` types, `wilcox.test()`, `kruskal.test()`, Spearman's rho and `ecdf()` are exact from it.
- **Use a mergeable sketch** (t-digest via `tdigest::td_merge()`, KLL) and mark the result approximate,
  as disk.frame did ("Estimate" for median, quantile, IQR).
  Sketches keep their error bounds under any order, but their exact contents depend on insertion and merge order,
  so they are `I` only up to the error bound — a metamorphic test must use the bound as tolerance.
- **Sort first, then stream**: a producer-side `ORDER BY x` turns quantiles and ranks into a one-pass scan.
  This re-introduces order, but as an explicit, declared requirement of this one consumer — the SQL `WITHIN GROUP` design.

Distance-based methods (`dist()`, `hclust()`, k-nearest neighbours) remain holistic;
chunking over *prediction* rows is the only exact option.

### 5.3 Invariant only in distribution: seeded resampling

Bootstrap, cross-validation folds, random starts and subsamples draw random numbers indexed by row position,
so the same seed gives a different result after reordering, although the distribution is unchanged.
Two remedies:

- **Accept `R` as order-free** for goal (a), with documentation that results are reproducible only in distribution
  under an unordered producer.
  This is honest but breaks the reproducibility users expect from `set.seed()`.
- **Key the randomness on the row, not the position.**
  Derive each row's fold, bootstrap weight or subsample membership from a hash of a stable row key and the seed,
  for example a Poisson bootstrap weight `qpois(u, 1)` per row and replicate,
  where `u` is a uniform derived from hashing (key, seed, replicate).
  The result is then exactly order-invariant *and* chunkable, because each row's draws are local.
  The cost is that the data need a stable key (or the producer must supply one, as `sdf_with_sequential_id()` does in Spark,
  which re-introduces an order),
  and that per-row hashing changes the stream of random numbers compared with today's `sample()`, so results differ from current R.

`chisq.test(simulate.p.value = TRUE)` shows that some `R`-looking functions are in fact `I`, because they draw from margins, not rows;
the registry should record this distinction.

### 5.4 Presentation-only order: first-appearance labels

`unique()`, `data.table` `by =`, dplyr `.by`, `rbind()` factor levels, `split()` within-group order, `cutree()` labels and
`nlme::varIdent()`'s reference stratum give the same *set* of results in a different arrangement.

- For goal (a) the consumer can **canonicalise**: sort group keys (`keyby =`, `group_by()`), sort factor levels, relabel clusters
  by a canonical rule (as sorting `kmeans()` centres made the experiment agree 5/5).
- Where the presentation affects *values* — the reference level of a contrast, `varIdent()`'s reference stratum,
  `rbind()`'s level order feeding a model matrix — the canonical order must be fixed before fitting,
  which is again global information (5.1).
- For goal (b), merges must align by label, never by position:
  the earlier catalogue verified that adding two `xtabs()` results with `+` silently puts counts under the wrong level.
  The prototype's table merge aligns by `names()` and is exact.

### 5.5 Numerical artefacts

Floating-point sums differ in the last bits between orders and chunkings.
Tests compare with tolerance.
Where bitwise reproducibility matters, a reproducible summation (Demmel and Nguyen, in the literature note) is needed.
Integer overflow that depends on order (`rowsum()` on integers) is a bug, and should be fixed in base R rather than worked around.

## 6. How each approach meets duckplyr's lazy materialisation

- Touching a column triggers execution, with the order behaviour that was fixed when the plan was built.
- **Documentation and annotation alone** do not reach duckplyr: it never learns which function touched the column.
- **A boundary mark** (4.2, 4.4) is readable before materialisation, and the experiment shows it survives verbs without executing anything.
  duckplyr would need to defer the order decision from plan construction to execution, which is possible because the plan is lazy.
- **A wrapper** (4.5) sees both the call and the frame and can set the mark only for consumers the registry calls order-free.
- **Stingy prudence** turns every touch into a catchable error (`tryCatch(sum(q$x), error = ...)` catches
  "Materialization is disabled, use `collect()` or `as_tibble()` to materialize"),
  so a wrapper can also *discover* whether an expression touches data at all before deciding.
- **A chunk source** (4.4) bypasses ALTREP: the consumer asks for chunks, duckplyr streams record batches,
  and the producer knows by construction that it may drop order — provided the consumer's merge is commutative,
  which the reducer type can declare (as Java's `Collector.Characteristics.UNORDERED` does).
- **Consistent permutation**: whatever the route, all columns of a frame must come from one execution,
  or the execution must be deterministic.
  This has to become an explicit part of the producer contract once order is dropped.
- **Leakage**: once materialised without order, the frame is an ordinary-looking data frame.
  Later `head()` or positional code sees arbitrary rows.
  Keeping the mark on the result (and checking it in `head()` and `[`, as the tripwire class does) limits the damage.

## 7. Recommendation: a layered plan

### Layer 1: cheap and immediately useful (one package, no coordination)

- **Publish the catalogue as data**: order class, chunk class and conditions for the ~1,200 functions,
  as a table in a small package, queryable by `row_order_class("stats::lm")`.
- **A testing helper**: `expect_row_order_invariant()` and `expect_chunk_invariant()` with relations chosen by order class,
  built on hedgehog permutations, so package authors can check their own functions and the registry can be validated.
- **A lintr linter** for the order-dependent calls and defaults the catalogue lists (`head()`, `cumsum()`, `diff()`, `[1]`,
  `kmeans()` without `algorithm = "Lloyd"`, `vcovHAC()` without `order.by`, `corAR1()` without `form`).
- **In duckplyr**: a per-frame `unordered()` mark (or a `collect(order = FALSE)` argument)
  instead of only the global `DUCKPLYR_OUTPUT_ORDER`, and a development option that shuffles unordered results,
  in the spirit of SQLite's `reverse_unordered_selects`.
- **A `with_unordered()` wrapper** that consults the registry, sets the mark only when the consumer is known to be order-free,
  and in development re-runs on a shuffled copy and compares.

These serve goal (a).
The decision stays with the user, but it becomes an informed and checked decision.

### Layer 2: a community protocol (several packages agree)

- **A reducer protocol**: `reducer(init, update, merge, finalize)` with declared properties
  (`commutative`, `exact` versus approximate with an error bound),
  and `Applicative`-style composition so one pass computes several reducers (the Haskell `foldl` idea, with a merge added).
  Implementations for moments, `X'X`/`X'y`, keyed counts with label-aligned merge, min/max/range, level unions,
  value-count tables and t-digest.
- **A chunk-source protocol**: one generic with schema, `next_chunk()`, `reset()` and optional `partitions()`,
  implemented by duckplyr/duckdb, arrow, DBI result sets, readr and in-memory data frames.
  It replaces the seven incompatible spellings listed in 4.4 and lets duckplyr stream without order.
- **A two-phase model-frame helper**: a pre-pass reducer that freezes levels, `predvars` and types,
  and a check that rejects formulas with unfrozen data-dependent terms.
  biglm, speedglm, fastglm and mgcv's `bam()` could adopt it and stop falling into the traps the catalogue reproduced.
- **Roxygen tags** (`@rowOrder`, `@chunk`) that write the package's entries into the shared registry.
- **Key-derived random numbers** as a small utility (`row_runif(key, seed)`), so resampling consumers can become exactly order-free.

These serve goal (b) and make goal (a) checkable rather than trusted.

### Layer 3: changes in base R

- **`model.frame()` / `model.matrix()`**: accept a frozen specification (levels, `predvars`) from a pre-pass as a first-class object,
  and offer an error instead of a silent per-chunk basis when a data-dependent term is not frozen.
- **Label-aligned merging** for tables: `xtabs`/`table` addition that aligns `dimnames`, or a documented `merge` method.
- **Order-independent combining**: an option for `rbind()` (and `factor()`) to build levels in sorted rather than first-appearance order.
- **Fix the order bugs** that are plainly bugs: integer `rowsum()` overflow depending on order, `aggregate()` merging keys that print alike.
- **Help-page sections** on row order for the functions whose dependence is hidden (`kmeans()`, `merge()`, `aggregate()`, `unique()`),
  and, longer term, a convention in *Writing R Extensions* for declaring it.
- **Mergeable summaries in stats**: `quantile()` and `ecdf()` from weighted value tables, and a merge for `ecdf` objects.

### What not to do

- Do not rely on an unordered data-frame class as a guarantee: `$` and `[[` strip it and `model.frame()` bypasses it.
- Do not patch base or other packages' namespaces at run time outside tests.
- Do not make comparisons order-insensitive globally; shuffle the input and keep the comparison strict for `D` and `S` functions.

## 8. Open questions

- **How much does order cost in practice?**
  duckplyr and DuckDB say order preservation makes plans more complicated and uses more memory,
  but no benchmark of `DUCKPLYR_OUTPUT_ORDER` on typical pipelines was found.
  If the gain is small for in-memory results, layer 1 for goal (a) matters less than layer 2 for goal (b).
- **Who is responsible when a mark is wrong?**
  A user who marks a frame unordered and then calls an order-dependent function gets a silently different result.
  Should the producer always attach a row-number column so that order can be restored, at a small cost?
- **Can conditional order classes be expressed compactly?**
  `lm()` is `I` unless `subset` is positional; `aggregate()` inherits from `FUN`; `kmeans()` depends on `algorithm`.
  A registry needs a small language for these conditions, and nobody has designed one.
- **Callbacks.**
  `tapply()`, `aggregate()`, `by()`, data.table `j` and `spark_apply()` take user functions.
  R cannot infer that a closure is a reducer; should these accept reducer objects alongside functions, as Dask's `Aggregation` does?
- **Is commutativity needed, or only associativity?**
  Clojure, Algebird and rayon require only associativity and keep chunk order.
  A protocol requiring commutativity gives producers full freedom but excludes order-sensitive yet chunkable consumers
  (running cumulative output, `first`/`last` with an explicit key).
- **Where should `R`-class functions land?**
  Treating them as order-free is defensible statistically and breaks seed reproducibility; key-derived random numbers fix both
  but change results relative to today's R.
- **Exactness of floating point.**
  Should "order-free" mean equal to tolerance, or bitwise equal through reproducible summation?
  The answer differs for audits and for exploratory work.
- **Consistent permutation across materialisations.**
  If a producer materialises a frame twice (or materialises columns separately), are the two orders guaranteed to agree?
  This needs to be part of any producer contract.
- **Verification debt.**
  Several rendered documentation pages cited here were confirmed only through their source files,
  and some quotes (Steele, Rabkin, Bismarck's "shuffle once") remain unverified; they should be re-checked from an unrestricted network.
