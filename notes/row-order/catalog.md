# Catalog: order-free, chunkable data-frame consumers (per-function findings)

Merged from the subagents' findings files; classes are defined in the report's legend.
Each part starts with the subagent's own scope and verification notes.

<!-- source: findings/base_utils.md -->
## Part: Findings: base, utils (and methods, tools)

Sources read in the R-devel checkout at `/home/user/r-svn/src/library/{base,utils}/R` and the C code they call
(`src/main/{unique,util,summary,array}.c`, `src/appl/maxcol.c`, `src/library/utils/src/io.c`).
Claims marked "verified" were checked with R 4.5.3 by permuting rows with a fixed seed (`df[sample(nrow(df)), ]`)
or by comparing a chunk against the whole frame; scripts are in `scratchpad/bu/t*.R`.
Each finding is one line so the files can be merged mechanically.

### base

- `base::table` (also `table()` on a data frame or a list of columns) — ORDER=I; CHUNK=K (A when every argument is a factor with declared levels); state: integer count per cell, keyed by the cross product of level labels; merge = align dimnames by label, add counts, re-sort labels; notes: non-factor arguments get `factor(a, exclude = exclude)` (table.R:84), whose levels are the *sorted* distinct values (factor.R:28-31), so per-chunk tables have different dims and must be merged by label (character sorts in the locale's collation); doubles are levelled via `as.character()` at 15 significant digits, so `0.1+0.2` and `0.3` share a cell and a chunk merge must key on the same strings; `useNA = "ifany"` adds the NA cell only if some chunk saw an NA; counts come from `tabulate()` as integer (table.R:146), so totals over more than 2^31 rows need double; verified `identical()` under row permutation.
- `base::rowsum.data.frame`, `base::rowsum.default` — ORDER=I with `reorder = TRUE` (groups are `sort()`ed, rowsum.R:29/40), S with `reorder = FALSE` (groups in first-appearance order, verified `b c a` vs `a c b`); CHUNK=K; state: per-group column sums; merge = `rowsum(rbind(r1, r2), c(rownames(r1), rownames(r2)))`; notes: TRAP — integer columns accumulate in a running C `int` that becomes a sticky `NA` as soon as a *partial* sum leaves the int range (src/main/unique.c:2035 matrix, :2109 data frame), so with mixed signs the result is order-dependent: `v = c(.Machine$integer.max, 1L, -1L)` gives `NA`, the permutation `c(1, 3, 2)` gives 2147483647 (verified); `sum()` instead switches to a double accumulator (`irsum`, summary.c:68) and `colSums()` uses long double, so they are safe; a chunked rewrite should accumulate in double or int64, which also removes the trap; `na.rm` is row-local; double results agree only to `all.equal()` (summation order).
- `base::tapply` (including `X` a data frame with a formula `INDEX`) — ORDER=I for an order-free `FUN` (cells are the sorted `as.factor()` levels), S or D otherwise, because `FUN` receives each group's values in input order (`tapply(x, g, "[", 1)` changes under permutation, verified); CHUNK=K when `FUN` is decomposable (sum, length, min/max, mean via (sum, n), var via (n, mean, M2)), H per group otherwise (median, quantile, mad); state: per-cell partial aggregate; notes: the level set is the union of distinct values, so it needs a K pre-pass or declared levels; `FUN = NULL` returns the cell index, which is E given the level sets (P); empty cells get `default = NA`.
- `base::by.data.frame` (+ `by.default`) — ORDER=I iff `FUN` is order-free (verified for `mean(d$x)`), otherwise S, since `FUN` sees each group's sub-frame in input order with its original row names (by.R:50); CHUNK=K if `FUN` reduces to a mergeable summary, otherwise H per group (each group's rows must be co-resident, so partition first with `split`); state: per-group partial result; notes: implemented as `tapply(seq_len(nd), IND, FUNx)` and inherits its sorted-level group order.
- `base::split.data.frame` (+ `split.default`) — ORDER=S: group names and their order are invariant (sorted `as.factor()` levels, split.R:27; `drop = FALSE` keeps empty levels), but within-group row order and row names follow the input (verified: identical names, group "a" identical only after sorting); CHUNK=K; state: per-group row buckets, O(n) rather than bounded — this is the partition step of an out-of-core group-by (append each chunk's pieces to per-group files or lists); notes: the result is the data itself, so the real target is split-apply-combine with a decomposable apply (use `rowsum`/`tapply`-style K state); `split<-` and `unsplit` are D by design (they scatter values back by within-group position) and are only sequentially chunkable, with one read cursor per group.
- `base::merge.data.frame` (+ `merge.default`) — ORDER=S (the multiset of output rows is invariant, verified; the row order is not); CHUNK=M for inner and `all.x` joins when `y` fits in memory (stream `x` chunks against a fixed `y`, a hash join), K for `all.y`/`all` (also keep the set of `y` keys matched so far and emit unmatched `y` rows at the end), H when both sides are large (sort-merge, or P with a hash-partition pass over both sides); state: build-side hash table plus matched-key set; notes: TRAPS in presentation — keys are numbered by first appearance in `x` (merge.R:111-112), so `sort = FALSE` emits key groups in first-appearance order; within a key the `x` and `y` rows are ordered by an unstable Shell sort (`isort_with_index`, src/main/util.c:667; verified scrambled ids within a key); `sort = TRUE` with more than one `by` column sorts by the `"\r"`-pasted *string* key (merge.R:106, 182, giving 10 < 2 < 9), except when `all = TRUE` and some rows are unmatched, where it orders by the actual columns (merge.R:123, 181), so chunks with and without unmatched rows sort differently (verified); factor keys are compared as character (merge.R:97); `by` of length 0 is a Cartesian product (chunk the outer side, M).
- `base::unique.data.frame` — ORDER=S (same set of distinct rows, verified; order and the kept row names are those of the first occurrence); CHUNK=K; state: hash set of rows seen so far, with rows emitted as soon as they are first seen; notes: implemented as `x[!duplicated(x), ]` (duplicated.R:136); `fromLast = TRUE` keeps last occurrences and needs a reverse scan or a second pass.
- `base::duplicated.data.frame`, `base::anyDuplicated.data.frame` — ORDER=D for the per-row flags and the returned index (which copy counts as "first" is positional), I for derived quantities such as `sum(duplicated(x))` and `anyDuplicated(x) > 0`; CHUNK=K; state: hash set of rows seen (anyDuplicated can stop early); notes: multi-column frames compare factor columns by integer code (`lapply(x[i], as.numeric)`, duplicated.R:40), so independently read chunks must harmonise level sets, or hash labels, before deduplicating across chunks.
- `base::summary.data.frame` (+ `summary.default`, `summary.factor`, `summary.matrix`) — ORDER=I (verified `identical()` under permutation); CHUNK=H for numeric columns because quartiles and median come from type-7 `stats::quantile()` (summary.R:42), everything else is A or K: min, max, mean and NA count (A), logical counts (A), factor level counts (K; the `maxsum` top-k plus "(Other)" needs all counts, summary.R:145), character Length, N.blank and min/max nchar (A) and N.unique (K, summary.R:58); state: per column (n, sum, min, max, NAs) plus a quantile sketch or a value-count map; notes: exact escape via K when a column has few distinct values (value counts give exact type-7 quantiles), otherwise KLL/t-digest approximations; `mean()` refines with a second pass in C (`real_mean`, summary.c:479), so A-state means match only to `all.equal()`.
- `base::Summary.data.frame` (`sum`, `prod`, `min`, `max`, `range`, `any`, `all` on a data frame) — ORDER=I; CHUNK=A; state: running sum/prod/min/max/any/all; notes: goes through `as.matrix()` and errors unless all columns are numeric-alike (dataframe.R:1682); integer `sum()` switches to a double accumulator on overflow (verified 3 × INT_MAX = 6442450941), so chunk partials should be double; `mean(df)` is unsupported (NA with a warning).
- `base::colSums`, `base::colMeans` (data frame via `as.matrix()`) — ORDER=I; CHUNK=A; state: per-column long-double sum and non-NA count; notes: integer input yields double and cannot overflow (LDOUBLE accumulators in src/main/array.c); character or factor columns error after `as.matrix()`; `rowSums`/`rowMeans` are E/M.
- `base::scale` (data frame via `as.matrix()`) — ORDER=E for the output rows, with invariant parameters; CHUNK=P with 2 passes (pass 1 A: per column n_nonNA, mean and M2 by Welford/Chan, giving `scaled:center` and `scaled:scale`; pass 2 M: apply); state: per-column (n, mean, M2); notes: TRAP — with `center = FALSE` the scale is the root mean square `sqrt(sum(x^2)/(n-1))` (scale.R:42), not `sd()` (verified 0.905 vs 0.898); with `center = TRUE` it equals the sd of the non-NA values; verified the two-pass result equals `scale()` under `all.equal()`; supplying numeric `center`/`scale` makes it plain M.
- `base::sweep` — ORDER=E; CHUNK=M with `MARGIN = 2` (`STATS` per column is a fixed parameter, typically from an A pre-pass); state: none; notes: with `MARGIN = 1` `STATS` is aligned by row position and must be chunked in lockstep.
- `base::factor`, `base::as.factor` (applied to a data-frame column) — ORDER=E given the level set, and the level set itself is I (sorted distinct values, factor.R:28-31); CHUNK=P (pass 1 K: distinct values per column, sorted at the end in the locale's collation; pass 2 M: `match()` to codes), or M with declared `levels =`; notes: the canonical global-information trap, since per-chunk `factor()` gives chunk-specific level sets and codes; doubles are levelled via `as.character()` at 15 significant digits.
- `base::droplevels.data.frame` (+ `droplevels.factor`) — ORDER=I for the used-level set, E for the rows; CHUNK=P (pass 1 K: per factor column, the levels actually used; pass 2 M: recode); notes: per-chunk `droplevels()` yields different level sets (verified); used levels keep their original order.
- `base::interaction` — ORDER=E given the levels, and the level sets are I (sorted `as.factor()` levels; `drop = TRUE` keeps `sort(unique(codes))`, interaction.R:44/55); CHUNK=P (pass 1 K: levels per factor, plus the observed combinations when `drop = TRUE`; pass 2 M); notes: per-chunk `drop = TRUE` gives different levels (verified); `lex.order` changes only the level order.
- `base::cut.default` (+ `cut.Date`, `cut.POSIXt`) — ORDER=E; CHUNK=M with explicit `breaks`, P with `breaks = <number>` (pass 1 A: `range(x)`, then breaks are spread over the range widened by range/1000 and labels are formatted from them, cut.R:30-37; pass 2 M); notes: `cut(x, 3)` per chunk gives different breaks and labels (verified); `cut.Date`/`cut.POSIXt` with `breaks = "month"` and similar anchor at `min(x)` and run to `max(x)` (dates.R:323/335, datetime.R:1109/1124), which needs the same A pre-pass.
- `base::data.matrix` — ORDER=E given the level sets; CHUNK=P when the frame has character columns, otherwise M; state (P): per character column the K set of distinct values; notes: character columns become `as.integer(factor(xi))` (data.matrix.R:38), codes over the *global* sorted distinct values, so a 2-row chunk recodes `c("b", "c")` as 1, 2 instead of 2, 3 (verified); factor and logical columns keep their codes, which are consistent only if all chunks share declared levels; integer versus double result depends only on column types.
- `base::as.matrix.data.frame`, `base::t.data.frame`, `base::apply` (with `MARGIN = 1` on a data frame) — ORDER=E; CHUNK=M if all columns are numeric/logical (or all character), P otherwise; state (P): per numeric column the common-format parameters (max width, significant digits needed, fixed vs scientific), mergeable by max; notes: TRAP — when any column is non-numeric, numeric columns are converted with `format(xj)` (dataframe.R:1559), which pads to a width and digit count chosen from the whole column: row 1 of the whole frame is `"  1.00"`, the same row as a 1-row chunk is `"1"` (verified), so `apply(df, 1, paste, collapse = "|")` changes with the chunking; `apply(df, 2, f)` inherits the class of `f`.
- `base::format.data.frame`, `base::print.data.frame` — ORDER=E for the row strings, with a column-global layout; CHUNK=P (pass 1 A: per column width, digits and scientific decision; for POSIXct columns also the "all times are midnight" and fractional-seconds flags of `format.POSIXlt()`, datetime.R:384-410; pass 2 M); notes: verified that chunk and whole differ (`"  1.00"` vs `"1"`, `"2024-01-01 00:00:00"` vs `"2024-01-01"`); `print` also truncates at `max.print` rows, which is positional.
- `base::subset.data.frame`, `base::transform.data.frame`, `base::within.data.frame`, `base::with.default` — ORDER=E iff the user expression is row-local; CHUNK=M; state: none, plus a running row offset to reproduce row names; notes: TRAP — expressions are evaluated on whole columns (frametools.R:25/70, eval.R:62), so `subset(df, x > mean(x))`, `transform(df, z = scale(x), r = rank(x), s = cumsum(x))` or anything using `x[1]`, a lag or `sample()` silently becomes per-chunk; short results recycle positionally.
- `` base::`[.data.frame` `` (and `[<-`, `[[<-`, `$<-` with row indices) — ORDER=E for a logical `i` (filters), D for integer or character `i` (positional or row-name addressing); CHUNK=M for a logical or row-local `i`; state: running row offset (A) to reproduce automatic row names, which are global positions; notes: duplicated selected row names are `make.unique()`d in encounter order (dataframe.R:732); a shorter logical `i` recycles positionally.
- `base::Ops.data.frame` (Arith, Compare, Logic) — ORDER=E; CHUNK=M; notes: TRAP — a non-scalar, non-list operand is recycled down the rows column-major (`split(rep_len(e2, prod(dim(e1))), ...)`, dataframe.R:1639), so `data.frame(a = 1:4, b = 1:4) * c(10, 100)` multiplies rows alternately by 10 and 100 (verified) and chunk boundaries must align with the recycling period; Compare and Logic return a logical matrix.
- `base::Math.data.frame` — ORDER=E for `abs`, `log`, `round`, `floor`, `sqrt` and the like, D for `cumsum`, `cumprod`, `cummax`, `cummin`, which are members of the Math group and are applied per column (dataframe.R:1596); CHUNK=M, or A as a sequential carry (last cumulative value) for the cum* functions; notes: `cumsum(df)` looks like an element-wise transform but is order-dependent (verified).
- `base::is.na.data.frame`, `base::anyNA.data.frame` — ORDER=E / I; CHUNK=M / A (logical OR, can stop early); state: none / one flag; notes: dataframe.R:124/135.
- `base::max.col` (data frame via `as.matrix()`) — ORDER=R with the default `ties.method = "random"`, E with "first" or "last"; CHUNK=M; state: none (RNG stream); notes: TRAP — the default draws `unif_rand()` for every tied row (src/appl/maxcol.c:75), so the same seed gives different answers under row permutation (verified); processing chunks in the original order with the RNG state carried over reproduces the result.
- `base::rbind.data.frame` — ORDER=S, which matters because it is the combine step of most chunked pipelines; CHUNK=M (append); state: none; notes: TRAP — result factor levels are the first-appearance union across the arguments (dataframe.R:1354), and character values bound into a factor column become new levels in appearance order (dataframe.R:1360): `rbind(c1, c2)` gives levels `p q r`, `rbind(c2, c1)` gives `p r q` (verified); duplicated row names are `make.unique()`d (dataframe.R:1465); declare levels up front or re-level after combining.
- `base::cbind.data.frame`, `base::data.frame` — ORDER=E; CHUNK=M with inputs chunked in lockstep; state: none; notes: shorter arguments recycle positionally.
- `base::order`, `base::sort_by.data.frame`, `base::xtfrm` — ORDER=S (stable sort: ties keep input order); CHUNK=H; state: all keys; notes: escape hatch = external merge sort (sorted runs plus a k-way merge, P with about log_k(#runs) passes) or counting sort (K) when keys have few distinct values; `order(df)` and `xtfrm(df)` error with "cannot xtfrm data frames" (dataframe.R:1695); `xtfrm.default` of non-numeric input uses `rank(ties.method = "min")` (sort.R:281).
- `base::Map`, `base::mapply`, `base::pmin`/`pmax`, `base::Reduce` over columns (e.g. `do.call(pmax, df)`, `Reduce("+", df)`) — ORDER=E; CHUNK=M; state: none; notes: row-wise across columns; `Reduce()` over a list of chunk states is the natural combine step but is order-sensitive for non-commutative steps such as `rbind` (see above).
- `base::write.dcf` — ORDER=E; CHUNK=M; state: none; notes: one record per row (dcf.R:228).
- `base::crossprod` — ORDER=I; CHUNK=A; state: p × p X'X summed over chunks; notes: not a data-frame consumer itself (errors with "requires numeric/complex matrix/vector arguments", verified), so it is reached via `as.matrix()`/`data.matrix()` and inherits their character-column traps.
- **verdict**: the most valuable targets are `table`/`tabulate` (K, or A with declared levels; per-chunk tables merge by aligning dimnames), `rowsum` (K; a chunked version should also accumulate integers in double, fixing the order-dependent overflow), `tapply`/`by` with decomposable `FUN`, and `summary.data.frame`, which is A/K except the quartiles (sketch, or exact via value counts). `unique.data.frame` (streaming K) and `merge` with an in-memory `y` (M hash join) are close behind. No base data-frame consumer carries state between calls, but the outputs of `rowsum` and `table` are closed under re-aggregation, so a chunk loop with `Reduce()` can be written today. The traps to remember are global-format and global-level coercions (`as.matrix`, `format`, `data.matrix`, `factor`, `droplevels`, `cut(breaks = n)`), first-appearance level unions in `rbind`, and the merge sort-order oddities.

### utils

- `utils::type.convert.data.frame` (`type.convert.list`, `type.convert.default`; also the type inference inside `read.table`) — ORDER=I (verified identical under permutation); CHUNK=P (pass 1 A: per column a 4-bit mask "can still be logical / integer / double / complex", AND-merged across chunks, because the chosen type is the first of logical < integer < double < complex < character that every non-NA string parses as (`ruleout_types`, io.c:500; `typeconvert`, io.c:549); for `as.is = FALSE` also the K set of distinct strings, sorted at the end (io.c:745); pass 2 M: convert with the type fixed, e.g. via `colClasses`); state: 4 bits per column, plus a distinct-string set for factors; notes: TRAP — chunk-local conversion is lossy and cannot be upcast afterwards: a chunk holding `"T", "F"` becomes logical and one holding `"007", "1"` becomes integer 7, 1, while the global column is character and must keep `"007"` (verified); only integer → double → complex upcasts are exact, so either keep raw strings or run the pre-pass; `numerals`, `tryLogical` and `na.strings` act per element; prior art: readr/vroom's `guess_max` sampling is the approximate one-pass escape.
- `utils::write.table`, `utils::write.csv`, `utils::write.csv2` — ORDER=E; CHUNK=M, and already chunk-capable via `write.table(chunk, file, append = TRUE, col.names = FALSE)`; state: running row offset if automatic row names should continue; notes: numbers are written per element at 15 significant digits (utils/src/io.c:1122) and classed columns via per-element `as.character()` (write.table.R:138-139), so chunked output is byte-identical to the whole (verified) unless the chunks carry fresh 1..k row names (verified to differ); TRAP — `write.csv` ignores `append` and `col.names` with a warning (write.table.R:147-160) and, on an open connection, repeats the header for every chunk (verified), so use `write.table(sep = ",", dec = ".", qmethod = "double", col.names = FALSE)` after the first chunk; embedded matrix columns go through `as.matrix()` and inherit its common-format trap.
- `utils::unstack.data.frame` (+ `unstack.default`) — ORDER=D (trap: the values are grouped by `tapply(values, ind, as.vector)` (frametools.R:65), and row i of the result pairs the i-th occurrence of every group, so permuting rows within a group changes the pairing (verified); the per-group multisets are I); CHUNK=K, sequential only; state: per-group queues, emitting a row once every group has a value, and per-group counts, because the result type (data frame vs list) depends on whether all group sizes are equal; notes: the inverse of `stack`, order-preserving by design.
- `utils::stack.data.frame` (+ `stack.default`) — ORDER=E; CHUNK=M; state: none; notes: the output is column-major (`unlist()` of the columns with `ind` blocks, frametools.R:33), so concatenating per-chunk results interleaves chunks inside each block (verified `1 2 5 6 3 4 7 8` vs `1:8`), which is S at the combine step unless each `ind` block is written to its own stream; `ind` levels come from the column names, not the data.
- `utils::head`, `utils::tail`, `utils::str.data.frame` — ORDER=D (positional by design); CHUNK=A (`head`: stop after n rows; `tail`: ring buffer of n rows); state: row counter or n-row buffer; notes: listed for completeness; `str()` shows the first values of each column.
- `utils::hashtab` (experimental) — not a data-frame consumer; notes: a mutable keyed hash map that can hold the K state of a chunk loop (seen-row set for `unique`, group → partial aggregate).
- skipped: `count.fields` and the `read.*` family are producers rather than data-frame consumers (`read.table(con, nrows = k)` on an open connection with fixed `colClasses` is the existing base idiom for chunked reading); `relist`, `hasName`, `combn` and `modifyList` do not touch rows; `edit`, `View` and `fix` are UI; `strcapture` builds a data frame per element (E/M).
- **verdict**: `type.convert` is the most interesting target, because column type inference is a mergeable lattice (4 bits per column) and a clean P = A pre-pass + M design, but only with raw strings kept or a second pass, since chunk-local conversion is lossy. `write.table` is already chunk-capable with `append = TRUE` (but `write.csv` is not). `stack` is trivially M; `unstack` is a hidden order dependence.

### methods, tools

- no user-facing function in `methods` or `tools` consumes data-frame rows (`methods` only defines the S4 class and wrappers that forward `$<-`, `[<-` and `[[<-` to the S3 methods, BasicClasses.R:296-327; `tools` uses data frames internally for package metadata), so there is nothing to report.
- **verdict**: none.

<!-- source: findings/stats_models.md -->
## Part: stats, part A: model fitting, model plumbing, multivariate methods

Scope: R-devel sources under `src/library/stats/R` (plus `../src` C/Fortran and `splines/R/splines.R`), R 4.5.3 for runtime checks.
Method for "verified" claims: rows permuted with a fixed seed, results compared with `all.equal()`;
scripts are in `scratchpad/models_tests/t1.R` … `t6.R` (lm/glm/aov/manova/lsfit; nls/loess/ppr/smoothers; kmeans/hclust/multivariate; biglm traps).
File references are relative to `src/library/stats/R` unless prefixed.

### stats

- `stats::lm`, `stats::lm.fit`, `stats::lm.wfit`, `stats::aov` (no `Error()`) — ORDER=I; CHUNK=A; state: incremental Givens/TSQR factor R plus Q'y and RSS (or X'WX, X'Wy, y'Wy), Σw, n, #(w≠0); p×p; notes: exact chunking needs a K pre-pass for factor levels, because `lm`/`glm` force `drop.unused.levels = TRUE` (lm.R:32, glm.R:51). `model.matrix` also turns character columns into `factor()` per call (models.R:647-649), so a chunk that lacks a level gets fewer columns. A missing first level moves the treatment baseline, and `contr.sum`/`helmert`/`poly` change shape. Pass `xlev` (verified: 4 vs 5 columns). Data-dependent bases (`poly`, `scale`, `ns`/`bs`) need `predvars` frozen by a pre-pass (`makepredictcall`, models.R:557-561). Verified: chunked X'X with frozen predvars + `xlev` equals `lm()` exactly. Whole-vector formula expressions (`I(x - mean(x))`, `cut(x, 5)`, `rank(x)`, `x/sum(x)`) have no `makepredictcall` hook and silently become chunk-local. Verified invariant: coef, `summary`, `anova`, `confint`, aliasing/NA pattern (dqrdc2 pivots by column, using a tolerance on column norms). The returned object is not invariant: `$effects` is order-dependent (verified: the signs of the first p effects and even the multiset of the n−p residual effects change), `qr.R()` row signs flip (verified), and `$qr`/`$residuals`/`$fitted.values`/`$model` are n-row (they need a second M pass given β). The normal equations square the condition number, so prefer Givens/TSQR. Prior art `biglm::biglm` + `update.biglm` is already chunk-capable (AS274 Givens QR). It re-runs `model.frame(terms, chunk)` per chunk without `xlev`/predvars and compares only `assign`; verified silently wrong with `poly(x, 2)` and with character columns whose level sets differ per chunk but have equal size.
- `stats::glm`, `stats::glm.fit` — ORDER=I; CHUNK=P; state: per IRLS pass X'WX and X'Wz (or Givens QR of √W·X, √W·z), deviance, Σw, flags for `validmu`/`valideta`/fitted-0/1 warnings; p×p; notes: needs iter+1 passes. The first pass uses row-local starting values from `family$initialize`: binomial `mustart = (w*y + 0.5)/(w + 1)` (family.R:309), poisson `y + 0.1` (family.R:170), Gamma/inverse.gaussian/gaussian `y`. Later passes fuse the deviance at β(k+1) with the next cross-products (glm.R:279-282; the convergence test is at glm.R:342). Each step-halving (non-finite deviance or invalid eta) costs an extra deviance pass. The null deviance needs Σwy/Σw (glm.R:401) and then a Σdev pass (fusable). Intercept + offset triggers a whole second IRLS for the null model (glm.R:110-128). Gamma AIC needs dispersion = dev/Σw before Σ log dgamma, so one more pass (family.R:471-474). `mustart`/`etastart`/`weights`/`offset` given as data columns are row-local. A custom family whose `initialize` uses whole-vector statistics (e.g. `mean(y)`) needs a pre-pass, and so does `wtol > 0` (needs Σw). Same level and basis traps as `lm`. Verified invariant for binomial (with weights) and poisson (with offset): coef, `iter`, deviance, null deviance, AIC, `anova` (Chisq/Rao), `drop1`, `confint`, `cooks.distance`. Prior art: `biglm::bigglm(data = function)` (multi-pass Givens; it starts from β = 0 rather than `mustart`, but verified to reach the same coefficients within 1e-6 and the same iteration count here), `speedglm::shglm`, `mgcv::bam(chunk.size =)`.
- `stats::kmeans` — ORDER=D (Hartigan–Wong default, MacQueen); I given fixed centres for Lloyd/Forgy; R for the default random starts; CHUNK=P (Lloyd only); state: per pass k×p centre sums, k counts, k withinss; notes: `centers = k` draws `x[sample.int(m, k), ]` (kmeans.R:99). `nstart ≥ 2` samples from `unique(x)`, which is in first-appearance order (kmeans.R:101-105, 128). So the RNG is indexed by row (verified: same seed, permuted rows → different `tot.withinss`). Hartigan–Wong (kmns.f OPTRA/QTRAN loop over points in row order with immediate centre updates) and MacQueen (kmeans.c, online update per point) depend on row order even from fixed centres. Verified: only 12% (HW) and 30% (MacQueen) of 40 permutations reproduced the converged centres, and 0% after one iteration. Lloyd matched in 100%. Lloyd's stop rule "no assignment changed" is equivalent to "centres unchanged", so no per-row state needs to survive between passes. `totss` is A. Chunked rewrite = Lloyd with deterministic or seeded-sketch initialisation (k-means||, reservoir); prior art `biganalytics::bigkmeans`, mini-batch k-means.
- `stats::hclust` — ORDER=D when dissimilarities tie (I otherwise); CHUNK=H; state: full `dist` (n(n−1)/2); notes: the NN-chain loop picks the first minimal pair with a strict `.LT.` (src/hclust.f:93-98), so with ties the merge sequence follows row index. Verified: `height` differs under permutation for complete, average, ward.D2, centroid and median on integer-valued data. Single linkage (MST) is invariant. Escape: CF-tree/BIRCH pre-clustering, or exact single linkage via blockwise MST.
- `stats::cutree` — ORDER=S; CHUNK=M (given the tree); state: none; notes: the partition is invariant (no ties), but cluster numbers follow the first appearance in observation order (verified: same partition, different labels). With tied heights the k-cut itself is ambiguous (verified partition changes, see `hclust`).
- `stats::nls` (`algorithm = "default"`, `"port"`, `"plinear"`), `stats::predict.nls` — ORDER=I; CHUNK=P; state: per Gauss–Newton iteration J'J, J'r, r'r (or incremental QR of [J r]); plinear: cross-products of [rhs, ∂rhs/∂θ·lin, y]; notes: the convergence criterion ‖Q₁'r‖/‖Q₂'r‖ (nls.R:322-326, plinear nls.R:146-158) follows from J'J, J'r and r'r. Every step-halving trial is one more deviance pass. `numericDeriv` is row-local only if the RHS expression is, so a RHS like `a*(x - mean(x))` changes meaning per chunk. Verified: coef and iteration count invariant for all three algorithms. `port` predictions differed by 5e-8 relative (convergence-tolerance noise from summation order). `predict.nls(newdata)` is M.
- `stats::getInitial`, `stats::sortedXyData`, self-start models (`SSlogis`, `SSasymp`, `SSasympOff`, `SSasympOrig`, `SSmicmen`, `SSbiexp`, `SSfpl`, `SSgompertz`, `SSweibull`) — ORDER=I; CHUNK=K; state: per distinct x, (Σy, n); notes: `tapply(y, x, mean)` is keyed by the character form of x (15 significant digits), then re-sorted (selfStart.R:139-142). The `initial` functions then run `lm`/`nls` on that averaged table in memory. Effectively H when x is continuous (#keys ≈ n); escape: bin x. Verified `SSlogis` initial values invariant.
- `stats::SSfol` (its `initial` function) — ORDER=D; CHUNK=H; notes: uses `which.max(resp)` and the last row, `resp[n]` and `input[n]` (zzModels.R:259-261), so it assumes rows sorted by time. Verified: `getInitial` on Theoph subject 1 changes under permutation (lKe −2.99 vs −2.85). The final `nls` usually reaches the same optimum, but the start (and possible failure) depends on row order.
- `stats::lm.influence`, `stats::influence`, `stats::hatvalues`, `stats::rstandard`, `stats::rstudent`, `stats::cooks.distance`, `stats::dffits`, `stats::dfbeta`, `stats::dfbetas`, `stats::covratio`, `stats::influence.measures` (lm and glm methods), `stats::hat` — ORDER=E; CHUNK=P; state: pass 1 = the fit (R or (X'WX)⁻¹, RSS/dispersion); pass 2 = M per row: h_i = ‖R⁻ᵀx_i‖², e_i, leave-one-out σ_i from RSS − e_i²/(1−h_i); `influence.measures` also needs Σ(h > 0) (A); notes: `lm.influence` zeroes residuals below 100·eps·median(|e|) (lm.influence.R:77). That holistic global needs an extra exact-median pass or a sketch, but it only touches near-zero residuals. `hat(x)` calls `qr.qy` with an n×rank identity (lm.influence.R:28-30). Verified: per-row outputs permute consistently with the rows.
- `stats::anova.lm`, `stats::anova.lmlist`, `stats::summary.lm`, `stats::vcov`, `stats::confint.lm`, `stats::confint.default`, `stats::summary.aov`, `stats::manova`, `stats::summary.manova`, mlm (`lm` with a matrix response) — ORDER=I; CHUNK=A; state: R, the first p effects Q₁'y (their squares are invariant, their signs are not), RSS; multivariate: X'Y (p×q) and Y'Y (q×q); notes: sequential SS come from `effects[1:p]^2` (lm.R:615-619). `summary.lm` keeps the full residual vector, and its print method shows residual quantiles (H, cosmetic). Verified invariant: `anova`, `summary`, `confint`, `manova` stats and SS, mlm coef.
- `stats::aov` with `Error()` — ORDER=I for the stratum summaries; CHUNK=K; state: per Error-cell (block/plot/subject) sums of [X, y] plus global cross-products; notes: the code fits a QR of the Error design and splits the rows of Q'X and Q'y by stratum (aov.R:106-125), using n × #levels memory. Stratum SS are projections X'P_sX (invariant; verified `summary` equal under permutation), but per-stratum `qty`/effects rows depend on row order. For nested factor `Error()` terms the projections are cell averages, so K keyed by cell; crossed Error terms need more.
- `stats::add1.lm`, `stats::drop1.lm`, `stats::step` (lm), `stats::extractAIC.lm` — ORDER=I; CHUNK=A; state: one cross-product (or QR) of [X_scope y] over the full scope; notes: every candidate's RSS/AIC follows by sweeping that one matrix. The current code re-evaluates the data with `model.frame(fob, xlev = )` (add.R:142-146), and `step()` refits through `update()` (add.R:834), so each candidate at each step is a full data pass. Prior art: `leaps::regsubsets` (has a biglm method). Verified: `step()` picks the same model under permutation.
- `stats::add1.glm`, `stats::drop1.glm`, `stats::anova.glm`, `stats::step` (glm), `stats::anova.glmlist` — ORDER=I; CHUNK=P; state: one IRLS (X'WX, X'Wz, dev) per candidate or sequential model; all candidates can share the same data passes; notes: `anova.glm` refits every prefix model (glm.R:519). `test = "Rao"` adds one WLS pass per model on the previous fit's working residuals and weights (row-local given β; add.R:308, 541). For `add1.glm` the Rao statistics of all candidates come from a single pass. Verified invariant.
- `stats::profile.glm`, `stats::confint.glm` — ORDER=I; CHUNK=P; state: per profile point one IRLS (X'WX, X'Wz, dev); notes: up to 2·p·(maxsteps−1) constrained fits. Each is warm-started with `etastart = X β + offset` (glm-profile.R:84, 95, 98), which is row-local given β, so a chunked version carries β, not the n-vector. The Wald `confint.default` is A from the fit. Verified `confint(glm)` invariant.
- `stats::profile.nls`, `stats::confint.nls` — ORDER=I; CHUNK=P; state: as `nls`, per profile point; notes: verified `confint(nls)` invariant.
- `stats::predict.lm`, `stats::predict.glm`, `stats::predict.mlm`, `stats::residuals.lm`, `stats::residuals.glm`, `stats::fitted`, `stats::weighted.residuals`, `stats::proj` — ORDER=E; CHUNK=M; state: the fit (β, `xlevels`, `contrasts`, predvars, R for `se.fit`, σ²/dispersion); notes: `newdata` rows are independent (`na.action = na.pass` default), and `rankdeficient = "non-estim"` is decided per row. Trap: `type = "terms"` (and `residuals(type = "partial")`) calls `model.matrix(object)` on the *training* data to centre by `colMeans` (lm.R:839, 850), so it reads the whole training set again unless the means are cached at fit time. `.checkMFClasses` (models.R:401-433) errors when a chunk reader infers a different column type (an all-NA numeric chunk becomes logical). Verified: `predict(newdata, se.fit = TRUE)` and `type = "terms"` unchanged when the training rows are permuted.
- `stats::model.frame` (default method) — ORDER=E; CHUNK=M given fixed levels and predvars (P otherwise); state: none (pre-passes: K for level sets, A/H for bases); notes: `subset`, `na.action`, `weights`, `offset`, `etastart`/`mustart` are row-local. `drop.unused.levels` and the `xlev` new-level check (models.R:568-603) need global level sets, so pass `xlev` from a K pre-pass. Predvars are captured on first evaluation (models.R:557-561), so per-chunk evaluation recomputes `poly`/`scale`/`ns`/`bs` per chunk unless a precomputed `terms` object with `predvars` is supplied.
- `stats::model.matrix` (default method) — ORDER=E; CHUNK=M given levels and contrasts; state: none; notes: character → `factor()` per call (models.R:647-649) gives sorted, collation-dependent levels (invariant, not first-appearance), but only the levels present in the chunk. Contrast matrices depend on `nlevels`. Verified: column count differs between chunks unless `xlev` is fixed.
- `stats::.getXlevels` — ORDER=I; CHUNK=K; state: union of levels per factor/character predictor; notes: (models.R:753-762) this is exactly the pre-pass that makes `model.frame`/`model.matrix`/`predict` chunk-exact.
- `stats::poly`, `stats::polym`, `stats::predict.poly`, `stats::makepredictcall.poly` — ORDER=I; CHUNK=P; state: pre-pass 1 n, Σx; pre-pass 2 centred power sums Σ(x − x̄)^k for k ≤ 2·degree (or Stieltjes: one pass per degree accumulating Σx·p_k² and Σp_k²); plus distinct-x count capped at degree+1; then M with `coefs = list(alpha, norm2)`; notes: the coefficients come from a QR of the centred Vandermonde matrix (contr.poly.R:88-103). The moment route is ill-conditioned at high degree; the Stieltjes route is stable. `raw = TRUE` is M.
- `stats::scale` inside formulas (`stats::makepredictcall.default`) — ORDER=I; CHUNK=P; state: pre-pass n, mean, M2 (Welford/Chan), then M; notes: `makepredictcall.default` freezes `center`/`scale` (models.R:745-751).
- `stats::cov`, `stats::cor`, `stats::var` (Pearson, data frames), `stats::cov.wt` — ORDER=I; CHUNK=A; state: Σw, Σw², mean vector, co-moment matrix (Chan merge); notes: `cov.wt` normalises `wt` by Σwt and divides by 1 − Σwt² (cov.wt.R:31-46), which merges as raw Σw and Σw². `use = "pairwise.complete.obs"` needs per-pair (n, sums, co-moments), p² state. Spearman is P (per-column rank pre-pass, H or K for few distinct values, then A). Kendall is H. Verified invariant (all three methods).
- `stats::prcomp` — ORDER=I for `sdev`; rotation and scores only up to column sign; CHUNK=A (+M for `x`); state: centre/scale moments plus a p×p cross-product or TSQR R; notes: SVD of the n×p centred matrix (prcomp.R:40) has no sign convention. Verified: `rotation` signs flip under permutation, |rotation| equal. `retx` scores are a second M pass. The SVD of the merged R gives the same d and V in exact arithmetic.
- `stats::princomp` — ORDER=I; CHUNK=A (+M for scores); state: `cov.wt` list (centre, cov, n.obs); notes: already chunk-capable through `covmat =` a list (princomp.R:60-64). The list path skips the (1 − 1/n) factor applied when x is given (princomp.R:78), so feed it `cov.wt(..., method = "ML")` (verified equal `sdev`). `fix_sign = TRUE` keeps loadings sign-stable (verified invariant).
- `stats::factanal` — ORDER=I; CHUNK=A (+M for scores); state: covariance + n.obs; notes: already chunk-capable through `covmat =` (factanal.R:50-56). The start uses `diag(solve(cv))`, and `nstart > 1` draws `runif` per variable, not per row. Regression/Bartlett scores are a second M pass. Verified loadings and scores invariant, and `covmat = cov.wt(x)` reproduces the raw fit.
- `stats::cancor` — ORDER=I; CHUNK=A; state: means and the joint cross-product of [x y] (or a TSQR of each block); notes: implemented with `qr()` of centred x and y and `qr.qy` against an n×dy identity (cancor.R:51-56), O(n·dy) memory. Verified `cor` and `xcoef` invariant (QR sign choices cancel).
- `stats::mahalanobis` — ORDER=E; CHUNK=M; state: `center`, `cov` (an A pre-pass when estimated from the same data).
- `stats::loess`, `stats::predict.loess` — ORDER=I; CHUNK=H for the fit, M for prediction over `newdata`; state: needs all rows (kd-tree, k-NN bandwidths); notes: `normalize` uses per-column trimmed SDs via a full sort (loess.R:118). `family = "symmetric"` recomputes robustness weights from the median |residual| each iteration (`lowesw`, loess.R:180). Verified fitted, `enp`, `s`, `one.delta` invariant (1-D with ties, 2-D symmetric, `surface = "direct"`). `predict(newdata)` with `surface = "interpolate"` and `se = FALSE` needs only the kd tree and ranges (loess.R:369-382). Otherwise the training rows must stay in memory, though `newdata` can still be chunked. Escape: pre-bin onto a grid.
- `stats::ppr` — ORDER=I; CHUNK=H; notes: alternating projection directions with `supsmu`/spline smoothing along sorted projections. Verified `alpha` and fitted invariant (`supsmu` and `gcvspline`).
- `stats::smooth.spline`, `stats::predict.smooth.spline` — ORDER=I; CHUNK=P (pre-pass then K); state: pre-pass mean(x), IQR(x) for the default `tol = 1e-6 * IQR(x)` (H; supply `tol` to avoid it), Σw, #(w > 0); then per bin `round((x − x̄)/tol)` the sums Σw, Σwy, Σwy² and the bin's x; notes: smspline.R:42, 78, 95 collapse ties into this table. The penalised fit and GCV then run in memory on the nx ≤ n unique values. Verified fit, λ and df invariant. Prediction is M.
- `stats::isoreg` — ORDER=I; CHUNK=K; state: per distinct x, (n, Σy); notes: ties are broken by `order(x, -y)` (isoreg.R:31), which pools each tie block, so the result equals PAVA on per-x means weighted by counts. Fitted values need a second lookup pass (M). Verified invariant.
- `stats::lowess` — ORDER=I; CHUNK=H; notes: nearest-neighbour local-linear fits over sorted x, with robustness iterations using the median |residual|. Ties at the left window edge are always at distance ≥ h, so they get weight 0, and right ties are explicitly picked up (src/lowess.c:59-91). Verified invariant under heavy ties. The default `delta` needs the range (A). Escape: pre-binning.
- `stats::supsmu` — ORDER=I; CHUNK=H; notes: `order(x, y)` tie-breaking (smspline.R:403) makes it canonical, except for rows with equal x and y but different `wt`. Running-line spans are counted in points. Verified invariant.
- `stats::ksmooth` — ORDER=I; CHUNK=A with user-given `x.points`, else P (range/n pre-pass, then A); state: per evaluation point Σkernel·y and Σkernel (2·n.points); notes: the default grid is `range(x)` with `n.points = max(100, n)` (ksmooth.R), so the state grows with n unless `n.points`/`x.points` is fixed. Kernel sums are order-free (src/ksmooth.c:33-58). Verified.
- `stats::cmdscale` — ORDER=I up to eigenvector sign (coordinates per row); CHUNK=H; notes: verified |coordinates| equal with flipped signs; escape: landmark MDS/Nyström.
- `stats::dist` — ORDER=E (pairwise output permutes with the rows); CHUNK=H; notes: output is n(n−1)/2, computable block-pairwise over chunk pairs, so only useful when the consumer is also blockwise.
- `stats::lsfit`, `stats::ls.diag` — ORDER=I for `lsfit` coefficients, E for `ls.diag` per-row diagnostics; CHUNK=A for `lsfit`, P (2 passes) for `ls.diag`; state: QR or X'WX, X'Wy, y'Wy; notes: verified.
- `stats::model.tables`, `stats::dummy.coef` — ORDER=I; CHUNK=P; state: the fit (A), then per-cell sums of term projections (K); notes: `model.tables.aov` is `proj()` followed by `tapply` over factor cells (model.tables.R:29, 215); projections are row-local given R.
- `stats::nlm`, `stats::optim`, `stats::nlminb`, `stats::optimize`, `stats::constrOptim` (as engines over a row-sum objective) — ORDER=I; CHUNK=P; state: per evaluation the scalar Σ of row contributions (+ gradient p-vector, + Hessian p×p); notes: each function or gradient evaluation is a full pass, and Nelder–Mead/BFGS/SANN need many. SANN's RNG is not indexed by row.
- `stats::update`, `stats::get_all_vars`, `stats::expand.model.frame`, `stats::na.omit`, `stats::na.exclude` (data frames) — ORDER=E; CHUNK=M; state: none; notes: plumbing. `update()` re-evaluates the stored call and so re-reads the whole data source (it inherits the fitter's class). The `na.*` functions are row filters. `na.exclude` pads by row position.
- `stats::approx`, `stats::approxfun`, `stats::spline`, `stats::splinefun` (fed from an x, y column pair) — ORDER=I with `ties = mean` (or any symmetric function); D with `ties = "ordered"`; CHUNK=K; state: per distinct x, the tie summary (Σy, n for mean); notes: `regularize.values` sorts and collapses ties with `tapply` (approx.R:50-61). `ties = "ordered"` skips sorting and collapsing and assumes pre-sorted x. Verified: its output changes when rows within ties are permuted.
- **verdict**: the biggest target is a chunked `lm`/`glm` engine built on three pieces: a K pre-pass for `.getXlevels`, frozen `predvars` (one pass for `poly`/`scale`, a sketch for `ns`/`bs`), and a Givens-QR accumulator. Everything else in the lm/glm family falls out of it: `summary`, `anova`, `confint`, `vcov`, `add1`/`drop1`/`step` for lm (one scope-wide cross-product), the Rao tests, and `predict`/`residuals`/influence as second M passes. It would fix the verified `biglm` traps (per-chunk `poly()` and level sets). Second, `kmeans`: Lloyd is P with k×p state, but the default Hartigan–Wong and MacQueen are order-dependent and the random starts are row-indexed (R), so a chunked version must switch to Lloyd plus deterministic seeding. Third, `nls` Gauss–Newton passes (J'J, J'r) and the K-table smoothers (`smooth.spline`, `isoreg`, `sortedXyData`/selfStart). Already chunk-capable: `princomp(covmat = cov.wt(..., method = "ML"))` and `factanal(covmat =)` with a merged `cov.wt` list, every `predict.*` over `newdata`, and prior art `biglm::biglm`/`update.biglm`, `biglm::bigglm(data = function)`, `speedglm::shglm` and `mgcv::bam(chunk.size =)`. Traps to flag everywhere: `effects`/`qr` are order-dependent, `hclust` depends on order under ties, `SSfol` uses the last row, `cutree` labels follow first appearance, and `predict(type = "terms")` re-reads the training data.

### splines

- `splines::ns`, `splines::bs` (with `df =`, inside formulas), `splines::makepredictcall.ns`, `splines::makepredictcall.bs` — ORDER=I; CHUNK=P; state: pre-pass `Boundary.knots = range(x)` (A) and interior knots = `quantile(x[!outside], …)` (splines/R/splines.R:41-45, 133-137); notes: exact quantiles are H, and a sketch changes the basis, so the result is not exact. After the knots are frozen by `makepredictcall.ns`/`bs` (splines.R:216, 227), basis evaluation is M. With explicit `knots` and `Boundary.knots` it is M from the start.
- **verdict**: the knot pre-pass is the only global step. Declaring knots up front (or accepting sketch quantiles) turns `ns`/`bs` into pure M for any chunked `lm`/`glm`.

<!-- source: findings/stats_tests.md -->
## Part: stats, part B: tests, contingency tables, aggregation, reshaping, univariate summaries, density

Sources: `src/library/stats/R/*.R`; a `file:line` without a directory refers to that folder, `src/…` to `src/library/stats/src`.
The checkout is R-devel (4.6.0 to be), while the installed R used for the empirical checks is 4.5.3.
Where the two differ it is said in the notes (Kendall's O(n log n) algorithm, exact Wilcoxon with ties, `free1way()`).
"Verified" means rows were permuted with a fixed seed and the results compared with `all.equal()`;
"verified E" means `f(d[p, ]) == f(d)[p]`.
The scripts are `scratchpad/stats_tests_work/verify1.R` … `verify6.R`.
`free1way()` only exists in R-devel; it was checked by sourcing `linkfun.R` and `free1way.R` into R 4.5.3.

Cross-cutting results:

- **Seeded simulated p-values are not row-order dependent here.**
  `chisq.test()`, `fisher.test()`, `ks.test()` and `free1way(B > 0)` simulate from table margins or from the tie table only, so with a fixed seed they are `I`, not `R` (verified).
- **The contingency table is the natural `K` state.**
  Every table test consumes only the table, so "chunk → `xtabs()` → add → test" is exact.
  The trap is level alignment: `xtabs(~g)` from chunks with levels {a,b} and {a,c} add with `+` *silently*, counting "c" as "b" (verified).
- **Rank tests reduce exactly to frequency tables over distinct values (× group).**
  `mood.test()` already does this in its tie branch.
  Kruskal–Wallis and Spearman rebuilt from such tables matched exactly (verified).
  All nine `quantile()` types only index order statistics, so they too are exact from a frequency table (type 1 verified).
  `H` therefore degenerates to `K` whenever the number of distinct values is bounded.
  `wilcox.test(digits.rank = 7)` rounds the values to 7 significant digits before ranking, a built-in pre-binning.
- **Positional pairing is the one real order trap in this area:** `pairwise.t.test(paired = TRUE)` and `pairwise.wilcox.test(paired = TRUE)`.

### stats

- `stats::xtabs` — ORDER=I; CHUNK=K; state: per-cell counts (or per-cell `sum(y)` for an LHS), keyed by the factor-level combination; `sparse = TRUE` → (i, j, x) triplets that are concatenated and summed by `dgTMatrix`; notes: verified. Levels come from `factor(u)`, i.e. sorted unique values (xtabs.R:53-61), so the result does not depend on first appearance. Cell sums are `tapply(y, by, sum)` (xtabs.R:67). Trap: chunk tables have chunk-local level sets and `drop.unused.levels`, so merging needs the union of levels (or declared factor levels) first; plain `+` on same-shaped tables with different levels is silently wrong (verified). `addNA`/`exclude` are row-local. This is the reducer that every table test below can consume.
- `stats::aggregate.data.frame`, `stats::aggregate.formula` — ORDER=I; CHUNK=K; state: per group the FUN's sufficient statistics (sum/count for `sum`, `mean`, `length`; min/max; n/mean/M2 for `var`/`sd`); `H` per group for `median`/`quantile`/`mad` (or `K` over distinct values within each group); notes: verified for `mean`, `median` and `sum`. Output groups are sorted by level index (`ident()` uses `as.factor()` aggregate.R:71, `sort(unique(grp))` aggregate.R:103), not by first appearance. Two `S` traps: (1) FUN receives each group's values in input order (`split(e, grp)` aggregate.R:108), so an order-sensitive FUN (`function(v) v[1]`, `paste`, `head`) is `D` (verified). (2) Numeric `by` values that differ but share `as.character()` (e.g. `0.1+0.2` and `0.3`) collapse into one group, whose printed key is the first occurring row's value (aggregate.R:103; verified). Rows with NA in `by` are dropped (aggregate.R:64), as is the formula method's `na.omit` (row-local). `drop = FALSE` expands the observed level sets, so they must be unioned across chunks. A chunked version needs FUN to be given as a (map, combine, finalize) triple, because R cannot infer decomposability from a closure.
- `stats::ave` — ORDER=E; CHUNK=P; state: pass 1 `K` (per-group FUN state over `interaction(..., drop = TRUE)`, ave.R:24); pass 2 `M` (look up each row's group value); notes: verified E for `FUN = mean`. The common idioms `ave(x, g, FUN = cumsum)` and `ave(x, g, FUN = seq_along)` are `D`: they number rows within a group in input order (verified for `cumsum`). Non-decomposable FUN (median) is `H` per group.
- `stats::free1way` (`.formula`, `.numeric`, `.factor`, `.table`; new in R-devel) — ORDER=I; CHUNK=K; state: `xtabs(w ~ y + groups [+ blocks + event])` over distinct `y` values (free1way.R:1835, 1904); notes: **already chunk-capable by design.** Everything downstream (Newton-Raphson ML, Wald/LRT/Rao, permutation via `r2dtable()` on the margins, free1way.R:1119) reads only the table. Verified: `free1way(y ~ g)` equals `free1way(as.table(sum of chunk tables))`. Results are invariant, also with `B = 200` under a fixed seed and with `nbins = 20`. `nbins > 0` bins `y` at `quantile(y, …)` breaks (free1way.R:1839), which needs an `H` pre-pass (or a sketch, at the cost of exactness). The formula method stores the whole model frame in the result (`RVAL$data <- mf`, free1way.R:1788), so the result itself is O(n). `exact = TRUE` re-expands `rep(z, times = w)` to O(n).
- `stats::chisq.test` — ORDER=I; CHUNK=K; state: two-way count table (`table(factor(x), factor(y))`) or a 1-D count vector; notes: verified, including `simulate.p.value = TRUE` under a fixed seed, because `C_chisq_sim` uses only the margins `sr`, `sc` (chisq.test.R:82). Trap: a data frame `x` is treated as a *count table* via `as.matrix()` (chisq.test.R:25), not cross-tabulated. The goodness-of-fit simulation allocates `sample.int(nx, B*n)` as an n × B matrix (chisq.test.R:125): O(n·B) memory for large n, where `rmultinom(B, n, p)` would be O(k·B) but changes the RNG stream.
- `stats::fisher.test` — ORDER=I; CHUNK=K; state: r × c count table; notes: verified, including a seeded `simulate.p.value` (`C_Fisher_sim(rowSums, colSums)`, fisher.test.R:104). The network algorithm and the conditional MLE/CI for 2×2 work on the table only. A data frame `x` is again taken as a count table (fisher.test.R:31). Levels via `as.factor()` are sorted.
- `stats::mantelhaen.test`, `stats::mcnemar.test` — ORDER=I; CHUNK=K; state: 2×2×K (or I×J×K) table, resp. the paired 2-way table; notes: verified. McNemar's pairs are the two columns of one row, so they are row-local. `exact = TRUE` for 2×2×K needs only the table.
- `stats::wilcox.test.default`, `stats::wilcox.test.formula` — ORDER=I; CHUNK=K; state: two-sample: per distinct `signif(value, digits.rank)` the counts in x and y, giving mid-ranks, W and the tie term; one-sample/`Pair`: per distinct `|d|` the counts of positive, negative and zero; notes: verified (asymptotic with ties, exact, exact and asymptotic `conf.int`, `Pair`). Ranks are taken on `signif(r, digits.rank)` (wilcox.test.R:622, 632), so `digits.rank = 7` bounds the precision. Exact p-values are the default only for n < 50. R-devel 4.6 adds exact permutation p-values with ties/zeros (`.pwilcox(z = midranks)`); the mid-rank vector is reconstructible from the `K` state. Exact `conf.int` needs `sort(outer(x, y, "-"))` (wilcox.test.R:673) or the Walsh averages `outer(x, x, "+")` (wilcox.test.R:272), both O(n²), so `H`. The asymptotic `conf.int` uses `uniroot()` over the shift, re-ranking each time; that can be evaluated from per-group sorted frequency tables (`K`) without touching rows again. The formula method forbids `paired`; use `Pair(x, y) ~ 1`, which is row-local.
- `stats::kruskal.test` — ORDER=I; CHUNK=K; state: (distinct x × group) count table, from which come the mid-ranks, per-group rank sums and the tie term; notes: verified invariant, and the rebuild from `table(x, g)` matched `kruskal.test()` exactly. Rows are `rank(x)` + `table(x)` (kruskal.test.R:57-62), which is `H` when x is continuous (distinct ≈ n). An alternative is `P`: pass 1 `K` (marginal frequency table of x), pass 2 `K` (per-group sums of mid-ranks). Only an asymptotic p-value exists, so nothing exact is lost.
- `stats::mood.test` — ORDER=I; CHUNK=K; state: per distinct pooled value the counts in x and in total; notes: verified. The tie branch already computes T from `u = sort(unique(z))`, `a = tabulate(match(x, u))` and `t = tabulate(match(z, u))` (mood.test.R:44-51), i.e. exactly this state. The no-tie branch (`rank(z)`) is the same with counts of 1, so it is `H` for continuous data.
- `stats::ks.test` (two-sample, default and formula) — ORDER=I; CHUNK=K; state: per distinct pooled value the counts in x and y; D = max |ΔF| at the distinct-value boundaries (ks.test.R:53-57); notes: verified (asymptotic, exact, exact with ties, and `simulate.p.value` under a fixed seed, which is `I` because `rsmirnov()` only uses `table(z)`, ks.test.R:184). The exact default applies only when `n.x*n.y < 10000`. One-sample KS: `y(sort(x)) - (0:(n-1))/n` is `H`, or `K` over distinct values; ties draw a warning.
- `stats::cor` (`method = "spearman"`), `stats::cor.test` (`method = "spearman"`) — ORDER=I; CHUNK=P; state: pass 1 `K` (marginal frequency tables of x and y, giving mid-rank lookups); pass 2 `A` (Pearson moments of (rank x, rank y)); notes: verified invariant, and the two-pass mid-rank rebuild matched `cor(method = "spearman")` exactly. Memory is O(distinct x + distinct y), not distinct pairs. `use = "pairwise.complete.obs"` re-ranks per column pair (cor.R:81-90), so one `K` table per pair. The exact p-value (`C_pRho`, only for n ≤ 1290, cor.test.R:156) needs only (S, n).
- `stats::cor` (`method = "kendall"`), `stats::cor.test` (`method = "kendall"`) — ORDER=I; CHUNK=H; state: —; notes: verified invariant. R 4.5.3 uses an O(n²) sign-pair loop; R-devel switched to Knight's O(n log n) merge sort (src/cov_kendall.c:33-36, 196; doc/NEWS.Rd:250), which is still holistic. Escape hatch: `K` over distinct (x, y) pairs, where concordant and discordant counts come from a 2-D cumulative table. Tie corrections in `cor.test` use only marginal tie tables (`table(x[duplicated(x)])`, cor.test.R:110). The exact `pKendall(q, n)` needs only (q, n) and applies to n < 50 without ties.
- `stats::density.default` (default `bw = "nrd0"`; also `"nrd"`, `"SJ"`) — ORDER=I; CHUNK=H; state: —; notes: verified invariant (default, `bw = "SJ"`, and weights). The default bandwidth needs `IQR(x)` (`bw.nrd0`, bandwidths.R:27), and `"nrd"`/`"SJ"` need quantiles too (bandwidths.R:35, 73), so it is holistic unless the quartiles come from a sketch (which perturbs the bandwidth) or from `K` over distinct values. The rest is cheap: see the next line.
- `stats::density.default` (numeric `bw`, or `bw = "ucv"`/`"bcv"`) — ORDER=I; CHUNK=P; state: pass 1 `A` (finite n, min, max; plus mean/M2 for ucv/bcv); [ucv/bcv: pass 2 `A`, a 1000-bin `tabulate()` on the range grid]; last pass `A`, linear binning `C_BinDist` onto a fixed 2n-point grid [lo, up] = [min − (cut+ext)·bw, max + (cut+ext)·bw] (density.R:140-149, src/massdist.c:34-68); notes: with numeric `bw` and user `from`/`to` it is a single `A` pass. BinDist is additive: the sum of the chunks' BinDist vectors equals the full one (verified). Default weights `1/nx` can be applied after binning. The FFT convolution and `approx()` run on the grid only. `warnWbw = var(weights) > 0` (density.R:27) is another `A` statistic.
- `stats::bw.ucv`, `stats::bw.bcv` — ORDER=I; CHUNK=P; state: pass 1 `A` (min, max, n, var); pass 2 `A` (counts on `nb = 1000` bins of width `diff(range)*1.01/nb`); notes: verified invariant on both the binned path (n = 5000) and the pairwise path (n = 300). For n > nb/2 the code itself bins first (`bw_pair_cnts(binned = TRUE)`, bandwidths.R:41-53) and `optimize()` then runs on bin-pair counts (`C_bw_den_binned`), so the two-pass version is exact. For n ≤ 500, `C_bw_den` is an O(n²) pair loop (src/bandwidths.c:112-151), which does not matter at that size.
- `stats::bw.nrd0`, `stats::bw.nrd`, `stats::bw.SJ` — ORDER=I; CHUNK=H; state: `A` (sd, n, range, bins) plus the quartiles; notes: verified invariant. `IQR`/`quantile` (bandwidths.R:27, 35, 73) are the only holistic part; `bw.SJ` otherwise has the same two-pass binned structure as `bw.ucv`. The `abs(x[1L])` fallback in `bw.nrd0` (bandwidths.R:28) is reached only for constant x, so it is order-free.
- `stats::quantile` (all 9 types), `stats::median`, `stats::fivenum`, `stats::IQR` — ORDER=I; CHUNK=H; state: —; notes: verified invariant. They use `sort(x, partial = …)` (quantile.R:61, 92; median.R:31-32; fivenum.R:26). Escape hatches: (a) `K` over a frequency table of distinct values is exact for every type, since all of them read x[j] and x[j+1] off cumulative counts (type 1 rebuild verified); (b) exact multi-pass selection (`P`: a histogram or sketch brackets the target, then a second pass collects the bracket); (c) t-digest/KLL approximations. An ordered factor (`type` 1 or 3) is `K` over levels.
- `stats::mad` — ORDER=I; CHUNK=H; state: —; notes: verified invariant. `median(abs(x - median(x)))` (mad.R:31) is two nested holistic steps. It is exact with a single `K` frequency table, though: the median comes from the table, and the |x − m| distribution is a re-keying of the same table. With sketches it is a 2-pass approximation.
- `stats::ecdf` — ORDER=I; CHUNK=K; state: sorted distinct values with counts (ecdf.R:25-29, `cumsum(tabulate(match(x, vals)))`); notes: verified invariant, and the rebuild from `table(x)` matched exactly. It is `H` for continuous data; the escape is a sketch or pre-binning.
- `stats::pairwise.t.test`, `stats::pairwise.wilcox.test` [`paired = TRUE`] — ORDER=D; CHUNK=H; state: —; notes: **trap.** `xi <- x[as.integer(g) == i]`, `xj <- x[as.integer(g) == j]` (pairwise.R:52-53, 74-75) pair the k-th observation of group i with the k-th of group j *by position*; there is no block/id argument. Permuting rows changes the p-values (verified with `p.adjust.method = "none"`; Holm saturating at 1 hid it at first). A correct rewrite needs a block key, then `K` keyed by block (as in `friedman.test()`).
- `stats::reshape` [`direction = "wide"`] — ORDER=S; CHUNK=K; state: per id, the wide row (its first-seen constant columns plus one slot per (time, v.name)), and the set of times; notes: verified. Column order follows `times <- unique(data[, timevar])`, i.e. first appearance (reshape.R:140); row order follows `!duplicated(data[, idvar])` (reshape.R:167). Two `D` cases: a duplicated (id, time) takes the first match (`match()`, reshape.R:177; verified: 1 vs 99), and a "constant" variable that actually varies takes the id's first row (reshape.R:167; it only warns; verified). The state is as big as the output, so chunking only helps when the wide result fits in memory. A 2-pass variant fixes the time set (columns) first.
- `stats::reshape` [`direction = "long"`] — ORDER=E; CHUNK=M; state: none, plus a running row offset when ids are positional; notes: each wide row is emitted once per time. Output is time-major (`rbind` over times, reshape.R:97-108), so chunked output comes out chunk-major, i.e. `S`. Without an `idvar` column, `ids = 1L:NROW(data)` (reshape.R:22, 60) becomes the id column and the row names, so ids are row positions (verified: id of the row with a = 30 went 3 → 1 under permutation). `anyDuplicated(ids)` (reshape.R:86) is a global uniqueness check, a `K` set or skipped. `new.row.names` are positional.
- `stats::t.test.default`, `stats::t.test.formula`, `stats::var.test` — ORDER=I; CHUNK=A; state: per group (2 groups, or 1 / paired differences) n, mean, M2 (Welford/Chan merge); notes: verified (formula, `Pair()`, `var.test`). The 2 groups are `factor()` levels, sorted (t.test.R:152), so "x" vs "y" does not depend on first appearance. `var()` is a two-pass long-double computation in C (src/cov.c:206), so a one-pass Chan merge agrees to rounding. The formula method rejects `paired` (t.test.R:133-134); `Pair(x, y) ~ 1` differences are row-local. `var.test` filters `is.finite()` rather than `!is.na()` (var.test.R:43). There is no entry point taking summary statistics, so a chunked version needs a new API.
- `stats::bartlett.test`, `stats::oneway.test` — ORDER=I; CHUNK=K; state: per group n, mean, M2 (bartlett.test.R:53-56; oneway.test.R:44-48), plus the global mean for `var.equal = TRUE`; notes: verified. They are exact under a Chan merge up to rounding. `oneway.test` with several RHS factors uses `interaction()`, still keyed by sorted levels.
- `stats::fligner.test` — ORDER=I; CHUNK=K; state: (distinct x × group) count table; notes: verified. The code needs group medians `tapply(x, g, median)` (fligner.test.R:57), then `rank(abs(x - med))` (fligner.test.R:59), which is holistic twice. From the (x, g) frequency table, though, both are exact in one pass: medians per group, then the |deviation| frequency table and mid-ranks, then per-group score means. Otherwise it is `P` with 3 passes and sketches (approximate).
- `stats::ansari.test` — ORDER=I; CHUNK=K; state: per distinct pooled value the counts in x and y (scores `pmin(r, N - r + 1)` on mid-ranks, ansari.test.R:45-46); notes: verified (asymptotic with ties; exact with `conf.int`; asymptotic `conf.int`). The exact p-value applies only without ties and for m, n < 50. Exact `conf.int` uses `outer(x, y, "/")` (ansari.test.R:75), so `H`. The asymptotic `conf.int` re-ranks `c(x/sig, y)` inside `uniroot()`: `P` with many passes, each `K` over distinct values.
- `stats::friedman.test` (default, formula) — ORDER=I; CHUNK=K; state: keyed by block: buffer the block's k responses until complete, then rank within the block and add to the per-group rank sums and the tie term `A`; notes: verified. Observations are re-sorted by `order(groups, blocks)` (friedman.test.R:42); blocks with an NA are dropped (friedman.test.R:51). Memory is bounded when the data are clustered by block; worst case O(#blocks). Wide matrix input (one row per block) is plain `A` row by row. The `table(groups, blocks) != 1` design check is `K` over cells.
- `stats::quade.test` — ORDER=I; CHUNK=H; state: per block (range, centred within-block ranks), O(#blocks × k); notes: verified invariant. It needs the rank of block ranges across all blocks, `rank(apply(y, 1, max - min))` (quade.test.R:52), so it is holistic over blocks. A 2-pass variant stores only the b ranges and then accumulates the scores (`A`). Unrelated bug: `b <- nlevels(blocks)` (quade.test.R:46) is computed before `complete.cases()` drops blocks with NA (quade.test.R:49). A block with an NA therefore still counts in b: the statistic was 0.7196 vs 0.7171 for the same data with that block removed. `friedman.test()` gets this right.
- `stats::pairwise.t.test`, `stats::pairwise.wilcox.test` [`paired = FALSE`] — ORDER=I; CHUNK=K; state: t: per group n, mean, sd (pooled or not; pairwise.R:32-36); Wilcoxon: (distinct x × group) table, from which each pair's rank sums follow; notes: verified invariant. `levels(g)` are sorted. `p.adjust` acts on the k(k−1)/2 p-values only.
- `stats::TukeyHSD` (`.aov`) — ORDER=I; CHUNK=K; state: after the fit: per-cell means and counts (via `model.tables(x, "means")`, TukeyHSD.R:32) and the MSE from the residual SS (TukeyHSD.R:49); notes: verified. For a one-way model, everything (group n, mean, M2) comes from one `K` pass without any fit. `ordered = TRUE` breaks ties among equal means by level order.
- `stats::model.tables` (`.aov`, `.aovlist`), `stats::replications` — ORDER=I; CHUNK=P; state: pass 1: the fit's QR/effects (the other agent's `lm`/`aov` cross-product state); pass 2: per-row projections (row-local given R and the effects) accumulated as `tapply(..., mean)` cell sums and counts (model.tables.R:215), i.e. `K`; notes: verified (`model.tables(aov(yc ~ g3 * f), "means")`). `replications()` alone is `K` (cell counts, `tapply(dummy, …, length)`, model.tables.R:330). Balanced designs need only the `K` cell means.
- `stats::ftable` (`.default` on a data frame/list, `.formula`) — ORDER=I; CHUNK=K; state: the underlying `table()` counts (ftable.R:30, 157-158); notes: verified for formula and data-frame input. Row/col variables are a reshaping of the `K` state; the same level-alignment caveat as `xtabs` applies.
- `stats::addmargins`, `base::proportions`/`prop.table`, `base::marginSums` — ORDER=I; CHUNK=M; state: none (they act on the already-reduced table); notes: these are post-processors of `K` state with cost O(cells), not O(rows). Only listed for completeness.
- `stats::complete.cases`, `stats::na.omit.data.frame`, `stats::na.exclude.data.frame`, `stats::na.fail` — ORDER=E; CHUNK=M; state: a running row offset; notes: verified E. The `"na.action"` attribute stores *positional* row indices named by row names (`seq(omit)[omit]`, nafns.R:85-86), so a chunked version must add the global row offset (verified: indices 5, 17 became 53, 240 after permuting). `na.fail` is `I` (input or error) and can abort at the first NA.
- `stats::get_all_vars`, `stats::expand.model.frame` — ORDER=E; CHUNK=M; state: none; notes: `get_all_vars` evaluates only the bare `all.vars(formula)` symbols in `data` (models.R:797-798), so no data-dependent transform is involved. `expand.model.frame` re-runs `model.frame()` with extra variables (expand.model.frame.R:40-44). `poly()`/`ns()`/`scale()` in the model formula are then recomputed over the whole new frame (data-dependent basis trap), so a pre-pass is needed for those. `na.expand = TRUE` re-aligns by row names (row-local).
- `stats::weighted.mean`, `stats::var` (single column), `stats::sd` — ORDER=I; CHUNK=A; state: `sum((x*w)[w != 0])`, `sum(w)` (weighted.mean.R:31); n, mean, M2; notes: verified. They agree to rounding (`var` is a long-double two-pass in C).
- `stats::qqnorm` (`.default`), `stats::ppoints`, `stats::qqplot` — ORDER=E; CHUNK=P; state: pass 1 `K` (frequency table of y, giving cumulative counts and n for `ppoints(n)`); pass 2 `M` with per-distinct-value counters; notes: `x <- qnorm(ppoints(n))[order(order(y))]` (qqnorm.R:34) breaks ties *by position*. Output x is therefore not strictly equivariant under ties (verified), although the multiset of (x, y) pairs is invariant (verified). `H` for continuous y. `qqplot(x, y)` sorts both samples: `H`, or `K` over distinct values. `ppoints` takes only n.
- `stats::shapiro.test` — ORDER=I; CHUNK=H; state: —; notes: verified. `sort(x)` feeds the Royston coefficients, and the hard cap is 3 ≤ n ≤ 5000 (shapiro.test.R:25), so out-of-core use does not arise. Subsampling would make it `R`. There is no formula method.
- `stats::prop.test`, `stats::binom.test`, `stats::poisson.test`, `stats::prop.trend.test`, `stats::pairwise.prop.test` — ORDER=I; CHUNK=A; state: per group successes and trials (or event counts and exposure); notes: they take counts, not rows. Building those counts from a data frame is a `K` `xtabs`/`table` pass.
- `stats::p.adjust` — ORDER=E; CHUNK=H; state: — (over the vector of p-values, not data rows); notes: `order(p)` + `cummax`/`cummin` (p.adjust.R) produce equal adjusted values for tied p-values, so the result is equivariant. `bonferroni` is `M` given n. Usually small, so not a chunking target.
- `stats::reorder.default` — ORDER=E; CHUNK=P; state: pass 1 `K` (per-level FUN, e.g. sum/count for `mean`); pass 2 `M` (relevel codes); notes: level order is `sort(scores)` (stable, so ties fall back to the sorted level order; reorder.factor.R:21-23), hence the level set is `I`.
- **verdict**: The most valuable targets are:
  (1) `xtabs()` as a chunk-mergeable `K` reducer feeding the table-only consumers `chisq.test`, `fisher.test`, `mantelhaen.test`, `mcnemar.test`, `prop.test` and `free1way.table`. It needs a level-aligning merge, because the naive `+` silently misaligns.
  (2) `aggregate()`/`ave()` with decomposable FUN given as a (map, combine, finalize) triple.
  (3) The rank-test family (`wilcox`, `kruskal`, `ansari`, `mood`, two-sample `ks`, `fligner`, Spearman) rewritten over (distinct value × group) frequency tables, which is exact `K` and turns `H` into `K` whenever distinct values are bounded (`mood.test()` already uses this form for ties).
  `density()` with numeric `bw` is a cheap exact `P`/`A` win, because `C_BinDist` linear binning is additive.
  Already chunk-capable: `free1way()` (R-devel), which reduces every input to an `xtabs()` and works entirely on it; it accepts a pre-summed table today (verified equal). All table-accepting tests accept pre-aggregated counts.
  Traps: positional pairing in `pairwise.t.test()`/`pairwise.wilcox.test()` with `paired = TRUE` (`D`); `reshape(direction = "wide")` (first-appearance columns, first-match duplicates); `aggregate()`'s first-occurrence key for numerically colliding groups; and the `quade.test()` NA-block bug.

<!-- source: findings/graphics_lattice.md -->
## Part: Findings: graphics, grDevices, grid, lattice

Scope: R 4.5.3 sources under `src/library/{graphics,grDevices,grid}/R` (plus `graphics/src/plot.c`, `graphics/src/stem.c`)
and lattice 0.22-9 (`rec/lattice/R`).
Empirical checks: `scratchpad/gl_work/check_base.R`, `check_lattice.R`, `check_lattice2.R`, `check_ss2.R`.
They compare returned objects (`hist(plot = FALSE)`, `boxplot(plot = FALSE)`, `chull`, `xyTable`, trellis
`x.limits`/`y.limits`/`aspect.ratio`/`packet.sizes`) and rendered 400x400 cairo PNGs pixel by pixel
under a random row permutation.
A "max delta <= 0.008" pixel difference means anti-aliasing rounding only, so it counts as visually invariant.

### Conventions used for plotting functions

- ORDER is assigned to the **rendered result plus the returned value**.
  Statistics that are invariant while only the overdraw z-order follows input order give `S`.
  Row order that changes geometry (connected lines, positions, labels, which value is shown) gives `D`.
- Two senses of "chunkable" are tagged in notes:
  **summary** (prepanel limits, bin counts, box stats: a mergeable state)
  and **drawing** (emitting marks chunk by chunk once a pre-pass has fixed the coordinate system).
  Typical drawing scheme: pass 1 = ranges (`A`), then `plot.new(); plot.window(xlim, ylim)` and `points()` per chunk (`M`).
- Z-order: base graphics draws in row order (last row on top).
  With one colour and no alpha this is visually invariant (only AA rounding: e.g. `plot(y ~ x)` max delta 0.008).
  With per-row `col`/alpha it is a real `S` effect (`plot(y ~ x, col = col)`: 5506 px differ, delta 1.0).
  Chunked drawing in the original row order reproduces it exactly; any other chunk order does not.
- Short graphical-parameter vectors (`col = c("red", "blue")`, `pch = 1:3`) are recycled **by row position**,
  which turns any function into `D`; a full-length per-row column is fine (permutes with rows).
- `type = "l"`/`"b"`/`"o"`/`"c"` connect points in row order (`plot.xy` → `C_plotXY`, plot.R:353-368): `D` everywhere in base graphics.

### graphics

- `graphics::hist.default` — ORDER=I; CHUNK=P; state: pass 1 `n`, `min`, `max` (Sturges/Scott also `sum`, `sum^2`); pass 2 bin counts on fixed breaks (A); notes: summary only (drawing is of the summary). With a fixed `breaks` vector of length >= 4 it is a single `A` pass (counts summed over chunks == full, verified). Sturges needs `n` and `range` before binning (hist.R:59, 82); verified 2-pass chunked Sturges == `hist()`. `breaks = "FD"` needs IQR → `H` (sketch). Trap: with <= 3 breaks the boundary fuzz uses `diff(range(x))` (hist.R:118-120), so even fixed breaks need a range pre-pass; `stop()` if `sum(counts) < n` (hist.R:131) needs `n`. Already summary-then-draw capable: `plot.histogram()` draws a `histogram` object built from merged counts (recompute `density = counts/(n*h)`, hist.R:133).
- `graphics::boxplot.default`, `graphics::boxplot.formula`, `graphics::boxplot.matrix` — ORDER=S; CHUNK=H; state: exact needs all values per group; approximate: per-group quantile sketch (pass 1), then per-group whisker ends = min/max of non-outliers and outlier list (pass 2, A + output-sized); notes: `stats`, `n`, `conf` invariant (verified); `out`/`group` follow input row order (calc.R:41 `x[out & nna]`; verified FALSE unsorted, TRUE sorted). `fivenum` → exact quartiles. Escape: t-digest/KLL, or exact `K` when few distinct values (fivenum from a value-count table), or multi-pass exact selection. Groups via `split(...)` → `K`. Already summary-then-draw capable: `bxp(z)` draws from a precomputed stats list (boxplot.R:136).
- `graphics::spineplot.default`, `graphics::spineplot.formula` — ORDER=D (non-numeric x) / I (numeric or factor x); CHUNK=P; state: pass 1 `n` (or `sum(weights)`) and `range(x)` for Sturges `pretty()` breaks (spineplot.R:122, 133-134); pass 2 `table(cut(x, breaks), y)` (fixed grid × y levels, A); notes: **trap** — for non-numeric x (Date, POSIXct, difftime) the default x-axis labels are `c(xorig[1L], xorig[c(diff(as.numeric(x1)) > 0, TRUE)])` (spineplot.R:149), which assumes x is sorted: unsorted input gives wrong labels or an error (verified: shuffled Date input → `'at' and 'labels' lengths differ, 9 != 81`). Numeric x verified pixel-identical. Factor x → `table(x, y)` `K`.
- `graphics::smoothScatter` — ORDER=D (ties only) / I (image); CHUNK=P; state: pass 1 5%/95% quantiles per axis for the default bandwidth (smooth2d.R:31-34, H → sketch; skip if `bandwidth` given) plus `min`/`max` (for `xlim` and `bkde2D`'s default `range.x` = range ± 1.5h); pass 2 `linbin2D` counts on a fixed `nbin`×`nbin` grid + `n` (A), FFT smoothing at finish; pass 3 bottom-`nrpoints` by density (bounded heap, A); notes: image verified invariant. The `nrpoints` outlier dots use `order(dens[...])[seq_len(nrpoints)]` (smoothScatter.R:83), so ties (several points in the same grid cell at the cut-off) are broken by row order (verified with a constructed 2-point tie: different point drawn). Supplying `xlim`/`ylim` filters rows first (M).
- `graphics::sunflowerplot.default`, `graphics::sunflowerplot.formula` — ORDER=I; CHUNK=K; state: counts per distinct `(signif(x, 6), signif(y, 6))` pair (via `xyTable`), plus range for limits; notes: even `rotate = TRUE` is invariant, because `runif()` is drawn once per *distinct sorted* pair (sunflowerplot.R:78-79), not per row (verified pixel-identical with a fixed seed). Already summary-capable: accepts a `list(x, y, number)` as from `xyTable()` (sunflowerplot.R:32-38), so merged chunk counts can be passed directly.
- `graphics::mosaicplot.formula` — ORDER=I; CHUNK=K; state: `table(mf)` cell counts (mosaicplot.R:411); notes: verified pixel-identical. Level sets must be known/declared (pre-pass or `factor(levels=)`); `na.action = na.omit` is row-local. `mosaicplot.default` itself takes a table.
- `graphics::cdplot.default`, `graphics::cdplot.formula` — ORDER=I; CHUNK=P; state: pass 1 `n`, `var`, IQR (bw.nrd0 → H, sketch) and `range` → grid `from - 4bw .. to + 4bw`; pass 2 per-y-level linear-binned counts on that fixed grid (K levels × A grid) plus level totals; notes: unconditional `density()` fixes `bw` and grid (cdplot.R:89-93), per-level `density()` reuses them (cdplot.R:106-111). With numeric `bw` and `from`/`to` it is one `A` pass. Verified pixel-identical.
- `graphics::barplot.formula` — ORDER=S (cbind LHS) / I (single LHS); CHUNK=K; state: `xtabs` cells; notes: single LHS goes through `xtabs()` (barplot.R:257), so bars are in level order (verified identical). With `cbind()` LHS the bars are columns of `t(mf[[1L]])` in **row order** (barplot.R:249-251; verified 40k px differ). `anyDuplicated(mf[-1L])` check (barplot.R:240) needs the global key set (`K`). Not an aggregator: duplicated cells are an error.
- `graphics::plot.design` — ORDER=I; CHUNK=K; state: per factor, per level `sum` and `count` for the default `fun = mean`, plus overall mean; notes: `tapply(y, xc, fun)` per factor (plot.design.R:40). Exact `K` only for decomposable `fun`; `fun = median` → `H`. Verified pixel-identical.
- `graphics::coplot` — ORDER=S; CHUNK=P; state: pass 1 `co.intervals` for numeric givens (H) or factor levels (K), plus `range(x)`, `range(y)` (coplot.R:226-229, A); pass 2 draw each row into every panel whose interval contains it (M); notes: overlapping shingles mean one row lands in several panels (fine for M). With `given.values` supplied the intervals are fixed and only ranges are needed. The `panel.smooth` option uses `lowess` → `H`. Rendering verified identical up to AA.
- `graphics::co.intervals` — ORDER=I; CHUNK=H; state: sorted values; notes: sorts and takes order statistics at `round(1 + ii)` and `round(r + ii)` (coplot.R:21-27); `eps` = half the minimum positive gap between sorted values (coplot.R:33-34), which no bounded sketch gives exactly. Escape: quantile sketch for endpoints, `K` when few distinct values.
- `graphics::plot.formula`, `graphics::plot.data.frame`, `graphics::pairs.default`, `graphics::pairs.formula` — ORDER=S; CHUNK=P; state: pass 1 per-column `min`/`max` (A); pass 2 draw points chunk by chunk (M); notes: drawing-chunkable; statistics are just ranges. `plot.data.frame` dispatches: 1 numeric column → `stripchart`, 1 non-numeric → `plot(x1)`, 2 → `plot(x[[1]], x[[2]])`, >= 3 → `pairs(data.matrix(x))` (plot.R:409-419). Traps: `plot(y ~ 1)` and a 1-column non-numeric frame fall back to an **index plot** (x = row number, plot.R:224 + xyz.coords.R:95-99) → `D`. `type = "l"` → `D` (verified 11k px differ). `pairs` panel functions like `panel.smooth` add `H`.
- `graphics::points.formula`, `graphics::text.formula` — ORDER=S; CHUNK=M; state: none (draws into the existing coordinate system); notes: the ideal chunk-wise drawers: per-row marks on an already set-up plot, no pre-pass needed. Only z-order (and `text` label overlap) follows row order. `subset` and `...` vectors are row-local (plot.R:284-295).
- `graphics::lines.formula` — ORDER=D; CHUNK=A; state: the last row of the previous chunk (to join the polyline across the chunk boundary); notes: connects points in row order (plot.R:266). Streamable only in the given order, not order-free.
- `graphics::stripchart.default`, `graphics::stripchart.formula` — ORDER=S (overplot) / I (stack) / R (jitter); CHUNK=P; state: pass 1 `range` of all values (stripchart.R:49); pass 2 draw (M); `method = "stack"` keeps per-distinct-value running counts (K); notes: `"stack"` offsets depend only on duplicate counts per value (stripchart.R:88-93) → verified pixel-identical. `"jitter"` draws `runif()` per row (stripchart.R:87) → `R` (verified differ). Groups via `split()` → `K`.
- `graphics::symbols` — ORDER=S; CHUNK=P; state: pass 1 `extendrange(x)`, `extendrange(y)` (symbols.R:69-72) and, for `inches > 0` (default), the global maximum of the size variable (`SymbolRange` → `pmax`, plot.c:3778-3786); pass 2 draw (M); notes: symbol scaling is a hidden global (max size), not just the axis range.
- `graphics::matplot`, `graphics::matpoints`, `graphics::matlines` — ORDER=D (missing x or type "l"/"b") / S (explicit x, type "p"); CHUNK=P; state: ranges (A) then draw (M); notes: `matplot(df)` with one argument uses `x <- seq_len(NROW(y))` (matplot.R:47-52), i.e. row index → `D` (verified 18k px differ). `matlines` defaults to `type = "l"` → `D`.
- `graphics::dotchart` — ORDER=S; CHUNK=P; state: `range(x)` and label widths (pass 1), then draw; notes: one line per input element at y = position (dotchart.R:81-84); with `groups` rows are stably sorted by group, so within-group order is row order (dotchart.R:87-94). Verified differ. A presentation of already-summarised rows, not an aggregator.
- `graphics::stars` — ORDER=S; CHUNK=P; state: per-column `min` and `range` for `scale = TRUE` (stars.R:97-99, A); then one glyph per row (M); notes: default `locations` lay glyphs out on a grid **by row index** (stars.R:56), so the layout follows row order (verified differ).
- `graphics::plot.factor` — ORDER=I/S; CHUNK=K/H; state: no `y` → `barplot(table(x))` (K); factor `y` → `spineplot` (K); numeric `y` → `boxplot(y ~ x)` (H); notes: dispatcher (plot.R:94-116).
- `graphics::stem` — ORDER=I; CHUNK=P; state: pass 1 `n`, `min`, `max` (line width and scale, stem.c:63, 73-76); pass 2 counts per (stem, leaf digit) on the now-fixed layout (A); notes: C code sorts (`R_rsort`, stem.c:63), but output depends only on counts per rounded leaf.
- `graphics::assocplot`, `graphics::fourfoldplot`, `graphics::mosaicplot.default`, `graphics::spineplot.default` (table input) — ORDER=I; CHUNK=K; state: contingency table; notes: take tables/arrays, not data frames; the chunkable part is the upstream `table()`/`xtabs()`.
- `graphics::hist.Date`, `graphics::hist.POSIXt` — ORDER=I; CHUNK=P; state: pass 1 `range` (and `n`) to choose `breaks = "months"` etc. (datetime.R:162-196); pass 2 bin counts (A); notes: same as `hist.default`.
- **verdict**: best targets are `hist` (2-pass `A`, already has `plot.histogram()` for merged counts), `boxplot` (sketch-based stats fed to the existing `bxp()`), and the scatter family (`plot.formula`/`pairs`/`points.formula`: range pre-pass + chunked `points()`); `smoothScatter` is a clean 3-pass rewrite (sketch → fixed-grid `linbin2D` → bottom-k). Already chunk-capable in the summary-then-draw sense: `plot.histogram()`, `bxp()`, `sunflowerplot(list(x, y, number))`, table-input `mosaicplot`/`spineplot`/`assocplot`/`fourfoldplot`/`barplot`, and drawing via `plot.new(); plot.window(); points()/text()` per chunk. Order traps: `spineplot` with non-numeric x (errors on unsorted input), `barplot(cbind(...) ~ k)`, `matplot(df)`/`plot(y ~ 1)` index plots, `smoothScatter` `nrpoints` ties.

### grDevices

- `grDevices::chull` — ORDER=S; CHUNK=A; state: current hull vertices (size O(h), mergeable: hull of union = hull of per-chunk hulls); notes: returns **row indices** of hull vertices, so indices change under permutation while the vertex set is invariant (verified). Merge of 5 chunk hulls == full hull as point sets (verified). Which duplicate of a repeated vertex is reported depends on order.
- `grDevices::boxplot.stats` — ORDER=S; CHUNK=H; state: exact needs all values; notes: `fivenum` (calc.R:28) → exact quartiles; `out` keeps input order (calc.R:41); whisker ends are `range(x[!out])` (calc.R:37), which is `A` once the fences are fixed. Escape: quantile sketch pass, then a fence pass (A); exact `K` for low-cardinality data.
- `grDevices::xyTable` — ORDER=I; CHUNK=K; state: count per distinct `(signif(x), signif(y))` pair; notes: `order(x, y)` then run-length counts (calc.R:131-139); output sorted by key. Chunk merge (sum counts by key) == full (verified). Note `digits` has no default here (`sunflowerplot` passes 6).
- `grDevices::densCols` — ORDER=E; CHUNK=P; state: pass 1 axis quantiles for the default bandwidth (H → sketch) and ranges; pass 2 `bkde2D` fixed-grid binned counts (A); pass 3 per-row density lookup and the range of per-row densities for `cut(dens, length(dens))` (smooth2d.R:72, A); pass 4 per-row colour (M); notes: per-row output permutes with input (verified).
- `grDevices::nclass.Sturges`, `grDevices::nclass.scott`, `grDevices::extendrange` — ORDER=I; CHUNK=A; state: `n` / `n, sum, sum^2, min, max` / `min, max`; notes: calc.R:94-100, utils.R:44-51. `nclass.scott` uses `var` (Welford/Chan).
- `grDevices::nclass.FD` — ORDER=I; CHUNK=H; state: exact IQR; notes: `IQR(signif(x, 5))`, with a fallback loop over tail quantiles when IQR is 0 (calc.R:104-110). Sketch escape.
- `grDevices::xy.coords`, `grDevices::xyz.coords` — ORDER=E; CHUNK=M; state: none; notes: row-local coercion. Traps: a 1-column data frame/matrix or a bare vector yields `x = seq_along(y)` (xyz.coords.R:61-67, 95-99), i.e. row index → `D`; a data frame with >= 3 columns silently uses only the first two.
- `grDevices::axisTicks`, `pretty` (as used for axes) — ORDER=I; CHUNK=A; state: the range only; notes: take `usr`/range (calc.R:146-150), so a range pre-pass suffices.
- **verdict**: `chull` (exact `A` with a mergeable hull, only the index output is `S`), `xyTable` (`K`), and `boxplot.stats` (the `H` core behind `boxplot`/`bwplot`; make it accept a sketch). Nothing here is chunk-capable today.

### grid

- **verdict**: no grid function accepts a data frame or aggregates rows (the only `as.data.frame` uses are internal coordinate splitting in coords.R:421-517). Out of scope.

### lattice

- `lattice::xyplot` (formula / data.frame methods) with `panel.xyplot` — ORDER=S (type "p") / D (type "l", "b", "o"; "s"/"S" on ties); CHUNK=P; state: pass 1 per-packet `min`/`max` of x and y (`scale_limits` = `range`, miscellaneous.R:145-150) and packet sizes (K over conditioning cells); pass 2 per-chunk panel drawing into fixed panels (M); notes: **summary** (limits, packet sizes) verified invariant. **Drawing:** type "l" draws in row order (xyplot.R:149-151, verified 16k px differ); "s"/"S" sort by x (xyplot.R:167, 182) but ties keep row order (verified 1.6k px differ on rounded data); "a" → `panel.average` (K), "r" → `lm` (A), "smooth" → `loess` (H); all three verified identical. Groups are drawn level by level (panel.superpose.R:89, 111), so the between-group z-order is deterministic and within-group follows rows. Architectural obstacle: the trellis object stores the data per packet (`panel.args[[i]] <- list(x = x[id], y = y[id])`, xyplot.R:416-417) and panels run at `print()` time. A practical chunked route already exists: print a skeleton with fixed `xlim`/`ylim`, then `trellis.focus("panel", i, j)` + `panel.points()` per chunk.
- `lattice::xyplot(aspect = "xy")`, `lattice::banking` — ORDER=D (ties in x) / I (no ties); CHUNK=H; state: all x-sorted successive differences; notes: **trap** — `prepanel.default.xyplot` returns `dx`, `dy` as diffs of the x-**sorted** data (xyplot.R:30-48), and `order()` breaks ties in x by row order, so the `dy` sequence and hence `banking()` = `median(abs(dx/dy))` (common.R:415-428; the default `lattice.getOption("banking")`) depend on row order. Verified: 20 permutations of rounded data give 8–10 distinct aspect ratios (0.095–0.177); untied data give 1. Median → `H` anyway.
- `lattice::levelplot`, `lattice::contourplot` (formula / data.frame) with `panel.levelplot` — ORDER=D (duplicated (x,y) cells or `region.type = "contour"`) / I (complete grid, unique cells); CHUNK=K; state: pass 1 `range(z)` for `at` (levelplot.R:719-724, A) plus sorted unique x and y values (K); pass 2 z per (x, y) cell (K, grid-sized); notes: **traps** — (1) `region.type = "contour"` builds `matrix(z, length(cx))` (levelplot.R:268) straight from data order, assuming rows are in grid order (verified 66k px differ under permutation of a complete grid); (2) `contourplot`/`contour = TRUE` fills `m[...] <- z` (levelplot.R:314-315) so with duplicated (x, y) the **last row wins** (verified 8.7k px differ); (3) default `panel.levelplot` draws one rectangle per row, so duplicated cells show the last-drawn z (verified 11.8k px differ). Complete grid without duplicates verified identical. Already summary-capable: `levelplot.table`/`levelplot.matrix` accept a pre-aggregated grid.
- `lattice::parallelplot` (`panel.parallel`) — ORDER=D; CHUNK=P; state: pass 1 per-variable `min`/`max` over **all** rows (default `lower`/`upper`, parallel.R:47-48, A); pass 2 one polyline per row (M); notes: **trap** — without `groups`, the default `col = superpose.line$col` (7 colours, parallel.R:44) is recycled over rows **by position** (parallel.R:61), so each row's colour depends on its position (verified 51k px differ even with "single colour"). With `groups` the z-order is still row order (verified 33k px differ).
- `lattice::bwplot` with `panel.bwplot` — ORDER=I; CHUNK=H; state: exact per-level values; approximate: per-level quantile sketch then fence pass (A); notes: `tapply(x, factor(y, levels = levels.fos), stats, ...)` (bwplot.R:515-519) with `levels.fos` sorted (bwplot.R:492); verified pixel-identical. Prepanel limits are ranges (bwplot.R:56, 71, A). Hook: `panel.bwplot(stats = boxplot.stats)` (bwplot.R:493) lets a sketch-based stats function be plugged in, though the panel still receives all rows.
- `lattice::histogram` (`prepanel.default.histogram`, `panel.histogram`) — ORDER=I; CHUNK=P; state: pass 1 global `n`, `min`, `max` → common breaks `do.breaks(extend.limits(range), round(log2(n) + 1))` (histogram.R:198-200, 317-323); pass 2 per-packet bin counts on those breaks (K packets × A bins); notes: verified identical, also with `breaks = NULL` (per-panel breaks: per-packet range pre-pass). `equal.widths = FALSE` → `quantile()` breaks (histogram.R:64) → `H`. Uses `hist()`, so the <= 3-break range-fuzz caveat applies.
- `lattice::densityplot` (`prepanel.default.densityplot`, `panel.densityplot`) — ORDER=R (default) / I (`plot.points = FALSE`/`"rug"`/`TRUE`); CHUNK=P; state: pass 1 `n`, `var`, IQR (bw.nrd0 → H, sketch) and `range`; pass 2 linear-binned counts on the fixed `density()` grid (A per packet/group); notes: default `plot.points = "jitter"` (densityplot.R:94) draws `jitter(rep(0, n))` per row (densityplot.R:155-156) → `R` (verified differ with fixed seed); without jitter verified identical. Prepanel also takes `quantile(x, c(.15, .85))` (densityplot.R:45-47) only for banking. The density is computed twice (prepanel and panel), i.e. it is already a 2-pass design.
- `lattice::qqmath` (`prepanel.default.qqmath`, `panel.qqmath`) — ORDER=I; CHUNK=H; state: exact needs `sort(x)`; notes: `sort(x)` or `quantile(x, f.value)` (qqmath.R:53-63, 117-118, 139-142); verified identical. **Limits are cheap:** xlim depends only on `n` (`distribution(ppoints(n))`, qqmath.R:43) and ylim is `range(x)` → `A`. With fixed `f.value` the panel is a natural sketch target; `tails.n` exact tails need only top-k/bottom-k heaps (A).
- `lattice::qq` — ORDER=I; CHUNK=H; state: both samples' sorted values; notes: `quantile()` of each level at `ppoints(max(n1, n2), a = 1)` (qq.R:242-256) at object construction. Sketch escape (two sketches + counts).
- `lattice::cloud` (`panel.cloud`, `panel.3dscatter`) — ORDER=I (points; ties in depth excepted) / D (type "l"); CHUNK=H (drawing) / P (limits); state: limits = ranges (A); drawing needs a global back-to-front sort by projected depth; notes: points are drawn in `sort.list(m[3,])` depth order (cloud.R:207-209), so z-order is order-free except exact depth ties (verified: only 366 px differ, from duplicated points with different colours). Chunked drawing breaks the painter's order across chunks; escape: depth-bucket pass after a range pre-pass (P with K/A buckets). Type "l" joins rows in data order (cloud.R:245) → `D` (verified).
- `lattice::wireframe` — ORDER=I (complete grid) / D (duplicated cells); CHUNK=K; state: z per (x, y) grid cell, sorted unique x and y; notes: complete grids are re-ordered with `order(x, y)` (cloud.R:1068-1074; verified identical); incomplete grids fill `tmp[(idx - 1) * length(uy) + idy] <- z` (cloud.R:1092), so the last duplicate wins.
- `lattice::panel.smoothScatter` — ORDER=D (ties only) / I (image); CHUNK=P; state: as `graphics::smoothScatter` (quantile-bandwidth pass (H → sketch) + range; `bkde2D` fixed-grid counts (A); bottom-`nrpoints` heap (A)); notes: `order(idens)[1:nrpoints]` (panel.smoothscatter.R:103) breaks density ties by row order. Verified identical on generic data.
- `lattice::panel.average`, `lattice::panel.linejoin` — ORDER=I; CHUNK=K; state: per distinct x (or y): `sum` and `count` for the default `fun = mean`; notes: `vals <- unique(sort(x))` then `fun(y[x == vals[i]])` (panels.R:482-496): exact `K` for decomposable `fun`, `H` otherwise; verified identical (`type = "a"`).
- `lattice::panel.lmline`, `lattice::prepanel.lmline` — ORDER=I; CHUNK=A; state: 2×2 `X'X`, `X'y`, plus `range(x)`; notes: `lm(y ~ x)` (panels.R:424-457); verified identical.
- `lattice::panel.loess`, `lattice::prepanel.loess` — ORDER=I; CHUNK=H; state: all (x, y); notes: `loess.smooth` (panel.smooth.R:23-67), local regression. Escape: pre-bin x onto a fixed grid with weights. Verified identical.
- `lattice::panel.violin` — ORDER=I; CHUNK=P; state: per level: pass 1 `n`, `sd`, IQR (H → sketch) and range; pass 2 binned counts on the fixed `density()` grid (K × A); notes: `split(x, factor(y))` + `density()` per level (bwplot.R:806-829); verified identical.
- `lattice::barchart`, `lattice::panel.barchart` — ORDER=S; CHUNK=M (drawing) / K (`stack = TRUE` limits); state: stacked limits = per-level positive and negative sums (`stackedRange`, bwplot.R:22-32); notes: **not an aggregator** — duplicated category rows are overplotted, not summed (verified 94 px differ with a duplicated level); stacked segments within a bar are ordered by group with a stable sort, so duplicates stack in row order (bwplot.R:185-201). Feed it `xtabs()` output (`barchart.table`) instead.
- `lattice::dotplot`, `lattice::stripplot` — ORDER=S (R with `jitter.data = TRUE`); CHUNK=P; state: ranges and factor levels (A/K) then points (M); notes: verified identical up to AA without jitter; `jitter.data = TRUE` uses `jitter()` per row (bwplot.R:462-467) → `R` (verified differ).
- `lattice::splom` (`panel.pairs`) — ORDER=S; CHUNK=P; state: per-variable `scale_limits` (range or levels, splom.R:137, A); then points per chunk (M); notes: verified identical up to AA.
- `lattice::equal.count` — ORDER=I; CHUNK=H; state: sorted values; notes: wraps `graphics::co.intervals` (shingle.R:57-64); verified levels identical. Sketch escape.
- `lattice::shingle`, `lattice::as.shingle` (numeric conditioning variables) — ORDER=I; CHUNK=K; state: `sort(unique(x))` (shingle.R:69); notes: numeric `| x` conditioning is silently turned into one packet per distinct value (`as.factorOrShingle`, miscellaneous.R:130-138) → `K` pre-pass whose size grows with distinct values. Packet membership is then row-local (`compute.packet`, common.R:765-783).
- `lattice::make.groups` — ORDER=E; CHUNK=M; state: none (label each chunk with its source name); notes: `rbind` plus a `which` factor (make.groups.R:35-46). Output row order follows input.
- `lattice::oneway` — ORDER=E (fitted/residuals) / I (location, spread); CHUNK=P; state: pass 1 per-level `sum`, `sum^2`, `n` (K) for the default `mean`/`sd`; pass 2 per-row residuals (M); notes: `tapply` (miscellaneous.R:101-106); a median location would be `H`.
- **verdict**: most valuable are `histogram` (2-pass `A`/`K`, the prepanel/panel split already mirrors the passes), `bwplot` (plug a sketch into the existing `panel.bwplot(stats =)` hook) and `xyplot`-family drawing (ranges per packet, then `trellis.focus()` + `panel.points()` per chunk, which already works today). Trellis objects otherwise hold all rows. Order traps to fix or document: `parallelplot` positional colour recycling, `levelplot(region.type = "contour")` grid-order assumption, last-row-wins for duplicated cells in `levelplot`/`contourplot`/`wireframe`, `aspect = "xy"` banking with tied x, and `densityplot`'s default jittered points (`R`).

<!-- source: findings/rec_mass_etc.md -->
## Part: Findings: MASS, nnet, class, boot, spatial, KernSmooth

Scope: recommended packages MASS 7.3-65, nnet 7.3-20, class 7.3-23, boot 1.3-32, spatial 7.3-18, KernSmooth 2.23-26 (R code in `rec/<pkg>/R`).
C/Fortran citations refer to the current CRAN tarballs (MASS 7.3-66, class 7.3-24, nnet 7.3-21, spatial 7.3-19, KernSmooth 2.23-27), extracted to `csrc/<pkg>/src`.
Every behavioural claim marked "verified" was tested in R 4.5.3 against the installed packages by permuting rows with a fixed seed and comparing with `all.equal()`.
The test scripts are in `rec_mass_tests/t1.R` … `t7.R`, `som.R` and `vg.R`.

Cross-cutting observations:

- Every hard class prediction in these packages (`predict.lda`, `predict.qda`, `lda(CV=TRUE)`, `qda(CV=TRUE)`, `predict.polr`, `predict.nnet`, `predict.multinom`) goes through `max.col()` with its default `ties.method = "random"`.
  R's `R_max_col` treats entries within a relative 1e-5 of the row maximum as ties and draws `unif_rand()` only for those rows (`src/appl/maxcol.c:64-76`).
  So class labels are `E` except near-tied rows, which are `R`, and the RNG stream depends on how many tied rows came earlier.
  A chunked rewrite should use `ties.method = "first"` or a per-row hash.
- Several fitters keep n-length per-row outputs (`fitted`, `residuals`, `w`, `x`, `model`), so a chunked fit needs a final `M` pass, or these components have to be dropped.

### MASS

- **verdict**: the best exact targets are `lda`/`qda`, which become `K` (per-group count, sum and SSCP; the SVD of the n×p residual matrix becomes an eigendecomposition of the pooled p×p matrix), `lm.ridge`, which is a single `A` pass, and `glm.nb`/`polr`/`fitdistr`, which become `P` with `A` passes. `ucv`/`bcv` also chunk exactly in 2 passes, as an O(n + nb²) replacement for the current O(n²) loop. `kde2d` with given `h`/`lims` is a single `A` pass. The holistic ones are `rlm` (MAD scale), `lqs`/`cov.rob`, `isoMDS`/`sammon` and `width.SJ`/`bandwidth.nrd` (IQR). Nothing in MASS is already chunk-capable. The closest is `negative.binomial(theta)`, a row-local family usable with `biglm::bigglm` when theta is fixed. Bugs found along the way are listed under `lqs`, `loglm`, `write.matrix` and `ucv`.
- `MASS::lda` (`lda.formula`, `lda.data.frame`, `lda.matrix`, `lda.default`; `method = "moment"/"mle"`) — ORDER=I; CHUNK=K; state: per group the count, the column sums and the p×p SSCP (Chan-merged), or the group sums plus one pooled within-group SSCP; notes: `f1 <- sqrt(diag(var(x - group.means[g, ])))` (`lda.R:113`) is the pooled within-group SS/(n-1). The SVD of the scaled n×p residual matrix (`lda.R:155-156`) needs only its right singular vectors and singular values, which come exactly from an eigendecomposition of p×p W; this matters numerically only near collinearity. The between-group SVD acts on the ng×p means. Verified invariant, including `|scaling|`. Factor trap: `as.factor(grouping)` uses sorted levels and drops empty groups with a warning (`lda.R:94-103`); predictor levels come from `model.frame` without `drop.unused.levels`, so an unused level gives a constant column and an error.
- `MASS::lda` (`CV = TRUE`) — ORDER=E; CHUNK=P; state: pass 1 is the `K` state above, pass 2 maps each row to its leave-one-out posterior; notes: verified row-equivariant. Trap: posteriors are normalized by the *global* `min(dist)` over all rows and groups (`lda.R:185`), while `predict.lda` uses the per-row minimum (`lda.R:266`). One far-out row therefore underflows to an all-`NaN` posterior, and its class then comes from `max.col` random ties (verified on iris plus one outlier). A chunked version should normalize per row, which is also more correct.
- `MASS::lda` (`method = "t"`) / `MASS::qda` (`method = "t"`) — ORDER=I; CHUNK=P; state: per iteration, weighted group sums, the sum of weights and the weighted SSCP; the weights are recomputed per row from the previous (means, scaling), and the convergence test `all(abs(w - w0) < 1e-2)` is a running max; notes: one pass per iteration. `lda.R:142` leaves a debugging `print(summary(w))` in production code, so every iteration prints quantiles (verified); it is cosmetic, but holistic if kept.
- `MASS::lda`/`MASS::qda` (`method = "mve"`) — ORDER=R; CHUNK=H; state: none (it calls `cov.rob`/`cov.mve`); notes: see `cov.rob`.
- `MASS::qda` (all front-ends, `method = "moment"/"mle"`) — ORDER=I; CHUNK=K; state: per group the count, the mean and either the p×p SSCP or an incremental Givens R factor; notes: the per-group `qr()` of the centred rows (`qda.R:135-141`) is unique only up to the signs of the rows of R. Verified: under permutation `scaling` flips column signs, while `|scaling|`, `ldet` and the posteriors are identical. A chunked version should fix signs, for example with a positive diagonal as from a Cholesky factorization. `CV = TRUE` is `E`/`P` as for `lda`, with the same global-min normalization (`qda.R:161`).
- `MASS::predict.lda`, `MASS::predict.qda` — ORDER=E; CHUNK=M; state: the fitted object; notes: `xlev = object$xlevels` fixes the factor levels. Class labels are `R` on near-ties because of `max.col` (`lda.R:288`, `qda.R:294`). Only `predict.qda(method = "looCV")` needs the training data.
- `MASS::glm.nb` — ORDER=I; CHUNK=P; state: per IRLS pass X'WX and X'Wz (p×p plus p); per `theta.ml` Newton step two scalar sums (score, info); one log-likelihood sum per outer iteration; notes: an outer alternation of at most `maxit` steps, each running a full `glm.fitter` IRLS (`negbin.R:146`) plus up to 10 `theta.ml` passes, so the total is roughly tens of passes. `etastart = eta` is per-row state but is recomputable from beta. `mf$drop.unused.levels <- TRUE` (`negbin.R:96`) is a factor-level trap and needs a levels pre-pass. Verified invariant. Prior art for fixed theta: `biglm::bigglm(family = MASS::negative.binomial(theta))`.
- `MASS::polr` — ORDER=I; CHUNK=P; state: start values from a binomial `glm.fit` IRLS (`polr.R:54-61`); then each BFGS `fmin`/`gmin` evaluation is one pass accumulating `-sum(wt*log(pr))` plus a (p+q)-vector gradient plus `all(pr > 0)` (`polr.R:338-371`); notes: typically 30–100 passes. `Hess = TRUE` adds the finite-difference `optimhess` gradient passes. The response levels set q, so empty response levels are a factor trap. Verified invariant.
- `MASS::predict.polr`, `MASS::predict.rlm`, `MASS::predict.lqs`, `MASS::predict.glmmPQL`, `MASS::predict.mca` — ORDER=E; CHUNK=M; state: the fitted object; notes: `predict.polr(type = "class")` uses `max.col`, so ties are `R`. `predict.glmmPQL` at level ≥ 1 needs the per-group random effects (`K`, from the fit).
- `MASS::lm.ridge` — ORDER=I; CHUNK=A; state: n, `colSums(X)`, `sum(Y)`, X'X, X'Y, Y'Y (centred via Chan); notes: one pass. `Xscale`, the SVD (eigendecomposition of the scaled X'X), `lscoef`, `HKB`, `LW` and `GCV` (`lm.ridge.R:32-56`) all follow from these moments exactly. Verified invariant. This is one of the cleanest targets.
- `MASS::fitdistr` — ORDER=I; CHUNK=P; state: for the closed forms (normal, log-normal, Poisson, exponential, geometric) n, Σx and Σx² (on `log x` for the log-normal) plus Σ`lgamma(x+1)` for the Poisson log-likelihood, which is a single `A` pass when the log-likelihood is computed analytically and 2 passes as coded; otherwise each `optim` evaluation is one pass of `-sum(log f(x_i))`; notes: Weibull, gamma and negative-binomial starts come from mean/var (an `A` pre-pass). Cauchy, logistic and t starts use `median(x)` and `IQR(x)` (`fitdistr.R:154,158`), which is `H` for the start only and avoided by passing `start=`. `hessian = TRUE` (`fitdistr.R:183`) adds the finite-difference passes. Verified invariant. It takes a vector, not a data frame.
- `MASS::rlm` (`rlm.formula`, `rlm.default`; default `scale.est = "MAD"`) — ORDER=I; CHUNK=H; state: per IRLS iteration a weighted X'WX/X'Wy (`A`) plus `median(abs(resid))` (exact median, `rlm.R:175`); notes: the MAD makes every iteration holistic, and a quantile sketch is the escape. The convergence test `irls.delta` on the full residual vector (`rlm.R:189`) is `A`, since old residuals can be recomputed from the old coefficients. `wt.method = "case"` uses a sort-based `wmad` (`rlm.R:80-86`, `H`). Verified invariant.
- `MASS::rlm` (`scale.est = "Huber"`, proposal 2) — ORDER=I; CHUNK=P; state: per iteration X'WX, X'Wy and `sum(pmin(r^2, (k2*s)^2))` (`rlm.R:177`); notes: only the initial `mad(resid, 0)` (`rlm.R:170`) is holistic, and it is just a start value of the fixed-point iteration, so a sketch or a pre-pass suffices. Verified invariant.
- `MASS::rlm` (`method = "MM"`) — ORDER=R; CHUNK=H; state: none; notes: it starts from an `lqs(method = "S")` fit, which uses random subsets. Verified: same seed and permuted rows differ at 1e-7, because the final IWLS reconverges.
- `MASS::lqs` / `lmsreg` / `ltsreg` (`lqs.formula`, `lqs.default`) — ORDER=R; CHUNK=H; state: none; notes: it uses random p-subsets when `choose(n, p) >= 5000` (`lqs.R:107,117`), but exhaustive enumeration (and so `I`, verified for n=21) below that. Each subset's criterion is a quantile or trimmed sum of all n squared residuals (`H`). Verified `R` for n=300. Bug: with `method = "S"` the refined coefficients are stored as `z$coefficents` (typo, `lqs.R:164`). `coef()` therefore returns the pre-refinement estimate, while `fitted.values`/`residuals` are post-refinement (verified: the max |fitted - X coef| is 0.21).
- `MASS::cov.rob` / `cov.mve` / `cov.mcd` — ORDER=R; CHUNK=H; state: none; notes: column `IQR` scaling (`lqs.R:218`), random subsets in C, then `quantile(dist, qn/n)` of the Mahalanobis distances (`lqs.R:264`). Verified `R`. `method = "classical"` is `colMeans` plus `var` (ORDER=I; CHUNK=A).
- `MASS::cov.trob` — ORDER=I; CHUNK=P; state: per iteration Σw, Σw·x, the weighted SSCP about the current location, and max|w − w0| (the weights are recomputable from the previous loc/scatter); notes: the SVD of `sqrt(w/sum(w)) * X` (`cov.trob.R:52`) is equivalent to an eigendecomposition of the p×p weighted SSCP. The final checks `mean(w)` and `mean(w*Q)` are `A`. Verified invariant.
- `MASS::boxcox` (`formula`, `lm`, `default`) — ORDER=I; CHUNK=P; state: pass 1 is n, Σlog y and X'X (or an R factor); pass 2 is, for each of the m λ values, X'y_λ and y_λ'y_λ (state m×(p+1), with m = 41 by default); notes: the scaling by the geometric mean (`boxcox.R:56`) needs pass 1. With an intercept in the model, a single pass on unscaled y plus the Jacobian term is mathematically equivalent but less stable for large |λ|. The RSS comes from `qr.resid` (`boxcox.R:65`), so `y'y − ||Q'y||²` with an incremental QR is exact. Verified invariant.
- `MASS::logtrans` (`formula`, `lm`, `default`) — ORDER=I; CHUNK=P; state: pass 1 is `min(y)` for the default α grid (`logtrans.R:20`) plus X'X; pass 2 is, per α, X'log(y+α), Σlog(y+α)² and Σlog(y+α); notes: 1 pass when `alpha` is supplied.
- `MASS::loglm` / `loglm1.data.frame` — ORDER=D; CHUNK=K; state: a cell table of summed frequencies keyed by the factor combination (plus, per cell, Σy·log y and the row count, to reproduce the deviance of the `.Within.` construction); notes: duplicate cells get an extra `.Within.` factor built after `order(rev(fac))`, which reorders `fac` and `rsp` (`loglm.R:94-96`), but the offset is taken from the unsorted data (`loglm.R:103-109`). With repeated cells *and* an offset, the offsets are attached to the wrong rows, so the fit depends on row order. Verified: the deviance changes by 30% under permutation; it is invariant without the offset or with unique cells. Also, cells absent from the data frame become structural zeros (start 0), not sampling zeros.
- `MASS::corresp` (`formula`, `factor`, `xtabs`) — ORDER=I; CHUNK=K; state: the 2-way contingency table; notes: the SVD runs on the small table. Verified invariant.
- `MASS::corresp.data.frame` / `corresp.matrix` — ORDER=E; CHUNK=P; state: pass 1 accumulates N, the column sums and Σ x_i x_iᵀ / r_i (c×c, where r_i is the row's own sum); pass 2 maps each row to its score; notes: here the data-frame rows are the row *categories* of a table, so `rscore` is row-equivariant and `cor`/`cscore` are invariant. An exact chunked version would eigendecompose the c×c Gram matrix in place of the full `svd` (`corresp.R`), up to sign.
- `MASS::mca` — ORDER=I; CHUNK=P; state: pass 1 is the Burt matrix G'G (L×L counts, `K` keyed by level pairs); pass 2 maps rows to `rs`/`fs`; notes: `d` and `cs` come from an eigendecomposition of the scaled Burt matrix, and `rs`/`fs` are row-equivariant. Verified invariant up to the signs of the singular vectors (on one permutation a column flipped). Factor trap: an unused level gives `Dc = 0` and `svd()` fails with "infinite or missing values" (`mca.R:33-34`, verified), so the declared levels must all be observed.
- `MASS::kde2d` — ORDER=I; CHUNK=P; state: with `h` and `lims` given, the n1×n2 grid of Σ dnorm(gx−x_i)·dnorm(gy−y_i), as one exact `A` pass that adds `tcrossprod` per chunk (`kde2d.R:34-36`); notes: the default `lims = c(range(x), range(y))` needs an `A` pre-pass, and the default `h` from `bandwidth.nrd` uses `quantile()` (`hist.scott.R:39-43`), which is `H` (sketch or user `h`). Verified invariant. The cost is O(n × grid), with no binning.
- `MASS::ucv`, `MASS::bcv` — ORDER=I; CHUNK=P; state: pass 1 is n, min, max and var; pass 2 is a histogram of `trunc(x/dd)` with about nb+2 bins; notes: `VR_den_bin` (`MASS/src/MASS.c:429-452`) counts binned pairwise differences with an O(n²) double loop. Those counts equal the autocorrelation of the bin-index histogram (verified equal to the C output on faithful), so an exact 2-pass version also costs only O(n + nb²). Bug: `ii = (int)(x/dd)` is anchored at 0, not at `xmin`, so for `nb < 101` |ii − jj| can reach `nb` and `cnt[nb]` is written out of bounds. valgrind flags `MASS.c:447`, and a 4-point example loses one pair.
- `MASS::width.SJ` — ORDER=I; CHUNK=H; state: as for `ucv` plus `IQR(x)` (`ucv.R:53`); notes: the IQR enters the pilot bandwidths. With a quantile sketch it becomes 2 passes, approximately. Verified invariant.
- `MASS::bandwidth.nrd` — ORDER=I; CHUNK=H; state: none; notes: it uses `quantile(x, c(.25, .75))` and `var` (`hist.scott.R:39-43`); a sketch is the escape.
- `MASS::truehist`, `MASS::hist.scott`, `MASS::frequency.polygon`, `MASS::nclass.freq` — ORDER=I; CHUNK=P; state: pass 1 is n, var, min and max (Scott, `nclass.freq`); pass 2 is the counts on fixed breaks; notes: `nbins = "FD"` and `hist.FD` need the IQR (`H`). With `breaks` supplied, one pass suffices.
- `MASS::huber` — ORDER=I; CHUNK=H; state: none; notes: `median(y)` start and a fixed `mad(y)` scale (`huber.R:21-22`); with s fixed, the location iteration is `P`/`A`. Verified invariant. Vector input.
- `MASS::hubers` — ORDER=I; CHUNK=H; state: per iteration Σ clipped y and Σ(clipped − mu)²; notes: the default `initmu = median(y)` and `s0 = mad(y)` (`hubers.R:17,31`) are only start values of the joint proposal-2 fixed point. With `initmu` given, it is `P`/`A` apart from the start of s, which is `H`. Verified invariant.
- `MASS::stepAIC`, `MASS::addterm`, `MASS::dropterm` — ORDER=I; CHUNK=P; state: inherited from the model class; one model fit per candidate per step, via `update()` (`stepAIC.R:178`) or `glm.fit` on a full-scope model matrix (`add.R:178-211,361-392`); notes: for `lm`, a single `A` pass accumulating the full-scope cross-product matrix [X_scope y]'[X_scope y] is exact for every submodel (leaps-style), so the whole search becomes one pass. Verified invariant for `lm`.
- `MASS::glmmPQL` — ORDER=D; CHUNK=P; state: at most `niter` outer PQL iterations, each a full `nlme::lme` fit, whose passes need per-group sufficient statistics (`K` keyed by group), plus the convergence sum Σ(eta − etaold)² (`glmmPQL.R:103`); notes: it is invariant (`I`) when `correlation` is absent or has a time covariate (verified). With `correlation = corAR1()` and no covariate, the within-group row order defines the time order, and the fixed effects changed by 0.4% under permutation (verified), so `D` within groups. `drop.unused.levels = TRUE` (`glmmPQL.R:53`).
- `MASS::lm.gls` — ORDER=D; CHUNK=H; state: none; notes: `W` is an n×n matrix indexed by row position (`lm.gls.R:33-39`). The result is equivariant only if `W` is permuted together with the rows, and the n×n `eigen` is holistic.
- `MASS::isoMDS`, `MASS::Shepard` — ORDER=D; CHUNK=H; state: none (dissimilarities); notes: they rank the dissimilarities with `order(dis)` (`isoMDS.R:53`). Tied dissimilarities are ranked by position, which changes the isotonic-regression blocks. Verified: with tied Manhattan distances and the same permuted start, the stress differs by 0.1% and the configuration by 12%. Without ties it is invariant (verified on swiss).
- `MASS::sammon` — ORDER=I; CHUNK=H; state: none; notes: it works on the n×n distance matrix with a `cmdscale` start. Verified invariant.
- `MASS::negexp.SSival` — ORDER=I; CHUNK=P; state: pass 1 is the mean and range of x; pass 2 is the quadratic least-squares cross-products; pass 3 is the least-squares cross-products of `exp(-x/th)`; notes: a selfStart for `nls`. It contains a stray `print(unlist(pars))`.
- `MASS::gamma.shape.glm`, `MASS::stdres`, `MASS::studres` — ORDER=I; CHUNK=P; state: `gamma.shape` runs Newton on two sums using the fitted mu (recomputable from the coefficients); `stdres`/`studres` need (X'X)⁻¹ (`A`) and then map rows to their hat values; notes: these take fitted objects; the residual outputs are row-equivariant.
- `MASS::write.matrix` — ORDER=E; CHUNK=P; state: pass 1 accumulates the common `format()` requirements (sign, integer width, significant digits and exponent: a mergeable max); pass 2 writes rows; notes: `format(t(x))` (`write.matrix.R:34`) chooses one format for the *whole matrix*, so each line's text depends on every other value. The existing `blocksize=` argument already writes in chunks but formats each block independently (`write.matrix.R:28`), so its output differs from the unchunked output: verified `1.000000 10.000000` versus `1 10`. It is the only chunked writer here, but it is not equivalent.
- `MASS::parcoord`, `MASS::ldahist`, `MASS::eqscplot` — ORDER=I; CHUNK=P; state: column min/max (`parcoord`); `pretty(range)` breaks then per-group counts (`ldahist`); notes: these are plotting helpers. `ldahist` density mode uses `width.SJ` (`H`).
- `MASS::theta.ml`, `MASS::theta.mm`, `MASS::theta.md` — ORDER=I; CHUNK=P; state: per Newton step, two scalar sums over (y, mu, w); notes: vector inputs, used inside `glm.nb`; at most `limit` (10–20) passes.

### nnet

- **verdict**: `multinom` is the target. It is exactly `P` with `A` passes (BFGS on a sum), and its `summ = 2/3` options already compress rows to unique covariate patterns (a `K` state), the nearest thing to existing chunk support. `nnet` has the same structure, but the optimum is numerically chaotic. Neither function is chunk-capable today.
- `nnet::multinom` — ORDER=I; CHUNK=P; state: per BFGS evaluation, the deviance and its gradient ((r+1)·(K−1) values) summed over rows; `qr(X)$rank` (`multinom.R:59`) can come from an incremental QR; notes: `rang = 0`, so the start is deterministic and no RNG is used. Response levels come from `as.factor` with empty levels dropped (`multinom.R:61-77`). Verified invariant on iris, birthwt and housing. `summ = 2/3` (C `VR_summ2`, a qsort plus merging of equal X rows) is a `K` compression and verified identical to `summ = 0`. Trap: `summ = 1` keys rows by a mixed-radix code `cumprod(apply(Z, 2, max) + 1)` (`multinom.R:83-92`) that assumes non-negative integer columns. With non-integer x, distinct rows collide and are merged: verified, 8 rows became 7 and the coefficients changed by 75%.
- `nnet::nnet` (`nnet.formula`, `nnet.default`) — ORDER=I; CHUNK=P; state: per BFGS evaluation, the error sum and the gradient (`nwts` values) over rows (C `VR_dovm`), plus `MaxNWts`; notes: the random start `runif(nwts)` is indexed by weight, not by row, so this is not `R`. Mathematically it is invariant, but non-convex BFGS amplifies the floating-point order of the sums. Verified: with the same seed, permuted rows change the weights by 47%, and even a 1e-15 relative perturbation in the original order changes them by 23%. With `size = 0` (convex) it is invariant. A chunked rewrite is legitimate but will not reproduce bitwise.
- `nnet::nnetHess`, `nnet:::multinomHess` (via `vcov.multinom`) — ORDER=I; CHUNK=A; state: the nw×nw Hessian (or information) summed over rows at fixed weights; notes: `multinomHess` loops over rows in R and accumulates crossproducts (`vcovmultinom.R`), a natural `A`.
- `nnet::predict.nnet`, `nnet::predict.multinom` — ORDER=E; CHUNK=M; state: the fitted object; notes: `type = "class"` uses `max.col`, so ties are `R` (`nnet.R:228`, `multinom.R:195`).
- `nnet::class.ind` — ORDER=E; CHUNK=M; state: none; notes: the columns come from `levels(as.factor(cl))`, so the levels need a pre-pass when `cl` is not already a factor.

### class

- **verdict**: `batchSOM` is the best exact target, `P` with an `A` state per radius (k-means-like). `knn`/`knn1` can be inverted to stream the *training* rows against an in-memory test set using per-test-row top-k heaps, or stream the test rows against an in-memory training set. The pointers' "lvq is `D`" is wrong: lvq draws random row indices (`R`). `SOM()` has a serious bug: it only ever updates code 1. Nothing here is chunk-capable today.
- `class::batchSOM` — ORDER=R; CHUNK=P; state: per radius, a winning-code sum (ng×p) and count (ng); then codes_j = Σ_{c: d(j,c) ≤ r} S_c / Σ N_c; notes: one pass per entry of `radii` (`SOM.R:26-31`). It is `R` because the default `init` samples rows by position (`SOM.R:24`), and because `knn1` breaks distance near-ties (relative `EPS = 1e-4`, `class.c:47`) at random. With `init` given and untied (jittered) data it is invariant (verified); on tied iris data, different seeds give different codes.
- `class::knn`, `class::knn1` — ORDER=R; CHUNK=H; state: for streaming over training rows, per test row the current k nearest (distance, class) plus the ties at the k-th distance (`use.all = TRUE`, up to `MAX_TIES`); for streaming over test rows, the full training set; notes: per test row the output is `E` given the training set, but vote ties draw `unif_rand()` in test-row order (`class.c:197`), so labels are `R` on ties. The training order is invariant in practice (verified for `k = 4`, both `use.all` settings, and `knn1`). However, the fuzzy tie fence compares against the *current* k-th distance (`class.c:124`), so near-tie membership within a relative 1e-4 can depend on training order. The levels come from `as.factor(cl)`.
- `class::knn.cv` — ORDER=R; CHUNK=H; state: none (O(n²)); notes: leave-one-out over the training set; a block-nested loop over (query chunk × training chunk) with top-k heaps is exact. Verified `E` except one vote-tie row, which changed under permutation with the same seed (`R`).
- `class::lvq1`, `lvq2`, `lvq3`, `olvq1` — ORDER=R; CHUNK=H; state: none; notes: `iters <- sample(n, niter, TRUE)` (`lvq.R:56,83,111,140`) draws random row positions, then sequential online updates follow. With a fixed seed, permuting rows changes the result (verified), which is `R`, not `D`. An exact stream is impossible because the updates need random access with replacement; processing a shuffled stream is a different, though distribution-equivalent, algorithm.
- `class::SOM` — ORDER=R; CHUNK=H; state: none; notes: it picks random rows `i = (int)(n * UNIF)` (`class.c:396`), then online updates. Bug: the neighbourhood-update loop `for (cd = 0; cd < ncodes; cd++)` (`class.c:417`) sits *inside* the winner-search loop that uses the same variable (`class.c:401`). The search therefore stops after code 0 and code 0 is always the winner. Verified: with `radii < 1` only code 1 ever changes from `init`.
- `class::lvqinit`, `class::multiedit`, `class::condense`, `class::reduce.nn` — ORDER=R; CHUNK=H; state: none; notes: they combine `knn.cv`/`knn` with `sample()` over row positions (`lvq.R:41`, `multiedit.R:30,49,61,72`).
- `class::lvqtest` — ORDER=E; CHUNK=M; state: the codebook; notes: it is `knn1(codebk$x, test, codebk$cl)`, with random ties.

### boot

- **verdict**: `boot()` is `R` by design, and a generic `statistic(data, i)` is holistic. The valuable exact rewrite is `stype = "f"/"w"` with a mergeable (weighted-sum) statistic: R replicate accumulators fed by chunk-wise multinomial counts (sequential binomial splitting, exact in distribution) or by the Poisson bootstrap (approximate). `cv.glm` with the default `K = n` is `I`; K-fold is `R`. `glm.diag` and `empinf` are `E`. Nothing is chunk-capable today. `simple = TRUE` only avoids storing the index matrix.
- `boot::boot` — ORDER=R; CHUNK=H; state: for statistics of the form Σ f_i·g(row_i) with `stype = "f"/"w"`, an R×dim(t) matrix of replicate accumulators (`A`), with strata `K`; notes: `ordinary.array` draws `sample.int(n, n*R, replace = TRUE)` over positions (`bootfuns.q:784-803`). Verified: same seed and permuted data give different `t`, and even the sorted `t` differs. `sim = "parametric"` resamples nothing (the statistic sees `ran.gen(data, mle)`).
- `boot::cv.glm` — ORDER=R; CHUNK=H; state: per fold, the complement-fit state (K parallel IRLS states of X'WX, X'Wz if folds are assigned by row hash); notes: `s <- sample0(rep(1:K, f), n)` (`bootfuns.q:845`) assigns folds by position. Verified: `K = 10` is `R`, while the default `K = n` (LOOCV, singleton folds) is `I` (verified). LOOCV needs n refits (`H`), with no hat-value shortcut. It uses `glmfit$y`, aligned by position with `data`, so NA-dropped rows misalign.
- `boot::censboot` — ORDER=R; CHUNK=H; state: for `sim = "weird"`, the K-M summary (`K` by unique failure time) plus the multiset of censored times (`K`); notes: `sim = "ordinary"` (via `cens.case`) and `sim = "model"/"cond"` (`cens.resamp`) draw per row, so they are `R` (verified for ordinary). `sim = "weird"` draws `rbinom` per *unique failure time* from `F.surv` and rebuilds sorted data (`cens.weird`), so it is `I` given `F.surv` (verified with the same seed and permuted rows).
- `boot::glm.diag` — ORDER=E; CHUNK=P; state: pass 1 is X'WX for the hat values (`A`); pass 2 maps rows to their residuals, h and Cook's distance; notes: verified row-equivariant. The scale for the Gamma family is a sum (`A`).
- `boot::empinf` — ORDER=E; CHUNK=H; state: none in general (`type = "jack"` evaluates the statistic n times, `"inf"` does n numerical derivatives); notes: verified row-equivariant for `jack`. For a linear or mergeable statistic, L_i is row-local given the global aggregates: `P` (an `A` pass, then `M`). `usual.jack`, `positive.jack` and `abc.ci` behave the same (n or 2n statistic evaluations).
- `boot::corr` — ORDER=I; CHUNK=A; state: Σw, Σw·x, Σw·y, Σw·x², Σw·y² and Σw·xy; notes: a weighted correlation of a 2-column data set.
- `boot::var.linear`, `boot::k3.linear` — ORDER=I; CHUNK=K; state: per stratum, the count and ΣL², or ΣL³; notes: vector input of influence values.
- `boot::exp.tilt`, `boot::saddle`, `boot::EL.profile`, `boot::EEF.profile` — ORDER=I; CHUNK=P; state: per `optim`/Newton evaluation, sums of exp(λL_i) or L_i·exp(λL_i), per stratum (`K`); notes: `saddle` with `type = "cond"` solves an n-variable `simplex` LP and Poisson/binomial `glm`s on the n rows, so it is `H`/`P`.
- `boot::tsboot` — ORDER=D; CHUNK=H; state: none; notes: block or model resampling of a time series, as expected.

### spatial

- **verdict**: `surf.ls` is an exact `P` target (range pre-pass, then an incremental QR with at most 28 parameters). `variogram`/`correlogram` are order-invariant with a fixed-size bin state but need all pairs, so a block-nested loop over chunk pairs is exact. `surf.gls` and the point-process functions are holistic. Nothing is chunk-capable today.
- `spatial::surf.ls` — ORDER=I; CHUNK=P; state: pass 1 is `range(x)` and `range(y)`, which are pushed into a C static via `VR_frset` (`kr.R:41-48`) to scale the coordinates; pass 2 is a Householder QR of the n×npar polynomial basis (`krc.c` `VR_ls`), replaceable by a Givens incremental R (npar(npar+1)/2 values, npar ≤ 28) plus Q'z; pass 3 maps rows to their residuals `wz`; notes: accepts a data frame with columns x, y, z. Verified invariant. The object stores the n-length `x`, `y`, `z`, `f` and `wz`.
- `spatial::surf.gls` — ORDER=I; CHUNK=H; state: none; notes: Cholesky of the n×n covariance (`l = double(n*(n+1)/2)`, `kr.R:110`). Verified invariant.
- `spatial::variogram`, `spatial::correlogram` — ORDER=I; CHUNK=H; state: per bin, Σ(z_i − z_j)² and a count (`nint` bins); `correlogram` also needs mean(z) and var(z) (`A`); notes: all-pairs O(n²) loops (`krc.c` `VR_variogram`, `VR_correlogram`). The bin width uses the maximum pairwise distance (the diameter, mergeable via a convex hull). A block-nested loop over chunk pairs with this fixed-size `A` state is exact. The mean pre-pass of `correlogram` can be removed by expanding the product. Verified invariant.
- `spatial::trls.influence`, `spatial::anova.trls`, `spatial::predict.trls`, `spatial::trmat`, `spatial::prmat`, `spatial::semat` — ORDER=E; CHUNK=M; state: the fitted object; notes: hat values via `stats::hat` on the stored basis (`A` for R⁻¹). Grid prediction is `M` over grid points, but `prmat`/`semat` sum over all stored data points per grid point.
- `spatial::Kfn`, `spatial::pplik` — ORDER=I; CHUNK=H; state: none; notes: pairwise point-pattern statistics on a `pp` list. `Kfn` has a `k`-bin state with edge correction, so the chunk-pair block loop applies.

### KernSmooth

- **verdict**: linear binning onto a fixed grid is the canonical exactly mergeable smoother state. Verified: chunked `linbin`/`rlbin` sums equal the full binning, and `locpoly(binned = TRUE)` on chunk-summed `rlbin` counts reproduces `locpoly(x, y)`. `locpoly(binned = TRUE)` (regression only) and `bkfe(binned = TRUE)` are *already* chunk-capable, but the binning helpers `linbin`/`rlbin` are not exported (`KernSmooth:::`). `bkde`/`bkde2D` need a range pre-pass unless `range.x` is given. `dpik`/`dpih` default to an IQR scale (`H`). `dpill` is a sort-based `D` trap.
- `KernSmooth::locpoly` — ORDER=I; CHUNK=P; state: pass 1 is min/max for `range.x`; pass 2 is `rlbin` xcounts and ycounts (2×`gridsize`) for regression, or `linbin` counts for a density; notes: 1 pass when `range.x` is given. `binned = TRUE` accepts pre-binned (xcounts, ycounts) (`all.R:648-653`); verified exact. In density mode (y missing), `binned` is ignored and x is binned as raw data.
- `KernSmooth::bkde` — ORDER=I; CHUNK=P; state: pass 1 is n, var (for the default bandwidth) and min/max (`range.x` ± 4h); pass 2 is `linbin` counts (`gridsize` 401); notes: 1 pass when `bandwidth` and `range.x` are given. Verified invariant. `n` is `length(x)`, so with `truncate = TRUE` out-of-range points still count in the normalizer.
- `KernSmooth::bkde2D` — ORDER=I; CHUNK=P; state: pass 1 is min/max per coordinate; pass 2 is `linbin2D` counts (M1×M2); notes: `bandwidth` is required. Verified invariant.
- `KernSmooth::bkfe` — ORDER=I; CHUNK=P; state: min/max, then `linbin` counts; notes: `binned = TRUE` (`all.R:187-194`) already accepts chunk-summed counts. Verified invariant.
- `KernSmooth::dpik`, `KernSmooth::dpih` — ORDER=I; CHUNK=H; state: with `scalest = "stdev"`, pass 1 is min, max, mean and var and pass 2 is `linbin` counts (`P`); notes: the default `scalest = "minim"` uses `quantile(x, 3/4) - quantile(x, 1/4)` (`all.R:333,428`), which is `H` (sketch escape). Binning standardized `sx` onto the standardized grid gives the same counts as binning x, so no extra pass is needed. `dpik` bins x twice and discards the first result (`all.R:420-421` versus `437-438`). Quirk: `linbin.f` has no `X == b` guard, unlike `rlbin.f:37`, so with the default `range.x = range(x)` the maximum point is silently dropped (verified: 271 of 272 counts on faithful). Chunked binning on the same grid reproduces this exactly. Verified invariant.
- `KernSmooth::dpill` — ORDER=D; CHUNK=H; state: none; notes: it sorts (x, y) with a stable `sort.list` and trims by rank (`all.R:495-502`), then `blkest`/`cpblock` fit polynomials on equal-count blocks of the sorted data (`blkest.f:27`). With tied x at a trim or block boundary, which y lands in which block follows input order. Verified: x rounded to 0.1 changes the result under permutation, while jittered x is invariant. The escape is approximate: a quantile sketch for the trim limits and block boundaries, then `rlbin` (`A`).

<!-- source: findings/rec_survival_etc.md -->
## Part: Recommended packages: survival, rpart, cluster, foreign, Matrix (codetools)

Installed versions checked: survival 3.8.6, rpart 4.1.24, cluster 2.1.8.2, foreign 0.8.91, Matrix 1.7.4, codetools 0.2.20 (R 4.5.3).
R-level `file:line` references point to `scratchpad/rec/<pkg>/R/`.
C-level references (`*.c`) come from CRAN source tarballs unpacked in `scratchpad/dl_recsrc/`
(survival 3.8-12, rpart 4.1.27, cluster 2.1.8.3, foreign 0.8-91), which are slightly newer than the installed builds except foreign.
Permutation checks (fixed seeds, `all.equal()`) are in `scratchpad/work_surv/t_*.R`.

Cross-cutting trap found here:
with OpenBLAS, `X %*% coef` gave identical covariate rows linear predictors that differ by 1 ulp depending on row position.
Anything that detects ties in a fitted score by exact equality (`concordancefit`, `royston`) therefore changed under row permutation,
although the fitted coefficients were identical.
A chunked rewrite must compute such scores per row deterministically or compare with a tolerance.

### survival

- `survival::coxph` — ORDER=I; CHUNK=P; state: per Newton step, K keyed by (stratum, unique stop time): for censored rows and for deaths separately Σw·r, Σw·r·x, Σw·r·xxᵀ (r = exp(η)), plus deadwt, ndead (row count) and Σw·x over deaths; reverse cumulative sums over time then give S0/S1/S2 for Breslow and Efron (coxfit6.c:384-447); for (start, stop] data the same aggregates keyed by stop time and by start time (risk set = {stop ≥ t} minus {start ≥ t}), after a K pre-pass of unique event times that drops rows spanning none (agreg.fit.R:26-30); pre-passes: weighted mean then weighted mean-abs-deviation per covariate for centering/scaling (2 A passes, coxfit6.c:155-180), K pass of unique times for `timefix`/`aeqSurv`; total ≈ 2A + 1K + (iter+1)·K; notes: verified permutation-invariant coef/var/loglik for breslow, efron, exact, `strata()`, `cluster`, (start, stop] with `id`, `tt()`, `frailty()`, `pspline()`, multi-state. Robust variance is on by default with cluster, non-integer weights, or an id with >1 event (coxph.R:322-325): +1 pass where each row's dfbeta is an M lookup into the final per-time cumulative hazard/x̄ curves, collapsed by `rowsum(rr, cluster)` (residuals.coxph.R:197) → K keyed by cluster (A without cluster). `coxph` always runs `concordancefit()` on the fitted lp (coxph.R:661-667), which is H and FP-tie sensitive (see `concordance`): `fit$concordance` tied.x changed 121→120 under permutation. Efron counts rows (`ndead`), so collapsing duplicate rows into case weights changes the Efron fit (verified; Breslow is exact under collapsing) — the K state must carry the death row count. `ties="exact"` needs elementary symmetric functions of the risk scores per event time (mergeable by polynomial multiplication in principle, not in the current code). Default `tt()` is O'Brien's rank within each risk set (coxph.R:219-225) → H; user `tt()` expands to one row per (subject, event time at risk). `pspline()` knots from `range(x)` (A pre-pass); `frailty()` adds per-cluster coefficients (K keyed by cluster) and an outer loop over theta. No chunk API exists.
- `survival::survfit.formula` (`survfitKM`, Kaplan–Meier / Fleming–Harrington) — ORDER=I; CHUNK=K; state: per (stratum, unique time) weighted and unweighted n.event, n.censor, n.enter; n.risk by reverse cumsum; KM/NA by cumulative products at finish; notes: verified invariant with strata, non-integer weights, influence, counting process with `id` + `entry`. `timefix` (`aeqSurv`) only re-bins keys using the sorted unique times and their mean (aeqSurv.R:15-23), so it can be applied at finish by merging adjacent keys. `start.time` default is `min(0, y)` (survfitKM.R:47, A). Robust variance is on by default with cluster, non-integer weights, or an id with >1 event (survfitKM.R:88-90): then a second pass building per-cluster influence over all times (K keyed by cluster × time, large). With (start, stop] + id, `survflag()` sorts by (group, id, time) to flag first/last segments (xtras.R:109-131, used at survfitKM.R:146) → needs id-partitioned input or a K pass keyed by id. Influence rows are labelled by row position (E).
- `survival::survdiff` — ORDER=I; CHUNK=K; state: per (stratum, unique time, group) events and exits; numbers at risk by reverse cumsum; G-rho weights (rho ≠ 0) from the pooled KM at finish; one-sample `offset()` test is A (sums); notes: verified rho=0 and rho=1 with `strata()`. Classic log-rank target.
- `survival::survreg` — ORDER=I; CHUNK=P; state: A pre-passes for `colMeans`/`sd` rescaling (survreg.fit.R:112-119) and weighted mean/var of y for `dist$init` (survreg.fit.R:138), one A pass for the "glim" start (XᵀWX, XᵀWz), intercept-only Newton then full Newton, each iteration one A pass (loglik, gradient, Hessian of size (p + nstrata)²); robust → per-row dfbeta collapsed by cluster (K); notes: verified weibull, lognormal, loglogistic. Straightforward biglm-style target.
- `survival::concordance` (`concordancefit`, `survConcordance`) — ORDER=I; CHUNK=H; state: for each event, weighted counts of at-risk rows with smaller/equal/larger predictor → 2-D dominance counts over (time, x) via a balanced tree over `sort(unique(x))` (concordance.R:274); notes: escape to K when x has few distinct values (counts per (time, x value), reverse cumsum per x) or approximate with x binned on a fixed grid (changes tie counts); `timewt` "S", "S/G", "n/G2" need KM/censoring KM (K); std.err needs per-row influence (second pass). Exact-equality tie detection is FP-sensitive (see top note). Verified invariant on raw covariates.
- `survival::cox.zph` — ORDER=I; CHUNK=P; state: transform "km" from per-time counts (K), "rank" = `rank(times)` over all rows, also from per-time counts (cox.zph.R:86), centering g(t) by its mean over events (A, cox.zph.R:102), then one K pass at fixed beta for the score test (Czph1/Czph2 with per-time S0/S1/S2 weighted by g(t)); notes: verified for km/rank/identity/log. The returned scaled Schoenfeld residuals are one row per event (state grows with events).
- `survival::predict.coxph`, `survival::survfit.coxph`, `survival::basehaz` — ORDER=E; CHUNK=P; state: lp/risk/terms for `newdata` are M (centered by `fit$means`); type "expected"/"survival", `survfit.coxph` and `basehaz` need the baseline hazard: one K pass over the training rows at the final beta keyed by (stratum, time), then M over `newdata` rows; notes: verified invariant. Chunkable over prediction rows today if the baseline is computed once.
- `survival::residuals.coxph` — ORDER=E; CHUNK=P; state: after the fit's K state (cumulative hazard and x̄ per time), martingale/deviance/score/dfbeta are an M pass; `collapse=` sums by cluster (K); notes: Schoenfeld residual rows at tied event times follow input order (S); verified dfbeta rows map back under permutation.
- `survival::aareg` — ORDER=I; CHUNK=K; state: per unique event time the risk-set Σw·xxᵀ (entries/exits keyed by time, reverse cumsum) plus each event's x row (grows with events); dfbeta array ncluster × (p+1) × ndeath (aareg.R:193); notes: the implementation materializes an n × ndeath risk matrix (aareg.R:148). Trap: `summary.aareg()` "slope" cumsums event rows (summary.aareg.R:41) in input order within tied times, so slope changed under permutation while coef/se/z/p did not (verified, also with continuous lung times which have 26 tied death times) → D on ties for that column.
- `survival::pyears` — ORDER=I; CHUNK=K; state: per cell (factor levels × `tcut` intervals) person-years, n, events, expected (ratetable lookups are row-local); notes: A if every classifier is `tcut` or has declared levels; `as.factor()` levels are data-dependent (pyears.R:143). Verified.
- `survival::survexp` — ORDER=I; CHUNK=P; state: cohort methods (ederer/hakulinen/conditional) need the output grid `sort(unique(Y))` (survexp.R:96-97, K pre-pass), then an A pass summing per-row expected survival/hazard on that fixed grid; with `times=` and ederer a single A pass; `method="individual.*"` is E/M; notes: verified hakulinen.
- `survival::finegray` — ORDER=S; CHUNK=P; state: pass 1 K keyed by (stratum, unique time) for the censoring KM G (and entry curve H with delayed entry) and the unique-time grid (finegray.R:97-104), plus per-id first/last rows (K by id or id-partitioned input); pass 2 M row expansion with weights G(t)/G(tᵢ); notes: values invariant after sorting (verified); output grouped by stratum, then input order.
- `survival::tmerge` — ORDER=D; CHUNK=K; state: keyed by id (streaming merge if data1 and data2 are partitioned/sorted by id); notes: trap — data2 is sorted by (id, time) stably (tmerge.R:297), so two `tdc()` values at the same (id, time) resolve to the last one in input order (verified: v = 2 vs 1 after swapping two rows); the first call without `tstop` takes the first data2 row per id (`!duplicated(id)`, tmerge.R:212); output follows data1's id order.
- `survival::survcondense` — ORDER=D; CHUNK=K; state: keyed by id (adjacent intervals with identical covariates merged); notes: real bug — it sorts by (id, stop) but two special branches index `Y` in data order instead of through `index` (survcondense.R:61, 63), so unsorted input keeps the wrong start time (verified: id 2's (0,10] + (10,20] condensed to (10,20] after reversing rows; correct on sorted input). Output order follows input.
- `survival::survcheck` — ORDER=I; CHUNK=K; state: keyed by id (rows sorted by time within id, survcheck.R:201-207), transition counts; notes: reported problem rows are positions (S). Verified transitions table.
- `survival::survfit.formula` (multi-state `survfitAJ`) — ORDER=I; CHUNK=K; state: per (stratum, time, from-state, to-state) weighted counts; notes: current state per id from `istate`/survcheck → needs id-partitioned input; verified competing-risk pstate/std.err invariant.
- `survival::survfit.formula` (interval-censored `survfitTurnbull`) — ORDER=I; CHUNK=P; state: one K pass compressing rows to distinct (L, R, strata) with weights, then the EM runs in memory on the compressed table (survfitTurnbull.R:158-203); notes: verified invariant.
- `survival::clogit` — ORDER=I; CHUNK=K; state: keyed by stratum (matched set): exact conditional likelihood per set; with sets contiguous in the input, one set at a time (M per set + A sum) per Newton step; notes: verified exact method invariant.
- `survival::cch` — ORDER=I; CHUNK=P; state: as `coxph` with case-cohort weights/offsets, plus K checks (unique id, event-time spacing, cch.R:19, 80-82); notes: verified Prentice, SelfPrentice, LinYing.
- `survival::rttright`, `survival::pseudo`, `survival::brier` — ORDER=E; CHUNK=P; state: K pass for the (censoring) KM curve per stratum, then M per-row weights/pseudo-values; `brier` then an A pass of squared errors at the requested times (ORDER=I for its output); notes: `rttright` with id needs the last row per id (rttright.R:121-123); verified all three.
- `survival::yates` — ORDER=I; CHUNK=P; state: after the fit, one A pass averaging per-row predictions over `population="data"` (factorial population: K over level combinations); notes: verified.
- `survival::survobrien` — ORDER=S; CHUNK=H; state: each covariate replaced by its percentile within every risk set (one output row per event time × at-risk subject); notes: verified downstream `coxph` invariant.
- `survival::royston` — ORDER=I; CHUNK=H; state: normal scores from ranks of η with tie averaging, plus the O(n²) Gönen–Heller loop over sorted η (royston.R:71-76); notes: ties found by exact `duplicated(eta)` (royston.R:39) → D and R.D changed under permutation (duplicated lp count 153 vs 154; FP trap above).
- `survival::survSplit`, `survival::tcut`, `survival::aeqSurv` — ORDER=E; CHUNK=M; state: none with fixed cut points (`cut <- unique(sort(cut))`, survSplit.R:65); `aeqSurv` alone needs a K pre-pass of unique times (P); notes: verified survSplit.
- `survival::nsk`, `survival::pspline` (basis constructors inside formulas) — ORDER=E; CHUNK=P; state: `nsk` boundary knots at `quantile(x, c(.05, .95))` (nsk.R:7) → exact-quantile pre-pass (H; sketch escape), `pspline` boundary knots at `range(x)` (pspline.R:5) → A pre-pass; then M; notes: data-dependent basis trap.
- `survival::neardate` — ORDER=D; CHUNK=K; state: data2 indexed by (id, date) (must be held), data1 streamed as M lookups; notes: returns row indices into data2; with tied (id, date) in data2 the stable `order(hash2)` (neardate.R:67-71) picks by input position.
- `survival::coxph.detail` — ORDER=I; CHUNK=K; state: per event time means, information, hazard; notes: verified.
- **verdict**: the strongest targets are `survfit.formula` (KM, K keyed by time), `survdiff` (K), and `coxph` (P with K per Newton step over per-time sufficient statistics, exactly what `coxfit6_iter` already accumulates), followed by `survreg` (P with A). Nothing in survival is already chunk-capable; case `weights` let users pre-aggregate identical rows, which is exact for KM and Breslow but not for Efron. Traps: `survcondense` special-case indexing bug, `tmerge` tie resolution, concordance/royston FP ties.

### rpart

- `rpart::rpart` — ORDER=R; CHUNK=H; state: each node scans every split point of each predictor in sorted order within the node (surrogates likewise); notes: default `xval=10` assigns folds with `sample(rep(1:xval, length.out = nobs))` by row position (rpart.R:119) → with a fixed seed the tree was identical but `xerror`/`xstd` changed under permutation (verified); with `xval=0`, or with a user-supplied fold-id vector stored as a column, it is I (verified for class, anova, poisson, exp, and n=5000 with ties). Exact escape: level-wise passes with K state keyed by (node, variable, distinct value) — class counts or Σy, Σy², n — exact when predictors have few distinct values and for categorical predictors (PLANET/MapReduce-style trees); otherwise histogram/quantile-sketch binning (LightGBM, Hoeffding trees) is approximate. `method="exp"` needs a K pre-pass of unique death times thinned with `quantile()` to ≤ 1000 (rpart.exp.R:32-39).
- `rpart::xpred.rpart` — ORDER=R; CHUNK=H; state: one tree per fold; notes: same `sample()` fold assignment (xpred.rpart.R:70); verified predictions changed under permutation.
- `rpart::predict.rpart` — ORDER=E; CHUNK=M; state: none (fitted tree); notes: verified; already chunkable over `newdata`.
- `rpart::residuals.rpart`, `rpart::rpart.matrix`, `rpart::na.rpart` — ORDER=E; CHUNK=M; state: none; notes: `rpart.matrix` maps factors to integer codes, so levels must be declared for chunks to agree.
- **verdict**: `predict.rpart` is the only exactly chunkable piece today; tree growing is H, with a level-wise K design exact only for low-cardinality predictors. Pass fold ids explicitly to remove the RNG dependence.

### cluster

- `cluster::mona` — ORDER=S; CHUNK=P; state: per level of the divisive tree, K keyed by current cluster: all pairwise 2×2 tables of the binary variables (p² × 4 counts per cluster) to pick the splitting variable; at most p levels; the missing-value imputation also uses 2×2 tables (A pre-pass); notes: the (variable, step) multiset was invariant, only the banner order follows input (verified); `as.factor()` coding per column (mona.q:17) requires both levels present. Most chunk-friendly method in the package.
- `cluster::daisy` — ORDER=E; CHUNK=H; state: output is all n(n−1)/2 pairs; pre-passes: column ranges for Gower (daisy.q:112, A), `stand=` mean-abs-deviation (2 A passes), `type$ordratio` ranks of distinct values via `as.ordered()` (daisy.q:63, K); notes: verified permutation-equivariant (Gower with asymm, standardized Euclidean). After the pre-passes the matrix can be filled block-pair by block-pair out of core.
- `cluster::pam` — ORDER=S; CHUNK=H; state: full dissimilarity matrix (n ≤ 65536); notes: partition and objective invariant, but among equal-cost candidates the medoid is chosen by row index (`ammax <= beter[i]`, pam.c:270), so medoid row ids changed with duplicated rows (verified); `medoids="random"`/`nstart` (default for `variant="faster"`, pam.q:5-6) makes it R (verified objective change). Assigning new rows to fixed medoids is M.
- `cluster::clara` — ORDER=R; CHUNK=P; state: subsamples drawn by row position, either by an internal `randm()` not tied to `set.seed()` (default `rngR=FALSE`) or by `unif_rand()` (clara.c:99-103); notes: with a fixed seed the partition changed under permutation for both settings (verified). Chunked variant: a reservoir sample (A) in pass 1, then an M pass assigning every row to the best medoids and summing the objective.
- `cluster::agnes` — ORDER=D; CHUNK=H; state: O(n²) dissimilarities; notes: trap — on tied integer data the sorted merge heights and the k=4 cut changed under permutation (verified), while continuous data were invariant; same tie behaviour as `stats::hclust`.
- `cluster::diana`, `cluster::fanny` — ORDER=I; CHUNK=H; state: O(n²) dissimilarities (fanny also n × k memberships iterated); notes: verified invariant on iris and on tied data for diana; no guarantee on ties.
- `cluster::silhouette` (default method with a `dist`) — ORDER=E; CHUNK=H; state: average unsquared dissimilarity of each row to each cluster; notes: average width invariant and rows map back (verified); computable block-wise over target rows.
- `cluster::ellipsoidhull` — ORDER=I; CHUNK=H; state: Titterington iteration keeps a weight per point (`spannel`), so state is O(n); notes: verified; exact escape: the minimum-volume ellipsoid depends only on convex-hull vertices, so an A pass for the hull (cheap in 2-D) can shrink the input.
- `cluster::clusGap` — ORDER=R; CHUNK=P; state: B+1 clusterings; notes: reference data drawn with `runif()` (clusGap.R:63) plus the clustering function's own randomness; verified Tab changed under permutation with a fixed seed.
- `cluster::medoids` — ORDER=S; CHUNK=H; state: `pam(k = 1)` within each cluster (medoids.R:41), O(n_c²) per cluster; notes: verified on continuous data; ties resolved by index.
- `cluster::meanabsdev` — ORDER=I; CHUNK=P; state: 2 A passes (mean, then mean |x − mean|); notes: used by `stand=TRUE` in pam/clara/fanny.
- **verdict**: `mona` (P with K 2×2 tables per level) and the `daisy` pre-passes are the only exact chunking targets; `clara` becomes streamable with a reservoir sample plus an assignment pass. Nothing is already chunk-capable; everything else is O(n²).

### foreign

- `foreign::write.dbf` — ORDER=E; CHUNK=P; state: A pre-pass per column (range for integer width and double decimals, max byte length for strings, dbf.R:83-97; record count), then M row writer; notes: verified per-chunk headers differ (integer width 4 vs 9, decimals 15 vs 10, string width 2 vs 10), so per-chunk files cannot simply be concatenated.
- `foreign::write.dta` — ORDER=E; CHUNK=P; state: A pre-pass for nobs and max string byte length per character column (sets the `str#` type, stataread.c:799-812), then M; notes: single pass possible on a seekable file by patching the header; value labels come from declared factor levels; verified rows permute.
- `foreign::write.foreign` (SPSS, SAS, Stata code + data) — ORDER=E; CHUNK=A; state: data file is row-wise `write.table()` (M); the code file needs only max `nchar` per string column (writeForeignCode.R:57, writeForeignSAS.R:107) and, for SAS, the max line length (re-reads the data file, writeForeignSAS.R:77), all accumulable during the row pass and written at the end; notes: the Stata variant is M.
- `foreign::write.arff` — ORDER=E; CHUNK=M; state: header from column classes and declared factor levels only, then `write.table()` rows (arff.R:128-160); notes: none.
- **verdict**: all writers are E; `write.arff` and `write.foreign` stream today in principle, `write.dta`/`write.dbf` need an A pre-pass (or header patching). `read.*` functions are producers and out of scope.

### Matrix

- `Matrix::sparse.model.matrix` — ORDER=E; CHUNK=M; state: none once levels and bases are fixed, else a K pre-pass for levels (P); notes: verified rows map under permutation and `rbind` of chunk results equals the full result with declared levels. Trap: character columns are converted with `factor(data[[i]])` per call (models.R:217), so a chunk missing a level yields fewer columns (verified 7 vs 8); declared factor levels or `xlev=` fix it; `poly()`/`ns()` in the formula are data-dependent.
- `Matrix::crossprod` / `tcrossprod` of a sparse model matrix — ORDER=I; CHUNK=A; state: XᵀX = Σ chunk X_cᵀX_c; notes: verified exact.
- `Matrix::fac2sparse`, `Matrix::fac2Sparse` — ORDER=E; CHUNK=P; state: K pre-pass for the level set, then M (each observation is one column); notes: `drop.unused.levels=TRUE` is the default (models.R:92-95), so a chunk lacking a level gets fewer rows (verified 2 vs 3); use `drop.unused.levels=FALSE` with declared levels for M.
- `Matrix::sparseMatrix` (from (i, j, x) triplet columns of a data frame) — ORDER=I; CHUNK=A; state: with fixed `dims`, the sum of chunk matrices (duplicated (i, j) are summed); otherwise K keyed by non-zero cells; notes: verified permutation and two-chunk sum equal, also for `repr="T"`.
- `stats::xtabs(sparse = TRUE)` (routes to Matrix) — ORDER=I; CHUNK=K; state: counts per observed cell; notes: verified invariant.
- **verdict**: `sparse.model.matrix` (M with declared levels) feeding `crossprod` (A) is an exact chunked pipeline for X'X-based fitting; the only trap is per-chunk level discovery for character columns and `fac2sparse`'s default `drop.unused.levels=TRUE`.

### codetools

- **verdict**: no data-frame consumers (exports are code walkers such as `checkUsage`, `findGlobals`, `walkCode`); nothing to catalogue.

<!-- source: findings/rec_nlme_mgcv.md -->
## Part: Findings: recommended packages nlme and mgcv

Sources: `scratchpad/rec/{nlme,mgcv}/R`; `file:line` citations refer to those files.
Empirical checks were run in R 4.5.3, comparing fits after permuting rows with a fixed seed (`all.equal()`).
The scripts are in `scratchpad/nm/t*.R` and `scratchpad/mg/t*.R`.
"Global perm" means all rows were shuffled.
"Within perm" means rows were shuffled only inside each group, so the groups stay contiguous.

### nlme

- `nlme::lme` (random effects given by `pdMat` only, no `correlation`/`weights`) — ORDER=I; CHUNK=K; state: per innermost group, the triangular R factor of `[Z X y]` (at most (q+p+1)² numbers) and n_i. These merge by stacking two factors and re-running QR (or Givens updates), and nested levels merge hierarchically; notes: verified on BodyWeight (random intercept and random slope) and Orthodont. logLik, fixef, ranef and the ranef row names were identical after global and within perm; fitted values are equivariant. The code already compresses the data once: with `reStruct` only, `MEdecomp()` (C `mixed_decomp`) replaces the N-row `conLin` with per-group R blocks (lme.R:306-310, lme.R:632-651). Every `nlminb`/`optim` likelihood evaluation then runs on that compressed state (`logLik.lmeStructInt`, lme.R:2811ff). The ideal rewrite is therefore one data pass followed by in-memory optimisation. The remaining global pieces are: factor levels (`model.frame(drop.unused.levels = TRUE)`, lme.R:231 → K pre-pass); starting values `0.375² colSums(Z²)/ngrps` (reStruct.R:262 → A, derivable from the R blocks); EM refinement, which runs on the full `conLin` before decomposition (lme.R:303) but could run on the compressed one; `getFixDF()` flags for whether each X column varies within groups (lme.R:465ff, C `inner_perc_table` → K); and fitted values and residuals, which need a second M pass with the b_i lookup (`oldConLin`, lme.R:400). The current code sorts rows by group with a stable `order()` (lme.R:241), so it needs group-contiguous rows; a streaming rewrite would hash by group instead.
- `nlme::lme`, `nlme::gls`, `nlme::gnls`, `nlme::nlme` with `correlation = corAR1()/corARMA()/corSymm()/corNatural()/corCAR1()` or `corSpatial` classes (`corExp`, `corGaus`, …) **without a covariate** — ORDER=D; CHUNK=P (one pass per optimizer evaluation, each a K pass over whole groups); state: per group, a buffer of all of the group's rows; notes: **trap**. Without a covariate, the "time" is the row position within its group: `seq_along` per group (corStruct.R:206-208); the spatial classes use `dist(seq_along(x))` (corStruct.R:1895) or `dist(1:nrow(data))` (corStruct.R:1907). Verified on BodyWeight. With `lme + corAR1()`, logLik went from −568.12 to −612.51 after within perm and to −612.72 after global perm. With `lme + corExp()` it went from −568.12 to −616.12. `gls` with `corAR1(~1|Rat)`, `corARMA(p=2, ~1|Rat)` and `corSymm(~1|Subject)` all changed too. With an explicit covariate the results are permutation invariant (ORDER=I, verified): `corAR1(~visit|Rat)`, `corARMA(p=2, ~visit|Rat)`, `corSymm(~visit|Subject)`, `corCAR1(~Time|Rat)` and `corExp(~Time|Rat)`. `corCompSymm` is exchangeable, so it is I even without a covariate (verified). A `corAR1` covariate whose within-group differences are not all 1 is silently converted to `corARMA(1,0)` (corStruct.R:962-969). Each likelihood evaluation whitens each group (C `AR1_recalc`/`spatial_recalc`), so the work is holistic within a group. With group-aligned chunks it becomes M over groups per pass. `gls` with a spatial structure and no groups is one N×N block (corStruct.R:1904-1909), so H. A rewrite could make `corCompSymm` single-pass K, since its whitening needs only per-group column sums of `[X y]`, n_i and the pooled X'X.
- `nlme::gls` (no `correlation`) — ORDER=I; CHUNK=A without weights and P with `varFunc`; state: the R factor of `[X y]` (or X'X, X'y, y'y) and N; notes: verified invariant for plain `gls`, `varPower()` and `varIdent()` logLik. `glsEstimate()` (gls.R:310ff) is a QR of the whitened `[X y]` via C `gls_estimate`. With `varIdent` the weights are constant within strata, so a rewrite could be single-pass K keyed by stratum (X_s'X_s, X_s'y_s, y_s'y_s, n_s) and then optimise offline. The current code does one data pass per `nlminb` evaluation (gls.R:118-140). `varPower()` with the default `~fitted(.)` needs the `needUpdate` outer loop, so it is P with alternating M and A passes. Rows are sorted only when a grouped `corStruct` is present (gls.R:65-77).
- `nlme::varIdent` (also stratified `varPower`/`varExp`/`varConstPower` with `form = ~ . | g`) — ORDER=S; CHUNK=M given the parameters; state: none (row-local weights), after a K pre-pass for the stratum labels; notes: **trap**. The reference stratum (fixed ratio 1) is the first stratum in data order (`uStrat <- unique(strat)`, varFunc.R:364). Verified with `gls(distance ~ age, Orthodont, weights = varIdent(~1|Sex))`: the reported ratio was Female = 1.0485 or Male = 0.9537, and sigma was 2.488 or 2.609, depending on which sex came first. logLik and β were identical. In `lme`, data are sorted by group first, but a stratum that varies within a group (`varIdent(~1|age)`) still changed its reference after within perm.
- `nlme::nlme`, `nlme::gnls`, `nlme::nlsList` — ORDER=I; CHUNK=P; state: `gnls` uses Gauss–Newton with J'J, J'r and RSS per pass (A); `nlme` alternates PNLS steps (per-group penalised Gauss–Newton, K per pass) with LME steps (per-group R factors of the linearised model, `MEdecomp`, nlme.R:798); `nlsList` keeps independent per-group nls state (K, or M over groups when chunks are group-aligned); notes: verified on Loblolly (`SSasymp`). For `nlme` the logLik difference after global perm was 1.4e-13, and fixef were equal. `gnls` with and without `varPower()`, and `nlsList` coefficients, were equal. The correlation trap above applies whenever `correlation=` is used.
- `nlme::lmList` — ORDER=I for coefficients (S for the `origOrder` attribute); CHUNK=K; state: per group X'X, X'y, y'y and n; notes: verified that coefficients and the list order are identical after global perm. `origOrder` is first-appearance order (lmList.R:95), so it changed. The code fits `lm()` on `split(data, groups)` (lmList.R:79-82). `split` keeps all factor levels, so each per-group fit sees the global level set (an aliased NA coefficient where a level is absent). Residuals and fitted values need a second M pass. `pooledSD()` and `lme.lmList()` starting values can be derived from the same K state.
- `nlme::groupedData` (and `nfGroupedData`/`nmGroupedData`) — ORDER=E; CHUNK=P (a K pass, then an M pass); state: per group `FUN(response)` (the default `max` is mergeable); notes: rows stay in input order. The grouping factor is re-levelled as `ordered(groups, levels = names(sort(tapply(response, groups, FUN))))` (groupedData.R:85-105). The sort is stable, so ties fall back to the original level order. Verified that the levels are identical after global perm. A holistic user `FUN` (median) makes the pre-pass H. The level order is presentation only (ranef row order, panels), not estimates.
- `nlme::gsummary`, `nlme::gapply`, `nlme::collapse.groupedData` — ORDER=I for `gsummary` (S for `collapse`); CHUNK=K; state: per group, sum and count for the default `mean`, per-group × level counts for the factor `Mode`, and a "differs from first value" flag for invariance detection; notes: `gsummary` sorts its output rows (newFunc.R:239). `Mode` uses `table()` and takes the first maximum in level order, so it is order-free. Verified identical after global perm. `gapply` applies an arbitrary `FUN` per group: K only if `FUN` is decomposable, otherwise holistic per group (M over groups when chunks are group-aligned). `collapse` orders the collapsed groups by `unique()` (groupedData.R:305), so S.
- `nlme::predict.lme`, `nlme::predict.gls`, `nlme::predict.nlme`, `nlme::predict.gnls` — ORDER=E; CHUNK=M; state: none; notes: fixed-effect factor levels come from the stored contrasts via `xlev` (lme.R:1857, gls.R:911), so a chunk with a subset of levels is safe. Random effects are looked up by group label, and unknown groups give NA. Verified for `predict.lme` that chunked results equal the whole-data result and that the output follows `newdata` order. `asList = TRUE` splits in first-appearance order (S, presentation only).
- `nlme::Variogram.lme`, `nlme::Variogram.gls`, `nlme::Variogram.default` — ORDER=D with the default `form = ~1`, and S with a covariate form; CHUNK=H within groups (K over groups when chunks are group-aligned); state: all within-group pairs, O(n_i²); notes: the default distance is the position within the group (`tapply(rep(1, n), grps, cumsum)`, lme.R:2644). With a covariate the semivariogram is pairwise within groups. `collapse = "quantiles"` bins by `quantile(dst, …)` (lme.R:2686), which is H. The escape is `collapse = "fixed"` with given breaks, giving A (per-bin sums and counts).
- `nlme::ACF.lme`, `nlme::ACF.gls` — ORDER=D; CHUNK=K given rows in time order; state: per-lag sums of products and counts, plus a buffer of maxLag rows per open group; notes: lag products are computed by within-group position (lme.R:837-849). This is time-series code by design and is listed only because it accepts a fitted grouped-data model.
- `nlme::simulate.lme` — ORDER=R; CHUNK=P; state: as for `lme`, per simulation; notes: `set.seed(seed)` and draws are indexed by row and group (simulate.R:153), followed by refits.

- **verdict**: nothing in nlme is chunk-capable today. Note that `lme` with `pdMat`-only random effects already reduces the data to per-group R factors in one step (`MEdecomp`, lme.R:306-310) and optimises on those. A rewrite is one K pass keyed by group, then optimisation with no further data access, then an M pass for residuals. That makes `lme` the top target, followed by `lmList` (K) and `gls` without correlation (A, or single-pass K by stratum for `varIdent`). The traps are serial or spatial `correlation=` without a covariate (D: position within group defines time) and the `varIdent` reference stratum (S: first-appearing stratum).

### mgcv

- `mgcv::bam` — ORDER=R for the default `discrete = FALSE` when `nrow > chunk.size`; I for `discrete = TRUE` or `nrow <= chunk.size`; D with `rho != 0`; CHUNK=A (Gaussian identity) or P (otherwise), **already chunked over the model matrix**; state: for Gaussian identity non-discrete, one pass of `qr_update` over chunks into (R p×p, f = Q'y, ‖y‖²). Each chunk's model matrix is built by `predict(G, mf[ind,], type = "lpmatrix")` (bam.r:1576-1612). `cluster=` merges per-node R factors by stacking and running QR again, or by summing X'X with `use.chol = TRUE` (bam.r:1621-1643). Smoothing parameters are then fitted by `fast.REML.fit()`/`magic()` on (R, f, rss.extra) alone (bam.r:1676-1692). Non-Gaussian non-discrete uses `bgam.fit()` PIRLS (bam.r:1053-1093): P with an A pass per iteration and a smoothing-parameter update per iteration (performance iteration). `discrete = TRUE` uses `bgam.fitd()`: P where each iteration forms X'WX by `XWXd()` (bam.r:657) on the discretised index, a bounded A state of weight sums per discretisation cell; notes: **trap**. The non-discrete basis is set up on `mini.mf()`. That is a seeded **positional** subsample (`temp.seed(66)`; `sample(1:n, chunk.size)`, bam.r:393-395) plus the first rows holding each min and max and one random row per factor level. Knots and eigenbases therefore depend on row order. Verified with n = 25,000 and the default `chunk.size`: after global perm, fitted values moved by up to 1.3e-2 (`tp`), 2.8e-2 (`cr`) and 6.4e-2 (Poisson `tp`). `ps` keeps identical fitted values because its knots come from the range and `mini.mf` includes the extreme rows. Its coefficients still change, because the sum-to-zero constraint is computed on the subsample. Verified invariant: `chunk.size = 1e5` (no subsample), `discrete = TRUE` (including `te()` and Poisson), and `cr` with user-supplied `knots`. The fit was also identical across `chunk.size` 1e5 and 1000 and with `use.chol = TRUE`. Discretisation is order-free: `compress.df()` uses `uniquecombs(…, TRUE)` and rounds onto an m-point grid over the range, and its RNG shuffle indexes the *sorted* unique set (bam.r:136-176). Its pre-pass is therefore bounded: per margin, the range (A) and the distinct values capped at m (bounded K). Not out-of-core today: bam still builds the full model frame in memory (bam.r:2323). It also keeps `var.summary`, which needs an exact median (bam.r:2362), the n-length y, w and offset vectors, the n × margins index matrix when discrete, and `object$model` (bam.r:2733). It recomputes the linear predictor in a final M pass (bam.r:2759). `samfrac < 1` takes an unseeded `sample()` for starting values (bam.r:2681), so R for the starting values only.
- `mgcv::bam.update` — ORDER=I (D with AR1); CHUNK=A, **already a streaming appender**; state: the stored `qrx` (R, f, ‖y‖²), updated by `qr_update()` with each new batch (bam.r:2888-2890). Smoothing parameters are re-fitted from that state alone (bam.r:2915). For AR1, the last whitened row `yX.last` is carried over; notes: verified that `bam` on 2,000 rows followed by two `bam.update()` calls of 2,000 rows each equals `bam` on all 6,000 rows (fitted values and sp), using `cr` with supplied knots. Limits: Gaussian identity non-discrete only (`stop("Model can not be updated")`, bam.r:2813; verified for Poisson). Basis, knots, constraints and `xlev` stay frozen from the first batch (`predict(b, newdata = mf, type = "lpmatrix")`, bam.r:2840). `b$model` grows by `rbind` (bam.r:2843), and fitted values are recomputed for all rows (bam.r:3007), so memory and time stay O(n) per update.
- `mgcv::predict.bam` on a `discrete = TRUE` fit (`predict.bamd`, the default `discrete = TRUE` argument) — ORDER=I but **not row-local**; CHUNK=M only with `discrete = FALSE`; state: none; notes: **trap**. `newdata` is re-discretised with `discrete.mf(newdata)` (bam.r:1847). When `newdata` has more unique covariate values than the grid size (1000 for 1-D, 100 per margin for 2-D, 25 for 3-D; `compress.df`, bam.r:136-158), the covariates are rounded onto a grid spanning `newdata`'s **own** range. Each prediction therefore depends on the other rows in the batch. Verified: predicting 6,000 rows at once versus in 500-row chunks differed by up to 0.032, and the chunks matched the exact `discrete = FALSE` prediction. Permuting `newdata` changed nothing. `predict.bam(discrete = FALSE)` is exact and chunkable (whole versus chunks differed by 8.9e-15) and also takes `block.size`/`cluster`.
- `mgcv::gam` — ORDER=I; CHUNK=P; state: pre-passes for factor levels (K), basis setup (see `smoothCon`), the constraint `colSums(X)` (A) and `var.summary` (min and max A, median H). After that comes an outer Newton or `bfgs` on log(sp), wrapping an inner PIRLS. Each PIRLS iteration is an A pass: the QR or X'WX of √W·X plus the derivative sums for REML. The extra θ of `nb()` or `tw()` adds row-sum derivative terms, which are still A; notes: verified identical fitted values, coefficients and sp after global perm for: `tp` at n = 400 (all unique points as knots) and n = 3000 (above `max.knots`), 2-D `tp`, `cr`, `s(f, bs = "re")`, Poisson, `nb()`, `tw()`, and `cox.ph()` with tied times (sorted by time, coxph.r:36-37; K keyed by unique event times per pass). The `tp` knot RNG indexes the sorted unique set (`uniquecombs(…, TRUE)` then a seeded `sample`, smooth.r:1286-1300), so the knots are order-free. `gam` holds the full X in memory. Its out-of-core analogue is the performance iteration in `bam`.
- `mgcv::smoothCon` / `smooth.construct.*` (the data-dependent part behind `s()`, `te()`, `ti()`; the specials themselves touch no data) — ORDER=I; CHUNK=P (a basis pre-pass, then an A constraint pass, then M); state: depends on the basis. `tp`/`ts`/`ds`/`gp`/`sos` need the covariate mean shift (smooth.r:1264, A) and the unique locations (K). Above `max.knots = 2000` unique locations, a seeded sample is drawn from the **sorted** unique set. Reproducing it exactly needs that whole set, so H; a reservoir sample of unique locations is the realistic escape and is R. These bases also need an eigen-decomposition over the knots. `cr`/`cs`/`cc` (and the default `te` margins) put knots at interpolated quantiles of `sort(unique(x))` (`place.knots`, smooth.r:1562-1578): H, or K when there are few distinct values, or a quantile sketch. `ps`/`bs`/`cp` take knots from min/max (smooth.r:1774, 1888): A. `re`/`fs`/`mrf` need factor levels: K. Every basis then needs the sum-to-zero constraint `C = colSums(X)` (smooth.r:3851): a second A pass; notes: supplying `knots=` removes the knot pre-pass. Evaluating rows with `PredictMat()`/`Predict.matrix()` is M given the smooth object.
- `mgcv::predict.gam` — ORDER=E; CHUNK=M, **already chunked**; state: none; notes: `block.size` defaults to 1000 when `newdata` is supplied (mgcv.r:2868). Factor columns are coerced to the fit's levels (mgcv.r:2834-2858). Verified that 50-row blocks and two separate halves equal the whole-data prediction, including chunks after `droplevels()`. `type = "lpmatrix"` disables blocking (mgcv.r:2875) but is still row-local.
- `mgcv::gamm` — ORDER=I without `correlation` (D with a covariate-free serial `correlation`); CHUNK=P; state: as `nlme::lme`; notes: verified logLik and fitted values invariant for a plain `gamm` and with `random = list(g = ~1)`. With `correlation = corAR1(form = ~1|g)` logLik changed after global perm; with `~t|g` it did not. Smooths become random effects in a single dummy group `factor(rep(1, nrow(X)))` (gamm.r:469, 531, 617). nlme's per-group `MEdecomp` therefore degenerates to one global QR of `[Z X y]`. A Gaussian `gamm` without correlation or weights is thus one A pass followed by optimisation on the compressed state. Non-Gaussian fits run the `gammPQL()` outer loop (gamm.r:1142-1235): P with one `lme` fit per iteration.
- `mgcv::uniquecombs` — ORDER=S for `ordered = FALSE`, I for `ordered = TRUE`; CHUNK=K; state: a dictionary of distinct rows keyed by their `paste0` text form, plus an M pass for the `"index"` attribute given the final dictionary; notes: verified that the unordered row order changes after permutation and the ordered result does not. `ordered = TRUE` sorts the keys in the C locale (smooth.r:200-210). Every internal caller that matters (`tp` knots, `compress.df`) uses `ordered = TRUE`.
- `mgcv::k.check`, `mgcv::gam.check`, `mgcv::qq.gam` — ORDER=R; CHUNK=H; state: sorted residuals or nearest-neighbour sets; notes: for n > 5000, `k.check` takes an **unseeded** `sample(1:n, subsample)` (plots.r:195). Its randomisation test shuffles residuals (plots.r:220, 248). The 1-D k-index uses `diff(rsd[order(x)])`, so ties follow input order (plots.r:217). The multi-D k-index uses `nearest()` (plots.r:243). Verified: with the same seed, p-values went from 0.1725 to 0.1525 after global perm while the k-index was unchanged (no ties). `qq.gam` randomises uniform quantiles against the observations (plots.r:156). The escape is subsampling, which the code already does.
- `mgcv::jagam` — ORDER=E; CHUNK=P (a basis pre-pass, then M); state: none per row once the basis is fixed; notes: verified that the rows of `jags.data$X` permute with the input and the penalty `S1` is identical. The JAGS data list holds the full X.
- `mgcv::vis.gam`, `mgcv::exclude.too.far`, `mgcv::plot.gam` — ORDER=I; CHUNK=A over data rows (M over the grid); state: the running minimum distance from each grid node to the data (`too.far`); notes: the grid comes from the stored `var.summary` (min, median, max, mode). `exclude.too.far()` scales the data by the **grid's** range, which makes the scaling row-local, and then takes, for each grid node, the minimum distance to any datum (C `MinimumSeparation`, plots.r:1589). That is a mergeable min state of size n.grid².
- `mgcv::variable.summary` (internal; stored as `var.summary` in every `gam` and `bam`) — ORDER=I; CHUNK=H; state: min and max (A), modal factor level (K), exact observed median (`quantile(type = 3)`, mgcv.r:2165), which is H; notes: the median is used only as the default "typical value" for plots and `vis.gam`. A quantile sketch would be an acceptable escape, but it would change what is stored.
- `mgcv::ginla` — ORDER=I; CHUNK=P; state: a repeated Newton/REML refit that needs the full `G$X` (A per pass in principle); notes: works only with a `gam` prefit or a `discrete = TRUE` `bam` (inla.r:202-204). No RNG use was found.
- `mgcv::in.out` — ORDER=E; CHUNK=M; state: none; notes: point-in-polygon per row (C `in_out`); verified that chunked results equal the whole-data result.
- `mgcv::summary.gam`, `mgcv::anova.gam`, `mgcv::concurvity`, `mgcv::gam.vcomp` — no data pass (plumbing on the stored `R`, `Vp` and `edf`); notes: `concurvity` and the `summary` p-values were verified equal after perm. `summary.gam` falls back to a seeded positional row subsample of the model frame (R) only for objects that lack `R` (mgcv.r:3987-3999).

- **verdict**: already chunk-capable: `bam(chunk.size = , cluster = , use.chol = )` (a chunked QR or X'X build), `bam.update()` (exact appending of rows for Gaussian additive models), `predict.gam(block.size = )` and `predict.bam(block.size = , cluster = )`. The most valuable target is `bam(discrete = TRUE)`, which is order-invariant (verified). Its discretisation pre-pass has bounded state: range plus at most m distinct values per margin. Each PIRLS step is a bounded A pass (`XWXd`). Only the in-memory model frame and the n-length index, y and w vectors keep it from being fully out-of-core. The second target is Gaussian non-discrete `bam` plus `bam.update()`: a single exact A pass. It first needs its `mini.mf()` positional subsample (R trap, bam.r:393-395) replaced by a pre-pass that is invariant to row order. The traps: `predict.bam` on discrete fits re-discretises `newdata` against the batch's own range, so it is not row-local; `k.check` is R and H.

<!-- source: findings/cran_depth1_a.md -->
## Part: CRAN depth 1, batch A (ada .. KFAS)

Source paths are relative to `src/<pkg>/`.
Empirical checks (fixed seed, row permutation, `all.equal()`) were run for data.table (`dt_check.R`) and gee (`gee_check.R`, `gee_check2.R`), all in the scratchpad.
Where behaviour lives in C/Fortran that was not extracted, the line says so and the claim rests on the R wrapper plus the algebra.

### data.table
- `data.table::[.data.table` (grouped `j` with `by=`/`keyby=`, GForce path) — ORDER=I with `keyby=`, S with `by=` (groups are re-ordered to first appearance, R/data.table.R:1603-1609); CHUNK=K; state: per-group decomposable state for the GForce functions `.N`, `sum`, `mean` (sum, n), `var`/`sd` (n, mean, M2 merged Chan-style), `min`, `max`, `prod`, `weighted.mean` (Σwx, Σw) (gfuns list, R/data.table.R:3215-3217); notes: verified that a `keyby` result with sum/mean/var/.N/weighted.mean/median is identical under row permutation, and that per-chunk `DT[i, .(s=sum(x), n=.N), keyby=g]` re-aggregated equals the global result; GForce `median` is H per group (escape: per-group sketch, or K when there are few distinct values); GForce `first`/`last`/`head`/`tail`/`[`/`[[`/`shift` are optimised but positional, so D (verified: `first(x)` by group changes under permutation); `.I`, `.GRP` and `rleid` follow input order; a non-GForce `j` is H per group unless the user's function is decomposable.
- `data.table::dcast.data.table` — ORDER=I; CHUNK=K; state: per (LHS × RHS) cell the state of a decomposable `fun.aggregate` (sum, length, min, max; mean as sum + count); notes: aggregation is `dat[, fun(...), by=varnames]` (R/fcast.R:193), and output rows and columns are sorted (`order_` with `sort=TRUE`, R/fcast.R:195-196), so casting merged per-chunk partial aggregates is exact (verified invariance for `sum`); with `fun.aggregate=NULL` a global uniqueness check silently switches to `length()`; non-decomposable or positional functions (`median`, `function(x) x[1]`) give H or D.
- `data.table::uniqueN` — ORDER=I; CHUNK=K; state: set of distinct key tuples (`forderv(retGrp=TRUE)`, R/duplicated.R:102-118); notes: exact answer needs the distinct set; escape: HyperLogLog-type sketch; verified invariant.
- `data.table::merge.data.table` and joins `X[i, on=]` — ORDER=E with respect to the streamed table, S for output order (`sort=TRUE` keys the result, R/merge.R:109; ties keep input order); CHUNK=M over `x` with `y` held in memory as the lookup (`y[x]`, R/merge.R:96), K when both sides must stream (sort-merge); state: for `all.y=TRUE`, the set of `y` keys matched so far (the anti-join `y[!x]`, R/merge.R:100); notes: `mult="first"/"last"` and `roll=` over duplicate keys in the lookup table pick a row by position, so D in the lookup table's row order.
- `data.table::unique.data.table`, `duplicated.data.table`, `anyDuplicated.data.table` — ORDER=S for `unique()` over all columns, D for `duplicated()` and for `unique(by=<subset>)` (which non-key values survive depends on which row came first; `fromLast` flips it; R/duplicated.R:26-44); CHUNK=K; state: set of seen keys; notes: rubric trap.
- `data.table::groupingsets.data.table`, `rollup.data.table`, `cube.data.table` — ORDER=S (each set is evaluated with `by=`, R/groupingsets.R:158-162); CHUNK=K; state: one keyed state per grouping set, or only the finest set when `j` is decomposable (roll it up afterwards); notes: GForce caveats as for `[`.
- `data.table::melt.data.table` — ORDER=E; CHUNK=M; state: none; notes: row-local reshape whose output stacks one block per measure variable, so concatenating chunk results yields the same multiset in a different order.
- `data.table::split.data.table` — ORDER=S (`sorted=FALSE` default keeps first-appearance group order, R/data.table.R:2547,2571); CHUNK=K; state: per-group append buffers (a partition, unbounded).
- `data.table::subset.data.table`, `na.omit.data.table`, `transform.data.table`, `within.data.table`, `as.matrix.data.table` — ORDER=E; CHUNK=M; notes: expressions that call global summaries such as `mean(x)` quietly become holistic.
- `data.table::setorder`, `setorderv`, `sort_by.data.table` — ORDER=S (stable sort, so ties keep input order); CHUNK=H; notes: escape is an external merge sort.
- `data.table::fwrite` (not in the scan; named in the brief) — ORDER=E; CHUNK=M; notes: already chunk-capable via `append=TRUE` (R/fwrite.R:1,65), and `fread(skip=, nrows=)` is the matching read side.
- `data.table::first`, `last`, `head.data.table`, `tail.data.table`, `shift`, `frollmean`, `frollapply` — ORDER=D; CHUNK=M with a carried overlap of window − 1 rows for the rolling functions; notes: the trap is their use inside grouped `j`, where they look like ordinary aggregates.
- **verdict**: grouped GForce aggregation with `keyby=`, `dcast` with a decomposable `fun.aggregate`, and `uniqueN` are exact K rewrites.
  The traps are `by=` output order, `unique(by=)`/`duplicated()`, and positional GForce functions.
  The only chunk-capable entry points are `fwrite(append=TRUE)` and `fread(skip=, nrows=)`; there is no out-of-core grouping.

### insight
- `insight::get_datagrid.data.frame` — ORDER=S, with D traps; CHUNK=P; state: pass 1 per column min/max for `range="range"` (A), distinct values and levels for factors, characters and integer protection (K), and quantiles/median/MAD for `range="iqr"/"ci"/"sd"/"mad"/[fivenum]` (H; escape: quantile sketch); the grid is then built from these summaries; notes: for character/logical columns `factors="reference"` takes `unique(x)[1]`, the first-appearing value (R/get_datagrid.R:1619,1635), and `.mode_value()` breaks ties by first appearance (R/get_datagrid.R:1645-1650), so both are D; character levels follow `unique()` order (S).
- `insight::n_unique.data.frame` — ORDER=I; CHUNK=K; state: per column set of distinct values (R/utilities.R:91-104); notes: escape is a HyperLogLog-type sketch.
- `insight::get_predicted.data.frame`, `get_modelmatrix.default` — ORDER=E; CHUNK=M; notes: `get_predicted.data.frame` only swaps arguments (R/get_predicted.R:346-353); prediction over `newdata` given a fitted model; `get_simulated.data.frame` is the same shim over `simulate()`, so R.
- **verdict**: plumbing.
  Only `get_datagrid.data.frame` aggregates rows, and it needs a summary pre-pass.
  The other ~100 candidates are getters, formatters and printers.

### gss
- `gss::ssanova`, `gssanova`, `gssanova1` (and `ssanova9` with `cov="long"` or a known covariance) — ORDER=R (default `id.basis <- sample(nobs, nbasis, prob=wt)`, R/ssanova.R:22; I when `id.basis` is supplied); CHUNK=P; state: pass 1 per-variable min/max for the cubic-spline domains (R/mkterm.R:36-37) plus a weighted reservoir sample of `nbasis` rows; pass 2 the cross-products Z'WZ, Z'Wy and y'Wy of Z = [s, r(x, x.basis)], which is nn × nn with nn = nnull + nbasis ≈ 10·n^(2/9); notes: the λ/θ search and the GCV/GML trace terms are functions of these cross-products (the Fortran `reg` call at R/ssanova.R:163 takes the n × nn matrix and was not extracted, so this rests on the algebra); `gssanova` needs one such pass per penalised-IRLS iteration; `partial=` calls `scale()`, which needs a mean/sd pre-pass; this is a bounded O(nbasis²) state, the same design as `mgcv::bam`.
- `gss::ssden`, `ssden1`, `sscden`, `sscden1`, `ssllrm` — ORDER=R (basis sampling, R/ssden.R:25); CHUNK=P; state: pass 1 the domain min/max (R/ssden.R:45-48) plus a reservoir basis sample; pass 2 weighted column sums and the cross-product of the n × nxis evaluation matrix [r(X_i, basis), φ(X_i)]; notes: the penalised likelihood −mean η(X_i) + log ∫ e^η depends on the data only through those column sums, and the quadrature is data-free; the cross-validation score in Fortran `dnewton` (R/ssden.R:217, not extracted) should also reduce to the second moments; `sscden` and `ssllrm` weight by distinct-x cells (`table(xx)[unique(xx)]`, R/sscden.R:89), which is K.
- `gss::sscox`, `sshzd`, `sshzd1`, `sshzd2d`, `sshzd2d1` — ORDER=R (basis sampled among events, R/sscox.R:54); CHUNK=P; state: a pre-pass for event times and ranges, then per Newton pass K keyed by event time (risk-set sums Σ e^η ξ and Σ e^η ξξ'); notes: `sscox` currently builds an n × nT risk-set indicator `t.wt` (R/sscox.R:135-136); in `sshzd` the per-subject hazard integrals are row-local and summed, so each pass is A.
- `gss::ssanova0` — ORDER=I; CHUNK=H; notes: full n × n kernel matrix (R/ssanova0.R:35); escape: use `ssanova` with a sampled basis.
- `gss::ssanova9` with `cov=list("arma", c(p, q))` — ORDER=D; notes: ARMA errors indexed by row position (R/ssanova9.R:33-35), a trap; `cov="long"` is invariant between ids.
- `gss::predict.ssanova`, `predict.ssanova0`, `predict.sscox`, `predict1.ssanova`, `predict9.gssanova`, `retroCI` — ORDER=E; CHUNK=M; notes: chunkable over `newdata` rows, including `se.fit`, which is a row-local quadratic form.
- **verdict**: `ssanova`/`gssanova` and `ssden` become exact two-pass algorithms (ranges plus reservoir basis, then fixed-size cross-products) once `id.basis` is chosen by reservoir sampling.
  Watch `ssanova9(cov="arma")`, which is D.
  Nothing in gss is chunk-capable today.

### eha
- `eha::coxreg`, `coxreg2`, `logrank` — ORDER=I for efron/breslow/ml, R when `max.survs` is below the risk-set size (risk-set sampling, R/coxreg.R:197, R/risksets.R:10-11) or `boot > 0`; CHUNK=P; state: pass 0 the unique event times per stratum (K); then per Newton pass, K keyed by (stratum, event time): risk-set sums Σ w e^{xb}, Σ w e^{xb} x and Σ w e^{xb} xx', plus event sums; notes: `risksets()` sorts by (strata, exit, −event) (R/risksets.R:72), so input order does not matter; a counting-process row (enter, exit] adds to a range of event times (difference array, then cumulative sum); `logrank()` is the score test at β = 0, a single K pass.
- `eha::toTpch` — ORDER=I; CHUNK=K; state: per (covariate cell × age interval) Σ events and Σ exposure; notes: `survSplit` (row-local) followed by `aggregate(FUN = sum)` (R/toTpch.R:70); the ideal compression step before `tpchreg`.
- `eha::pchreg` — ORDER=I; CHUNK=P, or K in a single pass without covariates; state: per optim pass, per (stratum × interval) D, Σ T e^{zb} and Σ X T e^{zb} (R/pchreg.fit.R:79-125); notes: the cuts are user-fixed; without covariates the MLE is closed-form D/ΣT (`loglik0`, R/pchreg.fit.R:79-91).
- `eha::tpchreg` — ORDER=I; CHUNK=P; state: log-likelihood and gradient sums per optim iteration over the aggregated table (R/tpchreg.fit.R:145); notes: input is small after `toTpch`.
- `eha::phreg`, `weibreg`, `aftreg`, `aftGompreg`, `mlreg` — ORDER=I; CHUNK=P; state: per Newton/optim pass the log-likelihood, score and Hessian sums per stratum (A); notes: `aftreg`/`aftGompreg` sort by (id, enter) (R/aftreg.fit.R:45) and integrate time-varying covariates over all spells of an id, so chunks must not split ids (otherwise K by id); the C code for phreg/weibreg (not extracted) works on strata-sorted data (R/weibreg.fit.R:64).
- `eha::toBinary` — ORDER=S; CHUNK=P; state: pass 1 event times per stratum (K); pass 2 emits each row once per risk set it belongs to (M); notes: `max.survs` sampling makes it R.
- `eha::age.window`, `cal.window`, `make.communal` — ORDER=E; CHUNK=M; notes: row-local truncation or splitting of spells (`make.communal` given `com.dat`).
- **verdict**: `toTpch` → `tpchreg` is already a compress-then-fit design: making `toTpch` chunk-wise is a K aggregation, and the fit is then tiny.
  `pchreg` and `coxreg` are exact P rewrites with event-time-keyed state.
  None of these is chunk-capable today.

### JM
- `JM::survfitJM.jointModel`, `predict.jointModel`, `rocJM` — ORDER=D within subject and E between subjects; R with `simulate=TRUE` (Monte Carlo per subject, R/survfitJM.jointModel.R:175,193); CHUNK=M over chunks that hold whole subjects; notes: `last.time` defaults to the time on the **last row** of each id, not the maximum (`tapply(time, id, tail, n = 1)`, R/survfitJM.jointModel.R:73, R/predict.jointModel.R:104, R/rocJM.R:98), and baseline covariates come from the last row per id (R/survfitJM.jointModel.R:48); sorting by (id, time) first removes the trap.
- `JM::aucJM.coxph`, `aucJM.jointModel`, `dynCJM.coxph`, `dynCJM.jointModel` — ORDER=I; CHUNK=H; notes: concordance over all subject pairs (R/aucJM.coxph.R:45-105); escape: per-subject risk scores are M, then a sort-based O(n log n) concordance or binned scores (K).
- `JM::prederrJM.coxph`, `prederrJM.jointModel` — ORDER=I; CHUNK=P; state: per-subject predicted survival (M), then the mean weighted loss (A); notes: censoring weights come from the fitted model per subject (R/prederrJM.coxph.R:43-46).
- `JM::weibull.frailty` — ORDER=I; CHUNK=P; state: per optim pass the log-likelihood and gradient sums over clusters (R/weibull.frailty.fit.R:59-62); notes: clusters must be whole within a chunk (otherwise K by id).
- **verdict**: the main finding is the last-row trap in the dynamic-prediction functions.
  Once data are sorted by (id, time), whole-subject chunks are an M map.

### gbm
- `gbm::gbm` — ORDER=D (`train.fraction` trains on the **first** floor(train.fraction · n) rows, R/gbm.R:126,375), plus R from the `bag.fraction` subsample and CV fold assignment; CHUNK=H; notes: trees grow on per-column sort orders `x.order <- apply(x[1:nTrain, ], 2, order)` (R/gbm.fit.R:454); escape: histogram boosting (pre-binned features, then per-node K histograms of gradient sums each pass, as in LightGBM or xgboost `hist`).
- `gbm::gbm.more` — ORDER=D/R, as for `gbm`; CHUNK=H; notes: needs the stored training data (`keep.data`).
- `gbm::predict.gbm` — ORDER=E; CHUNK=M.
- **verdict**: only prediction is chunkable.
  Flag `train.fraction` as a positional trap.

### Formula
- `Formula::model.frame.Formula`, `model.matrix.Formula`, `model.part.Formula` — ORDER=E; CHUNK=M given fixed factor levels (`xlev`), otherwise P with a levels pre-pass; notes: plumbing, but the building block for multi-part formula estimators downstream.
- **verdict**: no aggregation here; make sure the multi-part model frame can take declared levels.

### aod
- `aod::raoscott`, `aod::donner` — ORDER=I; CHUNK=K; state: per group N, Σn, Σy, Σn², Σny and Σy² (Σ(y − n p)² in `vratio` expands into these; group loop R/raoscott.R:74, R/donner.R:69-84); notes: groups are `sort(unique())`, so output is invariant.
- `aod::betabin`, `aod::negbin` — ORDER=I; CHUNK=P; state: per optim pass the log-likelihood (and gradient) sums (A); notes: starting values come from a `glm` (more passes); φ per random-effect level has a fixed size once the levels are known.
- `aod::quasibin`, `aod::quasipois` — ORDER=I; CHUNK=P; state: nested loops, an outer loop on φ where each step runs `glm` IRLS passes (A: X'WX, X'Wz) and a Pearson X² pass (A) (R/quasibin.R:24-35).
- `aod::splitbin` — ORDER=E (S for the generated `idbin` labels); CHUNK=M; notes: expands binomial rows into Bernoulli rows.
- **verdict**: `raoscott` and `donner` are single-pass K; the model fitters are standard P.

### coda
- `coda::mcmc` and the `mcmc`/`mcmc.list` methods `as.data.frame`, `xyplot`, `densityplot`, `qqmath`, `acfplot`, plus `cumuplot` — ORDER=D; notes: rows are iterations, and `start`/`end`/`thin` are positional; `densityplot`/`qqmath` are order-invariant per chain (H, or A/K when binned), but trace, autocorrelation and cumulative plots and the diagnostics (spectral effective size, Gelman) are D by design.
- **verdict**: nothing to chunk without ordered streaming.

### hexbin
- `hexbin::hexbin` (used by `hexbinplot.formula`, `hexplom.formula`, `hexplom.data.frame`) — ORDER=I (E with `IDs=TRUE`); CHUNK=A given `xbnds`/`ybnds`, otherwise P with a min/max pre-pass (default `xbnds = range(x)`, R/hexbin.s4.R:5); state: per hexagon cell the count, Σx and Σy (Fortran `hbin` returns `cnt`, `xcm`, `ycm` on a fixed imax × jmax grid, R/hexbin.s4.R:47-60), kept sparse; notes: to merge chunks, add the counts and combine the centres of mass weighted by count; prior art: `hexList`/`list2hexList` already require identical `xbnds`/`ybnds` across bins (R/hexbinList.R:46,76), which is exactly the merge precondition; `hexbinplot` takes per-panel bounds from `range(x)` (R/hexbinplot.R:88-97) and needs a global `maxcnt` for the colour scale (A).
- **verdict**: the cleanest A target in the batch: two passes, or one with declared bounds, and the merge is trivial.

### effsize
- `effsize::cohen.d.formula` (unpaired) — ORDER=I; CHUNK=K; state: per group n, mean and M2 (R/CohenD.R:149-153); notes: `paired=TRUE` without `| Subject(id)` pairs observations by position within group (R/CohenD.R:117, warning at R/CohenD.R:350-352), so D; with `Subject(id)` it is K keyed by subject.
- `effsize::cliff.delta.formula` — ORDER=I; CHUNK=H, or K for factors or few distinct values; notes: the numeric path sorts both samples (R/CliffDelta.R:97-98); the "Factor" algorithm uses only per-level tables (R/CliffDelta.R:108-125), which is the K degeneration; `return.dm` builds an O(n1·n2) dominance matrix.
- `effsize::VD.A.formula` — ORDER=I; CHUNK=H (ranks of the pooled sample, R/VD_A.R:37); notes: K over distinct values via per-value counts.
- **verdict**: `cohen.d` unpaired is K; the paired-by-position default is a D trap.

### exactRankTests
- `exactRankTests::wilcox.exact.formula`, `ansari.exact.formula`, `perm.test.formula` — ORDER=I; CHUNK=H; notes: ranks and Ansari scores (R/cscores.R:14, R/ansari.exact.R:30) and an exact permutation distribution via the shift algorithm over all scores (`pperm`/`qperm`); K when the scores take few distinct values (counts per score value suffice); confidence intervals invert over sorted differences (H).
- **verdict**: holistic; only small-support data degenerate to K.

### ca
- `ca::mjca.data.frame` — ORDER=I (`factor()` levels are sorted; row coordinates are E); CHUNK=P; state: pass 1 the Burt matrix Z'Z over all indicator columns (K keyed by level pairs, J × J) and the column masses; eigen-decomposition of the Burt matrix (`lambda="Burt"`/`"adjusted"`) or `iterate.mjca` (JCA) uses it only; pass 2 the row coordinates (M) (R/mjca.r:186-200); notes: `lambda="indicator"` is also derivable from the Burt matrix.
- `ca::ca.formula` — ORDER=I; CHUNK=K; state: `xtabs` cells.
- `ca::ca.data.frame` — ORDER=E (rows are table categories, not observations); CHUNK=P; state: pass 1 column sums (A), pass 2 the J × J cross-product of standardised residuals (A), pass 3 the row coordinates (M).
- **verdict**: `mjca` on raw categorical data is a clean one-pass Burt accumulation.

### EMCluster
- `EMCluster::dmixmvn`, `dmixmvn.wt`, `dlmvn` — ORDER=E; CHUNK=M.
- `EMCluster::emcluster` (with `e.step`/`m.step`, not in the scan) — ORDER=R through `init.EM` random starts (`em.EM`/`Rnd.EM`, R/fcn_init_EM.r:52-64), I given `emobj`; CHUNK=P; state: per EM pass, per class Σγ, Σγx and Σγxx' (A); notes: `e.step` is row-local, and per-chunk `m.step` outputs could be merged weighted by Σγ (Chan update).
- **verdict**: EM with the steps already exposed separately is close to chunk-ready.

### DiceKriging
- `DiceKriging::predict.km` — ORDER=E; CHUNK=M over `newdata`; notes: `cov.compute=TRUE` needs the joint covariance across new rows, which is H in `newdata` (R/kmStruct.R:265).
- `DiceKriging::kmData` (→ `km`) — ORDER=I; CHUNK=H (n × n covariance and Cholesky); notes: escape: subsampling or inducing points.
- **verdict**: chunkable over prediction rows only.

### dr
- `dr::dr` (methods sir, save, phd) — ORDER=I; CHUNK=P; state: pass 1 the weighted mean and X'WX (A) plus slice boundaries from y (H: `order(y)` and `table(y)`, R/dr.R:895-896; K when y has at most `nslices` distinct values, R/dr.R:882-883); pass 2 per-slice weighted sums Σz (SIR) and Σzz' (SAVE) (K by slice) or Σ y zz' (pHd, A); notes: as written it takes a QR of the n × p centred weighted X (R/dr.R:73-74), which a Cholesky of X'WX can replace; the `ire`/`pire` methods iterate (P); exact equal-count slices need sorting, so a quantile sketch would change the result.
- `dr::dr.weights` — ORDER=R; CHUNK=H; notes: random sampling (`nsamples`).
- **verdict**: SIR/SAVE/pHd are two-pass given slice boundaries.

### grpreg
- `grpreg::mfdr` (takes matrix `X`, not a data frame) — ORDER=I; CHUNK=A; state: for binomial models Σ P(1 − P) x_j² per column and λ, given the fit (computed in C); notes: `grpreg` itself takes a matrix, orthonormalises each group by SVD (R/orthogonalize.R:10; needs per-group X_g'X_g, A), then runs coordinate descent with an n-vector residual (P with O(n) state; a Gaussian covariance-update form would be A); `cv.grpreg` assigns folds randomly by position, so R.
- **verdict**: not a data-frame consumer; out of scope beyond this note.

### glm2
- `glm2::glm2` — ORDER=I; CHUNK=P; state: per IRLS pass X'WX, X'Wz and the deviance (A); notes: step-halving (R/glm.fit2.R:119-140) adds deviance-only passes (A); prior art for the same algorithm is `biglm::bigglm(data = function)`, which is chunk-capable.
- **verdict**: a straightforward P rewrite; reuse the bigglm pattern.

### gee
- `gee::gee` — ORDER=D within a cluster for `corstr` AR-M, stationary and non-stationary M-dependent, and unstructured: the working correlation is indexed by position within the cluster, with no time covariate (verified: permuting rows within clusters changes coefficients and robust SEs for AR-M and unstructured; `gee_check2.R`). Clusters are runs of **contiguous** equal `id` (man/gee.Rd:123-127), so any permutation that breaks contiguity fragments clusters: after a full shuffle, 60 ids became 296 runs, "independence" robust SEs changed and "exchangeable" coefficients changed (`gee_check.R`). ORDER=I under permutation of whole clusters (verified for all four structures). CHUNK=P; state: per Fisher-scoring pass Σ_i D_i'V_i⁻¹D_i, Σ_i D_i'V_i⁻¹(y_i − μ_i), moment sums for the scale and correlation parameters, and the sandwich meat Σ U_iU_i' (all A); notes: requires whole clusters per chunk, which is natural for files with contiguous clusters; `maxclsz` is computed by value with `split(id, id)` (R/ugee.R:204), inconsistent with the contiguity rule; the initial β comes from a `glm` on all rows (one more P).
- **verdict**: chunkable with A state per pass when chunks respect clusters.
  The contiguity and within-cluster position rules are the strongest trap in the batch.

### ismev
- `ismev::gamGPDfit` — ORDER=I; CHUNK=P; state: pass 1 the threshold `quantile(x, 1 − nexc/n)` when `nexc` is given (H; escape: quantile sketch; skipped when `threshold` is explicit, R/game.R:288); pass 2 filter the exceedances (M), which are the only rows kept; then backfitting `gam` fits on the exceedances in memory; notes: `init` defaults to `gpd.fit` on all data (P, an A optim pass each).
- **verdict**: the threshold-then-filter structure makes large data cheap: only exceedances need to fit in memory.

### bnlearn
- `bnlearn::ci.test` — ORDER=I; CHUNK=K for the discrete tests mi, mi-sh, x2, mi-adf and x2-adf (contingency table over the x, y, z configurations), A for the Gaussian tests cor, zf and mi-g (covariance of x, y, z), and K for mi-cg (per-configuration moments); R for the mc-*, smc-* and sp-* permutation tests (R/globals.R:13-16); jt is H (K for discrete ordinal data); notes: `bn.fit` (`method="mle"`/`"bayes"`, not in the scan) is the same story: per-node CPT counts (K) or per-node Gaussian regressions from the joint cross-product (A), in a single pass; structure learning (`hc`, `tabu`, `pc.stable`) re-queries counts for many candidate parent sets, so P.
- **verdict**: `ci.test` and `bn.fit` are single-pass K/A; `cluster=` parallelises over tests, not over data.

### irlba
- `irlba::prcomp_irlba` — ORDER=I up to sign (the random start vector is over columns, not rows); CHUNK=P; state: pass 1 column means and scales (A) (R/prcomp.R:72-110); each Lanczos step is a product X v (M, O(n) output) and X'u (A); a bounded-state alternative is one pass for X'X (A) when p is moderate; notes: prior art: `irlba` works with any object that has `%*%` methods (custom-class example, R/irlba.R:148-155), so an out-of-core matrix class gives a chunked `prcomp_irlba` without changing irlba; `retx` scores are M.
- **verdict**: already chunk-capable via a custom matrix class.

### fastmatrix
- `fastmatrix::ols` — ORDER=I; CHUNK=A for `method="chol"`/`"sweep"` (X'X, X'y) and for `"qr"` via incremental Givens updates, P for `"cg"`; state: X'X, X'y, y'y; notes: dispatches to `ols.fit.*` (R/ols.R:49-53).
- `fastmatrix::ridge` — ORDER=I; CHUNK=A; state: X'X, X'y, y'y; notes: GCV/MSE λ selection over a grid (R/ridge.R:24-54) is a function of the eigen-decomposition of X'X (the implementation is in C, not extracted).
- `fastmatrix::ccc`, `cov.weighted` — ORDER=I; CHUNK=A; state: n, weighted mean and covariance (`cov_weighted`, R/ccc.R:44-52); notes: the U-statistic variant changes only n-based corrections.
- `fastmatrix::kurtosis`, `skewness`, `mardia.test`, `WH.normal` — ORDER=I; CHUNK=P; state: pass 1 mean and covariance (A); pass 2 Mahalanobis-based sums: kurtosis Σ d_ii² (A); skewness Σ_ij d_ij³ (C code, presumably O(n²) pairs, but it equals the squared norm of the third-moment tensor Σ z_i⊗z_i⊗z_i, which is A with p³ state); notes: R/mardia.R.
- `fastmatrix::cov.MSSD` — ORDER=D; notes: the mean square successive difference estimator uses consecutive rows (man/cov.MSSD.Rd:21), a trap for a function that takes a plain data frame.
- `fastmatrix::mediancenter` — ORDER=I; CHUNK=P; state: per Weiszfeld-type iteration Σ x_i/‖x_i − m‖ and Σ 1/‖x_i − m‖ (A); notes: the C code was not extracted; this follows from the spatial-median definition.
- `fastmatrix::Mahalanobis`, `whitening`, `equilibrate` — ORDER=E; CHUNK=M given `center`/`cov`; notes: `equilibrate` needs a column-norm pre-pass (A).
- **verdict**: `ols`, `ridge` and `ccc` are single-pass A.
  Flag `cov.MSSD` as order-dependent.
  The remaining matrix-algebra helpers are plumbing.

### cocor
- `cocor::cocor` — ORDER=I; CHUNK=A; state: n and the Pearson moments of the 3–4 involved variables (per group for independent groups) (`cor()` calls, R/cocor.r:126-137).
- **verdict**: single-pass A.

### ebal
- `ebal::ebalance` — ORDER=I (weights are E); CHUNK=P; state: pre-pass treated-group moment totals (A); per Newton pass over control rows Σ w_i x_i and Σ w_i x_i x_i' (A), with `optimize()` line-search passes for Σ w_i (R/eb.R:12-33); notes: takes a matrix `X`; the final weights are a row-local map.
- **verdict**: an exact P rewrite with p × p state.

### infotheo
- `infotheo::mutinformation` (and the entropy estimators) — ORDER=I; CHUNK=K; state: joint and marginal count tables of the discretised variables; notes: the emp, mm, shrink and sg estimators are all functions of the counts (computed in C).
- `infotheo::discretize` — ORDER=I (E as a map); CHUNK=H for `"equalfreq"` (C `discEF`; escape: quantile sketch), P for `"equalwidth"`/`"globalequalwidth"` (min/max pass, then M) (R/discretize.R:11-18); notes: the default `nbins = NROW(X)^(1/3)` needs n.
- **verdict**: equal-width discretisation followed by count-based MI is two-pass exact.

### discretization
- `discretization::incon`, `Xi` — ORDER=I; CHUNK=K; state: counts per (attribute pattern × class) (`unique`/`duplicated` on patterns, R/incon.R:11-13).
- `discretization::disc.Topdown` (CAIM, CACC, Ameva) — ORDER=I; CHUNK=K keyed by (distinct x value × class), H in general; notes: candidate cut points are boundaries between sorted distinct values, so per-value class counts suffice to evaluate every candidate.
- **verdict**: class-count tables per distinct value make these exact K, with state bounded by the number of distinct values.

### aplpack
- `aplpack::compute.bagplot`, `bagplot` — ORDER=D for n > `approx.limit` (default 300): it takes a **systematic positional** subsample `round(seq(1, n, by = n/approx.limit))` (R/bagplot.R:251-258), so the result depends on row order deterministically; I below the limit; CHUNK=H (halfspace depth); notes: replace with a reservoir sample (R) or exact depth (H).
- `aplpack::plothulls` — ORDER=I; CHUNK=H; notes: convex-hull peeling.
- **verdict**: report the positional-subsample trap; nothing chunkable.

### airGR
- `airGR::SeriesAggreg.data.frame` — ORDER=D; CHUNK=K by calendar period; notes: assumes date-sorted input: the grid start and end come from the first and last rows and the time step from the first two rows (R/SeriesAggreg.data.frame.R:96-100); after merging onto that regular grid it aggregates `aggregate(. ~ Fac2)` by period (R/SeriesAggreg.data.frame.R:131,149-160), which is K for sum/mean and H per period for `ConvertFun = "Qxx"` quantiles.
- **verdict**: the period aggregation is K if keyed by `format(date)`; the first/last-row assumptions are the trap.

### investr
- `investr::calibrate.formula`, `invest.lm`, `invest.glm`, `invest.nls` — ORDER=I (R with bootstrap intervals); CHUNK=P; state: the underlying fit (lm: A; glm/nls: P with A per pass), then inversion on the fitted model only.
- `investr::predFit.lm`, `predFit.glm`, `predFit.nls`, `predFit.lme` — ORDER=E; CHUNK=M over `newdata`; notes: the Bonferroni/Scheffé `k` is user-supplied.
- **verdict**: thin layers over model fits; nothing package-specific to chunk.

### gslnls
- `gslnls::gsl_nls.formula`, `gsl_nls_large.formula` — ORDER=I; CHUNK=P; state: per iteration J'J, J'f and ‖f‖² (A); notes: `gsl_nls_large` uses GSL's `multilarge_nlinear` module (R/nls_large.R:3-4), whose trust-region methods consume J'J and J'f, so the algorithm is already A-per-pass, but the R wrapper materialises the full data.
- **verdict**: closest to chunk-ready among the nonlinear fitters; needs a chunked residual/Jacobian callback.

### grplasso
- `grplasso::grplasso.formula`, `lambdamax.formula` — ORDER=I; CHUNK=P; state: per block-coordinate-gradient iteration the gradient X'(y − μ) and blockwise curvature (A); `lambdamax` is one gradient pass at the null fit (A, after a null-model pass); notes: `predict.grplasso` is E/M.
- **verdict**: a standard P rewrite; nothing package-specific.

### dbarts
- `dbarts::bart2`, `dbarts`, `rbart_vi`, `xbart` — ORDER=R; CHUNK=H; notes: MCMC over trees with cut points from the data, plus random CV folds in `xbart`; `makeModelMatrixFromDataFrame` is E/M given fixed factor levels.
- **verdict**: not chunkable beyond prediction.

### ada
- `ada::ada.formula`, `ada.default`, `update.ada` — ORDER=R (bagging subsamples by position, R/ada.machine.R:19-22); CHUNK=H (`rpart` trees, R/ada.machine.R:84).
- **verdict**: not chunkable; prediction is M.

### AlgDesign
- `AlgDesign::optFederov`, `optMonteCarlo` — ORDER=R (`nRepeats` random starts, R/FederovOpt.R:9); CHUNK=H; notes: `data` is a candidate set and the exchange algorithm revisits every candidate.
- **verdict**: not a row-stream consumer.

### evd
- `evd::fbvevd`, `tcplot` — ORDER=I; CHUNK=P; state: per optim pass the log-likelihood sums (A); `tcplot` refits for each threshold in a grid (filter, then P).
- **verdict**: standard likelihood P.

### fmsb
- `fmsb::Kappa.test` — ORDER=I; CHUNK=K; state: the rater-by-rater confusion table.
- `fmsb::percentile` — ORDER=E as a map but needs ranks; CHUNK=H.
- **verdict**: `Kappa.test` is K; the rest is plotting.

### fritools
- `fritools::weighted_variance.data.frame` — ORDER=I; CHUNK=A; state: Σw, Σwx, Σwx² (R/weighted_variance.R:30-85).
- `fritools::tapply` — ORDER=I; CHUNK=K when `func` is decomposable.
- **verdict**: thin wrappers; `weighted_variance` is single-pass A.

### IDPmisc
- `IDPmisc::iplot`, `ipairs` — ORDER=I; CHUNK=P; state: min/max pass, then pixel-grid counts (A); notes: image scatter plots that bin points into pixels.
- `IDPmisc::NaRV.omit` — ORDER=E; CHUNK=M.
- **verdict**: pixel binning is the same fixed-grid A pattern as hexbin.

### HDInterval
- `HDInterval::hdi.data.frame` — ORDER=I; CHUNK=H; notes: per-column sort of posterior draws; escape: quantile sketch.
- **verdict**: holistic per column.

### iterators
- `iterators::iter.data.frame`, `isplit.data.frame` — ORDER=E; CHUNK=M; notes: prior art for chunk-wise consumption: `iter(df, by = "row")`, `isplit()` by group (R/isplit.R:99-106), plus `iread.table`/`ireadLines` (R/extra.R:118,149) and `idiv(chunkSize=)` (R/extra.R:85) for streaming input.
- **verdict**: infrastructure for chunked iteration, not a consumer.

### functionals
- `functionals::fmapg` — ORDER=S; CHUNK=K; notes: `split()` by group, then apply (R/fmapg.R:28-33); a partition with unbounded per-group buffers unless `.f` is decomposable.
- **verdict**: a group-partition helper.

### Skipped
Plumbing, plotting or ordered-by-design only: jsonlite, cli, DBI, digest (hash of the data frame, order-sensitive by design), colorspace, gmp, git2r, fansi, compare, common (`sort.data.frame` H/S, `changed` D), HSAUR2, HSAUR3, enrichwith, binom, beeswarm, deldir (Delaunay H; `duplicatedxy` D), Bolstad2 (`thin` D), KFAS (state-space time series), deSolve (ODE output), gtools (`running` D, `mixedorder` H), inflection (ordered curve data).

<!-- source: findings/cran_depth1_b.md -->
## Part: CRAN depth 1, batch B (kyotil .. zoo)

Scope: candidates in `batches/depth1_b.tsv` (456 rows, ~100 packages), plus a few no-candidate packages from `depth1_nocand.txt` in the same alphabetical range.
Claims are grounded in `src/<pkg>/R` (file:line); where behaviour lives in compiled code this is said explicitly.
`kernlab` and `clue` sort before `kyotil`, so they are left to batch A.

Empirical permutation checks (fixed seed, rows permuted, `all.equal()`), script `verify_b*.R` in the scratchpad:

- Check: `VGAM::vglm(y ~ x + g, negbinomial())`: coefficients identical under row permutation.
- Check: `VGAM::vglm(..., negbinomial(max.support = 5))` (forces simulated EIM): same seed, same order identical; permuted rows differ (1.2e-7) → `R`.
- Check: `lsr::pairedSamplesTTest` long form: moving the second-level rows first flips the t statistic (-2.19 → +2.19) while `group.names` stay `pre`, `post` → `D` trap.
- Check: `mclust::Mclust(faithful)` vs row-permuted: log-likelihood -1126.326 vs -1126.359 (different local optimum, n = 272 < 2000 so no subsampling); after a 1e-3 jitter both agree exactly, and `me()` from matched `z` is invariant → the order dependence comes from tie-breaking in the `hc()` initialisation.
- Check: `zoo::read.zoo(df)` vs permuted `df`: identical values (only a carried-over `names` attribute differs); `read.zoo(split = Inf)` swaps series membership of tied timestamps → `D`.

### VGAM

- `VGAM::vglm` — ORDER=I; CHUNK=P; state: per IRLS pass the VLM normal equations X_vlm' W X_vlm and X_vlm' W z (p_vlm × p_vlm) built from per-row M×M working weights and derivatives (family `@deriv`/`@weight` slots, vglm.fit.q:157-158, 352-353), plus the summed convergence criterion; typically 5-30 passes; notes: the solver whitens and stacks X into an n·M-row `X.vlm` and calls `lm.fit()` (vlm.wfit.q:166) — swap for a chunk-merged Cholesky/Givens QR as in `biglm`; `model.frame(drop.unused.levels = TRUE)` (vglm.R:43) and smart-prediction bases need a level/basis pre-pass; many `@initialize` slots use whole-data statistics such as `median(y)` (family.univariate.R:566) → pre-pass or pass `coefstart`/`etastart`; families with simulated expected information (`nsimEIM`, e.g. `negbinomial()` draws `rnbinom()` per row for rows whose support exceeds `max.support`, family.nbd.R:973) are `R` (verified); `negbinomial` already chunks its EIM by memory (`max.chunk.MB`, family.nbd.R:926-950) with series truncation `y.max = max(Q.maxs[chunk])`, so truncation depends on chunk composition (negligible numerically).
- `VGAM::vgam` — ORDER=I; CHUNK=P; state: outer IRLS × inner backfitting; `s()` terms smooth partial residuals with `vsmooth.spline` over unique x (K keyed by unique x per smoother per backfitting sweep, called via `s.vam`, vgam.fit.q:121); `sm.os()`/`sm.ps()` P-splines go through `mgcv::magic()` on the augmented whitened design (vlm.wfit.q:98-120), which could run on a chunk-merged R factor as `mgcv::bam` does → A per pass; notes: `sm.os()` puts knots at quantiles of unique x (sm.os.R:211) → H pre-pass unless knots are fixed; many passes (IRLS × backfitting).
- `VGAM::rrvglm`, `VGAM::cqo`, `VGAM::cao` — ORDER=I; CHUNK=P; state: alternating IRLS fits (rrvglm) or `optim()` over the constrained coefficient matrix C with nested GLM fits per objective evaluation (cqo.fit.q:785, cao.fit.q:193), each inner fit A per pass; notes: random starts `rnorm(M*Rank)`/`rnorm(p2*Rank)` are not row-indexed (cqo.fit.q:433-439), so a fixed seed gives an order-free result; `cao` smooths along the latent variable (K/H) and standardises site scores with `scale()` (cao.fit.q:830, A pre-pass); pass count (optim × IRLS) makes these poor chunking targets.
- `VGAM::predict.vlm`, `VGAM::predict.vgam`, `VGAM::predictqrrvglm`, `VGAM::predict.rrvgam`, `VGAM::calibrate.qrrvglm`, `VGAM::calibrate.rrvglm` — ORDER=E; CHUNK=M; state: none (coefficients and smart-prediction bases come from the fit); notes: calibrate solves a small optimisation per new row, still row-local.
- `VGAM::rootogram4vglm` — ORDER=I; CHUNK=K; state: observed frequency per response value and summed fitted pmf per value up to `max`; notes: one pass over `newdata` or the training rows.
- `VGAM::add1.vglm`, `VGAM::drop1.vglm`, `VGAM::anova.vglm`, `VGAM::lrtest_vglm` — ORDER=I; CHUNK=P; state: one `vglm` refit per candidate model; notes: inherit all `vglm` traps.
- **verdict**: `vglm` (IRLS over VLM cross-products, exact `P` with A state once initialisation and levels are fixed) is the main target, then `vgam` with `sm.os`/`sm.ps` terms via a bam-style R-factor merge; nothing in VGAM is chunk-capable today.

### zoo

- `zoo::zoo`, `zoo::read.zoo` (data-frame input), `zoo::as.zoo.data.frame(order.by = )` — ORDER=S; CHUNK=H; state: sort of all rows by the index, `index <- ORDER(order.by)` (zoo.R:8); notes: because the constructor sorts, everything downstream is invariant to the *input* row order (verified for `read.zoo`); ties in the index keep input order (stable sort, warning at zoo.R:5) → S; escape: if chunks already arrive index-sorted the constructor is M per chunk, otherwise an external merge sort; plain `as.zoo.data.frame(x)` is `zoo(as.matrix(x))` (as.zoo.R:21-24) and uses row positions as the index → D.
- `zoo::aggregate.zoo`, `zoo::read.zoo(aggregate = TRUE/FUN)` — ORDER=I; CHUNK=K; state: per `by` value an accumulator for decomposable FUN (sum, mean, count, min, max; `first`/`last` need index order within key, which zoo guarantees); notes: groups are coded by first appearance `MATCH(by, by)` but the result is rebuilt with `zoo()` and so re-sorted (aggregate.zoo.R:22-38) → order-free relative to the input; `by = as.yearmon` etc. is row-local; non-decomposable FUN (median) → H per group.
- `zoo::rollapply.zoo` (also `rollmean`, `na.locf` on zoo, `diff.zoo`, `lag.zoo`) — ORDER=D w.r.t. the index but I w.r.t. input rows (zoo sorts first); CHUNK=M; state: halo of the last `width - 1` rows (or the last non-NA value for `na.locf`) carried across boundaries of an index-sorted stream; notes: `width` counts observations, not time units, so irregular series silently mix spans.
- `zoo::read.zoo(split = Inf | -Inf)` — ORDER=D; CHUNK=K; state: occurrence counter per timestamp; notes: duplicate timestamps are numbered by input occurrence `ave(ix, ix, FUN = seq_along)` (read.zoo.R:115-116), so which series a value lands in depends on row order (verified) — notable trap.
- `zoo::na.locf.data.frame` — ORDER=D; CHUNK=M; state: last non-NA value per column carried across chunks; notes: operates on raw data-frame row order with no index (na.locf.R:53-57), unlike the zoo methods — trap.
- `zoo::zooreg` — ORDER=D; CHUNK=M; state: running row position; notes: a regular index is generated from position (start + (i - 1)/frequency).
- `zoo::summary.zoo` — ORDER=I; CHUNK=H; state: `summary()` of index and columns (zoo.R:85-96) needs quartiles; A if only min/max/mean are wanted.
- `zoo::write.zoo`, `zoo::as.data.frame.zoo`, `zoo::fortify.zoo`, `zoo::subset.zoo` — ORDER=E; CHUNK=M; state: none; notes: output follows index order.
- **verdict**: zoo is order-*dependent* by design but input-order-free once an index column is used; the chunk-relevant pieces are `aggregate.zoo` (K) and halo-carrying `rollapply` over index-sorted chunks; the traps are `read.zoo(split = Inf)`, `na.locf.data.frame` and positional `as.zoo.data.frame`.

### randomForest

- `randomForest::randomForest.formula`, `randomForest::randomForest.default` — ORDER=R; CHUNK=H; state: per tree a row-indexed bootstrap (`sampsize`, `strata`, drawn in compiled code) and node-wise split search over sorted values; notes: response with ≤ 5 unique values check (randomForest.default.R:20) is trivial; OOB error and importance need per-row OOB vote state; escape: online bagging (Poisson(1) row weights, still R) plus binned split search → one pass per tree depth with K state keyed by (tree, node, variable, bin); `combine()` merges forests grown on separate chunks — the only existing chunk-ish path, not equivalent to one forest on all rows.
- `randomForest::predict.randomForest` — ORDER=E; CHUNK=M; state: none; notes: classification ties are broken at random (predict.randomForest.Rd:75) → per-row RNG for tied votes (R); `proximity = TRUE` builds an ntest × ntest matrix (predict.randomForest.R:131) → H; new factor levels are checked against stored `xlevels` (predict.randomForest.R:97-103).
- `randomForest::na.roughfix.data.frame` — ORDER=I; CHUNK=P; state: pass 1 per-column median (H; quantile sketch or K when few distinct values) and per-factor level counts (K); pass 2 fill (M); notes: mode ties resolved by level order via `which.max(table(x))` (na.roughfix.R:12-13), so order-free.
- `randomForest::rfImpute.formula`, `randomForest::rfImpute.default` — ORDER=R; CHUNK=H; state: n × n proximity matrix per iteration (rfImpute.R:41).
- **verdict**: not a chunking target beyond `predict()` (M); forest growth is R and H, with `combine()` as prior art for chunk-parallel sub-forests.

### mda

- `mda::fda` (default `method = polyreg`) — ORDER=I; CHUNK=P; state: pass 1 A: X'X, X'G (class-indicator cross-products, p × J) and class weight sums (K by class) — `theta <- contr.fda(dp, theta)` (fda.R:42) needs the class proportions before `Theta`, but X'Theta = (X'G)·theta can be formed after the pass, and `ssm <- t(Theta) %*% fitted(fit)/n` (fda.R:47) equals Theta'X (X'X)⁻¹ X'Theta / n; pass 2 M + K: the stored `confusion(predict(obj), fg)` needs predictions and a J × J table; notes: `polyreg` uses `qr(x)` (polyreg.R:13); `polybasis` of degree > 1 is row-local; `method = gen.ridge` is also A; `method = mars` and `method = bruto` → H (below).
- `mda::mda` — ORDER=R; CHUNK=P; state: EM with fixed `iter = 5` passes, each a weighted fda fit on subclass-augmented rows → A cross-products weighted by responsibilities that can be recomputed row-locally from the current fit (mda.R:62-80); notes: starting subclasses from per-class k-means (`kmeans.start`) with random centres and `tries = 5` restarts (mda.start.R) → R.
- `mda::mars` — ORDER=I; CHUNK=H; state: per-column sort `tagx[, j] <- order(x[, j])` (mars.R:56) and knot search over data values (compiled); notes: binned candidate knots would give P × K.
- `mda::bruto` — ORDER=I; CHUNK=H; state: adaptive smoothing-spline backfitting (compiled, bruto.R:113).
- `mda::predict.fda`, `mda::predict.mda`, `mda::predict.mars` — ORDER=E; CHUNK=M; state: none.
- `mda::confusion.fda` — ORDER=I; CHUNK=K; state: J × J predicted-by-true counts.
- **verdict**: `fda` with `polyreg`/`gen.ridge` is an exact two-pass cross-product method; `mda` is P (EM) after an R initialisation; `mars`/`bruto` are holistic.

### pls

- `pls::mvr`, `pls::plsr`, `pls::pcr` (methods `kernelpls` default, `simpls`, `svdpc`) — ORDER=I; CHUNK=A; state: column means of X and Y, X'X, X'Y, Y'Y (centred via Chan-style merging); a second M pass only if scores, fitted values or residuals are wanted; notes: `kernelpls.fit` forms `XtY <- crossprod(X, Y)` (kernelpls.fit.R:115) but then recomputes `t.a <- X %*% r.a` and `p.a <- crossprod(X, t.a)` per component (144-146); algebraically p.a = X'X r.a / (r.a' X'X r.a), so the whole coefficient path runs on X'X (Dayal–MacGregor kernel algorithm 1); `svdpc` uses `La.svd(X)` (svdpc.fit.R:83), i.e. eigen(X'X); `scale = TRUE` (mvr.R:290) is a rescaling of the A state; `widekernelpls` (XX', n × n) → H; `oscorespls`/`nipals` → P (NIPALS, several A passes per component).
- `pls::mvr(validation = "CV")`, `pls::crossval`, `pls::cvsegments` — ORDER=R (`segment.type = "random"`, `sample(1:N)`, cvsegments.R:140) or D (`"consecutive"`/`"interleaved"` by row position, cvsegments.R:143-160); CHUNK=A; state: one set of cross-products per fold (training = total minus fold), exact if fold labels are assigned row-locally (e.g. by hashing a key); notes: LOO → n folds → H.
- `pls::mvrValstats` (`MSEP`, `R2`, `RMSEP` with `newdata`) — ORDER=I; CHUNK=A; state: per-ncomp SSE and test-response moments.
- `pls::predict.mvr`, `pls::scores.default`, `pls::predplot.mvr` — ORDER=E; CHUNK=M; state: none.
- `pls::stdize`, `pls::msc` — ORDER=I; CHUNK=P; state: pass 1 column means/sds (or mean spectrum), pass 2 M.
- **verdict**: `plsr`/`pcr` with `kernelpls`, `simpls` or `svdpc` are exact single-pass A methods once rewritten on X'X/X'Y; CV becomes A per fold if folds are assigned by key instead of position.

### pscl

- `pscl::zeroinfl` — ORDER=I; CHUNK=P; state: (1) starting values from `glm.fit` binomial on Y == 0 and Poisson/NB count fits (zeroinfl.R:288-313), each IRLS with A cross-products; (2) optional EM (`EM = TRUE`), each iteration two weighted IRLS fits (zeroinfl.R:330-400); (3) `optim()` BFGS on the summed log-likelihood with analytic gradient (zeroinfl.R:411), each fn/gr evaluation one A pass (scalar or (kx + kz + 1)-vector), Hessian by finite differences of the gradient (≈ 2p more passes); notes: `drop.unused.levels = TRUE` (zeroinfl.R:178) → level pre-pass; sums make it order-free up to FP; the number of passes is in the hundreds.
- `pscl::hurdle` — ORDER=I; CHUNK=P; state: as zeroinfl; notes: `separate = TRUE` runs two independent `optim()` calls (hurdle.R:308-315), the truncated count part on rows with Y > 0 (row-local filter), so both can share data passes.
- `pscl::predict.zeroinfl`, `pscl::predict.hurdle`, `pscl::predprob` — ORDER=E; CHUNK=M; state: none.
- `pscl::vuong` — ORDER=I; CHUNK=A; state: n, sum and sum of squares of per-row log-likelihood ratios between two fitted models.
- **verdict**: `zeroinfl`/`hurdle` are exact P targets (sum-of-rows likelihood under `optim`), costly in passes; caching per-chunk sufficient statistics is impossible because the likelihood is non-quadratic.

### mclust

- `mclust::Mclust`, `mclust::mclustBIC`, `mclust::densityMclust` — ORDER=D (ties) / R (n > 2000); CHUNK=P; state: after initialisation, EM passes with A state per component (Σz, Σz·x, Σz·xx') for each model × G; notes: initialisation is model-based agglomerative `hc()` on SVD-transformed data (`hcUse = "SVD"`, options.R:10; mclust.R:660) → O(n²) H; for n > `mclust.options("subset")` = 2000 a random row subset is drawn (mclust.R:596) → R; for n ≤ 2000 tied values make the hc merge order position-dependent (verified on `faithful`: different local optimum after permutation, identical after jitter); escape: initialise from a sample (or pass `initialization = list(hcPairs/z)`), then stream EM.
- `mclust::me`, `mclust::em`, `mclust::mstep`, `mclust::estep` — ORDER=I; CHUNK=P (`me`, `em`) / A (`mstep`) / M (`estep`); state: per-component weighted moments; notes: verified `me()` is permutation-invariant given matching `z`; the n × G `z` matrix need not be stored if the E-step is recomputed per chunk.
- `mclust::MclustDA` — ORDER=D/R; CHUNK=P; state: per class (K by class) the Mclust state above; notes: inherits the hc initialisation trap.
- `mclust::predict.Mclust`, `mclust::predict.densityMclust`, `mclust::predict.MclustDA` — ORDER=E; CHUNK=M; state: none.
- **verdict**: the EM core (`me`/`em`) is a clean P target with A state; the default `Mclust()` front end is neither order-free (ties in `hc()`) nor seed-stable under permutation (subset sampling).

### naivebayes

- `naivebayes::naive_bayes.formula`, `naivebayes::naive_bayes.default` — ORDER=I; CHUNK=K; state: class counts (`table(y)`), per class × numeric feature n, Σx, Σx² (`tapply(var, y, mean/sd)`), per class × categorical feature × level counts (`table(y, var)`, naive_bayes.default.R:58), per class Σx for `usepoisson` (line 34); notes: textbook exact chunkable model; Laplace smoothing is applied at the end; trap: the fitted object keeps the full training data (`data = list(x = data, y = y)`, naive_bayes.default.R:68) — a streaming version must drop it; `usekernel = TRUE` calls `density()` per class (line 43) → H (escape: fixed-grid binned KDE per class with a pre-chosen bandwidth).
- `naivebayes::gaussian_naive_bayes`, `naivebayes::multinomial_naive_bayes`, `naivebayes::bernoulli_naive_bayes`, `naivebayes::poisson_naive_bayes` — ORDER=I; CHUNK=A; state: J × p matrices `rowsum(x, y)` and `rowsum(x^2, y)` plus class counts (gaussian_naive_bayes.R:76-77); notes: σ from Σx² − n·μ² (cancellation) → use Welford/Chan merging.
- `naivebayes::nonparametric_naive_bayes` — ORDER=I; CHUNK=H; state: KDE per class.
- `naivebayes::predict.naive_bayes` — ORDER=E; CHUNK=M; state: none.
- **verdict**: `naive_bayes()` (non-kernel) and the specialised `*_naive_bayes()` fits are exact single-pass K/A; only the stored copy of the data blocks streaming.

### moments

- `moments::skewness`, `moments::kurtosis`, `moments::moment` (central, not absolute), `moments::all.moments`, `moments::agostino.test`, `moments::anscombe.test`, `moments::jarque.test` — ORDER=I; CHUNK=A; state: n and central power sums up to order 4 per column (Pébay pairwise merge); notes: the tests `sort()` x first (agostino.test.R:5) for no reason; the code is two-pass `x - mean(x)`.
- `moments::geary`, `moments::bonett.test`, `moments::moment(central = TRUE, absolute = TRUE)` — ORDER=I; CHUNK=P; state: pass 1 mean, pass 2 Σ|x − mean| and Σ(x − mean)² (geary.R: `tau <- sum(abs(x-mean(x)))/n`); notes: K if few distinct values.
- **verdict**: all of moments is chunkable; skewness/kurtosis/Jarque–Bera are single-pass A.

### lsr

- `lsr::pairedSamplesTTest` (long form `y ~ time + (id)`) — ORDER=D; CHUNK=K; state: values keyed by id to form pairs, then A over differences; notes: trap — wide columns follow `times <- unique(data[, within])` (longToWide.R:64, first appearance) while `group.names` come from `levels()` (pairedSamplesTTest.R:363), and the test uses `WF[, 2]` vs `WF[, 3]` (line 421); verified that putting the second level first flips the sign of t and of the reported mean difference with unchanged labels, so `one.sided` can test the wrong direction.
- `lsr::cohensD(formula, method = "paired")` — ORDER=D; CHUNK=K; state: as above; notes: pairs by within-group row position, the source itself warns (cohensD.R:160).
- `lsr::independentSamplesTTest`, `lsr::cohensD` (two groups), `lsr::oneSampleTTest`, `lsr::ciMean` — ORDER=I; CHUNK=K; state: n, mean, M2 per group (A for one sample); notes: group names from factor levels (independentSamplesTTest.R:171).
- `lsr::associationTest`, `lsr::goodnessOfFitTest`, `lsr::cramersV` — ORDER=I; CHUNK=K; state: contingency counts.
- `lsr::correlate` — ORDER=I; CHUNK=A; state: pairwise co-moments with pairwise-complete counts; notes: `corr.method = "spearman"` → H.
- `lsr::longToWide` — ORDER=S; CHUNK=K; state: rows keyed by id; notes: output columns ordered by first appearance of `within`.
- `lsr::wideToLong`, `lsr::expandFactors` — ORDER=E; CHUNK=M; state: none; notes: `expandFactors` needs the level set (pre-pass K or declared).
- `lsr::bars` — ORDER=I; CHUNK=K; state: n, mean, M2 per cell.
- `lsr::aad`, `lsr::modeOf`, `lsr::sortFrame` — ORDER=I; CHUNK=P / K / H; state: mean then Σ|x − mean| / counts per value / full sort.
- **verdict**: the two-group tests and association tests are trivially K; the long-form paired test is a genuine order trap (sign flips with row order).

### psychotools

- `psychotools::raschmodel` (also reached through `anchor.formula`, `anchortest.formula`) — ORDER=I; CHUNK=A; state: weighted item totals `cs <- colSums(y * weights)` and raw-score frequencies `rf` (raschmodel.R:56-58); conditional ML then optimises on these aggregates only, with no further data passes; notes: with missing responses the same statistics are kept per NA pattern (raschmodel.R:114-133) → K keyed by pattern; the identifiability check (all-0/all-1 items) follows from the totals.
- `psychotools::anchor.formula`, `psychotools::anchortest.formula` — ORDER=I; CHUNK=K; state: one Rasch sufficient-statistic set per level of the grouping covariate; notes: anchor selection then works on the two fitted models only.
- `psychotools::itemresp`, `psychotools::paircomp` — ORDER=E; CHUNK=M; state: none; notes: data-class constructors; scale/labels need a pre-pass or declaration.
- **verdict**: `raschmodel` is a rare exact single-pass fit (CML sufficient statistics); `anchortest` is K over two groups.

### segmented

- `segmented::segmented.lm`, `segmented::segmented.glm`, `segmented::segreg`, `segmented::stepreg` — ORDER=R; CHUNK=P; state: per iteration an lm/glm fit on [X, U(ψ), V(ψ)] → A cross-products (IRLS for glm), plus RSS evaluations for step-length control; notes: default `seg.control(n.boot = 10)` (seg.control.R:2) does bootstrap restarting with `sample(n, size.boot, replace = TRUE)` (seg.lm.fit.boot.r:135) → R; with `n.boot = 0` and user `psi` it is I; default starting ψ from `quantile(Z, ...)` (segmented.lm.R:240) → H pre-pass.
- `segmented::segmented.lme` — ORDER=R; CHUNK=P; state: repeated `nlme::lme` fits; notes: grouped data, invariant between groups only if the correlation structure has no positional component.
- `segmented::predict.segmented`, `segmented::predict.stepmented` — ORDER=E; CHUNK=M; state: none.
- **verdict**: `segmented.lm` with `n.boot = 0` and given `psi` is an exact P/A target; the defaults are R and need a quantile pre-pass.

### nlstools

- `nlstools::test.nlsResiduals` — ORDER=D; CHUNK=M; state: sign-run counter across chunks; notes: runs test on residual signs in row order (nlsResiduals.R:146-153) — trap, meaningful only for ordered data; the Shapiro–Wilk part is H.
- `nlstools::nlsContourRSS`, `nlstools::nlsConfRegions` — ORDER=I; CHUNK=A; state: RSS per grid / sampled parameter vector, all parameter points can be evaluated in one data pass; notes: `nlsConfRegions` samples parameters, not rows.
- `nlstools::nlsBoot`, `nlstools::nlsBootPredict` — ORDER=R; CHUNK=P; state: per replicate an `nls` refit on resampled residuals `sample(scale(resid1))` (nlsBoot.R:14).
- `nlstools::nlsJack` — ORDER=I; CHUNK=H; state: n leave-one-out refits.
- `nlstools::preview` — ORDER=E; CHUNK=M; state: none.
- **verdict**: little to gain; the residual runs test is an order trap.

### lmPerm

- `lmPerm::lmp`, `lmPerm::aovp` — ORDER=R; CHUNK=H; state: permutation p-values over the response; notes: the default `perm = "Exact"` falls back to Monte-Carlo `"Prob"` when N > `maxExact` (permtst.R:45), random permutations drawn in C (permtst.R:48) → R; exact enumeration is H; the point estimates are lm (A); `center = TRUE` (lmp.R:160) needs column means (A pre-pass).
- **verdict**: only the lm part chunks; permutation tests are R/H by nature.

### ppcor

- `ppcor::pcor`, `ppcor::spcor`, `ppcor::pcor.test`, `ppcor::spcor.test` — ORDER=I; CHUNK=A; state: covariance matrix, then `solve(cov)` (ppcor.R:23-33, 75-85); notes: `method = "spearman"`/`"kendall"` → H.
- **verdict**: Pearson partial correlations are single-pass A.

### outliers

- `outliers::grubbs.test`, `outliers::outlier`, `outliers::chisq.out.test` — ORDER=I; CHUNK=A; state: n, mean, M2, min and max (top-2/bottom-2 for `type = 20`); notes: the statistics only use extremes and moments (grubbs.test.R:15-41) even though the code sorts.
- `outliers::dixon.test` — ORDER=I; CHUNK=A; state: the 3 smallest and 3 largest values; notes: the test is limited to n ≤ 30 anyway.
- `outliers::scores` — ORDER=I; CHUNK=P; state: z/t/chisq: pass 1 moments then M (scores.R:14-34); `iqr`/`mad`: H (quantile sketch escape).
- `outliers::rm.outlier` — ORDER=I; CHUNK=P; state: pass 1 extremes and mean (H with `median = TRUE`), pass 2 M.
- `outliers::cochran.test` — ORDER=I; CHUNK=K; state: per-group variance.
- **verdict**: Grubbs/Dixon/chi-square outlier tests are exact single-pass A despite sorting.

### leaps

- `leaps::regsubsets.formula`, `leaps::regsubsets.default` — ORDER=I; CHUNK=A; state: (p+1) × (p+1) Givens QR built by AS274 `makeqr` (leaps.R:129); all subset searches (exhaustive, forward, backward, seqrep) then run on the QR only; notes: **already chunk-capable** through `leaps::regsubsets.biglm` (leaps.R:504) — fit `biglm::biglm()` and `update()` chunk-wise, then select subsets; factor levels need a pre-pass for the model matrix.
- **verdict**: `regsubsets` is the cleanest A in the batch, with existing biglm interop.

### lars

- `lars::lars` (`use.Gram = TRUE` default) — ORDER=I; CHUNK=A; state: column means and norms, Gram X'X (lars.R:68), X'y, y'y; notes: the path updates correlations from the Gram only (`Cvec <- Cvec - gamhat * Gram[, active] %*% w`, lars.R:204); the final `residuals <- y - x %*% t(beta)` (lars.R:238) only feeds RSS, which is y'y − 2β'X'y + β'X'Xβ; centring from raw sums risks cancellation → merge centred co-moments.
- `lars::cv.lars` — ORDER=R; CHUNK=A; state: per-fold Gram; notes: folds from `sample(1:n)` (cv.folds.R:4).
- **verdict**: `lars` is exact single-pass A once residuals are dropped.

### ncvreg

- `ncvreg::ncvreg` — ORDER=I; CHUNK=P; state: pre-pass A for standardisation `std(X)` (ncvreg.R:204) and λ_max from X'y; then compiled coordinate descent with residual updates (`cdfit_gaussian`/`cdfit_glm`, ncvreg.R:238-245; compiled, inferred), one pass per sweep; notes: for gaussian, covariance-update coordinate descent on X'X/X'y would make it A.
- `ncvreg::cv.ncvreg` — ORDER=R; CHUNK=P; state: per fold as above; notes: random fold assignment.
- **verdict**: gaussian `ncvreg` could become A (Gram-based CD); GLM families stay P.

### SparseM

- `SparseM::slm` — ORDER=I; CHUNK=A; state: sparse X'X and X'y, `chol(t(x) %*% x)` then `backsolve` (SparseM.R:1008-1010); notes: residuals and fitted values need a second M pass.
- **verdict**: exact single-pass A (sparse normal equations).

### MatrixModels

- `MatrixModels::glm4` — ORDER=I; CHUNK=P; state: per IRLS step sparse X'WX and X'Wz (`Cholesky(crossprod(...))`, modelMatrix.R:166-174; IRLS loop at modelMatrix.R:392); notes: model frame with unused levels dropped → pre-pass.
- `MatrixModels::model.Matrix` — ORDER=E; CHUNK=M; state: none given `xlev`; notes: `drop.unused.levels` and level sets need a K pre-pass.
- **verdict**: `glm4` is a sparse IRLS P target with A state per pass.

### yaImpute

- `yaImpute::yai` — ORDER=I; CHUNK=H; state: kNN index over reference rows (ANN kd-tree); notes: `method = "mahalanobis"`/`"msn"`: A pre-pass for centre/scale (yai.R:289-290) and canonical correlations (`cancor`, yai.R:364) from cross-products; `bootstrap = TRUE` resamples references `sample(refs, replace = TRUE)` (yai.R:252) → R; `method = "randomForest"` or `"ica"` → R; escape: chunk over target rows (M), or stream reference rows keeping a k-best heap per target (state n_targets × k).
- `yaImpute::newtargets`, `yaImpute::impute.yai`, `yaImpute::AsciiGridImpute` — ORDER=E; CHUNK=M; state: the fitted reference set; notes: `AsciiGridImpute` **already streams** raster rows, reading one line at a time with `scan(nlines = 1)` and calling `newtargets()` per row (asciigridimpute.R:268-351).
- **verdict**: target-side imputation is M and already streamed for grids; building the reference model is A (cancor) + H (kNN index).

### RANN

- `RANN::nn2` — ORDER=S; CHUNK=H; state: kd-tree over `data`; notes: query rows are M given the tree; ties between equidistant neighbours are resolved by tree layout → S; exact streaming over `data` is possible with a per-query top-k heap (state n_query × k).
- **verdict**: chunk over `query` (M); stream `data` only with a k-best merge.

### tree

- `tree::tree` — ORDER=I; CHUNK=H; state: recursive partitioning in compiled code (`BDRgrow1`, tree.R:69) with numeric split search over sorted values per node; notes: exact alternative is one pass per depth with K state keyed by (node, variable, distinct value) holding class counts or Σy, Σy²; binned splits make it A per depth; factor splits use per-level statistics (K).
- `tree::prune.tree(newdata = )` — ORDER=I; CHUNK=K; state: deviance per node accumulated by dropping new rows down the tree.
- `tree::predict.tree` — ORDER=E; CHUNK=M; state: none.
- **verdict**: validation-set pruning and prediction chunk; growing is H (or P × K level-wise).

### Matching

- `Matching::MatchBalance` — ORDER=R; CHUNK=H; state: per-arm moments for t-tests and variance ratios (A), eQQ statistics (`qqstats`, H), KS bootstrap `sample(1:obs, obs, replace = TRUE)` (GenBalance.R:202) → R.
- `Matching::Match` — ORDER=I (`ties = TRUE`) / R (`ties = FALSE`, random tie-breaking); CHUNK=H; state: nearest-neighbour search over all controls; notes: chunkable over treated units with all controls indexed.
- **verdict**: only the mean/variance balance statistics chunk.

### locfit

- `locfit::locfit` — ORDER=I; CHUNK=H; state: local likelihood fits at evaluation vertices; notes: defaults `alpha = 0.7` (nearest-neighbour bandwidth, a distance quantile per fit point) and `ev = rbox()` (adaptive tree from the data) (man/locfit.raw.Rd:8-13) → H; escape: fixed bandwidth `alpha = c(0, h)` plus fixed evaluation points (`ev = lfgrid()` or user points) needs only kernel-weighted local moment sums per evaluation point → A (P for non-Gaussian local likelihood); compiled core, reasoned from the wrapper and docs.
- `locfit::preplot.locfit`, `locfit::predict.locfit` — ORDER=E; CHUNK=M; state: none.
- **verdict**: exact chunking only with fixed bandwidth and grid; prediction is M.

### locpol

- `locpol::locpol` — ORDER=S; CHUNK=H; state: local polynomial fit on an `xeval` grid; notes: the grid fit itself is P (range pre-pass, `seq(min, max, len = xevalLen)`, locpol.R:764, then per-grid-point kernel moment sums → A) given `bw`; but `bw = NULL` triggers CV bandwidth selection (locpol.R:767-769, H), residuals need a local fit at every data point (locpol.R:782, H) and the variance smoother needs those residuals; the stored model frame and residuals are in sorted-x order, not input order (`xo <- order(...)`, locpol.R:759-760) → S.
- `locpol::predict.bivNpEst` — ORDER=E; CHUNK=M; state: none.
- **verdict**: with a given `bw` the regression estimate on the grid is an exact two-pass target; the default call is holistic.

### scam

- `scam::scam` — ORDER=I; CHUNK=P; state: per Newton/IRLS step a QR of the weighted design (`qr(wX11, LAPACK = TRUE)`, scam.fit1.r:529) and derivative quantities for GCV/UBRE that are row sums once R⁻¹ is known (scam.fit1.r:549) → ≥ 2 passes per step (A state); notes: shape-constrained smooths space knots through the data range when none are supplied (uni.smooth.const.r:24) → range pre-pass (A); no chunked fitter exists (unlike `mgcv::bam`).
- `scam::predict.scam` — ORDER=E; CHUNK=M; state: none; notes: **already processes `newdata` in blocks** (`block.size` default 1000, predict.scam.R:181).
- **verdict**: fitting is P with A state but needs a bam-style redesign; prediction is already blocked.

### minpack.lm

- `minpack.lm::nlsLM` — ORDER=I; CHUNK=P; state: per Levenberg–Marquardt iteration J'J, J'r and RSS → A; notes: the residual and Jacobian functions are evaluated on the full data by compiled MINPACK; chunking needs a user-level residual function that loops over chunks.
- **verdict**: exact P target in principle, low priority.

### Rfit

- `Rfit::rfit.default`, `Rfit::rfit`, `Rfit::raov` — ORDER=I; CHUNK=H; state: Jaeckel's dispersion needs ranks of residuals at every `optim()` step (rfit.default.R:43), plus orthonormal `qr.Q()` of the design (rfit.default.R:20-23); notes: τ estimation (`gettau`, `taustar`) uses pairwise residual differences → H; `jitter()` restart on non-convergence (rfit.default.R:46) uses RNG but not per row; escape: approximate ranks via quantile sketches.
- **verdict**: holistic by construction (rank-based).

### laeken

- `laeken::arpr`, `laeken::arpt`, `laeken::qsr`, `laeken::rmpg`, `laeken::incMedian`, `laeken::weightedMedian`, `laeken::weightedQuantile` — ORDER=I; CHUNK=H; state: weighted sort of incomes; notes: weighted quantile via `cumsum(weights)` over `order(x)` (weightedQuantile.R:73-90); the `rw[select] == p` branch is unreachable because `select` is the first index with `rw > p`, so tie order within equal incomes does not matter; escape: K exact when incomes have few distinct values (weights summed per value), else weighted t-digest; `arpr` = H pass for the threshold then an A pass for the weighted proportion; `breakdown =` domains → K × H.
- `laeken::gini` — ORDER=I; CHUNK=H; state: sorted incomes with cumulative weights (gini.R:203-211); notes: the formula Σ w·x·cw is symmetric within tied incomes (Σ_i w_i s_i = (W² + Σ w_i²)/2), so the optional `sort =` tie-breaker cannot change it; K exact over distinct incomes.
- `laeken::calibWeights` — ORDER=I; CHUNK=P; state: per Newton iteration `crossprod(X, w)` and the p × p Jacobian (calibWeights.R:116-174) → A; final weights g·d are row-local (M); notes: neat exact chunk target (raking/linear/logit calibration).
- `laeken::eqSS` — ORDER=I; CHUNK=P; state: pass 1 household member counts and members aged ≥ 14 per (year, household) via `table()` (eqSS.R:16-17) → K; pass 2 map back (M).
- `laeken::calibVars.data.frame`, `laeken::calibVars.matrix` — ORDER=E; CHUNK=M; state: none given the level set (K pre-pass).
- `laeken::bootVar` — ORDER=R; CHUNK=P; state: per replicate, H estimators on resampled rows.
- **verdict**: `calibWeights` (P with A state) and `eqSS` (K) chunk exactly; the poverty indicators need weighted quantiles (H, K for discrete incomes).

### SSBtools

- `SSBtools::model_aggregate`, `SSBtools::aggregate_by_pkg`, `SSBtools::FormulaSums`, `SSBtools::HierarchyCompute`, `SSBtools::tables_by_formulas` — ORDER=I; CHUNK=K; state: sums per output cell (crossprod of a sparse dummy model matrix with the values, or `aggregate(aggFormula, data, sum)`, FormulaSums.R:223); notes: `model_aggregate(pre_aggregate = TRUE)` already reduces rows to cells before building the model matrix — a built-in K reduction; arbitrary `fun_vars` functions are H per cell unless decomposable; output row order follows sorted cell keys (`SortRows`, FormulaSums.R:270).
- `SSBtools::ModelMatrix`, `SSBtools::Formula2ModelMatrix`, `SSBtools::Hierarchies2ModelMatrix`, `SSBtools::HierarchiesAndFormula2ModelMatrix` — ORDER=E; CHUNK=M; state: none once the column set (observed code combinations, K pre-pass) is fixed.
- `SSBtools::FindDisclosiveCells`, `SSBtools::Extend0fromModelMatrixInput` — ORDER=I; CHUNK=K; state: frequencies per code combination.
- `SSBtools::Extend0rnd1` — ORDER=R; CHUNK=K; state: as Extend0 with random extra rows (`sample`, Extend0rnd1.R:74).
- `SSBtools::Match`, `SSBtools::any_duplicated_rows` — ORDER=S; CHUNK=K; state: hash set of seen keys; notes: `Match` returns first-match positions.
- `SSBtools::Unstack`, `SSBtools::unmatrix`, `SSBtools::MatrixToDataFrame` — ORDER=E; CHUNK=M.
- **verdict**: statistical-disclosure tabulation is K throughout; `model_aggregate` is the target and its `pre_aggregate` step is already the chunk reduction.

### qtl

- `qtl::scanone` — ORDER=I (`method = "hk"`, `"mr"`, `"em"`) / R (`"imp"`, `n.perm > 0`); CHUNK=A (hk, mr) / P (em) / H (`"np"`, Kruskal–Wallis ranks); state: per locus regression cross-products of phenotype on genotype probabilities over individuals (rows); notes: compiled `R_scanone_hk` etc. (scanone.R:570-620); permutations (`n.perm`) → R; `batchsize` batches phenotype columns, not individuals.
- `qtl::calc.genoprob` — ORDER=E; CHUNK=M; state: none; notes: HMM along markers within each individual — row-local over individuals (compiled).
- **verdict**: `scanone(method = "hk")` is A per locus over individuals; the many `summary.*`/`plot*` candidates are plumbing on scan results.

### xtable

- `xtable::xtable.data.frame` with `auto = TRUE` (`xalign`, `xdigits`, `xdisplay`, `autoformat`) — ORDER=I; CHUNK=P; state: per column max decimals after `zapsmall(abs(v - floor(v)), zap)` (autoformat.R:22), which depends on the column-wide max, so pass 1 = max |frac| (A), pass 2 = max nchar (A); notes: without `auto`, digits/display come from column classes only.
- `xtable::print.xtable`, `xtable::print.xtableList`, `xtable::print.xtableMatharray` — ORDER=E; CHUNK=M; state: header/footer once, cells via `formatC()` per column (print.xtable.R:524-536); notes: default `hline.after = c(-1, 0, nrow(x))` needs the row count (emit at the end).
- **verdict**: a streaming LaTeX/HTML writer is easy (M) once digits are fixed; `auto = TRUE` needs a two-pass A pre-scan.

### R2HTML

- `R2HTML::HTML.data.frame`, `R2HTML::HTMLgrid` — ORDER=E; CHUNK=P; state: pass 1 per-column common format decisions (`format(x, digits = , nsmall = )` formats each column jointly, HTMLcore.R:731), i.e. max significant decimals/width (A); pass 2 M row emission; notes: chunk-wise `format()` would give inconsistent decimals across chunks.
- **verdict**: writer target needing a format pre-pass.

### writexl

- `writexl::write_xlsx` — ORDER=E; CHUNK=M; state: rows written by compiled libxlsxwriter in one call (`.Call(C_write_data_frame_list)`, write_xlsx.R:126); notes: no append API; `xl_sheet(auto_colwidth = TRUE)` sizes columns to their contents → max nchar per column (A pre-pass).
- `writexl::xl_filter_keep` — ORDER=E; CHUNK=M; state: none (row-local filter evaluation, xl_filter.R:374-381).
- **verdict**: M writer; column autofit is the only global quantity.

### WriteXLS

- `WriteXLS::WriteXLS` — ORDER=E; CHUNK=M; state: rows exported via temporary CSV + Perl; notes: `AdjWidth = TRUE` (WriteXLS.R:24, 263) needs per-column max widths (A pre-pass).
- **verdict**: M writer with an optional width pre-pass.

### r2rtf

- `r2rtf::rtf_body`, `r2rtf::rtf_encode`, `r2rtf::rtf_page` — ORDER=E; CHUNK=M; state: running page row count and previous by-group values; notes: with `page_by`/`group_by`/`subline_by` the input must already be sorted, `stop("Data is not sorted by ...")` (rtf_body.R:190) → D (requires order); `rtf_page(nrow = )` paginates by position; column widths are relative and user-given.
- **verdict**: sequential writer, chunkable as a stream with carried page/group state but not order-free when by-variables are used.

### tinytable

- `tinytable::tt.data.frame`, `tinytable::tt.default`, `tinytable::save_tt` — ORDER=E; CHUNK=P; state: pass 1 per-column smallest |value| for `num_fmt = "significant"` (column-wise significant digits, format_tt.R:17) and max cell width for grid/markdown output (A); pass 2 M rendering; notes: `num_fmt = "significant_cell"`/`"decimal"` make formatting cell-local; `group_tt(i = )` row groups are positional → D.
- **verdict**: renderer that needs a width/digits pre-pass, otherwise M.

### nanoarrow

- `nanoarrow::as_nanoarrow_array_stream.data.frame`, `nanoarrow::as_nanoarrow_array.data.frame`, `nanoarrow::infer_nanoarrow_schema.data.frame` — ORDER=E; CHUNK=M; state: schema only (inferred from column classes, not values); notes: the data-frame method wraps the whole frame as one batch (`basic_array_stream(list(x))`, array-stream.R:168-177), but `basic_array_stream(batches)` and `convert_array_stream(n = )` (convert-array-stream.R:46) already provide the batch-stream plumbing a chunked rewrite would use.
- `nanoarrow::as.data.frame.nanoarrow_array_stream` — ORDER=E; CHUNK=M; state: none (collects batches).
- **verdict**: the enabling infrastructure for chunk-wise consumption, already stream-capable.

### nanoparquet

- `nanoparquet::write_parquet` — ORDER=E; CHUNK=M; state: per row group the column statistics (min/max, A) and dictionaries (K); notes: row groups are fixed positional slices (`default_row_groups`, write-parquet.R:259-266); **already chunk-capable** via `append_parquet()` (write-parquet.R:369), which may rewrite the last row group to fill it.
- **verdict**: chunked writing exists (`append_parquet`).

### yyjsonr

- `yyjsonr::write_ndjson_file`, `yyjsonr::write_ndjson_str`, `yyjsonr::write_ndjson_raw` — ORDER=E; CHUNK=M; state: none; notes: no append flag, but NDJSON chunks concatenate trivially; the reader is already chunkable (`read_ndjson_file(nread, nskip)`, ndjson.R:40) though its column types come from the first `nprobe = 100` records → type inference is order-dependent (D) on read.
- **verdict**: M writer; mind the probe-based typing on the read side.

### RODBC

- `RODBC::sqlSave`, `RODBC::sqlUpdate` — ORDER=E; CHUNK=M; state: none; notes: rows are inserted with parameterised statements (`fast = TRUE`, sql.R:156-159); **chunk-capable** today via `sqlSave(append = TRUE)`; column types are chosen from the first chunk.
- **verdict**: already usable for chunked writes.

### sp

- `sp::SpatialPointsDataFrame`, `sp::SpatialMultiPointsDataFrame` — ORDER=E; CHUNK=M; state: bounding box `t(apply(coords, 2, range))` (SpatialPoints-methods.R:15-20) → A; notes: `match.ID` matches coordinate row names to data row names (SpatialPointsDataFrame-methods.R:13-24) → K join, otherwise positional zip of two inputs (chunks must align).
- `sp::aggregate.Spatial` — ORDER=I; CHUNK=K; state: per target polygon an accumulator, rows assigned by `over(by, x, fn = FUN)` (aggregate.R:82); notes: decomposable FUN only; area-weighted mode is geometric.
- `sp::spmap.to.lev`, `sp::split.SpatialPoints`, `sp::as.data.frame.Spatial*` — ORDER=E; CHUNK=M (split → K by factor).
- **verdict**: aggregation over polygons is K; constructors are M plus an A bbox.

### wk

- `wk::wk_handle.data.frame`, `wk::wk_handle_slice.data.frame`, `wk::wk_translate.data.frame`, `wk::wk_restore.data.frame`, `wk::as_xy.data.frame`, `wk::as_rct.data.frame`, `wk::as_crc.data.frame` — ORDER=E; CHUNK=M; state: handler state; notes: wk is a streaming handler framework — `wk_handle_slice(from, to)` and `wk_chunk_strategy_feature()`/`wk_chunk_strategy_coordinates()` (chunk.R:31-39) **already chunk** features; reducers such as `wk_bbox()`/`wk_envelope()` (bbox.R:12-36) are A.
- **verdict**: already chunk-capable; geometry reducers are A.

### lmodel2

- `lmodel2::lmodel2` — ORDER=I (R with `nperm > 0`); CHUNK=A; state: means and covariance matrix of (y, x) (`cov(yx)`, `cor(y, x)`, lmodel2.R:61-64) plus ranges for ranged major axis (lmodel2.R:143); notes: RMA rescaling is a transform of this state; permutation tests → R.
- **verdict**: OLS/MA/SMA/RMA Model II regression are single-pass A.

### rmeta

- `rmeta::meta.MH`, `rmeta::meta.DSL`, `rmeta::meta.summaries` — ORDER=I; CHUNK=A; state: Mantel–Haenszel numerator/denominator sums over strata (rows), and for DerSimonian–Laird Σw, Σwy, Σwy² for the Q statistic; notes: rows are studies.
- `rmeta::cummeta`, `rmeta::cummeta.summaries` — ORDER=D; CHUNK=A; state: running meta-analysis state; notes: cumulative meta-analysis over `subset = 1:i` in row order (meta.R:25-72) by design.
- **verdict**: fixed/random-effects pooling is A; `cummeta` is intentionally order-dependent.

### robumeta

- `robumeta::robu` — ORDER=I; CHUNK=P; state: per study (K keyed by `studynum`) the X'WX blocks, residual cross-products and size counts via `by(..., study)` (robu.R:155-196, 272); pass 1 estimates τ²/ρ, pass 2 the RVE weighted fit.
- `robumeta::predict.robu` — ORDER=E; CHUNK=M.
- **verdict**: exact K/P (study-clustered), provided rows of a study can be grouped.

### mixmeta

- `mixmeta::mixmeta` — ORDER=I; CHUNK=P; state: per iteration sums over studies of X_i'Σ_i⁻¹X_i-type terms (e.g. `sumList(lapply(Xlist, crossprod))`, mixmeta.reml.R:13); REML/ML by Newton or IGLS iterations; notes: multilevel random terms group studies → K keyed by group.
- `mixmeta::predict.mixmeta` — ORDER=E; CHUNK=M.
- **verdict**: P with A/K state; rows are studies, so data are usually small.

### kyotil

- `kyotil::iorw` — ORDER=R; CHUNK=P; state: glm/coxph fits on mediator and outcome models with inverse-odds weights (iorw.R:21-59); notes: default `nboot = 10000` bootstrap with row resampling → R; coxph part needs K over event times.
- `kyotil::myaggregate`, `kyotil::mytapply` — ORDER=I; CHUNK=K; state: per group accumulator for decomposable FUN.
- `kyotil::skew`, `kyotil::mycor` (pearson) — ORDER=I; CHUNK=A; notes: `mycor` spearman/kendall → H.
- `kyotil::myscale` — ORDER=I; CHUNK=P; state: means/sds then M (`scale()`, base.R:287-290).
- `kyotil::predict.auc` — ORDER=I; CHUNK=H; state: ranks `rank(c(score1, score2))` (auc.R:177); notes: K exact if scores have few distinct values.
- **verdict**: utility grab-bag; only the aggregation helpers chunk.

### qcc

- `qcc::mqcc`, `qcc::stats.T2`, `qcc::stats.T2.single` — ORDER=I; CHUNK=P; state: pass 1 centre (column means) and covariance (A), pass 2 Hotelling T² per row (M) (`solve(cov)`, mqcc.R:428-542); notes: control charts are read in time order, so run rules are D, but the limits are order-free.
- **verdict**: two-pass A then M.

### pastecs

- `pastecs::stat.desc` — ORDER=I; CHUNK=H; state: basic counts/min/max/sum (A) plus median (H) in the default `desc = TRUE`; notes: `norm = TRUE` adds Shapiro–Wilk (H); with `desc = FALSE` it is A.
- `pastecs::regul`, `pastecs::turnpoints`, `pastecs::vario`, `pastecs::disto`, `pastecs::escouf` — ORDER=D; CHUNK=M; notes: space/time series tools (expected order dependence).
- **verdict**: `stat.desc` is A except for the median.

### RWiener

- `RWiener::wdm` — ORDER=I; CHUNK=P; state: summed Wiener first-passage-time log-likelihood per `optim()` evaluation (wdm.R:76-98) → A; notes: `xvar` groups fit separately (K).
- **verdict**: P with scalar A state.

### sensemakr

- `sensemakr::sensemakr.formula`, `sensemakr::ovb_contour_plot.formula`, `sensemakr::ovb_extreme_plot.formula` — ORDER=I; CHUNK=A; state: the `lm` cross-products; partial R², robustness values and benchmark bounds are functions of t statistics and df of that single fit.
- **verdict**: single-pass A via a chunked `lm` (e.g. biglm).

### stabs

- `stabs::stabsel.data.frame` (with `glmnet.lasso`, `lars.lasso`, `lars.stepwise`) — ORDER=R; CHUNK=P; state: per subsample a selection path; notes: `B` complementary-pair subsamples by row (`subsample(rep(1, nrow(x)), B = B)`, stabsel.R:13) → R.
- **verdict**: R by design; each subsample fit could use a Gram-based lars (A).

### som

- `som::som`, `som::som.train` — ORDER=D; CHUNK=M; state: codebook updated sequentially; notes: online SOM training in compiled code with no row sampling in the R wrapper (som.R:62-89), so samples are visited in data order (SOM_PAK port; compiled, inferred) → D; `init = "sample"` draws rows (`sample`, som.R:10) → R; default `init = "linear"` uses `prcomp(data)` (som.R:28) → A pre-pass.
- `som::normalize` — ORDER=E; CHUNK=M (row-wise by default).
- **verdict**: order trap (sequential learning); a batch-SOM variant would be P with K state per codebook unit.

### proxy

- `proxy::dist`, `proxy::simil` — ORDER=S; CHUNK=H; state: all pairwise distances; notes: with `y` given (cross-distances) it is M over blocks of `x` rows given `y`; output labels follow input order.
- **verdict**: holistic except cross-distance blocks.

### timeDate

- `timeDate::skewness.data.frame`, `timeDate::kurtosis.data.frame` — ORDER=I; CHUNK=A; state: per-column power sums up to order 4.
- **verdict**: single-pass A.

### wrapr

- `wrapr::has_no_dup_rows`, `wrapr::checkColsFormUniqueKeys` — ORDER=I; CHUNK=K; state: hash set of seen keys (early exit on first duplicate).
- `wrapr::sortv` — ORDER=I; CHUNK=H; state: sort.
- `wrapr::draw_frame`, `wrapr::draw_framec` — ORDER=E; CHUNK=M.
- **verdict**: key-uniqueness checks are K.

### splitTools

- `splitTools::multi_strata` — ORDER=I; CHUNK=P; state: quantile-based binning of numeric stratification columns (H, or a quantile sketch) then K strata codes.
- **verdict**: K after a quantile pre-pass.

### normalp

- `normalp::lmp` — ORDER=I; CHUNK=P; state: `lm` start (A), then alternating `optim()` BFGS on the exponential-power log-likelihood and shape updates until convergence (lmp.R:4-37), each evaluation a summed A pass.
- **verdict**: P with A state.

### pesel

- `pesel::pesel` — ORDER=I; CHUNK=A; state: covariance matrix `eigen(cov(X))` (auxilliary.R:15, 49) with optional scaling; notes: n-asymptotics branch; the p-asymptotics branch works on the transposed problem (H in n).
- **verdict**: A for tall data.

### rrBLUP

- `rrBLUP::kin.blup` — ORDER=I; CHUNK=H; state: n × n kinship / Gaussian kernel matrix between genotypes.
- **verdict**: holistic.

### plotrix

- `plotrix::brkdnNest`, `plotrix::barNest`, `plotrix::multivari` — ORDER=I; CHUNK=K; state: FUN per nested factor cell (decomposable FUN such as mean, sd, length).
- `plotrix::std.error` — ORDER=I; CHUNK=A.
- **verdict**: grouped summaries feeding plots are K.

### nortest (no-candidate package)

- `nortest::pearson.test` — ORDER=I; CHUNK=P; state: pass 1 n, mean, sd; pass 2 counts in `n.classes` equiprobable classes `tabulate(floor(1 + n.classes * pnorm(x, mean, sd)))` (pearson.test.R:13-14) → A.
- `nortest::ad.test`, `nortest::cvm.test`, `nortest::lillie.test`, `nortest::sf.test` — ORDER=I; CHUNK=H; state: sorted sample (`sort(x)`, e.g. ad.test.R:5) for EDF / Shapiro–Francia statistics.
- **verdict**: only the chi-square test chunks (two passes).

### sm (no-candidate package)

- `sm::sm.density`, `sm::sm.regression` — ORDER=I; CHUNK=P; state: pass 1 n, range and sd; pass 2 binning onto `nbins = 8 log(n)` bins per dimension with per-bin counts/means/sums (`binning()`, utilities.r:48-62; enabled when n > 500, density.r:21) → A; the estimate is then computed from bins only; notes: bandwidth `h.select()` with the normal-reference rule uses `wvar()` (hselect.r:255-275, A), but `method = "cv"` on unbinned data (density.r:46-49 passes `nbins = 0`) → H.
- **verdict**: exact under sm's own binning approximation, with supplied or normal-reference bandwidth.

### stargazer (no-candidate package)

- `stargazer::stargazer` (data-frame summary table) — ORDER=I; CHUNK=A; state: per numeric column n, mean, sd, min, max (defaults `median = FALSE`, `iqr = FALSE`, stargazer.R:19-20; stargazer-internal.R:6893-6900); notes: `median = TRUE` or `iqr = TRUE` adds `quantile()` (stargazer-internal.R:4286) → H.
- **verdict**: the default summary table is single-pass A.

### statmod (no-candidate package)

- `statmod::mixedModel2` (`randomizedBlock`) — ORDER=I; CHUNK=P; state: REML scoring for one variance component via `La.svd` of block-projected designs (mixedmodel.R:71-103), with blocks K-keyed.
- `statmod::glmgam.fit`, `statmod::glmnb.fit` — ORDER=I; CHUNK=P; state: IRLS cross-products (A per pass).
- `statmod::elda` (`limdil`) — ORDER=I; CHUNK=K; state: tested/responding totals per (group, dose).
- `statmod::qresiduals` — ORDER=R; CHUNK=M; state: none; notes: randomised quantile residuals draw `runif(length(y))` per row (qres.R:34) → R under permutation with a fixed seed.
- **verdict**: `elda` is K; the GLM fitters are standard P.

### matrixStats (no-candidate package)

- `matrixStats::colSums2`, `colMeans2`, `colVars`, `colWeightedMeans`, `binCounts`, `binMeans` — ORDER=I; CHUNK=A; state: per-column sums / Welford moments / fixed-bin counts; notes: matrix interface (data frames must be coerced).
- `matrixStats::colMedians`, `colQuantiles`, `colMads`, `colRanks`, `colWeightedMedians` — ORDER=I; CHUNK=H.
- `matrixStats::colTabulates` — ORDER=I; CHUNK=K.
- `matrixStats::colCumsums` and friends — ORDER=D.
- `matrixStats::rowMeans2`, `rowVars`, `rowMedians`, `rowLogSumExps` — ORDER=E; CHUNK=M (row-wise over data rows).
- **verdict**: reference kernels for A/H/K column reductions.

### lmom (no-candidate package)

- `lmom::samlmu` — ORDER=I; CHUNK=H; state: sorted sample for probability-weighted moments (`sort.data = TRUE`, lmom.r:548-568).
- **verdict**: holistic (order statistics).

### survRM2 (no-candidate package)

- `survRM2::rmst2` — ORDER=I; CHUNK=K; state: per arm the number at risk and events per distinct time (Kaplan–Meier, `order(y)` in func_surv.R:10), then area under the curve up to τ.
- **verdict**: K over unique event times.

### Skipped

Candidates all plumbing (print/format/coercion/getters/plotting/interactive) or not data-frame consumers:
`NLP`, `PhysicalActivity` (accelerometer time series), `plotfunctions`, `rlang`, `remotes`, `parallelly`, `permute`, `popbio`, `praznik`, `relimp`, `rje`, `rmutil`, `rootSolve`, `rpanel`, `rpart.plot` (rules from a fitted tree), `rrapply`, `sets`, `spatstat.utils`, `textutils` (cell-wise `toHTML`/`toLatex` writers, M), `TeachingDemos`, `tinyplot`, `universals`, `varhandle`, `variables`, `wavelets` (DWT/MODWT, time series D), `whitebox`, `xfun` (`md_table`, M with a width pre-pass), `xmlparsedata`, `zeallot`, `mvtnorm` (`simulate.mvnorm` generates data), `nleqslv`, `microbenchmark`, `multcompView`, `modeltools` (model-frame plumbing), `sfsmisc`, `salso` (posterior clustering samples), `ThreeWay` (`CP`/`T3` are interactive, with 33/48 `scan`/`readline` prompts), `zipfR` (inputs are already frequency spectra), `ncf`, `pbapply` (`pbby` is `by()` with a progress bar), `pamr` (`pamr.batchadjust` adjusts genes, not data-frame rows).

<!-- source: findings/cran_depth2_a.md -->
## Part: Findings: CRAN depth 2, batch A (actuar .. lm.beta)

Sources read from the extracted CRAN tarballs under `scratchpad/src/<pkg>/R` (R code only).
Where behaviour lives in compiled code (libsvm, collapse C kernels, DuckDB, lavaan's few C helpers), the claim is reasoned from the R wrapper and the Rd files and says so.
Claims marked "verified" were checked with the current CRAN binaries on R 4.5.3,
by permuting rows with a fixed seed and comparing with `all.equal()`, or by a minimal reproducer;
the scripts are `scratchpad/tests/biglm_t.R` and `scratchpad/tests/lav_t.R`.
Each finding is one line so the files can be merged mechanically.

### biglm

- `biglm::bigglm.function` — ORDER=I; CHUNK=P; state: per IRLS pass an AS274 incremental Givens QR of the weighted working regression (`D`, `rbar` of length p(p-1)/2, `thetab`, `ss`; bigqr.init.R:4-7) plus running deviance, rss and n, optionally a second QR with p(p+1) columns for the sandwich meat; at most `maxit = 8` passes, gaussian needs 2 (pass 1 starts from `beta = NULL`, i.e. eta = 0, pass 2 only confirms convergence); notes: ALREADY CHUNK-CAPABLE and the reference design — `data` is a `function(reset)` that the fitter rewinds with `data(reset=TRUE)` and drains chunk by chunk on every pass (bigglm.R:40-42), and the Rd states that chunks "need not be the same size or in the same order when the data are reread" (bigglm.Rd:64-66); verified permutation-invariant against `glm()` (binomial, 5 passes). Global information up front is minimal and that is the weakness: `terms(formula)` is built without data, so `.` in the formula fails ("'.' in formula and no 'data' argument", verified); p and the `assign` vector are taken from the FIRST chunk's model matrix (bigglm.R:52-57) and later chunks are only checked with `identical(assn, attr(mm,"assign"))` (bigglm.R:58) — factor LEVELS are never carried forward (no `xlev`), so a character column whose chunks hold equally many but different values is silently mis-coded (verified: chunk 1 {a,b}, chunk 2 {b,c} gives coefficients `(Intercept), x, gc` where `glm()` gives `gb, gc`), and data-dependent terms (`poly()`, `ns()`, `scale()`) are re-evaluated per chunk (verified `poly(x,2)` disagrees with `glm()`); both are documented as forbidden (bigglm.Rd:70-73) but not detected. TRAPS/BUGS: `n <- n + nrow(chunk)` counts rows before `na.omit` (bigglm.R:43), so df.resid and the dispersion are wrong with NAs (verified: 300 NA rows give df.resid 2996 vs glm's 2696; `biglm()` counts correctly); with `sandwich = TRUE` the inner `for(i in 1:p)` (bigglm.R:74) clobbers the IRLS counter that feeds `iterations` and the `if (i >= maxit)` exit (bigglm.R:81,90), so with p >= maxit the fit stops after 2 passes, warns "ran out of iterations" and reports `iterations = p` (verified p = 9: iterations 9, converged FALSE vs 5/TRUE without sandwich); `rss` is scaled by the CHUNK mean weight `sum(w)/length(w)` (bigglm.R:70), so it depends on the chunking when weights vary; the deviance is accumulated at the pass's starting beta, i.e. lags the returned coefficients by one iteration.
- `biglm::biglm`, `biglm::update.biglm` — ORDER=I; CHUNK=A; state: AS274 Givens QR (`D`, `rbar`, `thetab`, `ss`) + n, plus a p(p+1)-column QR for `sandwich = TRUE` (biglm.R:17-27); notes: ALREADY CHUNK-CAPABLE: `fit <- biglm(f, chunk1); fit <- update(fit, chunk2)` (update.biglm.R:2-26), verified equal to a one-shot `biglm()`; same level/`assign` trap (update.biglm.R:10) and no data-dependent terms; `weights` must be a one-sided formula; the state is updatable sequentially but no merge of two independently built QRs is provided (possible by feeding one fit's sqrt(D)·R rows into the other's `update.bigqr`), so parallel map-reduce needs that extra step.
- `biglm::bigglm.data.frame` — ORDER=I; CHUNK=P; state: as `bigglm.function`; notes: wraps an in-memory data frame in a cursor closure returning `data[start:cursor,]` (bigglm.R:6-19), which keeps factor levels, so factor columns are safe here while character columns hit the level trap above; `chunksize = 5000`.
- `biglm::bigglm` (S4 `DBIConnection` method, `bigglm.RODBC`) — ORDER=I; CHUNK=P; state: as `bigglm.function`; notes: prior art for out-of-core GLM over a database: issues `SELECT <model vars> FROM <table>` and fetches `chunksize` rows at a time, re-issuing the query on every reset (sqlite.R:11-28, odbc.R:8-23); no `ORDER BY` needed because the fit is order-free.
- `biglm::predict.bigglm`, `biglm::predict.biglm` — ORDER=E; CHUNK=M; state: none (coef, vcov); notes: `model.frame(object$terms, newdata)` without `xlev` (predict.R:59) re-derives levels per newdata chunk; BUG: `se.fit = TRUE` calls `se.fit(newmm)` on the logical argument (predict.R:67) and fails with "could not find function se.fit" (verified), and would return the function `se` rather than values (predict.R:68).
- **verdict**: `bigglm(data = function(reset))` and `biglm()`+`update()` are the canonical already-chunked fitters; the valuable fixes are carrying `xlevels` (and `predvars`) from a declared or pre-pass level set instead of comparing `assign`, counting n after `na.omit`, and the sandwich loop-counter bug.

### ff

- `ff::chunk.ffdf`, `ff::chunk.ff_vector` — ORDER=E; CHUNK=M; state: none — returns a list of contiguous `ri` index ranges of size `BATCHBYTES %/% RECORDBYTES` in storage order (ffdf.R:1813-1858); notes: the chunk iterator itself; the package's own example feeds the chunks to `biglm::update()` (`for (i in chunk(firis)) biglmfit <- update(biglmfit, firis[i,,drop=FALSE])`, ffdf.R:1785-1800), i.e. prior art for the chunked-lm idiom; `ffdfapply` is in ffbase, not in ff (no match in these sources).
- `ff::ffvecapply`, `ff::ffrowapply`, `ff::ffcolapply`, `ff::ffapply` — ORDER=E; CHUNK=M; state: per-batch result, optionally reduced with a `CFUN`; notes: batched evaluation of an expression over `bbatch(N, B)` index ranges (ffapply.R:177-212); whether the whole computation is A/K depends on the user's expression and CFUN.
- `ff::csum`, `ff::clength`, `ff::cmean`, `ff::cmedian`, `ff::cquantile`, `ff::csummary` (CFUN) — ORDER=I; CHUNK=A; state: per-chunk result vectors combined after the fact; notes: TRAPS — `cmean` is the UNWEIGHTED mean of chunk means (`s/nl`, documented "(unweighted) mean", CFUN.R:58), exact only for equal chunk sizes although `bbatch()` usually leaves a short last chunk; `cmedian`/`cquantile`/`csummary` apply FUN to the rbind of per-chunk results (CFUN.R:52-55,145-150), i.e. the median of chunk medians, an approximation and not the global median (H); BUG: with `na.rm = TRUE`, `csum` and `cmean` add `l[[1]]` instead of `l[[i]]` (CFUN.R:238,254,288,311), verified `csum(c(1,NA), c(2,3), na.rm=TRUE)` gives `2 NA` instead of `3 3`.
- `ff::read.table.ffdf`, `ff::read.csv.ffdf` — ORDER=S; CHUNK=K; state: per factor column the growing level set; notes: levels are sorted within the first chunk and new levels are appended in order of appearance thereafter, so the integer coding depends on chunk size and row order (documented, ffcsv.R:172,186); fixed afterwards by the `sortLevels()` recode pass (fffactor.R:179-186) or up front with `levels=`/`appendLevels=FALSE` — prior art for "declare levels before streaming".
- `ff::as.ffdf.data.frame` — ORDER=E; CHUNK=M; state: none; notes: column-wise copy into ff files; plumbing apart from fixing factor levels at creation.
- **verdict**: ff supplies the chunk iterator (`chunk()`, `ffrowapply`) but no order-free reducers worth the name; fix the CFUN `na.rm` bug and weight `cmean` by chunk length.

### duckdb

- `duckdb::duckdb_register` — ORDER=E; CHUNK=M; state: none — registers the data frame as a zero-copy virtual table (register.R:45-62); notes: queries on the view run in DuckDB's vectorised, morsel-parallel engine (C++, not in these sources), where projections and filters are applied in the scan, `GROUP BY`/aggregates are K hash aggregates, and `ORDER BY`, exact `quantile_cont`/`median` are H (with `approx_quantile`/`reservoir_quantile` as sketches); result order without `ORDER BY` is engine-defined (S); `experimental = TRUE` enables experimental scan optimisations.
- `duckdb::duckdb_register_arrow`, `duckdb::dbAppendTable` (duckdb_connection) — ORDER=E; CHUNK=M; state: none; notes: prior art for streaming ingestion — an Arrow `RecordBatchReader` is scanned batch by batch (register.R:83-146), and `dbAppendTable` registers each R chunk as a temporary view and `INSERT ... SELECT`s it (dbAppendTable__duckdb_connection.R:27-35); `duckdb_read_csv` infers the schema from the first `nrow.check = 500` rows of each file (csv.R:76-85) and then streams with `COPY` — the same "global schema from a prefix" trap as bigglm's first chunk.
- **verdict**: DuckDB is the realistic out-of-core backend for the K/A aggregations catalogued elsewhere (`GROUP BY` with decomposable aggregates); nothing in its R layer needs rewriting.

### collapse

- `collapse::fsum`, `collapse::fmean`, `collapse::fprod`, `collapse::fmin`, `collapse::fmax`, `collapse::fnobs` (`.data.frame`, `.grouped_df`) — ORDER=I; CHUNK=K; state: per (group, column) sum, count, weighted sum and weight total, product, min, max (A when `g = NULL`); notes: the C kernels take an integer group id vector plus `ng` (fmean.R:59-77), so a chunked driver needs a global group dictionary (K) across chunks; groups are sorted by default (`.op$sort <- TRUE`, zzz.R:132; `GRP.default(sort = .op[["sort"]])`, GRP.R:96), with `sort = FALSE` the output follows first appearance (S, verified `GRP(c("b","a","b","a"), sort=FALSE)` gives b, a); `TRA =` turns any of them into P (pass 1 group stats, pass 2 M sweep); `fprod` overflows for long groups.
- `collapse::fvar`, `collapse::fsd` — ORDER=I; CHUNK=K; state: per group Welford (n, mean, M2) or weighted Welford, mergeable with Chan's formula; notes: `stable.algo = TRUE` default is Welford, `FALSE` is the one-pass sum-of-squares formula in long double (man/fvar_fsd.Rd:64-72).
- `collapse::qsu` (`.data.frame`, `.default`) — ORDER=I; CHUNK=K; state: per group n, mean, M2 (and M3, M4 with `higher = TRUE`), min, max via a one-pass Welford generalisation (man/qsu.Rd:19,79; `fbstatsCpp`, qsu.R:4-28); with `pid` the within/between decomposition needs those moments keyed additionally by entity (within SS = sum of per-pid M2, between stats over pid means), still one K pass.
- `collapse::collap`, `collapse::collapv` — ORDER=D with the defaults (I with a tie-free catFUN); CHUNK=K; state: per group the state of `FUN` for numeric columns (default `fmean`), of `catFUN` for categorical columns (default `fmode`: counts per (group, value)) and `wFUN` (default `fsum`) for weights (collap.R:95); notes: the D comes from `fmode`'s first-occurrence tie rule (next line); non-decomposable FUN (`fmedian`, `fnth`) makes it H per group; sort/order as for `GRP`.
- `collapse::fmode` (`.data.frame`) — ORDER=D; CHUNK=K; state: per (group, value) count or weight sum; notes: TRAP — default `ties = "first"` returns the first value in row order reaching the maximum count (man/fmode.Rd:75), verified `fmode(c(1,3,2,2,4,4,1,7))` = 2 but 4 on the reversed vector; `ties = "min"/"max"` is I (verified 1 both ways).
- `collapse::fgroup_by`, `collapse::GRP`, `collapse::group_by_vars` — ORDER=I; CHUNK=K; state: distinct key set (hash or radix order); notes: `sort = TRUE` by default (GRP.R:403), `sort = FALSE` gives first-appearance group order (S); `group_by_vars` is a getter.
- `collapse::fmedian`, `collapse::fnth` — ORDER=I; CHUNK=H; state: —; notes: exact order statistic per group (quickselect in C, weighted variant); escape hatch: K when the number of distinct values per group is small (value counts), otherwise a KLL/t-digest sketch per group.
- `collapse::fndistinct` — ORDER=I; CHUNK=K; state: per group set of distinct values; notes: HyperLogLog would make it A approximately.
- `collapse::fscale`/`STD`, `collapse::fwithin`/`W`, `collapse::fbetween`/`B` — ORDER=E; CHUNK=P; state: pass 1 K (per-group Welford mean/sd, man/fscale.Rd:74), pass 2 M (centre/scale or replace by group mean); notes: options `mean = "overall.mean"` or `sd = "within.sd"` add global moments to pass 1 but stay 2 passes.
- `collapse::fhdwithin`/`HDW`, `collapse::fhdbetween`/`HDB`, `fHDwithin`, `fHDbetween` — ORDER=E; CHUNK=P; state: per pass K sums per level of each fixed-effect factor (alternating projections via `fixest::demean`, fhdbetween_fhdwithin.R:4-11), plus A (X'X, X'y) for continuous covariates, then M for residuals; notes: number of passes set by the MAP convergence; a single factor is just 2 passes.
- `collapse::flag`/`L`, `collapse::fdiff`/`D`/`Dlog`, `collapse::fgrowth`/`G`, `collapse::fcumsum`, `collapse::ffirst`, `collapse::flast` — ORDER=D; CHUNK=H; state: —; notes: without `t`/`o` these use row order within groups; with `t` (lags/diffs) or `o` (fcumsum, fcumsum.R:69) the result is equivariant, but each group's rows must sit in one chunk sorted by time (chunk-by-group is then M); `ffirst`/`flast` are first/last in row order.
- `collapse::funique` (`.data.frame`) — ORDER=S; CHUNK=K; state: hash set of seen rows; notes: `sort = FALSE` default keeps first-appearance order (GRP.R:805,818).
- `collapse::varying` (`.data.frame`) — ORDER=I; CHUNK=K; state: per group first non-NA value and a "varies" flag, merged by OR and comparing first values.
- `collapse::pivot` — ORDER=D for `how = "wider"`/"recast" with duplicate id×name cells, E for "longer"; CHUNK=K; state: per (ids, names) cell the FUN state, default `FUN = "last"` (pivot.R:146), documented as "the last of those duplicates in first-appearance-order" (pivot.R:303); ids are sorted (`GRP.default(sort = TRUE)`, pivot.R:269); "longer" is row-local M.
- `collapse::descr` — ORDER=I; CHUNK=H; state: —; notes: quantiles via `.quantile` (descr.R:96-97, `Qprobs` default 1%..99%) plus moments (A) and frequency tables for categoricals (K); escape: KLL sketch for the quantiles.
- `collapse::BY` (`.data.frame`, `.matrix`, `.grouped_df`), `collapse::dapply`, `collapse::rsplit` — ORDER=S; CHUNK=H; state: —; notes: split-apply-combine with an arbitrary FUN needs complete groups (K-partitioning, then M per group); `dapply(MARGIN = 1)` is row-local M; `rsplit` keeps within-group row order.
- `collapse::psmat`, `collapse::psacf`, `collapse::pspacf` — ORDER=D; CHUNK=H; state: —; notes: panel-series reshaping and autocorrelations by (id, time).
- `collapse::fsubset`, `collapse::TRA` (given STATS), `collapse::%r+%`/`%r-%`/`%r*%`/`%r/%`/`%rr%`, `collapse::fdroplevels` — ORDER=E; CHUNK=M; state: none; notes: `fdroplevels` needs a K pass for the used levels first (P).
- **verdict**: `collap()`/`fsum`/`fmean`/`fvar`/`qsu` are clean K hash aggregations once a global group dictionary is maintained across chunks; watch `fmode(ties = "first")` (the default `catFUN` of `collap`) and `pivot(FUN = "last")`, which are row-order traps.

### datawizard

- `datawizard::standardize.data.frame`, `datawizard::center.data.frame` (and `.grouped_df`) — ORDER=E; CHUNK=P; state: pass 1 A per column (weighted n, mean, M2; per group for `grouped_df`), pass 2 M; notes: `robust = TRUE` uses `weighted_median`/`weighted_mad` (utils_standardize_center.R:262-279), making pass 1 H; ALREADY CHUNK-FRIENDLY in the sense that numeric `center=`/`scale=` or a `reference=` data frame fix the parameters (utils_standardize_center.R:254-283), so `standardize(chunk, center = m, scale = s)` is pure M; `unstandardize`/`unnormalize` invert from stored attributes (M).
- `datawizard::rescale.data.frame`, `datawizard::normalize.data.frame`, `datawizard::reverse.data.frame`, `datawizard::slide.data.frame` (and `.grouped_df`) — ORDER=E; CHUNK=P; state: pass 1 A min/max per column (data_rescale.R:121,142-143; normalize.R:99-100; data_reverse.R:91; slide.R:50), pass 2 M; notes: `range=`/`to=` arguments let the caller fix the parameters; `normalize` also checks `n_unique == 2` (bounded K).
- `datawizard::winsorize.data.frame` — ORDER=E; CHUNK=P; state: pass 1 H for `method = "percentile"` (sorts the column, winsorize.R:120-125), A for `"zscore"` (mean/sd; H with `robust = TRUE`), none for `"raw"`; pass 2 M clipping; notes: BUG — `n <- length(data)` counts NAs while `sort()` drops them (winsorize.R:120-123), so with NAs the upper threshold indexes past the sorted values and the upper tail is not clipped (verified: `c(1:10, 100, NA x6)` keeps 100).
- `datawizard::describe_distribution.data.frame` — ORDER=I; CHUNK=H; state: —; notes: the default `iqr = TRUE` computes `IQR(type = 6)` (describe_distribution.R:201-203) and `quartiles = TRUE` adds quantiles, so H; with `iqr = FALSE`, `centrality = "mean"` the rest (mean, SD, min, max, skewness, kurtosis) is A; `ci =` bootstraps (R); TRAP — the full column is kept as `attr(out, "data")` (describe_distribution.R:282,350,414).
- `datawizard::skewness.data.frame`, `datawizard::kurtosis.data.frame` — ORDER=I; CHUNK=A; state: n and power sums up to order 3/4 (or Welford-style central moments); notes: `iterations =` bootstraps the SE via `boot::boot` (R).
- `datawizard::data_tabulate` (`.default`, `.data.frame`, `.grouped_df`) — ORDER=I; CHUNK=K; state: counts (or weight sums) per value, per `by` cell; notes: `drop_levels = FALSE` reports empty factor levels from declared levels.
- `datawizard::means_by_group` (`.numeric`, `.data.frame`) — ORDER=I; CHUNK=K; state: per group weighted n, mean, M2; notes: the ANOVA table and CIs come from `lm(x ~ group)` and `emmeans` contrasts (means_by_group.R:196-228), all derivable from the K state.
- `datawizard::data_summary` (`.data.frame`, `.grouped_df`, `.matrix`) — ORDER=I; CHUNK=K; state: per group the state of each user expression; notes: arbitrary expressions evaluated on `split(x, l, drop = TRUE)` (data_summary.R:153,196); K only for decomposable expressions (mean, n, sd), H for median/quantiles.
- `datawizard::degroup`, `datawizard::demean` — ORDER=E; CHUNK=P; state: pass 1 K per-group means (`stats::ave`, demean.R:469-503; nested/cross-classified levels too), pass 2 M; notes: `center = "median"` is H; `center = "mode"` uses `distribution_mode()`, whose ties are broken by FIRST APPEARANCE (`uniqv <- unique(x)`, descriptives.R:32-47) although the message says "Returning the smallest value" (verified: `distribution_mode(c(3,3,1,1))` returns 3) — D.
- `datawizard::categorize` (`.data.frame`, `.grouped_df`) — ORDER=E; CHUNK=P; state: pass 1 H for the default `split = "median"` and `"quantile"`, A (min/max) for `"equal_length"`/`"equal_range"`, A for `"mean"`; pass 2 M; notes: codes are additionally shifted by `min(out)` (categorize.R:235), another global quantity; `labels = "median"` adds per-category medians (H).
- `datawizard::adjust` — ORDER=E; CHUNK=P; state: pass 1 A (X'X, X'y of `lm(var ~ effects)`), pass 2 M residuals; notes: `multilevel = TRUE` fits `lme4::lmer` (P, K per group), `additive = TRUE` fits `gamm4` (H/P), `bayesian = TRUE` fits rstanarm (R); residuals are written back at `complete.cases(data)` over all columns (adjust.R:233), not only the model variables.
- `datawizard::data_unique` (`.data.frame`, `.grouped_df`), `datawizard::data_duplicated` — ORDER=D; CHUNK=K; state: per key the kept row (and its NA count for `keep = "best"`); notes: `keep = "best"` keeps the duplicate with fewest NAs, then the first (data_unique.R:77-87), `"first"`/`"last"` are positional; the key is `paste(..., sep = "_")` (data_unique.R:61), so values containing "_" can collide.
- `datawizard::data_to_wide` — ORDER=S; CHUNK=K; state: per id the cells; notes: new column order is `unique(data[, names_from])`, i.e. first appearance (data_to_wide.R:352).
- `datawizard::ranktransform` (`.data.frame`, `.grouped_df`), `datawizard::data_arrange` — ORDER=E; CHUNK=H; state: —; notes: ranks/sort; external merge sort is the escape.
- `datawizard::data_merge` — ORDER=S; CHUNK=K; state: hash of the resident table's keys; stream the other side.
- `datawizard::data_to_long`, `data_separate`, `data_replicate`, `data_filter.data.frame`, `data_match`, `data_modify.data.frame`, `recode_values`, `convert_na_to`, `convert_to_na`, `replace_nan_inf`, `to_factor`, `labels_to_levels`, `assign_labels`, `to_numeric`, `empty_rows` — ORDER=E; CHUNK=M; state: none; notes: `convert_to_na(drop_levels = TRUE)` and `to_numeric(dummy_factors = TRUE)` need the global level set (K pre-pass or declared levels); `data_filter.grouped_df`/`data_modify.grouped_df` evaluate expressions per group, so `x == max(x)` style filters need a K pre-pass (P).
- `datawizard::empty_columns` — ORDER=I; CHUNK=A; state: per column "any non-missing" flag.
- `datawizard::smoothness.data.frame` — ORDER=D; CHUNK=H; state: —; notes: lag-1 autocorrelation or differences in row order.
- `datawizard::data_rotate` — ORDER=S; CHUNK=H; state: —; notes: transpose, output columns are input rows.
- **verdict**: mostly row-local transforms whose global parameters (mean/sd, min/max) come from one A pre-pass and can already be passed in (`center=`, `scale=`, `range=`, `reference=`); `means_by_group`/`data_tabulate` are K; fix the `winsorize` NA bug and the `distribution_mode` tie rule.

### lavaan

- `lavaan::lavaan`, `lavaan::cfa`, `lavaan::sem`, `lavaan::growth` (complete continuous data, ML/GLS/ULS) — ORDER=I; CHUNK=K; state: per group n, mean vector and cross-product/Welford covariance (A per group); the optimiser then works on the moments only, with no further pass over rows; notes: ALREADY CHUNK-CAPABLE via the summary-data arguments `sample_cov`, `sample_mean`, `sample_th`, `sample_nobs`, `nacov`, `wls_v` (lavaan 0.7-3, xxx_lavaan.R:31-43) — compute the moments chunk-wise and pass them (mind the N vs N-1 rescaling of `sample_cov`); `sampling_weights` just weight the moments.
- `lavaan::lavaan` & co. with `missing = "ml"` (FIML) — ORDER=I; CHUNK=K; state: per missingness pattern n, mean and covariance of the observed variables (`lav_data_mi_patterns`, lav_data_patterns.R:2-68); the FIML log-likelihood is evaluated from the per-pattern statistics (`lav_mvn_mi_loglik_samp`, lav_mvnorm_missing.R:76-120) and the h1 model by EM over the same statistics (lav_samplestats.R:734-783), so one K pass suffices; notes: the number of patterns can approach n; verified permutation-invariant (two groups, two variables with NAs, `estimator = "MLR"`: coefficients and SEs equal).
- `lavaan::lavaan` & co. with robust estimators (`MLM`, `MLR`, `se = "robust"`, scaled tests) — ORDER=I; CHUNK=P; state: Gamma/NACOV needs fourth-order moments (A, O(p^4) accumulators in one pass with raw moments, or 2 passes centred, lav_samplestats_gamma.R); MLR/Huber-White needs casewise scores at the estimates, i.e. one extra A pass after estimation; notes: with missing data the casewise scores are per row (another pass).
- `lavaan::lavaan` & co. with `ordered =` (DWLS/WLSMV) — ORDER=I; CHUNK=P; state: pass 1 K — univariate tables for thresholds (`tabulate`, lav_samplestats_step1.R:92) and bivariate tables for the polychoric correlations (lav_samplestats_step2.R:61); pass 2 A — NACOV from casewise scores evaluated at the pass-1 estimates; notes: with exogenous covariates the thresholds come from probit regressions (more passes); verified permutation-invariant (WLSMV coefficients and scaled chi-square equal).
- `lavaan::lavaan` & co. with `cluster =` (multilevel) — ORDER=I; CHUNK=K; state: per cluster size and mean (`lav_data_cl_patterns`, lav_data_patterns.R:148-), then within/between covariances; notes: rows of a cluster need not be adjacent for the sums, but the cluster table grows with the number of clusters.
- `lavaan::lavaan` & co. with `se = "bootstrap"` or `test = "bollen.stine"` — ORDER=R; CHUNK=P; state: per replicate moments; notes: resampling indexed by row position.
- `lavaan::efa` — ORDER=I; CHUNK=A; state: per group n, means, covariance; notes: also accepts `sample_cov`; rotation and fitting work on the moments.
- `lavaan::sam` — ORDER=I; CHUNK=P; state: as `lavaan` per block; notes: structural-after-measurement fits several lavaan models (measurement blocks, then structural part), each from sample statistics.
- `lavaan::lavH1`, `lavaan::inspectSampleCov`, `lavaan::lavInspectSampleCov` — ORDER=I; CHUNK=K; state: the h1 sample statistics as above (per group, per pattern).
- `lavaan::lavTables` — ORDER=I; CHUNK=K; state: one-way, two-way or response-pattern frequency tables of the ordinal variables.
- `lavaan::varTable` (with a data frame) — ORDER=I; CHUNK=K; state: per variable nobs, mean, variance, number of levels.
- **verdict**: lavaan is already "sufficient statistics in, model out" for complete continuous data; the valuable chunking target is computing the per-group, per-missingness-pattern and bivariate-table statistics (K) chunk-wise, with one extra pass for robust NACOV/casewise scores.

### emmeans

- `emmeans::ref_grid` — ORDER=I; CHUNK=K; state: one pass over the recovered data: per numeric covariate sum and n for the default `cov.reduce = mean` (ref-grid.R:455), its distinct values up to `cov.thresh` to decide `cov.keep` (ref-grid.R:607), sorted level sets of factors/characters (ref-grid.R:507,579,589), and the sum of `(weights)` per observed factor cell for `.wgt.` (ref-grid.R:851-872); notes: everything after the grid (emmeans, contrasts, tests) works on grid × vcov without rows; data are obtained by `recover_data()`, which re-evaluates the model's `data` from the call environment, so it needs the full data in RAM today; `cov.reduce = median` or a user function makes it H; `counterfactuals =` stacks all rows per counterfactual level, an A pass (mean of predictions per level) over chunks.
- `emmeans::qdrg`, `emmeans::qdrg.default` — ORDER=I; CHUNK=K; state: same reference-grid pass over `data`; notes: prior art for decoupling — builds a grid from a formula, data and user-supplied `coef`/`vcov`, so a model fitted out of core (e.g. by `biglm`) can feed emmeans given only the K summary.
- `emmeans::recover_data.*` (`.call`, `.lm`, `.lme`, `.gls`, `.svyglm`, `.lqmm`, `.MCMCglmm`, `.mcmc`, `.carbayes`, `.averaging`, `.gnls`, `.svyolr`, `.mmer`, `.brmsfit`) — ORDER=E; CHUNK=M; state: none; notes: model-frame plumbing; a chunked emmeans would replace it with the K summary above.
- `emmeans::joint_tests` — ORDER=I; CHUNK=K; state: via `ref_grid` (`cov.reduce`); notes: the rest is grid algebra.
- **verdict**: `ref_grid` needs one K pass (covariate means, level sets, cell weights) and nothing else from the rows; making `recover_data` optional when that summary is supplied (as `qdrg` nearly does) is the target.

### gamlss

- `gamlss::gamlss` — ORDER=I; CHUNK=P; state: per inner IRLS step of each parameter (mu, sigma, nu, tau) the weighted LS cross-products X'WX, X'Wz (A, `lm.wfit`, gamlss-5.R:227,531-636) plus the global deviance sum (gamlss-5.R:300-301,646-660); smoothers in the backfitting loop add `pb()` P-splines on a B-spline basis over [min, max] of x (pb.R:69-74, an A pre-pass; `pb.control(quantiles = TRUE)` makes it H), `cs()` knots at unique x (K), `lo()` (H), `random()`/`re()` (K per level); notes: RS (default) nests up to `n.cyc = 20` outer cycles × `cyc = 50` inner IRLS × `bf.cyc = 30` backfitting iterations (gamlss-5.R:1225,1263), so potentially hundreds of passes; CG adds cross-derivatives, still row sums; per-row working state (current linear predictors of every parameter) must be recomputed from coefficients each pass or kept out of core, and smoothers keep fitted values rather than coefficients.
- `gamlss::gamlssML` — ORDER=I; CHUNK=P; state: per objective evaluation the summed log-likelihood (A); notes: `nlminb`/`optim` (gamlssML.R:117-126), numerical Hessian adds passes.
- `gamlss::predict.gamlss`, `gamlss::predictAll` — ORDER=E; CHUNK=M; state: none per newdata row; notes: TRAP for chunked prediction — every call rbinds the TRAINING data with `newdata`, rebuilds the model matrix and refits `lm.wfit` on the training rows ("safe" prediction, predict.gamlss_23_12_21.R:62-140), so each chunk costs a full pass over the training data and needs `data =`; smoother predictions use the stored `$fun(xeval)` since 5.0-3 (pb.R:455-470) and are row-local.
- `gamlss::devianceIncr` — ORDER=E; CHUNK=M; state: none; notes: per-row deviance increments; their sum is A.
- `gamlss::gamlssCV`, `gamlss::CV` — ORDER=R; CHUNK=P; state: per fold the gamlss fit state; notes: fold ids `sample(K.fold, N, replace = TRUE)` indexed by row position (gamlssVGD_23_12_21.R:442); `gamlssVGD`/`VGD`/`TGD` take a user `rand` or `newdata` and are deterministic given them.
- `gamlss::getPEF`, `gamlss::getQuantile` — ORDER=D; CHUNK=H; state: —; notes: other covariates are fixed at their median (H) with `how = "median"`, or at the LAST observation `tail(x, 1)` with `how = "last"` (getPEF.R:58-70), which is row-order dependent; factors use the modal level (K).
- `gamlss::lms` — ORDER=I; CHUNK=P; state: as `gamlss`, repeated per candidate family and power transformation.
- `gamlss::stepGAIC`, `stepGAIC.VR`, `stepGAIC.CH`, `stepGAICAll.B`, `dropterm.gamlss`, `addterm.gamlss`, `drop1All`, `add1All`, `drop1TGD`, `add1TGD`, `stepTGD` — ORDER=I; CHUNK=P; state: one full gamlss fit per candidate term per step; notes: the TGD variants add a test-deviance A pass over `newdata`.
- `gamlss::pcat` — ORDER=I; CHUNK=P; state: per factor level the working sums (K), iterated for the level-merging penalty.
- `gamlss::wp`, `gamlss::bp` — ORDER=I; CHUNK=H; state: —; notes: worm/bucket plots on residual quantiles; `bp(bootstrap = TRUE)` resamples (R).
- **verdict**: parametric GAMLSS is P with A per pass (lots of passes); the most useful fix for chunked use is `predict.gamlss(newdata)` refitting on the training data per call.

### e1071

- `e1071::naiveBayes.default`, `e1071::naiveBayes.formula` — ORDER=I; CHUNK=K; state: class counts (`table(y)`), per class × numeric column n, mean, M2 (`tapply(mean)`, `tapply(sd)`, naiveBayes.R:12-15), per class × level counts for categoricals (`table(y, var)`, naiveBayes.R:19); notes: Laplace smoothing is applied at finalisation; prior art — the formula method accepts a contingency TABLE as `data` and fits from its margins (naiveBayes.R:64-80).
- `e1071::predict.naiveBayes` — ORDER=E; CHUNK=M; state: none.
- `e1071::svm.formula` (via `svm.default`) — ORDER=I; CHUNK=H; state: —; notes: libsvm SMO over the full kernel (C code, reasoned from the wrapper); `scale = TRUE` needs an A pre-pass for column means/sds (`scale_data_frame`, svm.R:156-173), stored for prediction; `cross =` and `probability = TRUE` add libsvm-internal resampling (R); escapes: linear kernel via SGD/LiblineaR, or chunk only the prediction rows.
- `e1071::predict.svm` — ORDER=E; CHUNK=M; state: none; notes: scales `newdata` with the stored centre/scale (svm.R:444).
- `e1071::gknn.formula`, `e1071::predict.gknn` — ORDER=I; CHUNK=H; state: —; notes: k-nearest neighbours; chunkable over the test rows only, with the training set resident.
- `e1071::tune`, `e1071::tune.nnet`, `e1071::tune.rpart` — ORDER=R; CHUNK=P; state: per fold × parameter combination a model; notes: `perm.ind <- sample(n)` (tune.R:71) assigns folds by row position.
- `e1071::scale_data_frame` — ORDER=E; CHUNK=P; state: pass 1 A column means/sds, pass 2 M; notes: accepts numeric `center`/`scale` vectors (M).
- `e1071::matchControls` — ORDER=D; CHUNK=H; state: —; notes: full `cluster::daisy` distance matrix (matchControls.R:47) and greedy nearest-control matching in case order, without replacement, ties broken by `sample()` (matchControls.R:49-60).
- `e1071::ica` — ORDER=D; CHUNK=P; state: unmixing matrix W updated row by row; notes: online SGD over rows in input order for `epochs` passes (ica.R:34-41) — streaming-native but order-dependent; random initial W.
- **verdict**: `naiveBayes` is a textbook K fit (and already takes tables); `skewness()`/`kurtosis()` (vector input, not flagged) are A; `svm` is H.

### gnm

- `gnm::gnm` — ORDER=I; CHUNK=P; state: per Newton/IRLS iteration X'WX, X'Wz for the non-eliminated parameters (A) plus per-level sums for the `eliminate` factor (K, absorbed analytically); notes: nonlinear terms get random starting values when `start` is missing, so the result depends on the seed (local optima) but not on row order.
- `gnm::expandCategorical` — ORDER=I; CHUNK=K; state: counts per (covariate pattern, category); notes: `group = TRUE` sorts by the covariates (`order(covar)`, expandCategorical.R:27-35) and tabulates — itself a pre-aggregation for multinomial-as-Poisson fits.
- `gnm::predict.gnm` — ORDER=E; CHUNK=M; state: none.
- **verdict**: `gnm` with `eliminate` is a P fit with K state; `expandCategorical` is the reusable K aggregation.

### brglm2

- `brglm2::brglmFit` (glm `method = "brglmFit"`; via `add1.brglmFit`/`drop1.brglmFit`) — ORDER=I; CHUNK=P; state: per quasi-Fisher iteration X'WX (A), then hat values from the current inverse information and the summed adjustment term (`hat_values`, brglmFit.R:462-529) — 2 passes per iteration (or reuse the previous iteration's inverse); notes: `add1`/`drop1` refit per term.
- `brglm2::brmultinom`, `brglm2::bracl` — ORDER=I; CHUNK=H; state: —; notes: as implemented, a Poisson log-linear fit with ONE nuisance parameter per observation (`Matrix::Diagonal(nkeep)`, brmultinom.R:216-236, bracl.R:153-159), so the parameter vector grows with n; K if the rows are first aggregated by covariate pattern; a direct multinomial IRLS would be P with A.
- `brglm2::brnb` — ORDER=I; CHUNK=P; state: per iteration A cross-products plus score sums for the dispersion.
- `brglm2::predict.bracl`, `brglm2::predict.brmultinom`, `brglm2::model.matrix.brmultinom` — ORDER=E; CHUNK=M; state: none.
- **verdict**: `brglmFit` is a P/A fit needing hat values per pass; the multinomial wrappers are H as written.

### brglm

- `brglm::brglm` — ORDER=I; CHUNK=P; state: per iteration a `glm.fit` on adjusted pseudo-responses (A per inner IRLS pass) plus hat values from `XWXinv` (brglm.R:184-219); notes: hats need the previous iteration's inverse information.

### GLMMadaptive

- `GLMMadaptive::mixed_model` — ORDER=S; CHUNK=P; state: per subject (K) the adaptive Gauss-Hermite contributions, with per-subject modes and curvatures carried across passes (updated every `update_GH_every = 10`), `iter_EM = 30` EM then quasi-Newton iterations (mixed_model.R:150-154); notes: rows of one subject must be in one chunk; subject ids are coded by first appearance (`match(id, unique(id))`, mixed_model.R:104), and TRAP — `weights` is one per subject (`length(unique(id))`, mixed_model.R:109) and matched positionally to that first-appearance order.
- `GLMMadaptive::predict.MixMod`, `GLMMadaptive::scoring_rules`, `GLMMadaptive::effectPlotData.MixMod` — ORDER=E; CHUNK=M; state: none for marginal/`mean_subject` predictions; notes: subject-specific predictions need empirical-Bayes estimates per subject (K, chunk by complete subjects).

### coxme

- `coxme::coxme` — ORDER=I; CHUNK=P; state: per Newton iteration K keyed by unique event time (sums of exp(eta), exp(eta)x, exp(eta)xx' per time, then reverse cumulative sums over sorted times; Efron ties need the per-time tied-death sums) plus K blocks per random-effect level; notes: needs a sort by time or time-keyed aggregation; `strata` partition the time keys.
- `coxme::lmekin` — ORDER=I; CHUNK=H; state: —; notes: n × n kinship/`varlist` covariance matrices.

### arules

- `arules::eclat` — ORDER=I; CHUNK=P; state: exact chunked mining is 2-pass SON — pass 1 local frequent itemsets per chunk at scaled minimum support, pass 2 global counts of the union of candidates (K); notes: as implemented H (vertical tid-lists in memory, C code); `apriori` (not flagged) is level-wise P with one K counting pass per itemset size; coercing a data frame to transactions is K (items from factor levels).
- `arules::discretizeDF` (and `discretize`) — ORDER=E; CHUNK=P; state: pass 1 H for the default `method = "frequency"` (quantile breaks), A for `"interval"` (range), R/P for `"cluster"` (k-means), none for `"fixed"`; pass 2 M via `cut()`; notes: `onlycuts = TRUE` returns the breaks for reuse on later chunks (prior art).
- `arules::confint.rules` — ORDER=I; CHUNK=K; state: rule contingency counts; notes: `method = "bootstrap"` resamples (R).

### ape

- `ape::compar.gee`, `ape::binaryPGLMM`, `ape::correlogram.formula`, `ape::compar.lynch` — ORDER=D; CHUNK=H; state: —; notes: n × n phylogenetic correlation `vcv(phy)` (compar.gee.R:20-22); rows are matched to tips by rownames, but if the rownames do not match all tips they are IGNORED with a warning and rows are taken positionally (compar.gee.R:26-37); O(n) tree-traversal algorithms (contrasts, phylolm) exist but are not row chunking.
- `ape::Initialize.corPhyl` (`corBrownian`, `corPagel`, … with `nlme::gls`) — ORDER=D; CHUNK=H; state: —; notes: without a `form = ~species` covariate "species will be taken as ordered in the data frame" (PGLS.R:55-57).
- `ape::yule.cov` — ORDER=D; CHUNK=H; state: —; notes: data rows are indexed positionally by node number (`X[phy$edge[, 1], ]`, yule.R:41-43).
- `ape::lmorigin` — ORDER=R; CHUNK=P; state: per permutation X'X, X'y; notes: `nperm = 999` row permutations (lmorigin.R:81); with `nperm = 0` it is A.
- `ape::dist.gene` — ORDER=I; CHUNK=H; state: —; notes: pairwise distances.
- `ape::as.phylo.formula` — ORDER=S; CHUNK=K; state: taxonomy hierarchy; notes: tip order follows the data.
- `ape::predict.compar.gee`, `ape::label2table`, `ape::updateLabel.data.frame` — ORDER=E; CHUNK=M; state: none.
- **verdict**: no worthwhile chunking targets (species-level H); the positional-matching fallbacks are the traps.

### gdata

- `gdata::nPairs` — ORDER=I; CHUNK=A; state: k × k pairwise non-missing counts and nested complete-case counts (nPairs.R:16-24).
- `gdata::write.fwf` — ORDER=E; CHUNK=P; state: pass 1 A maximum formatted width per column (write.fwf.R:75-82), pass 2 M writing; notes: appending chunks with per-chunk widths yields misaligned files unless `width=` is fixed.
- `gdata::update.data.frame` — ORDER=D; CHUNK=K; state: hash of the resident table's keys; notes: duplicate keys in `new` — the last assignment wins (update.data.frame.R:11-17); unmatched rows are appended in input order.
- `gdata::frameApply` — ORDER=I; CHUNK=H; state: —; notes: groups sorted by pasted key (frameApply.R:12-14); arbitrary FUN per group needs complete groups.
- `gdata::drop.levels.data.frame`, `gdata::mapLevels.data.frame` — ORDER=I; CHUNK=K; state: used-level sets; notes: dropping is then an M recode (P); `mapLevels(sort = FALSE)` is first-appearance (S).
- `gdata::wideByFactor`, `gdata::bindData`, `gdata::trim.data.frame`, `gdata::unknownToNA.data.frame`, `gdata::NAToUnknown.data.frame`, `gdata::isUnknown.data.frame` — ORDER=E; CHUNK=M; state: none; notes: `wideByFactor` needs the factor's level set.

### circular

- `circular::watson.williams.test.formula` — ORDER=I; CHUNK=K; state: per group n, sum cos, sum sin (`tapply(x, group, MeanCircularRad)`, watson.williams.test.R:146).
- `circular::watson.wheeler.test.formula` — ORDER=R; CHUNK=H; state: —; notes: circular ranks with `rank(x, ties.method = "random")` (watson.wheeler.test.R:112) — with ties the statistic depends on RNG and row position; the per-group sums of cos/sin of uniform scores afterwards are K.
- `circular::wallraff.test.formula` — ORDER=I; CHUNK=H; state: —; notes: pass 1 K group mean directions, pass 2 angular distances fed to `kruskal.test` ranks (wallraff.test.R:59,131).
- `circular::sd.data.frame`, `circular::var.data.frame` — ORDER=I; CHUNK=A; state: per column n, sum cos, sum sin; notes: TRAP — circular exports its own `var` generic and `var.data.frame <- function(x, ...) sapply(x, var, ...)` (var.circular.R:10-12, NAMESPACE:190), so after `library(circular)` `var(df)` returns per-column variances instead of `stats::var`'s covariance matrix (verified on `mtcars[, 1:3]`).
- `circular::windrose` — ORDER=I; CHUNK=A; state: 2-D histogram over fixed direction bins (`bins = 12`, windrose.R:134-143) × speed classes; notes: speed classes need a max pre-pass.

### Hotelling

- `Hotelling::hotelling.test.formula`, `Hotelling::hotelling.stat` — ORDER=I; CHUNK=K; state: per group (two) n, mean vector, cross-products; notes: `shrinkage = TRUE` uses `corpcor::cov.shrink` (hotelling.test.r:94-95), which also needs sums of squared standardised cross-products (still A, O(p^2) more); `perm = TRUE` is R.
- `Hotelling::summarise.formula`, `Hotelling::summarise.data.frame` — ORDER=I; CHUNK=H; state: —; notes: default stats include `median` (summarise.R:67-70), otherwise K.
- `Hotelling::clr`, `Hotelling::alr` — ORDER=E; CHUNK=M; state: none; notes: row-wise log-ratio transforms.

### actuar

- `actuar::cm` — ORDER=I; CHUNK=K; state: per portfolio unit (contract, and each hierarchy level) weighted totals, weighted means and within sums of squares (rows are contracts, ratio columns are periods); notes: Bühlmann-Gisler and Ohlsson structure parameters are closed forms of those sums; `method = "iterative"` iterates over the K state in memory (`tol`, `maxit`), not over rows; regression credibility needs per-contract X'WX (K).

### flexmix

- `flexmix::flexmix` (not flagged; candidates were plumbing) — ORDER=R; CHUNK=P; state: per EM iteration and component the weighted M-step sufficient statistics (A for linear components, nested IRLS for GLM components); notes: initial posteriors are a random cluster per observation (`sample(seq_len(k), ...)`, flexmix.R:420), and the SEM/random classification steps sample per row (flexmix.R:263,278); posteriors can be recomputed per row from parameters, so no per-row state; grouped data (`~ x | g`) need a K pass per group.

### dlnm

- `dlnm::smooth.construct.cb.smooth.spec`, `dlnm::Predict.matrix.cb.smooth` — ORDER=E; CHUNK=P; state: pass 1 knots/ranges for the exposure and lag bases (A/H), pass 2 M basis rows; notes: each row carries its own exposure-history matrix, so the smooth itself is row-local; TRAP is upstream — `crossbasis()` builds the lags with `Lag(..., group)` in row order when `x` is a vector (crossbasis.R:14,64), which is D.

### isotree

- `isotree::isolation.forest` — ORDER=R; CHUNK=H; state: —; notes: each tree is grown on a random subsample (`sample_size`, default all rows, isoforest.R:46); with a small `sample_size` a one-pass reservoir sample per tree then in-memory growth is the escape.
- `isotree::predict.isolation_forest` — ORDER=E; CHUNK=M; state: none; notes: chunkable over prediction rows; `isotree.add.tree` adds trees fitted on new data (incremental model growth, prior art, not equivalent to a batch fit); `isotree.set.reference.points` stores reference rows for distance/kernel outputs (H).

### BART

- `BART::bartModelMatrix` — ORDER=I; CHUNK=P; state: pass 1 per numeric column min/max for the default uniform cutpoint grid (A), distinct values when fewer than `numcut` (bounded K), or quantiles with `usequants = TRUE` (H) (bartModelMatrix.R:69-102); notes: `xinfo =` accepts user cutpoints (prior art for declared global information); the BART MCMC itself is R with thousands of passes.

### Boruta

- `Boruta::Boruta.formula`, `Boruta::Boruta.default` — ORDER=R; CHUNK=H; state: —; notes: random forests with shadow features from row permutations.

### lightgbm

- `lightgbm::lgb.convert_with_rules` — ORDER=I; CHUNK=P; state: pass 1 K level sets (`as.factor(unique(...))`, i.e. sorted, lgb.convert_with_rules.R:139-157), pass 2 M recoding; notes: returns `rules` that can be passed back for later chunks (prior art).
- `lightgbm::lgb.interpret` — ORDER=E; CHUNK=M; state: none; notes: per-row feature contributions.

### dbscan

- `dbscan::glosh` — ORDER=I; CHUNK=H; state: —; notes: kNN core distances, full `dist()` and an hclust (GLOSH.R:104-120).

### apcluster

- `apcluster::negDistMat`, `apcluster::expSimMat`, `apcluster::linSimMat`, `apcluster::corSimMat`, `apcluster::linKernel` — ORDER=E; CHUNK=H; state: —; notes: n × n similarity matrices; `sel =` computes only selected rows, so output row blocks can be produced chunk-wise with all data resident.

### agricolae

- `agricolae::carolina` — ORDER=I; CHUNK=K; state: X'X/X'y over the nested design factor levels (`lm` with nested terms, carolina.R:13-70).
- `agricolae::correlation` — ORDER=I; CHUNK=A; state: pairwise sums for `method = "pearson"`; notes: `"spearman"`/`"kendall"` are H.
- `agricolae::resampling.model` — ORDER=R; CHUNK=P; state: per permutation an ANOVA; notes: `sample(yy)` (resampling.model.R:19).

### irr

- `irr::rater.bias`, `irr::stuart.maxwell.mh` — ORDER=I; CHUNK=K; state: rater × rater contingency table (`table`, rater.bias.R:10-11).

### bbmle

- `bbmle::mle2` — ORDER=I; CHUNK=P; state: per objective evaluation the summed negative log-likelihood (formula interface `-sum(do.call(ddistn, arglist2))`, mle.R:163); notes: numerical Hessian adds passes; a user `minuslogl` is opaque.

### COMPoissonReg

- `COMPoissonReg::glm.cmp` — ORDER=I; CHUNK=P; state: per optimiser evaluation the summed log-likelihood (row-local normalising constants); notes: `predict.cmpfit`/`predict.zicmpfit` are E/M.

### kohonen

- `kohonen::supersom` — ORDER=R; CHUNK=P; state: per epoch K sums per map unit (batch modes); notes: the initial codebook is a random sample of rows (`sample(1:nobjects, ncodes)`, supersom.R:100) and online mode presents rows in random order.

### evmix

- `evmix::fmgamma`, `evmix::fmgammagpd`, `evmix::fmgammagpdcon` — ORDER=I; CHUNK=P; state: summed log-likelihood per optimiser evaluation; notes: threshold profiling over `useq` repeats the fit per threshold.
- `evmix::mrlplot`, `evmix::tshapeplot`, `evmix::tscaleplot` — ORDER=I; CHUNK=P; state: per threshold count and sum of excesses (A, mrlplot) or a GPD fit (P); notes: the default threshold range comes from quantiles (H pre-pass).

### GeneralizedHyperbolic, ghyp, Benchmarking

- `GeneralizedHyperbolic::hyperblm`, `ghyp::fit.ghypuv`, `Benchmarking::sfa` — ORDER=I; CHUNK=P; state: summed log-likelihood (and gradient) per optimiser or EM evaluation.

### clinfun

- `clinfun::permlogrank` — ORDER=R; CHUNK=P; state: per permutation the log-rank sums keyed by event time (K after `order(strat, time)`, permlogrank.R:59); notes: `nperm = 5000`.

### berryFunctions

- `berryFunctions::linReg`, `berryFunctions::mReg` — ORDER=I; CHUNK=A; state: `lm` cross-products; notes: `mReg` also fits nonlinear forms (P).
- `berryFunctions::headtail`, `berryFunctions::insertRows` — ORDER=D; CHUNK=M; state: none; notes: positional by definition.

### circlize

- `circlize::chordDiagramFromDataFrame` — ORDER=S; CHUNK=K; state: per sector the sums of absolute link values (`tapply(abs(df$value1), df$rn, sum)`, chordDiagram.R:1172); notes: sector order defaults to first appearance and link drawing order follows rows.

### other small ones

- `corrgram::corrgram` — ORDER=I; CHUNK=A; state: pairwise-complete correlation sums; notes: panels draw raw rows.
- `descr::descr` — ORDER=I; CHUNK=H; state: —; notes: quantile summary.
- `geos::geos_inner_join` — ORDER=S; CHUNK=K; state: STR-tree index of `y` resident; notes: stream `x` chunks against it (geos-join.R:50-58).
- `baseline::mvrValstats` — ORDER=I; CHUNK=A; state: MSEP/R2 sums over `newdata` predictions.
- `fabricatr::draw_ordered`, `fabricatr::reveal_outcomes` — ORDER=E; CHUNK=M; state: none; notes: `draw_ordered` with a noisy link draws per row (R).
- `lhs::qdirichlet` — ORDER=E; CHUNK=M; state: none.
- `data.tree::as.Node.data.frame` — ORDER=S; CHUNK=K; state: tree keyed by path; notes: child order follows rows.
- `gsignal::buffer` — ORDER=D; CHUNK=M; state: frame overlap carry-over.

### Skipped

future, lgr, litedown, lazyeval, formula.tools, gsubfn, gWidgets2, bit64, distributions3, isotone, bio3d, lm.beta, jmvcore, behavr, cppRouting, JADE (input is an array of matrices), Exact (input is a 2 × 2 table) — candidates were printing, coercion, formula utilities, metadata getters or not row-wise data consumers; also the plumbing members of otherwise listed packages (lavaan `modindices`/`standardizedSolution`/`lavParameterEstimates`/`parTable`/`lavResiduals`/`lavTestScore`/`lavEffects`/`lav_pt_from_lm`/`lavTablesFitCp`, emmeans `contrast`/`summary`/`test`/`coef`/`mvcontrast`/`hpd.summary`/`as.data.frame.*`, gamlss `AIC`/`GAIC*`/`plot`/`term.plot`/`par.plot`/`plotDF`/`plotLambda`, collapse `qDF`/`qDT`/`qTBL`/`namlab`/`to_plm`/`reindex`/`[.indexed_frame`/`as.data.frame.qsu`/`as.data.frame.descr`, datawizard `data_peek`/`data_seek`/`data_rename`/`data_extract`/`data_group`/`reshape_ci`/`format.*`/`as.table.*`, ff `[.ffdf`/`matprint`, actuar `[.grouped.data`, agricolae `table.freq`/`summary.graph.freq`, e1071 `boxplot.bclust`/`plot.svm`, flexmix `plotEll`/`as.data.frame.simple_triplet_matrix`, ape `anova.ace`/`BOTHlabels`/`varCompPhylip`, coxme `anova.coxme*`, gnm `anova.gnm`/`add1.gnm`/`drop1.gnm`, bbmle `as.data.frame.*`, GLMMadaptive `print.*`, circular `plot.circular`/`points.circular`/`rose.diag`/`summary.circular`/`print.density.circular`/`circular`/`as.data.frame.circular`).

<!-- source: findings/cran_depth2_b.md -->
## Part: Findings: CRAN depth 2, batch B (lmtest .. zCompositions)

Sources read from the extracted CRAN tarballs under `scratchpad/src/<pkg>/R` (R code only).
Where behaviour lives in compiled code, the claim is reasoned from the R wrapper and the Rd files and says so.
Claims marked "verified" were checked with the current CRAN binaries on R 4.5.3
by permuting rows with a fixed seed and comparing with `all.equal()`;
the script is `scratchpad/b2work/check1.R`.
Each finding is one line so the files can be merged mechanically.

### lmtest

- `lmtest::raintest` — ORDER=D with the default `order.by = NULL`, I with `order.by = "mahalanobis"` or a formula (up to ties in `z`, which `order()` breaks by input position); CHUNK=H (exact: the central subset is chosen by row position or by an order statistic of `z`/the Mahalanobis distance); state: full-data X'X, X'y, y'y (A) plus X'X, X'y, y'y of the selected subset; notes: TRAP — the default "central fraction" is `from <- ceiling(quantile(1:n, ...))` on *row positions* (raintest.R:22-28), so the statistic changes under row permutation (verified FALSE; with `order.by = "mahalanobis"` verified TRUE); the Mahalanobis variant uses colMeans and (X'X)^-1 (raintest.R:30-38), so it is P with 3 passes if the cut-off distance comes from a quantile sketch (pass 1 A: means and X'X; pass 2: distance quantile; pass 3 A: subset cross-products) — exact only with an exact selection pass.
- `lmtest::gqtest`, `lmtest::hmctest` — ORDER=D with `order.by = NULL`, I with `order.by` (ties broken by input position); CHUNK=H with `order.by` (split point is an order statistic of `z`), P with 2 passes if the split value of `z` is given or sketched (pass 1: quantile of `z`; pass 2 A: separate X'X, X'y, y'y below/above the split; `hmctest` needs the full-sample fit first, so 3 passes); notes: TRAP — both split the sample at a row *position* (`X[1:point1,]`, gqtest.R:45-46; `resi[1:point]`, hmctest.R:38), verified FALSE for `gqtest` without `order.by` and TRUE with `order.by = ~x2`; `hmctest(simulate.p = TRUE)` adds R.
- `lmtest::dwtest` — ORDER=D without `order.by` (verified FALSE), I with `order.by` up to ties; CHUNK=P in the given order only (pass 1 A: X'X, X'y; pass 2: `sum(diff(res)^2)` with the previous chunk's last residual carried over), the approximate p-value additionally needs X'AX with A the tridiagonal difference operator (a lag-1 cross-product, same carry-over); the exact p-value (`exact = TRUE`, default for n < 100) builds the n x n matrix and its eigenvalues (dwtest.R:49-53), H; notes: Durbin-Watson is the canonical "looks like a regression diagnostic but uses row order" trap; with `order.by` it needs a sort first.
- `lmtest::bgtest`, `lmtest::harvtest`, `lmtest::grangertest` (formula methods) — ORDER=D (lagged residuals `resi[1:(n-x)]`, bgtest.R:36; recursive residuals via rank-one updates in row order, harvtest.R:21-40; `lag()` on zoo series, grangertest.R:39-51); CHUNK=P in time order only (sequential scan with a carried state of `order` residuals or the running (X'X)^-1); notes: `order.by` sorts first, ties by input position; listed only because they share the `formula, data` signature with the order-free tests.
- `lmtest::bptest` — ORDER=I (verified); CHUNK=P with 2 passes; state: pass 1 A: X'WX, X'Wy, y'Wy, Z'WZ, Z'W1, count of positive weights; pass 2 A: given beta and sigma2, Z'W r^2, sum r^2, sum r^4 (the studentized statistic uses the unweighted `sum(w^2)`, bptest.R:49-51); notes: the X/Z complete-case alignment is by row *names* (bptest.R:31-37), which a chunked version replaces with a row-local joint complete-case mask.
- `lmtest::coxtest`, `lmtest::encomptest`, `lmtest::jtest` (default `vcov.`) — ORDER=I (coxtest verified); CHUNK=A; state: the joint Gram matrix of [X, Z, y] (union of both models' regressors); notes: every step of the Cox test is a projection of y or of a fitted vector onto span(X) or span(Z) (coxtest.R:61-85), and fitted values are linear in X or Z, so all residual sums of squares follow from the joint Gram; the J and encompassing tests augment one design with the other's fitted values or regressors, again expressible through the same Gram; with a sandwich `vcov.` they become P (one more score pass).
- `lmtest::petest` — ORDER=I; CHUNK=P with 2 passes (pass 1 A: Gram of [X, Z, y, log y]; pass 2 A: cross-products with log(fitted) and exp(fitted), which are non-linear in the coefficients, petest.R:118 onwards); notes: needs positive fitted values.
- `lmtest::resettest` — ORDER=I (verified); CHUNK=A for `type = "regressor"` (powers of the regressors are row-local), P with 2 passes for `type = "fitted"` (pass 1 A: X'X, X'y and the moments of y, since y is `scale()`d first, resettest.R:20; pass 2 A: cross-products of [X, yhat^2, yhat^3, y]) and for `type = "princomp"` (pass 1 A: `cov(Z)` for the first principal component, resettest.R:37-40); notes: the global `scale(y)` does not change the F statistic when an intercept is present, so it can be dropped.
- `lmtest::waldtest.formula`, `lmtest::lrtest.formula`, `lmtest::waldtest.default`, `lmtest::lrtest.default`, `lmtest::coeftest` — ORDER=I; CHUNK=inherits the fitter (A for `lm`, P for `glm`); state: per nested model the fitter's state; notes: the formula methods call `lm(formula, data)` (waldtest.R:5-10, lrtest.R:5-10) and the default methods refit nested models via `update()`, so a chunked version needs chunk-capable fitters (`biglm`-style); with a sandwich `vcov` see sandwich.
- **verdict**: `bptest`, `resettest` and the non-nested tests (`coxtest`, `jtest`, `encomptest`) are exact A/P(2) targets built on X'X-type Gram matrices; `raintest` (default), `gqtest`, `hmctest`, `dwtest`, `bgtest`, `harvtest` are D traps — order-free only with `order.by`, and then they need a sort or quantile; nothing is chunk-capable today.

### sandwich

- `sandwich::vcovHC` (`meatHC`), `sandwich::vcovOPG`, `sandwich::sandwich` — ORDER=I (HC3 and HC5 verified); CHUNK=P with 2 passes after the fit: pass 1 is the model's own fit state (X'X for `lm`), pass 2 A: sum of omega_i x_i x_i' with omega from the row-local residual and hat value h_i = w_i x_i'(X'WX)^-1 x_i; `vcovOPG` is crossprod(estfun)/n, A; notes: HC4/HC4m/HC5 also use `p = round(sum(h))` (= rank, known in advance), and HC5 scales every omega_i by `max(h)` (vcovHC.R:67-83), so HC5 needs one more A pass for max(h) before the meat pass (3 passes in all); the hat-value warning lists row names (vcovHC.R:98), presentation only.
- `sandwich::vcovCL` (`meatCL`) — ORDER=I (HC1 and HC2 verified); CHUNK=K for HC0/HC1; state: per cluster the k-vector of summed scores, plus G and n; merge = add per key, then crossprod over clusters (vcovCL.R:169-172); notes: multi-way clustering adds keys for every cluster intersection, built by pasting labels (vcovCL.R:60-67), so K over each intersection; HC2/HC3 need the cluster block (I - H_gg)^(-1/2) or ^-1 (vcovCL.R:146-159), which needs *all rows of a cluster together*: chunkable by cluster after a partition, or K with per-cluster X_g and residuals held (size grows with cluster sizes); `cluster` given as a formula is looked up with `expand.model.frame()` on the original data.
- `sandwich::vcovPL` (`meatPL`) — ORDER=D without `order.by` (verified FALSE), I with `order.by` (verified TRUE); CHUNK=K with `order.by` and `aggregate = TRUE`; state: per time period the summed scores (vcovPL.R:93-98), then a kernel HAC over the nt time totals at the end; notes: TRAP — without `order.by` the time index is the row's *position within its cluster*, built from `make.unique(as.character(cluster))` (vcovPL.R:69-74), so the Driscoll-Kraay estimator silently depends on row order; once aggregated by time, the HAC step is small (nt x k).
- `sandwich::vcovPC` (`meatPC`) — ORDER=D without `order.by`, I with it; CHUNK=H; state: residuals arranged as a time x cluster panel; notes: same TRAP as `vcovPL` — the default time index is the position within the cluster via `make.unique()` (vcovPC.R:66-71); the Beck-Katz estimator needs the N x N contemporaneous residual covariance `crossprod(e)/t` over the panel (vcovPC.R:99-109) and per-cluster X blocks, so it is K by time period only if chunks hold complete time periods, otherwise holistic.
- `sandwich::vcovHAC`, `sandwich::NeweyWest`, `sandwich::kernHAC`, `sandwich::meatHAC`, `sandwich::bwAndrews`, `sandwich::bwNeweyWest`, `sandwich::weightsLumley` — ORDER=D (default order is `1:n`, vcovHAC.R:41-53; verified FALSE); CHUNK=P in time order (lagged score cross-products with a carried window of `lag` rows; bandwidth selection fits an AR(1)/VAR to the scores, another sequential pass); notes: obvious time-series code, listed because `vcovHAC(lm_fit)` on a cross-sectional data frame silently uses row order.
- `sandwich::vcovBS.lm`, `sandwich::vcovBS.glm`, `sandwich::vcovBS.default` — ORDER=R (wild bootstrap verified FALSE under permutation with the same seed); CHUNK=P with R replicates per pass, `type = "xy"` is H as written (resamples cluster index lists, vcovBS.lm.R:114-117); state for an exact chunked rewrite with counter-based RNG keyed by cluster id: wild/webb/mammen/norm, one pass after the fit, A per replicate: X'W(r * v_g) (R k-vectors); fractional, A per replicate: X'W_b X, X'W_b y with exponential cluster weights (R k x k matrices); xy as a Poisson bootstrap, likewise; notes: draws are indexed by cluster in *first-appearance* order (`factor(cluster, levels = unique(cluster))`, vcovBS.lm.R:103), so the same seed gives different results under permutation; the `glm`/default methods refit with `update()` per replicate, so each replicate is a full P fit.
- `sandwich::vcovJK`, `vcovBS(type = "jackknife")` — ORDER=I (verified); CHUNK=K for `lm`; state: per cluster X_g'X_g and X_g'y_g, from which every leave-one-cluster-out estimate is (X'X - X_g'X_g)^-1 (X'y - X_g'y_g); notes: the current code refits with `.lm.fit()` on `unlist(cli[-j])` per cluster (vcovBS.lm.R:118-121), O(G n k^2); for `glm` it is G full refits.
- **verdict**: `vcovHC` (P, 2 passes) and `vcovCL` (K by cluster) are the main targets and exact; `vcovJK` for `lm` collapses to K; `vcovPL` without `order.by` is a D trap and becomes K with `order.by`; the bootstrap types become exact A-per-replicate if draws are keyed by cluster id.

### quantreg

- `quantreg::rq` with `method = "pfn"` (`rq.fit.pfn`) and `"ppro"`/`"pfnb"` — ORDER=I for the returned optimum (pfn verified, and equal to `"br"`), R for the path (uses `sample(n, m)`); CHUNK=P with about 4 passes and bounded state; state: pass 1: a uniform subsample of m = round(sqrt(p) n^(2/3)) rows (reservoir sampling; quantreg.R:871-878); pass 2: residuals and "band" widths from the subsample fit, and two quantiles of r/band (quantreg.R:887-893), sketchable since they only need to bracket the fit; pass 3 A+bounded: rows below/above the bracket are collapsed into two "glob" pseudo-observations (sum of x, sum of y, quantreg.R:902-913), rows inside (about 0.8 m) are kept; solve the reduced LP; pass 4 M: check the residual signs of globbed rows (quantreg.R:917-919), refit with fixups or double m; notes: the Portnoy-Koenker preprocessing is the existing near-streaming algorithm in this batch — prior art for chunking an LP-based estimator; its fix-up loop is a bounded number of extra passes.
- `quantreg::rq` (default `method = "br"`, `"fn"`, `"sfn"`, `"lasso"`, `"scad"`) — ORDER=I up to non-unique LP solutions (the simplex may return a different vertex when the solution is not unique); CHUNK=H; state: all rows; notes: escape hatches are `pfn`/`ppro` above and `method = "conquer"` (quantreg.R:670), a smoothed convolution-type loss whose gradient is a sum over rows (P, A per iteration, exact for the smoothed objective only); `mf$drop.unused.levels <- TRUE` (quantreg.R:103) needs a level pre-pass; multiple `tau` loop over full fits.
- `quantreg::predict.rq`, `quantreg::predict.rqs`, `quantreg::predict.rq.process`, `quantreg::predict.rqss` — ORDER=E; CHUNK=M; state: none; notes: uses the stored `xlevels`; interval = "confidence" uses the stored covariance, M as well.
- `quantreg::rqss` — ORDER=I; CHUNK=H; state: all rows; notes: `qss1` puts knots at `unique(x[order(x)])` (rqss.R:203), so K for the knot set if x has few distinct values, but the penalized fit is a sparse LP over all rows; `qss2` triangulates all (x, y) points with `interp::tri.mesh` (rqss.R:291), H.
- `quantreg::nlrq`, `quantreg::crq`, `quantreg::rqProcess`, `quantreg::KhmaladzeTest`, `quantreg::ParetoTest`, `quantreg::Hill`, `quantreg::Pickands` — ORDER=I; CHUNK=H; state: all rows; notes: interior-point/LP fits per iteration or per tau, censored QR with recursive reweighting, and tail-index estimates from extreme order statistics; only escape is subsampling.
- `quantreg::dynrq` — ORDER=D (lags via zoo); CHUNK=H; notes: time-series QR, listed for completeness.
- **verdict**: `rq(method = "pfn")` is prior art for chunking a holistic estimator — subsample, glob the tails into two aggregate rows, verify, repeat; it could be rewritten to stream with a reservoir sample and a quantile sketch; everything else is H.

### robustbase

- `robustbase::lmrob` — ORDER=R (random subsamples for the S-estimator; `nResample = 500`, `subsampling = "nonsingular"`, lmrob.MM.R:61-80); CHUNK=H for the S start, P for the MM step; state: S step needs the M-scale of each candidate's residuals over all rows (a 1-D root find of a sum, so P with A per iteration, for a fixed batch of candidates evaluated together); MM step is IRWLS, each iteration A (weighted X'WX, X'Wy); notes: for n > `fast.s.large.n = 2000` the fast-S already works on `groups = 5` random subsets of `n.group = 400` rows (lmrob.MM.R:727-736), built-in subsample prior art; the candidate draws are row-indexed, so a seed does not survive permutation; covariance `.vcov.avar1` is A.
- `robustbase::covMcd` — ORDER=R (FAST-MCD), I for `nsamp = "deterministic"` (DetMCD); CHUNK=H; state: C-steps need the h smallest Mahalanobis distances (a selection), each C-step then A (mean, scatter of the selected rows); notes: FAST-MCD already partitions large n into `kmini` subsets of `nmini` rows (covMcd.R:195-204), prior art; the reweighting step is M (qchisq cut-off) plus A, so only the raw estimate is holistic; with a distance quantile sketch the C-steps become approximate P.
- `robustbase::ltsReg.default`, `robustbase::ltsReg.formula` — ORDER=R; CHUNK=H; notes: FAST-LTS, same structure as `covMcd` (h smallest squared residuals per C-step).
- `robustbase::glmrob` — ORDER=I for `method = "Mqle"` with `weights.on.x = "none"` or `"hat"`, R with `weights.on.x = "robCov"`/`"covMcd"`; CHUNK=P (IRLS with Huber-type weights on Pearson residuals, A per iteration); notes: `"hat"` needs the hat values, one extra A pass for (X'X)^-1; `method = "BY"`/`"WBY"` is an optimisation over all rows, P with A per evaluation.
- `robustbase::nlrob` — ORDER=I for `method = "M"` (IRLS, P with A per iteration), R for `"MM"`, `"tau"`, `"CM"`, `"mtl"` (random search over the parameter space); CHUNK=P; notes: the random search draws parameters, not rows, so those methods would be order-invariant up to the subsequent scale estimates.
- `robustbase::adjbox.formula` — ORDER=I; CHUNK=H; notes: medcouple and quartiles; K if few distinct values.
- `robustbase::predict.lmrob`, `robustbase::predict.nlrob` — ORDER=E; CHUNK=M.
- **verdict**: the MM/IRWLS phases of `lmrob`, `glmrob` and `nlrob` are P with A per iteration; the high-breakdown starts (`lmrob` S, `covMcd`, `ltsReg`) are holistic and seed-dependent, but already use random-subset partitioning (`groups`/`n.group`, `kmini`/`nmini`) that a streaming version could adopt.

### psych

- `psych::alpha` — ORDER=D (only when row 1 is NA for a zero-variance item; I otherwise); CHUNK=P with 2 passes (A if the key reversal is folded in algebraically); state: pass 1 A: item n, sums, min, max, sd, pairwise cross-products (`cov(x, use = "pairwise")`, alpha.R:68-69) and K response frequencies per item (bounded by `max = 10` categories); pass 2 A: total-score moments and `cor(total, x)` after reversing keyed items with the global min+max (alpha.R:113-117); notes: TRAP — for items with zero variance the code takes `first.bad <- x[1, bad]` (alpha.R:62) and adds `sum(first.bad, na.rm = TRUE)` to every total (alpha.R:121), so if row 1 is NA for a constant item the constant is silently dropped: total mean 2.355 with the NA row first vs 3.105 with it last (verified); `n.iter > 1` bootstrap is R (alpha.R:215); `impute = "median"` needs an H pre-pass.
- `psych::corr.test` (`corTest`) — ORDER=I; CHUNK=A for `method = "pearson"`; state: per pair (n, sum x, sum y, sum x^2, sum y^2, sum xy) for pairwise deletion; notes: spearman/kendall (corr.test.R:7, 19) are H, or K when each column has few distinct values (ranks and concordance from the contingency table); p-values, CIs and `adjust` work on the p x p result.
- `psych::fa`, `psych::principal`, `psych::irt.fa`, `psych::paSelect`, `psych::vssSelect` — ORDER=I; CHUNK=A for `cor = "cor"`/`"cov"`/`"wtd"` (fa.R:449-455), K for `"poly"`/`"tet"` (tables), H for `"spearman"`/`"kendall"` (fa.R:456-457); state: p x p cross-products (pairwise counts); notes: everything after the correlation matrix is p x p; factor scores need a second M pass using global means and sds (P); `n.iter > 1` resamples rows, R (fa.R:75-80).
- `psych::polychoric`, `psych::tetrachoric` — ORDER=I; CHUNK=K (A once the categories are known); state: per item marginal counts (global thresholds, `global = TRUE`) and per item pair the contingency table (`tabulate()` into a fixed grid, polychoric.R:16, 27), at most `max.cat = 8` categories; notes: the ML step then optimises over the tables only (polychoric.R:136) — exact chunking target; `weight` makes the tables weighted sums, still K.
- `psych::statsBy` — ORDER=I; CHUNK=K; state: per group n, column sums, sums of squares and cross-products (from which group means, sds, within-group pooled correlations `rwg`, between-group `rbg`, and ICC1/ICC2 follow); notes: uses `by()` over groups (statsBy.r:66-106, 156-161); character columns are recoded with `as.factor()` (sorted levels, I); `cor = "poly"`/`"tet"` per group are K per group; spearman/kendall are H per group.
- `psych::ICC` — ORDER=I (verified for `lmer = FALSE`); CHUNK=A for `lmer = FALSE` on complete data (input is subjects x raters, one row per subject); state: per-rater column sums, sum of squared row totals, sum of squares, n; notes: the two-way ANOVA mean squares follow from these (ICC.R:78-84); default `lmer = TRUE` fits crossed random effects with lme4 (ICC.R:45), P/H; for complete balanced data the REML components equal the ANOVA ones when non-negative.
- `psych::describe`, `psych::describeBy` — ORDER=I (verified); CHUNK=H because of median, mad, trimmed mean and optional quantiles (describe.R:271-283); A for n, mean, sd, se, min, max, range, skew and kurtosis; describeBy is K over groups of the same; notes: `fast = TRUE` (default for > 1e7 cells) drops mad and trimmed mean but still computes the median (describe.R:268-271), so it is not A; escape is a quantile sketch, or K with few distinct values; factor/character columns are recoded via `as.numeric(as.factor())`, sorted levels.
- `psych::describeFast` — ORDER=I except the type check reads row 1 (`is.numeric(x[1, i])`, describe.R:69-72), presentation only; CHUNK=A; state: per column non-NA count, complete-case count.
- `psych::cor.wt`, `psych::SD`, `psych::circadian.stats` — ORDER=I; CHUNK=A (weighted moments; circular mean via sums of sin/cos, K by group); notes: `bigCor` (bigCor.R:3-21) blocks over *columns* of size 30, not rows — useful prior art for a wide p but each block still reads all rows.
- `psych::score.multiple.choice`, `psych::crossValidation`, `psych::scaling.fits` — ORDER=E for per-person scores, I for item statistics; CHUNK=P (M scoring, then A item/total moments and K `responseFrequency`).
- `psych::winsor`, `psych::winsor.mean`, `psych::winsor.sd`, `psych::winsor.var`, `psych::interp.quantiles` — ORDER=E/I; CHUNK=H, or P with a quantile sketch (pass 1 quantiles, pass 2 clip + A).
- `psych::densityBy`, `psych::violinBy`, `psych::multi.hist`, `psych::ellipses` — ORDER=I; CHUNK=H (kernel densities, loess), A for binned histograms.
- **verdict**: `polychoric`/`tetrachoric` (K over contingency tables), `fa`/`principal` and `corr.test` (A cross-products), `statsBy` and `ICC(lmer = FALSE)` (K/A) are clean exact targets; `alpha` is P(2) but has a real first-row D trap; `describe` is H only because of median/mad/trimmed mean.

### vegan

- `vegan::rda.formula`, `vegan::rda.default`, `vegan::varpart` (RDA path) — ORDER=I (eigenvalues and species scores verified, including signs on BCI); CHUNK=A for eigenvalues, species scores and biplot scores; state: column sums and the Gram matrix of [Y, X, Z] (response, constraints, conditions), from which centring, partialling and the fitted covariance Y'X(X'X)^-1X'Y follow (`initPCA` is column `scale()` then division by sqrt(n-1), ordConstrained.R:43-55); notes: site scores (`wa`/`lc`) need a second M pass; with factor constraints the model-matrix levels need a K pre-pass; eigenvector signs are fixed by the decomposition, presentation only.
- `vegan::cca.formula`, `vegan::cca.default` — ORDER=I (eigenvalues verified); CHUNK=P with 2 passes; state: pass 1 A: column totals and grand total (`initCA`, ordConstrained.R:67-82); pass 2 A: row-weighted Gram of the chi-square residual matrix with the constraints and conditions (row weights are row-local); notes: site scores are a third M pass.
- `vegan::decostand` — ORDER=E; CHUNK=M for row-margin methods (`total`, `normalize`, `hellinger`, `rank`, `clr`, `alr`, `pa`; MARGIN = 1 defaults, decostand.R:17-22, 37-43), P with 2 passes for column-margin methods (`max`, `frequency`, `range`, `standardize`; pass 1 A: column max/min/sums/moments), and for `chi.square` (row and column totals) and `log` (global smallest positive value, decostand.R:111); H for `rclr` (OptSpace matrix completion, decostand.R:222); notes: `range.global` already lets the caller supply the column parameters (decostand.R:47-52), and the returned attributes let `decobackstand` invert — prior art for "parameters fixed by a pre-pass".
- `vegan::specaccum` — ORDER=I for `method = "exact"` (default), `"rarefaction"`, `"coleman"` (verified), D for `"collector"` (verified FALSE), R for `"random"`; CHUNK=A for exact/rarefaction/coleman; state: per species the number of occupied sites `colSums(x > 0)` or total counts (specaccum.R:47, 82, 97), plus `cor(x > 0)` (p x p cross-products) for the conditioned SD (specaccum.R:58); notes: TRAP — `"collector"` accumulates species in the *row order* of sites (specaccum.R:23-27), a time-series-like curve on a data frame that looks unordered.
- `vegan::specpool`, `vegan::estimateR.data.frame` — ORDER=I (specpool verified); CHUNK=A for specpool (per species incidence frequency, specpool.R:35-45; K by `pool`), M for estimateR (one estimate per site row).
- `vegan::diversity`, `vegan::renyi`, `vegan::tsallis`, `vegan::fisher.alpha`, `vegan::radfit.data.frame`, `vegan::coverscale` — ORDER=E; CHUNK=M (one output per site row, diversity.R:27-28 uses MARGIN = 1); notes: with `MARGIN = 2` they become per-species column totals, A.
- `vegan::envfit.formula`, `vegan::factorfit` — ORDER=I for the fit, R for the permutation p-values; CHUNK=A (vectors: regression of each variable on fixed ordination scores) and K (factor centroids by level); notes: permutation tests reshuffle rows, H/R.
- `vegan::adonis2`, `vegan::adonis`, `vegan::anosim`, `vegan::mrpp`, `vegan::betadistances`, `vegan::bioenv.formula`, `vegan::capscale`, `vegan::dbrda` — ORDER=I for statistics, R for permutation p-values; CHUNK=H; state: the n x n dissimilarity matrix (`vegdist`, adonis.R:23; Gower-centred G, adonis.R:100) and `getPermuteMatrix` (adonis.R:49); notes: the statistic is a function of pairwise distances, so it is chunkable only as blocks of row *pairs* (E over pairs, O(n^2) work); for Euclidean distance on raw data PERMANOVA reduces to RDA sums of squares and becomes A.
- `vegan::anova.cca`, `vegan::simulate.capscale` — ORDER=R; CHUNK=H; notes: row permutations of residuals (anova.cca.R:11, permutest.cca.R:167).
- `vegan::predict.cca`, `vegan::predict.rda`, `vegan::predict.dbrda` — ORDER=E; CHUNK=M for `newdata`.
- `vegan::adipart`, `vegan::multipart`, `vegan::hiersimu` (default and formula) — ORDER=I for the observed partition, R for the null models; CHUNK=K (aggregate rows by each hierarchy level, then diversity per aggregate).
- `vegan::ordisurf`, `vegan::gdispweight`, `vegan::optspace` — ORDER=I; CHUNK=H/P (mgcv GAM on scores; per-species quasi-Poisson GLMs, P with A per IRLS iteration; matrix completion).
- **verdict**: `rda`/`cca`/`varpart` are exact A/P(2) targets via the Gram of [Y, X, Z]; `specaccum(method = "exact")`, `specpool` and `diversity` are trivially A/M; `specaccum(method = "collector")` is a D trap; all distance-based methods (`adonis2`, `anosim`, `mrpp`, `metaMDS`, `capscale`, `dbrda`) are H in n^2.

### memisc

- `memisc::contract.data.frame` — ORDER=S with the default `sort = FALSE` (cells listed in first-appearance order via `match(x, unique(x))`, contract.R:1-9), I with `sort = TRUE`; CHUNK=K; state: hash of distinct `by` combinations with counts or weight sums (`tabulate`/`rowsum`, contract.R:57-74); notes: per-chunk codes are first-appearance codes, so merge by value, not by code.
- `memisc::Means.data.frame`, `memisc::Means.formula`, `memisc::Means.data.set` — ORDER=I; CHUNK=K; state: per cell (n, sum, sum of squares, weight sums); notes: means via `tapply` over factors (Means.R:162-180), so cells follow the sorted level sets; the weighted SE uses a two-pass formula (`weighted.mean((x - wm.x)^2)`, Means.R:73-74) that rewrites to moments.
- `memisc::genTable`, `memisc::Aggregate`, `memisc::fapply.default`, `memisc::By.data.frame`, `memisc::By.default`, `memisc::percentages.formula` — ORDER=I iff the per-cell expression is order-free; CHUNK=K when the expression is decomposable (`table`, `percent`, counts, means), H per cell otherwise; state: per-cell partial summary; notes: they split by the factors in the formula and evaluate an arbitrary expression per cell.
- `memisc::Within.data.frame`, `memisc::collect.data.frame`, `memisc::Reshape`, `memisc::to.data.frame` — ORDER=E (Reshape and to.data.frame: S, output order follows input order and `id` values); CHUNK=M; notes: `Within` is D or global only if the expression uses aggregates.
- `memisc::sort.data.frame` — ORDER=S (stable sort); CHUNK=H.
- **verdict**: `contract` (K, S-ordered by default) and `Means`/`genTable`/`Aggregate` (K with decomposable cells) are the targets; nothing is chunk-capable.

### matrixTests

- `matrixTests::row_t_welch`, `row_t_equalvar`, `row_t_onesample`, `row_t_paired`, `row_f_var`, `row_cor_pearson`, `row_oneway_equalvar`, `row_oneway_welch`, `row_bartlett`, `row_jarquebera`, `row_cosinor`, `row_levene`, `row_kruskalwallis`, `row_waerden`, `row_flignerkilleen`, `row_brownforsythe`, `row_andersondarling`, `row_kolmogorovsmirnov_twosample`, `row_wilcoxon_onesample`, `row_wilcoxon_twosample`, `row_wilcoxon_paired` (an all-numeric data frame `x` is coerced with `as.matrix`, ttest.R:96) — ORDER=E over the data frame's rows, which are independent *tests*; CHUNK=M over rows; state: none; notes: every output row depends only on its input row (and the matching row of `y`), so streaming a tall frame of features x samples is trivial; paired variants pair columns of `x` and `y` by position.
- `matrixTests::col_*` (same tests on columns, `col_t_welch` is `row_t_welch(t(x), t(y))`, ttest.R:282-284) — ORDER=I across observations (rows of the data frame); CHUNK=A for t, F, Pearson, Jarque-Bera and cosinor (moments, cross-products with cos/sin of a fixed period); K for one-way ANOVA/Welch/Bartlett (per-group moments); P with 2 passes for Levene (pass 1 group means, pass 2 moments of |x - mean_g|, levene.R:74-77); H for Brown-Forsythe (group medians, levene.R:167), Kruskal-Wallis and van der Waerden (`rowRanks`, kruskal.R:56, waerden.R:54), Fligner, Anderson-Darling, KS and Wilcoxon (K when few distinct values).
- **verdict**: the `row_*` family is the cleanest M case in the batch (one test per row); the `col_*` moment tests (t, F, Pearson, ANOVA, Bartlett) are exact A/K targets; rank tests are H.

### maditr

- `maditr::take.data.frame`, `maditr::take_if.data.frame`, `maditr::take_all.data.frame`, `maditr::query.data.frame`, `maditr::query_if.data.frame`, `maditr::rollup.data.frame`, `maditr::cube.data.frame`, `maditr::groupingsets.data.frame` — ORDER=S with `by` (data.table keeps groups in first-appearance order), I with `keyby` (sorted); CHUNK=K when the `j` expressions are decomposable (sum, .N, mean, min/max), H per group otherwise; state: per-group partial aggregates (per grouping set for rollup/cube); notes: thin wrappers that build `DT[i, j, by]` (let.R:405-460); `i` filters are E; `j` expressions that use `first()`, `last()`, `shift()` or `.I` are D.
- `maditr::let.data.frame`, `maditr::let_if.data.frame`, `maditr::let_all.data.frame` — ORDER=E (D if expressions are window/position functions such as `shift()`, `first()`, `.I`); CHUNK=M without `by`, P with `by` (pass 1 K: group aggregates; pass 2 M: broadcast back); state: per-group aggregates; notes: `by` makes new columns depend on the whole group.
- `maditr::dcast`, `maditr::dcast.data.frame`, `maditr::to_wide` — ORDER=S (row and column order from sorted keys, but `fun.aggregate` sees values in input order); CHUNK=K (cells keyed by row key x column key with decomposable `fun.aggregate`; the default `length` is K).
- `maditr::melt.data.frame`, `maditr::rows.data.frame`, `maditr::columns.data.frame` — ORDER=E; CHUNK=M.
- **verdict**: `take(..., by =)` / `dt_summarize` with decomposable aggregates (K) is the target; output order is S unless `keyby` is used.

### plyr

- `plyr::ddply`, `plyr::daply`, `plyr::dlply`, `plyr::d_ply`, `plyr::summarise` (inside ddply), `plyr::count` — ORDER=I for the group order (group ids use `sort(unique(x))`, id.r:75), S when the number of possible combinations exceeds 2^31 (then ids are `match(char_id, unique(char_id))`, first appearance, id.r:44-46); within each group `.fun` sees rows in input order, so the result is I only for order-free `.fun`; CHUNK=K for decomposable `.fun` (count is K via `id()` and tabulate), H per group otherwise (each group's rows must be co-resident); notes: `drop = FALSE` enumerates all level combinations.
- `plyr::arrange` — ORDER=S (stable `order()`, ties keep input order); CHUNK=H (external merge sort).
- `plyr::mutate` — ORDER=E for row-local expressions; CHUNK=M; notes: expressions that use `mean(x)` or `cumsum(x)` make it P or D.
- **verdict**: `count` and `ddply` with decomposable summaries are K targets; nothing is chunk-capable (the parallel backend splits by group, not by rows).

### pROC

- `pROC::roc.formula`, `pROC::roc.data.frame` (`roc.default`), `pROC::auc.formula` — ORDER=I; CHUNK=K; state: per distinct predictor value, the number of controls and cases; finalise by sorting keys and cumulating to sensitivity/specificity, AUC (Mann-Whitney), partial AUC, and the medians that pick `direction = "auto"` (roc.R:350-355); notes: thresholds are midpoints of `sort(unique(predictor))` (roc.utils.R:91-94) and only algorithm 2 remains (roc.R:369), so the whole curve is a function of the keyed counts; for a continuous predictor the key set grows to O(n), so in practice H — escape is rounding/binning the predictor (approximate) or a sketch; levels come from `levels(as.factor(response))`, sorted, I.
- `pROC::ci.auc.formula`, `pROC::ci.formula`, `pROC::roc.test.formula`, `pROC::multiclass.roc.formula` — ORDER=I for DeLong (default) and for multiclass (pairwise ROCs over level pairs, K per pair); R for `method = "bootstrap"`, `"venkatraman"` (permutations), and `ci.se`/`ci.sp`/`ci.thresholds`/`ci.coords` (bootstrap by default); CHUNK=K for DeLong; state: as for `roc` (placement values of each case/control follow from the counts per distinct value); notes: bootstrap resamples rows, R and H.
- `pROC::coords.roc`, `pROC::coords.smooth.roc`, `pROC::plot.roc.formula`, `pROC::lines.roc.formula` — ORDER=I; CHUNK=K (operate on the curve); notes: `smooth(method = "density")` uses `density()` of each class, H or binned A; `"binormal"` fits on the curve, K.
- **verdict**: `roc`/`auc` and DeLong CIs/tests are exact K over distinct predictor values (bounded only for scores with few distinct values — rounded scores give a bounded, approximate version); bootstrap variants are R.

### mstate

- `mstate::Cuminc` — ORDER=I; CHUNK=K; state: per unique event time (and group) the number at risk and events by failure cause; notes: now a wrapper around `survfit(Surv(time, statuscr) ~ group)` (Cuminc.R:113-155), i.e. Aalen-Johansen from risk-set counts.
- `mstate::msprep`, `mstate::expand.covs.default`, `mstate::expand.covs.msdata` — ORDER=E per subject, S for ids; CHUNK=M; state: none; notes: TRAP (presentation) — without `id` the subject id is the row position `1:n` (msprep.R:160-162), so ids in the long-format output change under permutation; each wide row expands to its transition rows independently.
- `mstate::crprep.default` — ORDER=I; CHUNK=P with 2 passes (pass 1 K: censoring Kaplan-Meier over unique times; pass 2 M: expand each subject with time-varying weights).
- `mstate::msfit`, `mstate::haz_function`, `mstate::redrank` — ORDER=I; CHUNK=K (msfit: cumulative transition hazards from a `coxph` fit over unique event times) and P (redrank: alternating `coxph` fits, each a pass of K over risk sets).
- `mstate::MarkovTest` — ORDER=R (B bootstrap/permutation replicates); CHUNK=H.
- **verdict**: `Cuminc` and `crprep` reduce to K over unique event times; `msprep` is M per subject but uses row position as the default id.

### ordinal

- `ordinal::clm` (and `clm2`) — ORDER=I; CHUNK=P (Newton-Raphson; each iteration A: log-likelihood, gradient and Hessian are sums over rows); state: (ntheta + p)^2 per iteration plus a pre-pass K for the response levels with positive weight and the covariate levels (`drop.unused.levels = TRUE`, `y.levels <- levels(droplevels(y[weights > 0]))`, clm.frames.R:165-176); notes: starting thresholds come from `qlogis((1:ntheta)/(ntheta+1))`, data-free (clm.start.R:86).
- `ordinal::clmm`, `ordinal::clmm2` — ORDER=I; CHUNK=P with K per outer iteration; state: per grouping level the conditional-mode / quadrature contributions (Laplace or AGQ), so each group's rows must be together; notes: chunkable by group after partitioning.
- `ordinal::predict.clm`, `ordinal::predict.clm2` — ORDER=E; CHUNK=M.
- `ordinal::anova.clm`, `ordinal::nominal_test.clm`, `ordinal::scale_test.clm`, `ordinal::dropterm.clm2`, `ordinal::addterm.clm2` — ORDER=I; CHUNK=P (refits, each P).
- **verdict**: `clm` is a clean P (Newton, A per iteration) target; `clmm` is P with per-group K.

### xgboost

- `xgboost::xgb.ExtMemDMatrix`, `xgboost::xgb.DataIter`, `xgboost::xgb.QuantileDMatrix.from_iterator`, `xgboost::xgb.DataBatch` — ORDER=I (hist method); CHUNK=P (already chunk-capable); state: a weighted quantile sketch per feature to fix bin edges (one pass over the iterator), then per boosting round and tree level the gradient/Hessian histograms per node x feature x bin (A); notes: prior art — training data is consumed batch by batch through a user callback (NAMESPACE exports `xgb.DataIter`, `xgb.ExtMemDMatrix`); `subsample < 1` and `colsample_*` are R; the sketch merge order can change bin edges slightly.
- `xgboost::xgb.DMatrix` (data.frame input), `xgboost::xgb.create.features`, `xgboost::predict.xgb.Booster` — ORDER=E; CHUNK=M; notes: factor columns are converted using their level sets (declare levels or a K pre-pass); prediction is per row.
- `xgboost::xgb.plot.shap`, `xgb.plot.shap.summary`, `xgb.ggplot.shap.summary` — ORDER=E/I; CHUNK=M (per-row SHAP) plus plotting; notes: plumbing beyond the per-row contributions.
- **verdict**: the only package in this batch whose fitter is already chunk-capable (`xgb.ExtMemDMatrix`/`xgb.DataIter`); its quantile-sketch + histogram design is the template for H-to-P escapes elsewhere.

### MuMIn

- `MuMIn::stdize.data.frame`, `MuMIn::stdize.formula` — ORDER=E; CHUNK=P with 2 passes (pass 1 A: column means and sds, `sd(x)` or 2 sd for Gelman scaling; pass 2 M); notes: `source =` reuses the scaling of an earlier `stdize` result, prior art for parameters fixed in advance.
- `MuMIn::dredge` (not flagged), `MuMIn::model.sel.default`, `MuMIn::model.avg.default`, `MuMIn::model.avg.model.selection`, `MuMIn::predict.averaging` — ORDER=I (E for prediction); CHUNK=inherits the fitter, one refit per candidate model; notes: all subsets could share a single pass for linear models (the Gram of all candidate regressors gives every sub-model's fit).
- `MuMIn::arm.glm`, `MuMIn::stackingWeights` — ORDER=R (random splits of rows); CHUNK=H.
- `MuMIn::jackknifeWeights`, `MuMIn::BGWeights` — ORDER=I; CHUNK=H as written (leave-one-out refits; Bates-Granger from prediction covariances over rows, A once predictions exist).
- **verdict**: `stdize` (P, 2 passes) and the shared-Gram idea for `dredge` over `lm`; the rest refits.

### udpipe

- `udpipe::udpipe`, `udpipe::udpipe.data.frame`, `udpipe::udpipe.character`, `udpipe::udpipe.list` — ORDER=E (one annotation per document row); CHUNK=M; notes: prior art — `parallel.cores`/`parallel.chunksize` already annotate in chunks of documents and `rbindlist` the results (udpipe_parse.R:388-420).
- `udpipe::document_term_frequencies.data.frame`, `udpipe::document_term_matrix.data.frame`, `udpipe::txt_freq` — ORDER=S for DTM rows (documents are levelled by `unique()`, first appearance, nlp_flow.R:285) and I for terms (`factor(term)`, sorted); txt_freq is I (table sorted by key, then a stable sort by frequency, utils.R:430-441); CHUNK=K; state: sparse counts per (document, term).
- `udpipe::cooccurrence.data.frame` — ORDER=I for the counts, S for ties in the output order (`setorder(result, -cooc)`, nlp_cooccurrence.R:176); CHUNK=K; state: per (group, term) presence (nlp_cooccurrence.R:153), then pair counts per group; notes: needs each group's terms together (partition by group); `cooccurrence.character` with `skipgram` counts *adjacent* tokens and is D on token order.
- `udpipe::keywords_rake`, `udpipe::keywords_collocation`, `udpipe::txt_sentiment`, `udpipe::paste.data.frame` — ORDER=D within documents (token sequence: n-grams, negator windows `n_before`/`n_after`, pasting order); CHUNK=M per document if documents are not split across chunks; notes: rows of a token data frame are not exchangeable within a document.
- `udpipe::strsplit.data.frame`, `udpipe::cbind_dependencies`, `udpipe::cbind_morphological`, `udpipe::as_conllu`, `udpipe::dtm_align` — ORDER=E; CHUNK=M (per token or per sentence).
- **verdict**: annotation is already chunked; DTM building is K; token-sequence functions are D within documents — a classic "data frame that is really a sequence" trap.

### tokenizers

- `tokenizers::tokenize_words.data.frame`, `tokenize_characters.data.frame`, `tokenize_sentences.data.frame`, `tokenize_lines.data.frame`, `tokenize_paragraphs.data.frame`, `tokenize_regex.data.frame`, `tokenize_character_shingles.data.frame`, `tokenize_ngrams.data.frame`, `tokenize_skip_ngrams.data.frame`, `tokenize_ptb.data.frame`, `tokenize_word_stems.data.frame` — ORDER=E (one token list per document row, named by `doc_id`); CHUNK=M; state: none.
- **verdict**: trivially M.

### pomp

- `pomp::pomp` (data frame `data` with `times`) — ORDER=D (time series; rows are observation times); CHUNK=P only sequentially (particle filters are sequential scans); notes: obvious time-series code; the many `as.data.frame.*` methods are plumbing.
- **verdict**: not a target (D by design).

### statnet.common

- `statnet.common::compress_rows.data.frame` — ORDER=I for the distinct rows and their frequencies (rows are sorted with `order.data.frame` first, misc.utilities.R:221-229); E/D for the returned `ordering` attribute; CHUNK=K; state: hash of distinct rows with counts.
- `statnet.common::sort.data.frame`, `statnet.common::order.data.frame` — ORDER=S (stable `order()`); CHUNK=H.
- **verdict**: `compress_rows` is K; the formula utilities are plumbing.

### zCompositions

- `zCompositions::cmultRepl` — ORDER=E; CHUNK=P with 2 passes; state: pass 1 A: column sums (and column minima of the closed data for `adjust = TRUE`, cmultRepl.R:115); pass 2 M: each row's GBM/SQ/BL hyper-parameter uses the leave-one-out column sums `alpha[i, ] <- colSums(X[-i, ])` (cmultRepl.R:90-94), i.e. total minus own row; notes: the current loop is O(N^2 D) in R, so the chunked rewrite is also faster.
- `zCompositions::multRepl`, `zCompositions::multReplus` — ORDER=E; CHUNK=M (row-local replacement given the detection limits).
- `zCompositions::lrEM`, `zCompositions::lrEMplus`, `zCompositions::lrSVD`, `zCompositions::lrSVDplus`, `zCompositions::multLN` — ORDER=I for `rob = FALSE`; CHUNK=P (EM for a multivariate normal with left-censoring in alr coordinates: per iteration E-step row-local, M-step A sufficient statistics; lrSVD's iterative low-rank imputation via the p x p Gram, A per iteration); notes: `rob = TRUE` uses robust regressions (robustbase `lmrob`), R/H.
- `zCompositions::lrDA` — ORDER=R (data augmentation MCMC); CHUNK=P.
- `zCompositions::multKM` — ORDER=I; CHUNK=K (Kaplan-Meier per column over unique values for left-censored data).
- `zCompositions::zPatterns` — ORDER=I; CHUNK=K (counts of zero/missing patterns).
- `zCompositions::perLog` — ORDER=R (permutation tests); CHUNK=H.
- **verdict**: `cmultRepl` (P, 2 passes via leave-one-out column sums) and the EM imputers (`lrEM`, P with A per iteration) are exact targets.

### rsm

- `rsm::rsm` — ORDER=I; CHUNK=A (an `lm` on first/second-order coded terms); state: X'X, X'y of the FO/TWI/PQ/SO design; notes: canonical analysis, `steepest` and `canonical.path` work on the fit.
- `rsm::coded.data`, `rsm::as.coded.data`, `rsm::val2code`, `rsm::code2val` — ORDER=E; CHUNK=M with explicit `formulas`; P with 2 passes when codings are derived from the data (`range()` and its midpoint, coding.R:92-93).
- **verdict**: `rsm` is A after coding.

### ResourceSelection

- `ResourceSelection::rsf`, `ResourceSelection::rspf` — ORDER=I for the point estimate, R for `B > 0` (bootstrap resamples rows via the `boot` index into the per-row log-likelihood, rsf.fit.R:6-16); CHUNK=P (`optim` on a sum of row log-likelihood contributions, rsf.fit.R:71; each evaluation A, BFGS with numerical gradients means many passes).
- `ResourceSelection::sindex`, `ResourceSelection::wrsi` — ORDER=I; CHUNK=A; state: per habitat column the used and available totals.
- `ResourceSelection::makeUsedAvail.formula`, `ResourceSelection::predict.rsf` — ORDER=E; CHUNK=M.
- `ResourceSelection::simulateUsedAvail` — ORDER=R; CHUNK=M; state: none; notes: simulates used/available points from given parameters.
- **verdict**: `sindex`/`wrsi` are A; `rsf` is P; `hoslem.test` (not flagged) bins by fitted-value deciles (hoslem.test.R:9), H or P with a sketch.

### lqmm

- `lqmm::lqm` — ORDER=I; CHUNK=P (gradient search on the check loss, each iteration A: loss and subgradient sums; step size from `sd(y)`, an A pre-pass, lqmm.R:285); notes: converges to the rq solution only approximately.
- `lqmm::lqmm` — ORDER=I (rows are sorted by group first, `order(grp)`, lqmm.R:393), except that group weights are taken from each group's first row (`model.weights(dataMix)[!duplicated(grp)]`, lqmm.R:403), D if weights vary within a group; CHUNK=P with K per group (Gauss-Laguerre/Hermite quadrature per group).
- `lqmm::lqm.counts` — ORDER=R (jittering); CHUNK=P.
- `lqmm::predict.lqm`, `lqmm::predict.lqm.counts`, `lqmm::predict.lqmm` — ORDER=E; CHUNK=M.
- **verdict**: `lqm` is P with A per iteration; `lqmm` is P with per-group state.

### sampling

- `sampling::strata` — ORDER=D (semantic, not just RNG); CHUNK=K; state: per stratum the unit ids (for srswor), or per-row inclusion probabilities (poisson); notes: TRAP — the `size` vector is matched to strata in *first-appearance* order of `unique(data[, stratanames])` (strata.r:50, used as `size[i]` in the loop), so permuting rows assigns the sample sizes to different strata: with sizes `c(2, 8)` the selected counts were a=2, b=8 in the original order and a=8, b=2 after reversing the rows (verified); within strata selection is `srswor()` with `sample.int` (R).
- `sampling::cluster` — ORDER=R (clusters are sorted factor levels, cluster.r:56, so only the draws are positional); CHUNK=K (cluster ids), then a second M pass to collect selected rows.
- `sampling::postest`, `sampling::rhg`, `sampling::rhg_strata` — ORDER=I; CHUNK=K; state: per post-stratum or response-homogeneity group the weighted sums and counts.
- `sampling::getdata` — ORDER=E; CHUNK=M (join selected unit ids with the data).
- **verdict**: estimators (`postest`, `rhg`) are K; `strata` hides a first-appearance dependency in how `size` is matched.

### validate

- `validate::satisfying.data.frame`, `validate::violating.data.frame`, `validate::lacking.data.frame` — ORDER=E when every rule is record-wise; CHUNK=M for record-wise rules, P when rules contain global or grouped aggregates (`mean(x)`, `do_by()`, `is_unique()`, which need an A/K pre-pass); notes: they require record-wise output (utils.R:62-64); `is_linear_sequence(sort = FALSE)` is D (genericrules.R:112).
- **verdict**: M with a pre-pass for aggregate rules.

### splitstackshape

- `splitstackshape::concat.split`, `splitstackshape::concat.split.compact` (`cSplit`) — ORDER=E; CHUNK=P with 2 passes (pass 1 A: the maximum number of pieces per split column, which fixes the number of output columns; pass 2 M).
- `splitstackshape::Reshape` (`merged.stack`, `getanID`) — ORDER=S/D; CHUNK=M; notes: duplicated ids are made unique with `sequence(.N)` by id (getanID.R:40), so the secondary index follows row order.
- `splitstackshape::stratified` (not flagged) — ORDER=R; CHUNK=K.
- **verdict**: minor; M/P reshaping.

### polycor

- `polycor::hetcor.data.frame` — ORDER=I; CHUNK=A/K for the default two-step estimates; state: Pearson pairs A; polychoric pairs K (contingency tables); polyserial pairs A+K (two-step `rho = sqrt((n-1)/n) sd(y) cor(x, y) / sum(dnorm(cuts))` with cuts from `cumsum(table(y))`, polyserial.R:37-39); notes: `ML = TRUE` or `std.err = TRUE` optimises a row-wise likelihood for polyserial (P, A per evaluation) and a table likelihood for polychoric (K); the bivariate-normality test bins the `scale()`d variable at fixed normal quantiles (utilities.R:20-26), P with 2 passes.
- **verdict**: exact single-pass target for the two-step estimator.

### wdm

- `wdm::wdm`, `wdm::indep_test` — ORDER=I (likely D in ties for Chatterjee's `xi`, whose x ties are broken by "a fixed, reproducible ordering" unless `seeds` is given, man/wdm.Rd:31; compiled code not inspected); CHUNK=A for `pearson` (weighted moments), H for `spearman`, `kendall`, `hoeffding`, `blomqvist`, `xi` (ranks/medians; K with few distinct values); state: weighted sums and cross-products for Pearson.
- **verdict**: only weighted Pearson is A.

### pcaPP

- `pcaPP::cor.fk` — ORDER=I; CHUNK=H (Knight's O(n log n) Kendall tau); notes: K when both variables have few distinct values (concordance from the contingency table).
- `pcaPP::ScaleAdv` — ORDER=E; CHUNK=H (median/mad/Qn centring and scaling), P with a sketch.
- **verdict**: H.

### philentropy

- `philentropy::distance` — ORDER=E over row *pairs*; CHUNK=M over blocks of pairs (output is n x n); notes: each row is a probability vector; `est.prob = "empirical"` normalises rows, M.
- `philentropy::lin.cor` — ORDER=I; CHUNK=A for Pearson, H for Spearman/Kendall.
- **verdict**: pairwise; not a streaming target.

### pdp

- `pdp::partial` (`partial.default`) — ORDER=I for partial dependence, E for `ice = TRUE`; CHUNK=P with 2 passes; state: pass 1: the grid (min/max for `grid.resolution` A, `sort(unique())` for factors/characters K, quantiles H, `trim.outliers` boxplot statistics H; pred_grid.R:30-50); pass 2 A: for each grid point, the sum and count of predictions over the chunk with `pred.var` overwritten; notes: the pass 2 cost is grid size x rows predictions, but the state is only the grid; `approx = TRUE` predicts at an `exemplar()` row instead.
- `pdp::exemplar.data.frame` — ORDER=I; CHUNK=H for numeric medians, K for factor modes (`which.max(table())`, exemplar.R:44-50).
- **verdict**: `partial` is an exact P(2) target with grid-sized state.

### mvmeta

- `mvmeta::mvmeta` — ORDER=I; CHUNK=A for `method = "fixed"` (GLS sums of X_i'S_i^-1 X_i), P with 2 passes for `"mm"`, P with A per iteration for `"reml"`/`"ml"` (IGLS / Newton over the between-study covariance); state: (k p)^2 sums over studies; notes: rows are studies, so n is small in practice.
- `mvmeta::predict.mvmeta` — ORDER=E; CHUNK=M.
- **verdict**: exact, but rarely large.

### poLCA

- `poLCA::poLCA` — ORDER=I (random starting values are drawn per class x category, not per row, poLCA.R:88-89, so a seed survives permutation); CHUNK=P (EM; per iteration the E-step is row-local and the M-step needs class-weighted counts per item category, A); state: R classes x sum_j K_j counts; notes: without covariates the likelihood depends only on the response-pattern counts, so it can be compressed to K over distinct patterns once and then iterated in memory; `K_j` is taken from the column maxima, an A pre-pass; with covariates the Newton step for the logit coefficients is A per iteration.
- **verdict**: exact P (EM) target that also collapses to K over response patterns.

### reclin2

- `reclin2::problink_em` — ORDER=I; CHUNK=K; state: counts of distinct comparison patterns (`pairs[, list(n = .N), by = on]`, tabulate_patterns.R:60), then EM on the pattern table (problink_em.R:55-80); notes: prior art — the cluster version tabulates patterns per worker and merges by summing counts (cluster_tabulate_patterns.R:22), exactly the K merge.
- `reclin2::compare_vars.pairs` — ORDER=E over pairs; CHUNK=M.
- **verdict**: already distributed-chunk-capable (`cluster_pair` + `tabulate_patterns`).

### RcppEigen, RcppArmadillo, RcppGSL

- `RcppEigen::fastLm.formula`, `RcppArmadillo::fastLm.formula`, `RcppGSL::fastLm.formula` — ORDER=I; CHUNK=A for the coefficients, P with 2 passes for residuals/se; state: X'X, X'y, y'y; notes: RcppEigen `method = 2` (LLT), `3` (LDLT) and `5` (SymmEig) already work on X'X (man/fastLm.Rd:35-37), so they are exactly A; the default pivoted QR (method 0) and the Armadillo/GSL solvers factor the full X (H as written, A with incremental QR); `model.frame` levels need a pre-pass.
- `RcppEigen::predict.fastLm`, `RcppArmadillo::predict.fastLm`, `RcppGSL::predict.fastLm` — ORDER=E; CHUNK=M.
- **verdict**: normal-equation variants of `fastLm` are A today in all but the API.

### nls2

- `nls2::nls2` — ORDER=I; CHUNK=P; state: for `algorithm = "brute-force"`/`"grid-search"`/`"random-search"` the residual sum of squares of every candidate parameter vector (one pass, A with one scalar per candidate); then Gauss-Newton via `nls` (J'J, J'r per iteration, A); notes: random search draws parameters, not rows, so it stays I.
- **verdict**: P.

### mltools

- `mltools::bin_data` — ORDER=E; CHUNK=M with explicit breaks; P with 2 passes for `bins = <n>` (`seq(min, max)`, bin_data.R:107) and H (or P with a sketch) for `binType = "quantile"` (bin_data.R:117).
- **verdict**: classic `cut(breaks = n)` / quantile-bin pre-pass trap; other exports (`one_hot`, `mse`, `auc_roc`, `empirical_cdf`) are M/A/H/K respectively.

### readstata13

- `readstata13::save.dta13` — ORDER=E; CHUNK=P with 2 passes (pass 1 A: row count and per-column maximum string lengths, which fix `str#` vs `strL` types in the header; pass 2 M: write rows); notes: factor value labels come from the level sets.
- **verdict**: a streaming writer is feasible with a header pre-pass.

### spatstat.univar, spatstat.sparse

- `spatstat.univar::uniquemap.data.frame`, `spatstat.sparse::representativeRows` — ORDER=S (each row maps to the index of its first duplicate, so indices follow input order); CHUNK=K (hash of distinct rows to first index).
- **verdict**: K.

### terra

- `terra::global`, `terra::zonal`, `terra::freq`, `terra::crosstab` (raster methods; not flagged — the flagged SpatVector methods are plumbing) — ORDER=I; CHUNK=A (`global` with built-in `fun` names such as mean, sum, min, max, range, rms, sd, notNA runs block-wise in C++ via `mglobal`, zonal.R:337-349) and K (`zonal` by zone, `freq`, `crosstab`); notes: prior art — terra processes rasters in row blocks (`blocks()`, `readStart`/`readValues`/`writeStart` are exported); with an R function `global` reads all values or a regular `spatSample(maxcell)` (zonal.R:358-366), the H escape via subsampling.
- **verdict**: built-in global/zonal statistics are already chunked (A/K); arbitrary R functions are H.

### Renext

- `Renext::Renouv` — ORDER=I; CHUNK=P (A for the exponential exceedance model: count and sum over the threshold; P with A per `optim` evaluation for GPD/Weibull; historical `MAX.data`/`OTS.data` blocks add per-block terms); notes: the threshold is given, so no quantile pass.
- `Renext::spacings.data.frame` — ORDER=I; CHUNK=H (sorted spacings).
- `Renext::predict.Renouv`, `Renext::anova.Renouv` — ORDER=I; CHUNK=A; state: none beyond the fitted objects; notes: work on fits, plumbing.
- **verdict**: exponential POT is A.

### Other flagged packages

- `miscTools::colMedians`, `miscTools::summarizeDF` — ORDER=I; CHUNK=H (column medians), K/A for summarizeDF (counts per level, min/mean/max).
- `yulab.utils::scale_range` — ORDER=E; CHUNK=P with 2 passes (pass 1 min/max; pass 2 M).
- `randomizr::declare_ra` — ORDER=R; CHUNK=K; state: per block/cluster unit counts; notes: random assignment is indexed by unit position within blocks/clusters, so a seed does not survive permutation.
- `word2vec::doc2vec` — ORDER=E; CHUNK=M; state: none; notes: one embedding per document row (average of word vectors).
- `word2vec::word2vec_similarity` — ORDER=E; CHUNK=M over query rows; state: the vocabulary embedding matrix; notes: top-n over the vocabulary per query row is H within that row.
- `vioplot::vioplot.formula`, `vioplot::histoplot.formula` — ORDER=I; CHUNK=H (kernel density per group), A for histoplot with fixed breaks.
- `Rtsne::Rtsne.data.frame` — ORDER=R (random initial embedding, perplexity-based neighbour search); CHUNK=H.
- `quantregForest::quantregForest` — ORDER=R (bootstrap samples per tree); CHUNK=H (tree growing; quantile prediction from the weighted empirical distribution of y in the leaves).

### No-candidate packages (depth 2, lmtest .. z)

Skimmed the in-range packages whose scan found nothing; most are optimisers, I/O, or graphics.
fitdistrplus, energy, bigmemory and LaF fall in batch A's alphabetical range and are not covered here.

- `xts::as.xts.data.frame` (and xts generally) — ORDER=D; CHUNK=P in time order only; state: carried window; notes: time index; `order.by` sorts with ties by input position; not a target.
- `PRROC::roc.curve`, `PRROC::pr.curve` — ORDER=I; CHUNK=K per distinct score (weighted counts), H for continuous scores.
- `ModelMetrics::mse`, `rmse`, `mae`, `logLoss`, `brier`, `confusionMatrix`, `precision`, `recall`, `f1Score`, `kappa`, `mcc` — ORDER=I; CHUNK=A; state: sums, or a fixed 2 x 2 table at a given cutoff.
- `ModelMetrics::auc`, `ModelMetrics::gini`, `ModelMetrics::mauc` — ORDER=I; CHUNK=H; state: all scores; notes: rank-based (Mann-Whitney), K with few distinct scores.
- `twosamples::ks_test`, `cvm_test`, `ad_test`, `wass_test`, `dts_test`, `kuiper_test` — ORDER=I for statistics, R for the permutation p-values; CHUNK=H (ECDFs of the pooled sample), K with few distinct values.
- `missMethods::impute_mean` — ORDER=E; CHUNK=P with 2 passes (A column means, then M).
- `missMethods::impute_median`, `missMethods::delete_MAR_rank`, `missMethods::delete_MAR_censoring`, `missMethods::impute_LS_adaptive` — ORDER=E/I; CHUNK=H; notes: medians, ranks, quantiles, nearest neighbours by correlation.
- `missMethods::impute_EM` — ORDER=I; CHUNK=P; state: per EM iteration the sufficient statistics per missingness pattern (`norm::prelim.norm`/`em.norm`); notes: patterns are K.
- `missMethods::impute_sRHD`, `missMethods::delete_MCAR` — ORDER=R; CHUNK=M (P for hot-deck donor pools); notes: draws per row.
- `poweRlaw::estimate_xmin` — ORDER=I; CHUNK=H (scans sorted candidate xmin with a KS distance).
- `sda::sda` — ORDER=I; CHUNK=P with 2 passes (pass 1 K: class means and frequencies; pass 2 A: centred variances and shrinkage-intensity moments) when p is small; it uses an SVD of the centred n x p data for p >> n.
- `princurve::principal_curve` — ORDER=I; CHUNK=H (iterated projection and smoothing).
- `wordspace::dsm` (triplets), `wordspace::dsm.score` — ORDER=I; CHUNK=K (sparse co-occurrence counts) then P (marginals, then M association scores); `rsvd` is R.
- `pbdMPI::allreduce`, `pbdMPI::reduce` — ORDER=I; CHUNK=A; state: whatever the caller reduces; notes: prior art — SPMD reductions are exactly the A/K merge step for distributed chunks.

### Skipped

units, rjags, runjags, pander, rlist, timeSeries, openxlsx2, mitools, VineCopula, oce (CTD profile processing is D by design), qdapRegex, seasonal, svMisc, r4subcore, metalite — candidates were all coercion, printing, I/O wrappers or formula utilities; terra's flagged SpatVector methods and statnet.common's formula helpers are likewise plumbing.

<!-- source: findings/cran_depth3_a.md -->
## Part: CRAN depth 3, batch A (abc .. MCMCglmm)

Scope: the 66 packages in `batches/depth3_a.tsv`.
Packages whose main fitters were not flagged by the static scan (e.g. `CDM::din()`, `eRm::RM()`, `Amelia::amelia()`, `gmodels::CrossTable()`) were added where the lead asked for them.
File references are relative to `src/<pkg>/`.
Empirical checks (fixed seed, permuted rows, `all.equal()`) were run for `bain::t_test()` + `bain()`, `gmm::gmm()` with default and `"MDS"` weighting, and `marginaleffects::datagrid()`.
The results are quoted in the lines below.

### glmnet

- `glmnet::glmnet` (family `"gaussian"`, `type.gaussian = "covariance"`, the default when nvars < 500) — ORDER=I; CHUNK=A; state: Σw, weighted column sums and sums of squares, X'WX (p×p), X'Wy, Σw·y, Σw·y² (merged with Chan's formulas for centring); notes: default set at R/glmnet.R:389; the null deviance comes from `weighted.mean(y, weights)` (R/elnet.R); covariance-mode coordinate descent (Fortran `elnet1`, reasoned from the R wrapper and documentation) touches the data only through standardized inner products, which it caches as variables enter. A one-pass Gram matrix plus moments therefore reproduces the whole lambda path exactly, with lambda_max = max|X'y|/N from the same state; input is a numeric matrix (data frames go through `makeX()`).
- `glmnet::glmnet` (binomial, poisson, multinomial, mgaussian, gaussian `"naive"`, and `glmnet.path()` for family objects) — ORDER=I; CHUNK=P; state: a standardization pre-pass (A), then per lambda × IRLS iteration the weighted Gram X'WX and X'Wz of the quadratic approximation; notes: naive mode sweeps residuals over all rows per coordinate, but each IRLS quadratic step can be summarized by covariance-mode state; passes ≈ Σ over lambda of IRLS iterations (warm starts); `family = "cox"` needs risk-set sums ordered by time, so it is H, or K over unique event times.
- `glmnet::cv.glmnet` — ORDER=R; CHUNK=P; state: per fold the `glmnet` state above; notes: `foldid = sample(rep(seq(nfolds), length = N))` is positional (R/cv.glmnet.R:257); deriving `foldid` from a row key makes it I, and for gaussian all fold Grams are one K-by-fold pass (training Gram = total − fold).
- `glmnet::makeX`, `glmnet::prepareX` — ORDER=E; CHUNK=P; state: a pre-pass for level sets of character columns (K) and, with `na.impute = TRUE`, train-row column means (A), then M; notes: character columns become factors via `stringsAsFactors = TRUE` (R/makeX.R:99), so the level sets come from the data; `model.matrix(~ . - 1)` with `contrasts = FALSE` emits one column per level, so levels must be declared for chunking; imputation means at R/makeX.R:103.
- `glmnet::predict.glmnet` (`newx`) — ORDER=E; CHUNK=M; state: none; notes: coefficients are fixed.
- **verdict**: gaussian `glmnet()` in covariance mode is an exact one-pass A target, computing the whole path in memory from Gram plus moments; `cv.glmnet()` becomes a single K-by-fold pass once fold ids are hashed from a row key. No chunked interface exists (`bigGlm()` is unpenalized `glmnet()` on an in-memory matrix).

### fastglm

- `fastglm::fastglm_streaming` — ORDER=I; CHUNK=P; state: per IRLS iteration X'WX, X'Wz and deviance accumulated over `chunk_callback(i)`; notes: **already chunk-capable**: "The C++ solver re-pulls all chunks (including this one) on each pass" (R/streaming.R); restricted to `method` 2/3 (LLT/LDLT on the normal equations); supports Firth.
- `fastglm::fastglm` (`fastglm.default`, `fastglmPure`) — ORDER=I; CHUNK=P; state: as above; notes: the default `method = 0L` (R/fit_glm.R:519ff) uses a column-pivoted QR of √W·X, which does not merge, so exact streaming needs normal-equation Cholesky (as in `fastglm_streaming`) or an incremental Givens QR per pass; `big.matrix` input with `big.crossprod` (R/bigmemory_methods.R) is a second out-of-core path.
- `fastglm::fastglm_hurdle` — ORDER=I; CHUNK=P; state: the binomial zero part takes an IRLS Gram over all rows, the zero-truncated count part an IRLS Gram over rows with y > 0, and θ comes from an inner Brent loop over log-likelihood sums (A per θ); notes: the two likelihoods are separable (R/fastglm-hurdle.R:3-9), so both parts share the same passes; the method-of-moments θ start is an A pre-pass.
- `fastglm::fastglm_zi` — ORDER=I; CHUNK=P; state: per EM iteration a row-local E-step (τ_i), then two weighted IRLS Grams (nested passes) plus a θ Brent loop; the final vcov is a numerical Jacobian of the summed score (≈2p extra A passes); notes: R/fastglm-zi.R:8-15.
- **verdict**: the package already has `fastglm_streaming()` (and bigmemory support). The cheap extension is a `chunk_callback` for `fastglm_hurdle()`/`fastglm_zi()`, whose passes are all A-type.

### marginaleffects

- `marginaleffects::avg_predictions`, `avg_comparisons`, `avg_slopes` (and `by =` on the non-avg functions) — ORDER=I; CHUNK=K (A when `by = TRUE`); state: per `by` cell Σw·estimate, Σw, and Σw·∂estimate/∂β (p-vector); notes: aggregation uses data.table `keyby`, so cells come out sorted (R/by.R:94-109); the analytic Jacobian of an average is a weighted column sum, `crossprod(w, X)` (R/get_jacobian_analytic.R:210-221, 286-291), so A. The numerical Jacobian (R/get_jacobian.R:30-56) re-evaluates the whole pipeline p+1 (forward) or 2p (centred) times. The perturbed coefficient vectors are fixed in advance, so all of them fit in ONE pass with (p+1)×cells state instead of p+1 passes. `"differenceavg"`/`"ratioavg"` are functions of averages, so also A.
- `marginaleffects::predictions`, `comparisons`, `slopes` (unit level) — ORDER=E; CHUNK=M (after an A pre-pass); state: none per chunk beyond the fitted model; notes: the default `eps` for slopes is `1e-4 * diff(range(x))` (R/sanitize_variables.R:424-425), so it needs a min/max pre-pass; `variables = "sd"/"2sd"/"minmax"` need A, while `"iqr"`/`"fivenum"` need quantiles, so H (R/sanitize_variables.R:108,124; R/get_comparisons_data_numeric.R:112-113); the delta-method J is one row per output row, so M; `newdata = NULL` uses the model's stored data.
- `marginaleffects::datagrid` (default `grid_type = "mean_or_mode"`; also behind `newdata = "mean"`) — ORDER=D; CHUNK=K; state: Σx and n per numeric column, and value counts per categorical or logical column; notes: `get_mode()` breaks ties by first appearance (`ux <- unique(x); ux[which.max(tabulate(match(x, ux)))]`, R/mean_or_mode.R:4-11). **Verified**: a 16/16 tied factor gives mode `"x"` on the data and `"y"` on the reversed rows. Breaking ties by sorted level would fix it; `grid_type = "balanced"` uses `sort(unique())` (R/datagrid.R:3), so it is K and invariant.
- `marginaleffects::predictions` with `variables = "x"` on a numeric with fewer than 6 distinct values — ORDER=S; CHUNK=K; state: set of distinct values; notes: the counterfactual values are `unique(modeldata[[v]])` in first-appearance order (R/sanitize_variables.R:162-164), so output row order follows input order; with 6 or more values `fivenum()` is used, which is H.
- `marginaleffects::plot_predictions`, `plot_comparisons`, `plot_slopes` — ORDER=I; CHUNK=P; state: pre-pass for the condition grid (50-point `seq()` over the range is A, R/sanitize_condition.R:94-97; `fivenum`/quartiles for the 2nd–4th conditions are H, :123-167), then the `avg_*` K state; notes: the plotted curve is a set of `avg_*`-type estimates over the grid.
- `marginaleffects::inferences` — ORDER=R; CHUNK=P; state: per replicate the refit's state; notes: `method = "boot"/"rsample"/"fwb"` resample rows (R/inferences_boot.R:20) and `"conformal_*"` use random splits. `method = "simulation"` draws β from an MVN, which is not row-indexed, so ORDER=I with an A state of R draws × cells in one pass.
- `marginaleffects::get_predict.*`, `get_model_matrix.*`, `set_coef.data.frame` — ORDER=E; CHUNK=M; state: none; notes: the fitted model's `terms`/`xlevels` fix the columns; `get_predict.mblogit` inherits mclogit's per-choice-set normalisation (K, see mclogit).
- **verdict**: `avg_predictions()`/`avg_comparisons()`/`avg_slopes()` are exact single-pass K targets, delta-method SEs included, if the p+1 perturbed predictions are evaluated per chunk; the default `datagrid()` mode tie-break is a verified order trap.

### margins

- `margins::margins` (`margins.default`, `.glm`, `.lm`, `.betareg`, `.polr`, `.clm`, `.multinom`, `.nnet`, `.merMod`, `.svyglm`) with `vce = "delta"` — ORDER=I; CHUNK=P; state: pass 1 takes max|x| per variable (A) for the step size; pass 2 accumulates per `at` cell the column sums of unit effects and of (p+1) coefficient-perturbed unit effects (A); notes: `setstep <- x + max(abs(x), 1)·sqrt(eps) - x` uses the column-wide max (R/dydx.R:93-94), so unit effects are not row-local without that pre-pass. The Jacobian loops over coefficients, calling `FUN` (a full-data `colMeans`) once per coefficient (R/jacobian.R; R/gradient_factory.R:26,35), which is p+1 passes today and could be one. The returned `margins` object is the unit-level data with `dydx_*` columns appended (E).
- `margins::marginal_effects` (`.default`, `.glm`, `.polr`, …), `margins::dydx.default`, `dydx.factor`, `dydx.logical` — ORDER=E; CHUNK=P (A pre-pass, then M); state: max|x| (`change = "dydx"`), min/max (`"minmax"`), mean/sd (`"sd"`); `"iqr"` uses `fivenum()` (R/dydx.R:106-107), so H; notes: `dydx.factor` takes levels from `levels(as.factor(data[[variable]]))` (R/dydx.R:159), so a factor-level pre-pass is needed for character columns.
- `margins::margins(vce = "bootstrap")` — ORDER=R; CHUNK=P; state: per replicate the full `margins()` state on a resample; notes: `sample(seq_len(nrow(data)), nrow(data), TRUE)` refits per replicate (R/get_effect_variances.R:142); `vce = "simulation"` draws β by `MASS::mvrnorm` (R/get_effect_variances.R:98), which is not row-indexed, so I, with A state per draw.
- `margins::cplot` (`.default`, `.polr`, `.clm`) — ORDER=I; CHUNK=P; state: range pre-pass for `prediction::seq_range()` (R/cplot.R:159); other variables are set by `prediction::mean_or_mode` (A/K); `what = "effect"` reruns `margins()` per grid value; notes: the mode tie-break lives in package prediction (same code as marginaleffects, so likely the same trap).
- **verdict**: `margins()` with the delta method takes 1 pre-pass plus 1 pass if the p+1 perturbations are carried together; today it makes p+1 full passes.

### bayestestR

Here "rows" are posterior draws (chains concatenated); every summary is per column.

- `bayestestR::p_direction` (`.data.frame`, `.mcmc`, `.MCMCglmm`, `.BGGM`; `method = "direct"`) — ORDER=I; CHUNK=A; state: per parameter count(x > null), count(x < null), n; notes: R/p_direction.R:708ff; `method` set to a density method makes it H (KDE).
- `bayestestR::p_significance` (`.data.frame`, …) — ORDER=I; CHUNK=A; state: counts beyond ±threshold, n; notes: R/p_significance.R:370-382; the default threshold for a bare data frame does not depend on the draws.
- `bayestestR::bayesfactor_restricted.data.frame` — ORDER=I; CHUNK=A; state: per hypothesis the count of posterior and prior draws satisfying it; notes: `posterior_p <- sapply(posterior_l, mean)` (R/bayesfactor_restricted.R:319-320); prior and posterior can stream separately.
- `bayestestR::p_rope.data.frame` (`rope(ci = 1)`) — ORDER=I; CHUNK=A; state: count inside the ROPE, n; notes: with `ci = 1` the ETI bounds are min/max, so every draw is inside the CI.
- `bayestestR::hdi` (`.data.frame`, `.mcmc`, `.MCMCglmm`, `.get_predicted`) — ORDER=I; CHUNK=H; state: all rows; notes: `sort.int(x)` then a sliding window (R/hdi.R:462); escape: a quantile sketch, or a fixed-grid histogram after a range pre-pass (2 passes, approximate).
- `bayestestR::eti`, `bci`, `spi`, `ci` (`.data.frame`, …) — ORDER=I; CHUNK=H; state: all rows; notes: `stats::quantile` (R/eti.R:327, R/bci.R:347-349, R/spi.R:413); `bci` also needs the proportion below the posterior mean (A); escape: t-digest/KLL.
- `bayestestR::rope`, `equivalence_test` (`.data.frame`, …) — ORDER=I; CHUNK=H; state: all rows; notes: CI bounds via `ci()` then the proportion inside the ROPE among CI draws (R/rope.R:839-847), which is P(2) if the quantiles are sketched.
- `bayestestR::point_estimate`, `describe_posterior` (`.data.frame`, …) — ORDER=I; CHUNK=H; state: all rows; notes: the defaults (median, ETI, MAP) are holistic; `centrality = "mean"` is A.
- `bayestestR::map_estimate`, `p_map`, `estimate_density` (`.data.frame`, `.grouped_df`) — ORDER=I; CHUNK=H; state: all rows; notes: KDE with `bw = "SJ"` (R/estimate_density.R:221); `bw.SJ` scales with `min(sd, IQR/1.349)`, so it needs quantiles; given a bandwidth, linear binning on a fixed grid is P(2) with A state.
- `bayestestR::bayesfactor_parameters.data.frame`, `si.data.frame` — ORDER=I; CHUNK=H; state: all rows; notes: logspline density fits to prior and posterior.
- `bayestestR::sexit` — ORDER=I; CHUNK=H; state: all rows; notes: median plus proportions.
- `bayestestR::weighted_posteriors.data.frame` — ORDER=R; CHUNK=M; state: none; notes: `sample(nrow(temp_params), size = …)` per model (R/weighted_posteriors.R:289); reservoir sampling per model would stream it.
- `bayestestR::*.get_predicted` methods — ORDER=E; CHUNK=M; state: none (H across draws within a row); notes: chunk over predicted rows; per predicted row the draws in the `iterations` attribute are summarized holistically.
- **verdict**: `p_direction()`, `p_significance()`, `bayesfactor_restricted()` and `p_rope()` are exact single-pass A over draws; every interval or density summary is H and needs a quantile sketch.

### ade4

- `ade4::as.dudi` (engine of every `dudi.*`) — ORDER=I; CHUNK=P; state: pass 1 accumulates the weighted cross-product (√w·X·√cw)'(√w·X·√cw), p×p, used when n ≥ p (A); pass 2 maps row scores `li`/`l1` (M); notes: `crossprod` then `eigen` (R/dudi.R:25-30); n < p switches to the n×n `tcrossprod`, which is H; the result stores `tab`, the transformed full table, which is an M output.
- `ade4::dudi.pca` — ORDER=I; CHUNK=P; state: weighted means and sds (A; mergeable with the Gram in a single Chan-style pass), then as `as.dudi`; notes: `row.w = rep(1, n)/n` needs only n; `scannf = TRUE` is interactive.
- `ade4::dudi.coa`, `dudi.nsc`, `dudi.dec` — ORDER=I; CHUNK=A (then M); state: grand total N, column sums, and the p×p matrix Σ_i x_ij·x_ik / r_i (row sum r_i is row-local); notes: `df/row.w`, `sweep(df, 2, col.w)` (R/dudi.coa.R) expand exactly into these sums. When the input is long-format records rather than a contingency table, the table itself is a K `xtabs` first; zero rows become NA→0, which is row-local.
- `ade4::dudi.acm`, `dudi.fca`, `prep.fuzzy`, `prep.fuzzy.var` — ORDER=I; CHUNK=P; state: pass 1 builds the Burt matrix (indicator cross-products) and level weights (A given level sets); pass 2 accumulates row scores and per-level score sums for `cr` (`tapply(x, qual, sum)`, R/dudi.acm.R, so K); notes: factor level sets must be fixed.
- `ade4::dudi.mix`, `dudi.hillsmith` — ORDER=I; CHUNK=P; state: pre-passes for `stats::poly(w, 2)` on ordered or quantitative columns (`add.square`) (R/dudi.mix.R:44,56: needs moments up to order 4, A), level sets with `drop = TRUE` (K), and weighted means and sds; then the Gram (A) and scores (M); notes: polynomial bases and dropped levels are data-dependent, so they need declaring or a pre-pass.
- `ade4::nipals` — ORDER=I; CHUNK=P; state: per iteration the loadings sums Σ_i x_ij·t_i and Σ t_i² over observed cells (A), where t_i is recomputed row-locally from the previous loadings; notes: the start `th <- X[,1]` is row-aligned (R/nipals.R:33), and NA handling is per cell; the user's `tol` is overwritten by `tol <- 1e-9` (R/nipals.R:13).
- `ade4::withinpca`, `scalefacwt` — ORDER=I; CHUNK=K; state: per factor level the count, sums, and within-group cross-products (Chan merge), from which the pooled within Gram follows; notes: `tapply(x, fac, sum)/cla.w` (R/withinpca.R:11-13); `scaling = "partial"` needs per-level variances, also K.
- `ade4::pcaiv`, `pcaivortho`, `discrimin.coa` — ORDER=I; CHUNK=P; state: X'WX, X'WY and Y'WY (A) give the fitted-value Gram Y'X(X'WX)⁻¹X'Y exactly; pass 2 maps row scores; notes: the current implementation calls `lm()` per column of `dudi$tab` (R/pcaiv.R); covariates are `scalewt()`-ed first (A pre-pass).
- `ade4::sepan`, `mfa`, `statis`, `pta`, `foucart`, `ktab.data.frame` — ORDER=I; CHUNK=P; state: per block the cross-products X_k'DX_l (A), from which RV coefficients and the compromise follow; then scores (M); notes: `statis` builds n×n operators `wk %*% t(wk)` (R/statis.R:19), which is H as written, but RV = ‖X_k'DX_l‖² is exact from p×p blocks.
- `ade4::suprow.*` — ORDER=E; CHUNK=M; state: none; notes: projects supplementary rows on fixed axes.
- `ade4::supcol.*` — ORDER=I; CHUNK=A; state: Xsup'·diag(lw)·li (supplementary columns × axes); notes: Xsup rows must be aligned with the original rows.
- `ade4::loocv.dudi`, `loocv.between`, `loocv.discrimin` — ORDER=I; CHUNK=H; state: all rows; notes: n refits; exact alternative: pass 1 accumulates the A state, pass 2 performs a rank-one downdate plus eigen per row (M, O(n·p³)).
- `ade4::dist.binary`, `dist.prop`, `dist.quant`, `dist.ktab`, `divc`, `dpcoa` — ORDER=I; CHUNK=H; state: all rows; notes: n×n output or row×row distances; `divc` rows are species aligned with a species distance matrix.
- `ade4::mld` — ORDER=D; CHUNK=H; state: all rows; notes: orthobasis vectors index rows by position (a series or phylogeny).
- ade4 `*.rtest`/`randtest.*` (RV.rtest, mantel.rtest, procuste.rtest; not in the scan list) — ORDER=R; CHUNK=P; notes: row permutations.
- **verdict**: `dudi.pca()`, `dudi.coa()` and `dudi.acm()` (via `as.dudi()`) are exact P(2) targets: an A Gram pass, eigen in memory, then an M pass for scores. `withinpca()` is single-pass K, and `pcaiv()` is A on cross-products.

### h2o

H2O is a client for a JVM cluster whose frames are already split into distributed chunks, and its algorithms run as map-reduce passes over them, so it is prior art throughout.

- `h2o::h2o.glm` — ORDER=I (R with `nfolds` and the `"AUTO"`/`"Random"` fold assignment; D with `fold_assignment = "Modulo"`); CHUNK=P; state: per IRLSM iteration a Gram X'WX and X'Wz reduced over chunks; notes: `solver` choices at R/glm.R:228; `"Modulo"` (R/glm.R:215) assigns folds by row position.
- `h2o::h2o.kmeans` — ORDER=R; CHUNK=P; state: per Lloyd pass the per-centroid sums and counts (A); notes: `init` is Furthest, PlusPlus or Random with a seed; `estimate_k` is deterministic.
- `h2o::h2o.gam` — ORDER=I; CHUNK=P; state: per IRLS iteration the Gram of the spline basis, reduced server-side; notes: GLM on a spline basis; knot locations are data-dependent server-side unless `knot_ids` are supplied.
- `h2o::h2o.summary`, `h2o::h2o.hist` — ORDER=I; CHUNK=A; state: per-column moments, approximate-quantile histograms, and fixed bins; notes: approximate quantiles by default, with `exact_quantiles = TRUE` as the opt-in (R/frame.R:2486-2512), which is prior art for H→sketch; `hist` does a range pre-pass, then fixed bins (P(2)).
- `h2o::h2o.performance` — ORDER=I; CHUNK=A; state: per-chunk metric sums and binned threshold counts; notes: metrics from per-chunk sums; AUC from binned thresholds (server-side).
- `h2o::h2o.permutation_importance` (+ `_plot`) — ORDER=R; CHUNK=P; state: per permuted feature the metric sums on a subsample; notes: `n_samples = 10000` subsample plus permutations (R/permutation_varimp.R:31-34).
- `h2o::h2o.shap_summary_plot`, `h2o.shap_explain_row_plot`, `h2o.predict_rules`, `h2o.mojo_predict_df`, `h2o.ice_plot`, `h2o.pd_multi_plot`, `h2o.residual_analysis_plot` — ORDER=E; CHUNK=M; state: none; notes: PD/ICE take one M+A pass per grid value; the SHAP summary subsamples, so R. state: none
- `h2o::h2o.calculate_fairness_metrics`, `h2o.inspect_model_fairness`, `h2o.fair_*_plot` — ORDER=I; CHUNK=K; state: per protected-group cell the confusion counts and metric sums; notes: metrics per protected-group cell.
- `h2o::as.h2o.data.frame` — ORDER=E; CHUNK=M; state: none; notes: writes the data frame to a temporary CSV with `data.table::fwrite` and calls `h2o.uploadFile` (R/frame.R:4175-4194); the server parser chunks the file.
- **verdict**: prior art rather than a target. Its GLM shows the "A state per pass, reduced over chunks" design, and `h2o.summary()` shows "approximate quantiles by default". The trap is `fold_assignment = "Modulo"`.

### gmm

- `gmm::gmm` (default `vcov = "HAC"`) — ORDER=D; CHUNK=P; state: pass 1 accumulates Z'X, Z'y, Z'Z for the first-step 2SLS (A); pass 2 forms the weighting matrix from moments g_t = z_t·e_t; notes: the default `vcov = "HAC"` with `prewhite = 1` and `bw = bwAndrews` (R/gmm.R:14) computes kernel autocovariances across adjacent rows (`.myKernHAC`, R/gmm.R:577-585). Cross-sectional IV users therefore get an order-dependent estimator unless they set `vcov = "MDS"`/`"iid"`. **Verified**: permuting rows of a linear IV fit moves the coefficients by 9e-3 with HAC, while `vcov = "MDS"` gives identical coefficients and vcov.
- `gmm::gmm(vcov = "MDS"/"iid")`, including the formula methods `momentEstim.baseGmm.twoStep.formula` and `momentEstim.tsls.twoStep.formula` — ORDER=I; CHUNK=P; state: pass 1 takes Z'X, Z'y, Z'Z (A); pass 2 takes `crossprod(gt)/n` and the moment means (A; R/gmm.R:586-590); pass 3 maps residuals and fitted values (M); notes: R/momentEstim.R:295-320. The nonlinear `g` function, `type = "iterative"` and `"cue"` run each objective evaluation as one A pass inside `optim`, so P.
- `gmm::gel`, `evalGel`, `ATEgel` — ORDER=I (`smooth = FALSE`); CHUNK=P; state: per θ an inner Newton for λ with Σρ'(λ'g_i)·g_i and Hessian sums (A per step); implied probabilities are M; notes: `smooth = TRUE` kernel-smooths moments over time, so D.
- `gmm::sysGmm`, `sur` — ORDER=I; CHUNK=P; state: as for `gmm`, per equation block; notes: the default `vcov = "MDS"` (R/sysGmm.R:63-64) is invariant; `vcov = "HAC"` makes it D.
- `gmm::evalGmm` — ORDER=D; CHUNK=A; state: moment means and the weighting matrix at fixed θ; notes: the default `vcov = "HAC"` (R/gmm.R:50-51) is order-dependent; with `"iid"` it is I and one A pass.
- `gmm::bwWilhelm` — ORDER=D; CHUNK=H; state: all rows; notes: HAC bandwidth with an `order.by` time index.
- `gmm::getDat` — ORDER=E; CHUNK=M; state: none; notes: model-frame construction.
- **verdict**: the linear two-step `gmm(vcov = "MDS")` is an exact P(2–3) target with A state; the default HAC is a verified order trap for cross-sectional data.

### fBasics

- `fBasics::ghFit`, `hypFit`, `ghtFit`, `sghFit`, `tFit` — ORDER=I; CHUNK=P; state: `scale = TRUE` needs an sd pre-pass (A; R/dist-ghFit.R:40); then each `nlminb` objective is one A pass of `-sum(dgh(...))` (R/dist-ghFit.R:51); notes: `doplot = TRUE` adds a `density()` plot (H, display only); `tFit` uses `-sum(log(dt(...)))`.
- `fBasics::.mrlPlot` — ORDER=I; CHUNK=P; state: pre-pass for the mean and max (thresholds `seq(umin, umax, length = nint)`); pass 2 accumulates per threshold the sum and count of exceedances (A, nint cells) (R/plot.R:108ff); notes: mean residual life on a fixed threshold grid.
- `fBasics::.qStableFit` — ORDER=I; CHUNK=H; state: all rows; notes: McCulloch quantile estimator via `sort(x)`.
- `fBasics::tsHessian` — ORDER=I; CHUNK=P; state: one objective sum per perturbation; notes: numerical Hessian, one objective evaluation (A) per perturbation.
- `fBasics::linearInterp`, `linearInterpp`, `akimaInterp`, `akimaInterpp`, `krigeInterp` — ORDER=I; CHUNK=H; state: all rows; notes: triangulation or kriging; chunkable over output grid points only.
- **verdict**: the distribution fitters are textbook P with A state per likelihood evaluation.

### geoR

- `geoR::variog` — ORDER=I; CHUNK=H; state: per distance bin Σ(z_i − z_j)², the count, and the cloud; notes: `dist(as.matrix(coords))` over all pairs (R/variogram.R:103), with the default `max.dist` equal to the maximum pairwise distance (:131) before binning in C (`binit`, :140); `trend` uses a detrending `lm()` pre-pass (A). Escape: fixed `uvec`/`max.dist`, then a block-pair nested loop over chunk pairs with A state per block pair (exact but quadratic I/O).
- `geoR::likfit`, `loglik.GRF`, `krige.bayes`, `xvalid` — ORDER=I; CHUNK=H; state: all rows; notes: n×n `varcov.spatial` plus `solve` (R/likGRF.R:639-650); `xvalid` is leave-one-out; only kriging *predictions* are chunkable, over the prediction locations.
- `geoR::variog.mc.env`, `sample.geodata` — ORDER=R; CHUNK=H; state: all rows; notes: `data[sample(1:n.data)]` permutations (R/variogram.R:952-953).
- `geoR::jitterDupCoords.default` — ORDER=R; CHUNK=H; state: all rows; notes: random jitter of duplicated coordinates.
- **verdict**: nothing streams exactly; `variog()` with fixed bins is the only realistic out-of-core candidate (block-pair passes).

### gam

- `gam::gam` (with `s()` terms; `s.wam`, `general.wam`) — ORDER=I; CHUNK=P; state: per local-scoring/backfitting sweep and per smooth term, the partial-residual sums and weights keyed by unique x (K), then refit spline coefficients that recompute each row's f_j(x_ij) on the fly; notes: smoothing variables are rounded to `signif(x, 6)` and reduced to `unique(sort())` (R/gam.match.R; R/s.wam.R `bakfit`), so the smoother state is K over unique x, while the parametric part takes X'WX per sweep (A). The number of passes is outer IRLS × backfitting sweeps, and convergence is up to `bf.epsilon`.
- `gam::gam` with `lo()` terms (`lo.wam`) — ORDER=I; CHUNK=H; state: all rows; notes: loess needs local neighbourhoods; it degenerates to K only when x has few unique values.
- `gam::predict.Gam` / `newdata.predict.Gam`, `preplot.Gam` — ORDER=E; CHUNK=M; state: the fitted object; notes: predicting on new data re-smooths the stored *training* partial residuals at `xeval` for every smooth term (R/newdata.predict.gam.R:39-43). That is an in-memory O(n_train) state per call, but each new row is independent.
- `gam::step.Gam` — ORDER=I; CHUNK=P; state: per candidate model the `gam()` state; notes: refits per candidate model.
- **verdict**: `gam()` with `s()` terms is an exact P target with K-over-unique-x state, a rare holistic-looking smoother that is exactly chunkable.

### betareg

- `betareg::betareg` — ORDER=I; CHUNK=P; state: pass 1 takes `lm.wfit` start values on the link-transformed y (A; R/betareg.R:291), where `type = "BC"/"BR"` and the `(y·(n-1)+0.5)/n` adjustment need n; pass 2 takes the residual variance for the φ start (A); each `optim` BFGS log-likelihood and gradient evaluation is then one pass (A), followed by Fisher scoring with the expected information sums (A, `fsmaxit = 200`); notes: R/betareg.R:164-169, 631.
- `betareg::predict.betareg` — ORDER=E; CHUNK=M; state: none; notes: fixed coefficients.
- `betareg::simulate.betareg` — ORDER=R; CHUNK=M; state: none; notes: one draw per fitted row.
- `betareg::betamix` — ORDER=R; CHUNK=P; state: per EM iteration the component-weighted log-likelihood and gradient sums; notes: flexmix EM with random initial clustering.
- `betareg::betatree` — ORDER=I; CHUNK=H; state: all rows; notes: partykit model-based recursive partitioning: split search and parameter-instability tests order the data by each partitioning variable.
- **verdict**: `betareg()` is a standard P target with A state per likelihood/gradient evaluation.

### earth

- `earth::earth` (`earth.formula`, `earth.default`) — ORDER=I; CHUNK=H; state: all rows; notes: the MARS forward pass (`.Call("ForwardPassR")`, R/earth.fit.R:454; C code) scans each predictor's sorted values as candidate knots subject to `minspan`/`endspan`, which are counts of observations. Escape: pre-bin each x to a quantile grid, after which each forward-step candidate needs only the hinge-basis Gram (A per step, P overall). The backward pruning pass works from bx'bx (A). `glm = ` adds IRLS (P); `nfold` uses random folds (R).
- `earth::expand.bpairs.default`, `expand.bpairs.formula` — ORDER=E; CHUNK=M; state: none; notes: expand binomial pairs per row.
- `earth::predict.earth` — ORDER=E; CHUNK=M; state: none; notes: evaluates the fitted hinge basis per row.
- **verdict**: the forward pass is H; only prediction is chunkable without approximation.

### ks

- `ks::kde`, `ks::kdde` — ORDER=I; CHUNK=P; state: pass 1 takes ranges, sd, and the covariance used for `pre = "sphere"` (A); pass 2 does linear binning onto a fixed `bgridsize` grid (A), from which the binned plug-in bandwidth (`hpi`/`Hpi` with `binned = TRUE`) and the binned estimate both follow; pass 3 re-bins if the final grid range (range ± `supp`·h) differs; notes: binning is the default when n > 1 (d = 1), > 500 (d = 2) or > 1000 (d > 2) (R/binning.R:25-33; R/kde.R:21-76). `compute.cont = TRUE` (the default) evaluates the density at every data point and takes quantiles (R/kde.R:136-137, 806ff), which is a further M pass plus H quantiles; approximate those from the grid and bin counts, or set `compute.cont = FALSE`. Binned estimation is unavailable for d > 4.
- **verdict**: `kde()` is a near-exact P target (2–3 A passes) because it already bins by default; only the contour levels are holistic.

### MatchIt

- `MatchIt::matchit(method = "nearest")` — ORDER=D; CHUNK=H; state: all rows; notes: greedy matching in `m.order`; the default is `"largest"` for a propensity score and `"data"` otherwise (R/matchit2nearest.R:525-527), and "any ties are broken based on the order in which the data appear" (:190). So Mahalanobis or Euclidean matching depends on input order, and propensity-score matching depends on order through ties. The `distance = "glm"` propensity model is P.
- `MatchIt::matchit(method = "exact")` — ORDER=I; CHUNK=K; state: treated and control counts per covariate cell, followed by row-local weights (M); notes: subclass labels may follow cell order.
- `MatchIt::matchit(method = "cem")` — ORDER=I (D with `k2k = TRUE`, whose default `m.order = "data"`, R/matchit2cem.R:495); CHUNK=P; state: a pre-pass for range/Sturges breaks (A), then counts per coarsened cell (K), then M; notes: cells are coarsened covariate combinations.
- `MatchIt::matchit(method = "subclass")` — ORDER=I; CHUNK=H; state: all rows; notes: subclass cut points are `quantile(distance, …)` (R/matchit2subclass.R:178-180); escape: a quantile sketch, then K.
- `MatchIt::matchit(method = "full"/"optimal"/"cardinality"/"quick")` — ORDER=I; CHUNK=H; state: all rows; notes: global network-flow or LP optimization; `method = "genetic"` is R.
- `MatchIt::mahalanobis_dist`, `scaled_euclidean_dist`, `robust_mahalanobis_dist`, `euclidean_dist` — ORDER=I; CHUNK=H; state: covariance or sd (A) or ranks (`robust`, H), then an n_t×n_c matrix; notes: chunkable over treated rows once the scale is fixed.
- `MatchIt::match_data`, `add_s.weights` — ORDER=E; CHUNK=M; state: none; notes: attach per-row weights and subclass to the original rows.
- **verdict**: exact and CEM matching are K; nearest-neighbour matching is order-dependent by design and documentation.

### mclogit

- `mclogit::mclogit` — ORDER=I; CHUNK=P; state: per IRLS iteration X'WX and X'Wz, where the working weights need per-choice-set softmax denominators (K keyed by set); notes: exact passes need all rows of a set in the same chunk, or a K pre-pass per iteration for set sums. Random effects (PQL) add per-group K state.
- `mclogit::mblogit` — ORDER=I; CHUNK=P; state: multinomial IRLS Gram per iteration (A), plus K per random-effect group; notes: random effects are fitted by PQL.
- `mclogit::predict.mclogit`, `predict.mmclogit` (`type = "response"`) — ORDER=I; CHUNK=P; state: pass 1 takes Σexp(η) per choice set (K), pass 2 maps p = exp(η)/Σ (M); notes: `rowsum(exp.eta, set)` (R/mclogit.R:571-574); `type = "link"` is E/M.
- `mclogit::predict.mblogit`, `predict.mmblogit` — ORDER=E; CHUNK=M; state: none; notes: the multinomial softmax is within a row.
- `mclogit::simulate.mclogit`, `simulate.mblogit` — ORDER=R; CHUNK=M; state: none; notes: one draw per fitted row.
- **verdict**: `mclogit()` is P with K-per-set state; prediction is chunkable if chunks are grouped by choice set.

### icenReg

- `icenReg::ic_np` — ORDER=I; CHUNK=K; state: weighted counts per distinct (L, R) interval pair, per factor level; notes: the Turnbull support comes from `sort(unique(c(lower, upper)))` (R/internal_utilities.R:10-11), and the EM/ICM runs on the reduced data (R/ic_np.R:105), so the K reduction is exact.
- `icenReg::ic_sp` — ORDER=I (R with `bs_samples > 0`); CHUNK=P; state: a K pre-pass for the maximal-intersection support, then per ICM iteration the gradient and Hessian sums w.r.t. β (A) and the baseline masses (K over support); notes: the default `bs_samples = 0` (R/ic_sp.R:89-91); the bootstrap resamples rows (R/internal_utilities.R:23).
- `icenReg::ic_par` — ORDER=I; CHUNK=P; state: log-likelihood and gradient sums per optimizer step; notes: optimizer over a log-likelihood sum, A per evaluation.
- `icenReg::ic_bayes` — ORDER=R; CHUNK=P; state: log-likelihood sum per MCMC proposal; notes: MCMC with one log-likelihood pass per proposal; impractical to stream.
- `icenReg::getFitEsts` — ORDER=E; CHUNK=M; state: none; notes: fitted survival quantities per new row.
- `icenReg::diag_covar`, `diag_baseline` — ORDER=I; CHUNK=P; state: per stratum or cut the `ic_sp`/`ic_par` state; notes: refits per stratum or cut.
- **verdict**: `ic_np()` is an exact single-pass K reduction followed by an in-memory NPMLE.

### dfidx

- `dfidx::dfidx` — ORDER=D (S when both indices are given as columns); CHUNK=K; state: rows keyed by the first index (choice situation); notes: with `idx = c(NA, "alt")` the first index is created positionally as `rep(1:nchid, each = nalts)` (R/dfidx.R:168-172); the same holds for `levels =` without `idx` (:137-141). A missing second index is also derived from within-group row order (:396-400). With explicit indices the data are sorted by them (`sort = TRUE`, :385-391), so output order is canonical (S).
- `dfidx::mean.dfidx` — ORDER=D (ties only); CHUNK=K; state: per alternative the sums and counts; notes: for character columns `factor(x, levels = unique(x))` followed by `which.max(table(x))` breaks mode ties by first appearance (R/methods.R:309-310).
- `dfidx::model.frame.dfidx` — ORDER=E; CHUNK=M; state: none; notes: row-local given the index columns.
- **verdict**: a trap package, since its positional index construction silently assumes contiguous, ordered rows.

### CDM

- `CDM::din` (and `gdina`, which shares the code; not in the scan list) — ORDER=I; CHUNK=K; state: weighted frequency per distinct item-response pattern (NA coded as 9); notes: `item.patt.subj` pastes responses and `rowsum(weights, item.patt.subj)` (R/din.R:151-166), after which the EM runs on patterns; the weight normalization `nrow·w/sum(w)` needs n and Σw (A).
- `CDM::mcdina` — ORDER=I; CHUNK=P; state: per EM iteration the expected counts per item × category × skill class × group (A; `while (iter < maxit …)`, R/mcdina.R:151); notes: rows could be collapsed to (pattern, group) counts first (K) as `din()` does; groups are `sort(unique(group))` (R/mcdina.R:47).
- `CDM::modelfit.cor`, `modelfit.cor2` — ORDER=I; CHUNK=A; state: observed and expected pairwise item moments; notes: `posterior` must be row-aligned with `data`.
- `CDM::IRT.repDesign` — ORDER=E (R for `jktype = "BOOT"`); CHUNK=M; state: none; notes: replicate weights from `jkzone`/`jkrep` via BIFIEsurvey.
- `CDM::sequential.items` — ORDER=E; CHUNK=M; state: none; notes: recodes polytomous items row by row.
- **verdict**: `din()` and `gdina()` already reduce the data to K response-pattern counts, so an exact chunked front end is trivial.

### eRm

- `eRm::RM`, `PCM`, `RSM`, `LLTM`, `LPCM`, `LRSM` (conditional ML; not in the scan list) — ORDER=I; CHUNK=K; state: item-category raw-score totals (`colSums(X01)`, R/cmlprep.R:8) and raw-score frequencies per NA-pattern × group (`table(rvel)`, R/cmlprep.R:41; NA structures at :69-70); notes: CML depends only on these sufficient statistics, so without missing data the state is fixed-size (A).
- `eRm::person.parameter` — ORDER=I; CHUNK=K; state: raw-score frequencies per NA pattern; notes: estimates are per raw score (and NA pattern), and the per-person output maps back as M.
- **verdict**: `RM()`/`PCM()` are exact single-pass K (A without NAs).

### lfe

- `lfe::felm` — ORDER=I; CHUNK=P; state: per alternating-projection sweep, for each fixed-effect factor, the sums and counts per level of the current residual (K), where each row's residual is recomputed from the accumulated level adjustments; the centred X'X and X'y follow (A); notes: centring by `demeanlist()` (R/felm.R:374; C code) converges to `eps`; `exactDOF` and `compfactor()` (R/felm.R:449) need the connected components of the FE bipartite graph (union-find over levels, mergeable K); cluster-robust SEs use K by cluster; `Nboot` resamples rows (R/felm.R:1325), so R.
- `lfe::fepois` — ORDER=I; CHUNK=P; state: per IRLS iteration the per-FE-level weighted sums (K) and the centred Gram (A); notes: IRLS outer loop with weighted demeaning inside, K state per level.
- `lfe::getfe` (`method = "kaczmarz"`, not in the scan list) — ORDER=I up to tolerance; CHUNK=P; state: per sweep the per-level effect adjustments; notes: Kaczmarz sweeps rows sequentially, so the iterate path depends on order but the converged solution does not.
- **verdict**: `felm()` is an exact P target with K state per FE level, and it is the model case of "multi-pass with keyed state".

### grf

- `grf::lm_forest`, `multi_arm_causal_forest` (and the other forests) — ORDER=R; CHUNK=H; state: all rows; notes: subsampling (`sample.fraction = 0.5`) with honesty splits and a random `seed` (R/lm_forest.R:126-138); `Y.hat`/`W.hat` default to out-of-bag regression forests; tree growth sorts by candidate variables. `predict()` is chunkable over test rows (M).
- **verdict**: not a target, apart from chunked prediction.

### aorsf

- `aorsf::orsf` — ORDER=R; CHUNK=H; state: all rows; notes: oblique random forest with bootstrap or subsample per tree and Newton-Raphson linear-combination splits; prediction is M.
- **verdict**: not a target (randomized trees); prediction is M.

### chemometrics

- `chemometrics::stepwise` — ORDER=I; CHUNK=A; state: full X'X, X'y and y'y over all candidate columns; notes: `step()` on `lm()` fits (R/stepwise.R:36-43). Every sub-model's RSS and BIC follow from the full cross-product, so the whole search is one pass.
- `chemometrics::lassocoef`, `plotRidge` — ORDER=I; CHUNK=A; state: column means and norms, X'X and X'y; notes: `lars()` with `use.Gram = TRUE` (the default for moderate p) and `MASS::lm.ridge()` (R/plotRidge.R:18) depend only on these; the residual plot needs an M pass.
- `chemometrics::lassoCV`, `ridgeCV`, `lmCV`, `mvr_dcv`, `pcaCV` — ORDER=R (D with `segment.type = "consecutive"`/`"interleaved"`); CHUNK=P; state: per fold the Gram or lm cross-products; notes: `cvsegments(n, k, type = segment.type)` (R/ridgeCV.R:34; R/lmCV.R:25; R/mvr_dcv.R:69; R/pcaCV.R:17); consecutive and interleaved folds are positional, so order-dependent even with no RNG.
- **verdict**: `stepwise()` (lm) and `lassocoef()` are single-pass A on the Gram; the CV helpers carry a positional-fold trap.

### caper

- `caper::pgls` — ORDER=I; CHUNK=H; state: all rows; notes: phylogenetic VCV (n×n) with `solve(V)` (R/pgls.R:23,58-64); rows are matched to tips by name, so row order is irrelevant.
- `caper::crunch`, `brunch`, `macrocaic` — ORDER=I; CHUNK=H; state: all rows; notes: independent contrasts by tree traversal over all tips.
- `caper::comparative.data`, `caicStyleArgs` — ORDER=S; CHUNK=K; state: tip-label match table; notes: rows reordered to tree order via `match()` (R/comparative.data.R:52-57).
- `caper::fusco.test`, `phylo.d` — ORDER=R; CHUNK=H; state: all rows; notes: randomization.
- `caper::predict.pgls` — ORDER=E; CHUNK=M; state: none; notes: X·β on new rows.
- **verdict**: nothing streams; the phylogenetic VCV makes the fitters holistic. `comparative.data()` only reorders rows to match the tree.

### gplots

- `gplots::plotmeans` — ORDER=I; CHUNK=K; state: per group n, Σy, Σy²; notes: `split()`, then mean and var per group (R/plotmeans.R:45-60).
- `gplots::balloonplot.table` — ORDER=I; CHUNK=K; state: count per table cell; notes: table cells.
- `gplots::bandplot.formula` — ORDER=D (ties in x); CHUNK=H; state: all rows; notes: `order(x)` then running mean and sd with window `n·width` (R/bandplot.R:39-43). Tied x values keep input order, so the running windows change under permutation. The unused helper `wapply(method = "range")` would be P(2) with A state on a 50-point grid.
- `gplots::lowess.formula`, `plotLowess`, `overplot`, `panel.overplot` — ORDER=I; CHUNK=H; state: all rows; notes: lowess.
- **verdict**: only `plotmeans()` is exactly chunkable.

### lavaan.mi

- `lavaan.mi::lavaan.mi`, `cfa.mi`, `sem.mi`, `growth.mi` — ORDER=I; CHUNK=A per imputation; state: per imputed data set the sample means and covariances (normal-theory ML), adding fourth-order moments for robust estimators; notes: data must be a list of imputations, `mids`, or `amelia` (R/lavaan.mi.R:124-157), so the natural chunk is the imputation. `missing = "fiml"` needs K by missingness pattern, and ordinal indicators need bivariate tables (K). The A claim comes from lavaan's semantics, not from this package's code.
- `lavaan.mi::poolSat` — ORDER=I; CHUNK=A; state: per imputation the means, covariances and n; notes: saturated moments by `lavaan::lavCor` per imputation (R/pool-saturated.R:228ff).
- `lavaan.mi::lavTestLRT.mi`, `lavTestScore.mi`, `modindices.mi`, `parameterEstimates.mi` — ORDER=I; CHUNK=A; state: per imputation the log-likelihood at pooled parameters (`pool.method` D3/D4); notes: otherwise these pool fitted results across imputations without touching rows.
- **verdict**: each imputation is an exact A reduction to sample moments, so `lavaan.mi()` can stream rows of every imputation into moment matrices; the natural chunk is the imputation.

### FME

- `FME::summary.sensFun` — ORDER=I; CHUNK=K; state: per variable Σ|S|, ΣS², ΣS and n (`aggregate(..., by = list(Vars))`, R/sensFun.R:156-158); notes: L1 and L2 norms of sensitivity functions.
- `FME::summary.sensRange` — ORDER=I; CHUNK=H; state: all rows; notes: per-output quantiles (q05–q95) across runs.
- `FME::cross2long` — ORDER=E; CHUNK=M; state: none; notes: wide-to-long reshape.
- **verdict**: `summary.sensFun()` is single-pass K; the rest are summaries or plots of model runs.

### gaston

- `gaston::LD.clump` — ORDER=D (ties in p); CHUNK=H; state: all rows; notes: greedy clumping in `order(p)` (R/ld_clump.r:15), so SNPs with tied p-values are processed in input order.
- `gaston::SNP.duplicated` — ORDER=S; CHUNK=K; state: hash set of seen keys; notes: returns indices of later duplicates by key (C++ hash, R/snp_duplicated.r); which copy counts as the duplicate depends on order.
- `gaston::SNP.match` — ORDER=E; CHUNK=P; state: pass 1 builds the key set of `table` (K), pass 2 matches rows (M); notes: lookup by key in `table`.
- **verdict**: only `SNP.duplicated()`/`SNP.match()` are keyed, and `LD.clump()` has a tie-order trap.

### crs

- `crs::crs.formula` — ORDER=I; CHUNK=H; state: all rows; notes: the default `knots = "quantiles"` (R/crs.R:531) needs quantile knots. Given the knots, each candidate (degree, segments, λ) is a weighted least-squares fit on a B-spline basis, with categorical kernel weights per unique categorical cell (K); `cv.ls` uses hat values (second pass), and `nmulti = 2` restarts NOMAD. With fixed knots it is P with K state.
- `crs::crsiv.formula`, `crsivderiv.formula` — ORDER=I; CHUNK=H; state: all rows; notes: Landweber–Fridman iterations of `crs()` fits.
- `crs::predict.crs` — ORDER=E; CHUNK=M; state: none; notes: evaluates the fitted spline basis per row (knots fixed).
- **verdict**: holistic by default (quantile knots); with fixed knots it becomes a P target with K-per-categorical-cell state.

### bsts

- `bsts::bsts`, `dirm`, `mbsts`, `AddDynamicRegression` — ORDER=D; CHUNK=H; state: all rows; notes: state-space models whose Kalman filtering and smoothing run in time order; `dirm` and `mbsts` key rows by `timestamps`, which are sorted, so they are invariant only if timestamps are supplied.
- **verdict**: time-ordered by design; not a target.

### bain

- `bain::t_test.formula` (feeding `bain()`) — ORDER=D; CHUNK=K; state: per group n, Σy, Σy²; notes: **bug**. `rval$n` and `rval$v` are built in `unique(model_frame[[2]])` first-appearance order (R/t_test_wrapper.R:145-148), while `rval$estimate` (from `t.test`) and its names follow `levels(g)` (:154-156). When the data list the second level first, n and variance swap relative to the means. **Verified**: with groups of 10 and 30, `t_test(y ~ g)` returns n = (10, 30) on the data and (30, 10) on permuted rows, and `bain(., "groupa = 0")` gives BF.c 3.87 vs 7.49 (the equality hypothesis is unaffected). The paired branch pairs rows by within-group position (:140), which is inherently D.
- `bain::seBeta` — ORDER=I; CHUNK=P; state: covariance (A); `estimator = "ADF"` needs fourth-order moments of the centred data, either as a second pass (A) or as one pass of raw moments up to order 4 (precision trap); notes: standardized-coefficient SEs.
- **verdict**: report the `t_test.formula()` ordering bug upstream; after the fix it is single-pass K.

### MCMCglmm

- `MCMCglmm::MCMCglmm` — ORDER=R; CHUNK=H; state: all rows; notes: Gibbs sampling with per-row latent variables for non-Gaussian families, an n-sized state updated every iteration; Gaussian-only models need mixed-model-equation cross-products (A) per iteration, which is thousands of passes.
- `MCMCglmm::gelman.prior` — ORDER=I; CHUNK=P; state: pass 1 takes column means, sds and binary-column means (A); pass 2 takes X1'X1 and X1'X2 (A); notes: `scale(x, scale = sd(x)·2·(n-1)/n)` then `solve(t(X1) %*% X1, t(X1) %*% X2)` (R/gelman.prior.R:12-23).
- **verdict**: `gelman.prior()` is P(2) with A state; the sampler is not a target.

### abc

- `abc::abc` (rejection or local-linear regression; not in the scan list, whose candidates are plot/summary methods) — ORDER=I; CHUNK=H; state: all rows; notes: summary statistics are scaled by `mad()` (`normalise`, R/abc.R:131-135), and acceptance takes the `nacc`-th smallest distance (`sort(dist)[nacc]`, :152), then weighted `lsfit` on accepted rows (:224; A). Escape: a quantile sketch for the mad, plus a bounded top-k heap (size nacc) for acceptance, then an A pass. `method = "neuralnet"` is R.
- `abc::cv4abc` — ORDER=R; CHUNK=H; state: all rows; notes: random choice of validation simulations.
- **verdict**: rejection ABC is near-chunkable: a mad sketch plus a top-k heap, then an A pass for the regression adjustment.

### cvTools

- `cvTools::cvFit.function`, `cvTuning.function` (and `cvFolds`) — ORDER=R (D for `type = "consecutive"`/`"interleaved"`); CHUNK=P; state: per fold the fitted model's state; notes: `cvFolds` uses `sample(n)` (R/cvFolds.R:79) or positional folds (:61); deriving folds from a row key makes it I.
- `cvTools::predict.lts` — ORDER=E; CHUNK=M; state: none; notes: fixed coefficients.
- **verdict**: random or positional folds; hash fold ids from a row key to make CV order-invariant and single-pass for A-type fits.

### fwb

- `fwb::vcovFWB` (and `fwb()`) — ORDER=R; CHUNK=P; state: per replicate the statistic's state under row weights; notes: the default `wtype = "exp"` draws `rexp(n·R)` filled by row (R/fwb.R:465-469) and normalizes by `rowMeans`, a per-replicate scalar that can be applied at the end. `wtype = "poisson"` (R/fwb.R:479-481) is the classic streaming bootstrap with independent per-row weights. If those weights were seeded from a row key, all R replicates of an A-type statistic would fit in one pass (state R × statistic) and the result would become order-invariant.
- **verdict**: prior art for chunk-friendly resampling (`wtype = "poisson"`), but its RNG is positional.

### fst

- `fst::write_fst` — ORDER=E; CHUNK=M; state: none; notes: column store written in blocks.
- `fst::read_fst`, `fst::fst` / `as.data.frame.fst_table` — ORDER=E; CHUNK=M; state: none; notes: prior art: random row-range access `read_fst(from, to)` (R/fst.R:187) is a ready-made chunk reader for any target in this batch.
- **verdict**: prior art: a column store with row-range reads, the natural chunk source.

### future.apply

- `future.apply::future_by` (`.data.frame`, `.default`), `future_tapply` — ORDER=I; CHUNK=K; state: rows hash-partitioned by INDICES; notes: FUN is arbitrary, so each group must be complete (exact when chunks are partitioned by key); the output follows sorted factor levels. Prior art: futures chunk *elements* (groups) across workers (`future.chunk.size`, `future.scheduling`), not rows.
- **verdict**: keyed (group-complete) parallelism; prior art for chunking over groups, not rows.

### labdsv

- `labdsv::indval.default` — ORDER=R; CHUNK=K; state: per cluster × species the abundance sums and presence counts, plus cluster sizes; notes: Fortran `duleg` (R/indval.R:29); the permutation test with `numitr = 1000` reshuffles cluster labels, so R; the indicator values themselves are I.
- `labdsv::ccm` — ORDER=E; CHUNK=M; state: none; notes: compares row i of `model` with row i of `data` (R/ccm.R:18-26).
- **verdict**: `indval()` is single-pass K for the indicator values; the p-values need permutations.

### diversitree

- `diversitree::make.pgls` — ORDER=I; CHUNK=H; state: all rows; notes: tree-structured likelihood over all tips, with data matched by name.
- **verdict**: not a target.

### coneproj

- `coneproj::shapereg` — ORDER=I; CHUNK=H; state: all rows; notes: the edge matrix comes from the sorted distinct x (`makedelta(t, shape)`, R/coneproj.R:524), followed by the cone projection `coneB` on all rows. Without covariates the fit is constant within ties, so it reduces exactly to K over unique x with Σy and counts. `test = TRUE` simulates with `rnorm(n)` per row (`nloop`), so R.
- **verdict**: H in general; exact K reduction to unique x when there are no covariates.

### cobs

- `cobs::drqssbc2` — ORDER=I; CHUNK=H; state: all rows; notes: L1 (quantile) B-spline regression solved as a sparse LP over all rows; knots default to quantiles.
- **verdict**: not a target (LP over all rows).

### Amelia

- `Amelia::amelia` (not in the scan list) — ORDER=R; CHUNK=P; state: per EM iteration the sufficient statistics (sums and cross-products of observed and conditionally imputed values), grouped by missingness pattern (K); notes: each imputation first takes a nonparametric bootstrap with `runif(nrow(x))` indices (`bootx`, R/emb.r:80); with `lags`/`leads`, rows are sorted by time within cross-section (R/prep.r:244-258), which is keyed and therefore fine.
- **verdict**: EM per imputation is P with K-by-missingness-pattern state, but the bootstrap makes it R.

### copula

- `copula::empCopula` — ORDER=I (R for `ties.method = "random"`); CHUNK=A; state: for fixed evaluation points u, the counts of rows with X ≤ u; notes: the constructor only stores pseudo-observations (R/empCopula.R:167-182), which come from ranks (`pobs`, H) if computed from raw data; `smoothing = "beta"/"checkerboard"` needs ranks, so H.
- **verdict**: evaluation at fixed points is A; building pseudo-observations needs ranks (H).

### fields

- `fields::predict.Krig` — ORDER=E; CHUNK=M; state: the fitted object (coefficients and knots); notes: each new location needs a cross-covariance with all training knots, O(n_train) per row, while the `Krig()` fit itself is H.
- **verdict**: only kriging prediction is chunkable, over the new locations.

### fpc

- `fpc::cov.wml` — ORDER=I; CHUNK=A; state: Σw, Σw·x, Σw·xx' (Chan merge); notes: R/fpc.R:92-128; weights are normalized by Σw.
- **verdict**: `cov.wml()` is single-pass A.

### gmodels

- `gmodels::CrossTable` (not in the scan list; the scanned `fit.contrast` is plumbing on a fitted model) — ORDER=I; CHUNK=K; state: the two-way table; notes: chi-square, row/column proportions and McNemar follow from the table, and `fisher.test` runs on the table after the K reduction.
- **verdict**: `CrossTable()` is single-pass K.

### lawstat

- `lawstat::lorenz.curve` — ORDER=I; CHUNK=H; state: all rows; notes: needs values sorted with cumulative weighted shares; it reduces to K when the variable has few distinct values.
- **verdict**: H (sorted cumulative shares).

### aqp

All candidates operate on horizon tables grouped by profile id, so they are chunkable only when chunks never split a profile.

- `aqp::checkHzDepthLogic` — ORDER=D; CHUNK=K (profile-complete groups); state: all horizons per profile; notes: `hzDepthTests` flags `sort(top) != top` and `bottom[-n] != top[-1]` (R/checkHzDepthLogic.R:191,205), so row order within a profile is semantic and permuted horizons are reported invalid.
- `aqp::collapseHz`, `fillHzGaps`, `hz_dissolve`, `accumulateDepths` — ORDER=I (after sorting by depth within profile); CHUNK=K; state: all horizons per profile; notes: adjacency within profile.
- `aqp::aggregateColor`, `thicknessOf`, `get.ml.hz` — ORDER=I; CHUNK=K; state: per group sums, weights and counts; notes: per group or profile sums and counts.
- `aqp::brierScore` — ORDER=I; CHUNK=A; state: Σ squared error and n; notes: mean of row-local scores.
- `aqp::hz_segment` — ORDER=E; CHUNK=M; state: none; notes: clips each horizon to fixed intervals.
- `aqp::L1_profiles` — ORDER=I; CHUNK=H; state: all horizons per group; notes: L1 (geometric) medians.
- **verdict**: group-complete per profile: chunk by profile id; `checkHzDepthLogic()` treats within-profile row order as semantic.

### BMisc

- `BMisc::make_balanced_panel`, `set_balanced_panel` — ORDER=S; CHUNK=P; state: pass 1 takes the number of periods (K over `tname`) and rows per id (K), pass 2 filters (M); notes: `dt[, if (.N == nt) .SD, by = idname]` (R/BMisc.R:32-33) returns rows grouped by first appearance of the id.
- `BMisc::get_principal_components` — ORDER=S; CHUNK=P; state: a K pivot to wide (id × period), then the period × period cross-product over ids (A), then scores per id (M); notes: `dcast` + `prcomp(center = FALSE)` (R/BMisc.R:1807-1814).
- `BMisc::sort_panel` — ORDER=S; CHUNK=H; state: all rows (external sort); notes: orders rows by id and time.
- **verdict**: `make_balanced_panel()` is P(2) with K state per id; the outputs keep first-appearance id grouping (S).

### BBmisc

- `BBmisc::normalize.data.frame` — ORDER=E; CHUNK=P; state: per column mean and sd, or min and max (A), then M; `method = "robust"` needs median and MAD, so H; notes: column-wise normalization.
- `BBmisc::convertDataFrameCols`, `convertRowsToList` — ORDER=E; CHUNK=M; state: none; notes: column type conversion.
- **verdict**: `normalize()` is P(2) (A then M).

### chk

- `chk::check_key` — ORDER=I; CHUNK=K; state: set of seen keys (uniqueness); notes: uniqueness check on key columns.
- `chk::vld_join` — ORDER=I; CHUNK=P; state: pass 1 collects the key set of `y` (K), pass 2 checks each row of `x` (M); notes: `merge()` with `unique(y[by])`.
- **verdict**: key checks are K.

### dagitty

- `dagitty::localTests` (`type = "cis"`) — ORDER=I; CHUNK=A; state: the sample covariance and n; notes: **already accepts sufficient statistics** via `sample.cov`/`sample.nobs` (R/dagitty.R:1751,1769). `"cis.chisq"` needs K tables, `"cis.loess"` is H, and `R =` bootstraps (R).
- **verdict**: `localTests(type = "cis")` already accepts sufficient statistics (`sample.cov`, `sample.nobs`), the exact A interface.

### extraDistr

- `extraDistr::dbvnorm`, `dbvpois`, `ddirichlet`, `ddirmnom` — ORDER=E; CHUNK=M; state: none; notes: row-wise densities of matrix or data frame input.
- **verdict**: row-wise densities, M.

### laGP

- `laGP::aGP.parallel` — ORDER=E; CHUNK=M; state: none; notes: prior art, since it already splits the prediction locations `XX` into chunks (`split(1:n, rep(1:chunks, length = n))`, R/parallel.R:81), while the training design X stays in memory (local neighbourhood search, H in X).
- `laGP::blhs` — ORDER=R; CHUNK=H; state: all rows; notes: bootstrapped block Latin hypercube subsample.
- **verdict**: prior art for chunking over prediction rows (`aGP.parallel()`).

### animation

- `animation::cv.nfeaturesLDA` — ORDER=R; CHUNK=P; state: per fold the class means and pooled covariance; notes: random CV folds over LDA fits; each fit is A (class means and pooled covariance).
- **verdict**: not a target (teaching demo).

### hdf5r

- `hdf5r::flatten_df` — ORDER=E; CHUNK=M; state: none; notes: flattens nested columns row by row; prior art: HDF5 chunked datasets with hyperslab reads give row-range access like `fst`.
- **verdict**: prior art (HDF5 hyperslab chunk reads); no statistical consumers.

### Skipped

formatters, knitr, gtable, jagsUI, lotri, cols4all, forestplot, algebraic.mle, GpGp, gdalraster (candidates were all print, format, or coercion plumbing).

<!-- source: findings/cran_depth3_b.md -->
## Part: CRAN depth 3, batch B (MCMCpack .. xlsx)

Sources read from `src/<pkg>/R`.
Empirical checks (fixed seed, row permutation, `all.equal()`) were run for speedglm, survey and multgee;
scripts are in `scratchpad/scripts_b/`.

### speedglm

- `speedglm::shglm` — ORDER=I; CHUNK=P; state: per IRLS pass, X'WX (keyed by column name so that columns for factor levels first seen in later chunks can be added), X'Wz, deviance, RSS, AIC terms; pass 1 also accumulates n, Σw, Σwy and the zero-weight count, pass 2 the null deviance (it needs Σwy/Σw from pass 1); notes: **already chunk-capable (prior art)**. `datafun(reset=TRUE/FALSE)` is a user-supplied chunk reader, called again for every IRLS iteration (speedglm.r:215-216, :329-345). Rank and pivot are fixed from X'WX after pass 1 (:330-334). Chunk X'WX blocks are merged by row and column name (:318-325). Factor levels are the running union, `sort()`ed (:357-363), so the column order is deterministic. `start`, `mustart` and `etastart` are not supported (:212-214). Verified: same coefficients as `speedglm()`, and identical after a row permutation with chunk size 700.
- `speedglm::speedlm`, `speedglm::speedlm.fit`/`speedlm.wfit` — ORDER=I; CHUNK=A; state: X'X (or √w-weighted), X'y, y'y, colSums(X), Σw, Σlog w, n, zero-weight count; notes: the in-memory fit is already sufficient-statistic based (speedlm.R:14-19, :98-112). `set.default=list(row.chunk=)` only blocks the in-memory `crossprod` (`cp()`, miscellanea.r:45ff). It is not out-of-core. `model.frame(drop.unused.levels=TRUE)` (speedlm.R:188) makes the X columns chunk-dependent unless levels are declared.
- `speedglm::updateWithMoreData` / `update.speedlm(add=TRUE)` — ORDER=D (trap); CHUNK=A; state: the same sufficient statistics, added to the previous fit; notes: **prior art, but buggy for factors**. The merged level set is `c(old levels missing from the new chunk, new chunk levels)`, with no sort (speedlm.R:312). When the rank is full, the new X'X and X'y are then added *positionally* (:343, :345, :377, :379). A later chunk that lacks a middle level (e.g. `b` of `a,b,c`) permutes the dummy columns, and the coefficients are silently wrong: in the test, `fb` was 0.315 against the true 0.995. A chunk that lacks the first level is harmless. So the result depends on how rows are split into chunks. Workaround: pass factors with fixed full levels, or `all.levels=TRUE`. There is also a typo: `set$rowchunk` (:342, :350, :376, :384) is always NULL, which ignores `row.chunk`.
- `speedglm::speedglm` / `speedglm.wfit` — ORDER=I; CHUNK=P; state: per IRLS iteration X'WX, X'Wz, deviance; notes: it holds X in memory and loops IRLS over it (speedglm.r:109-153). `shglm` is the out-of-core variant. Verified invariant under row permutation.
- `speedglm::predict.speedlm`/`predict.speedglm` — ORDER=E; CHUNK=M; state: none; notes: it uses the stored `xlevels` (predict.r:43).
- `speedglm::drop1.speedlm`/`add1.speedlm`/`*.speedglm` — ORDER=I; CHUNK=A (lm) or P (glm); state: drop1 for lm could subset the stored X'X, but the code refits from `object$model` or `data` (summary.speedlm.R:199-229); notes: it needs `model=TRUE`, i.e. all rows.
- **verdict**: `shglm` is real prior art for a multi-pass IRLS over a `datafun` reader. `updateWithMoreData` is prior art for single-pass lm updating, but it needs a fix that aligns X'X by column name (as `shglm` does) before it is safe.

### survey

- `survey::svytotal.survey.design2`, `svymean.survey.design2`, `svyratio.survey.design2` — ORDER=I; CHUNK=K; state: Σw·x (and Σw) for the estimate (multistage.R:789, :865), plus the per-(stratum, PSU) totals of w·x and w used by the variance; notes: the variance `svyrecvar` → `onestrat` does `rowsum(x, cluster)` per stratum, then centres within the stratum and takes a crossprod (multistage.R:256-310). So the state is keyed by (stratum, PSU) for the first stage, and by the full stage path when later-stage fpc is given (recursion at :400ff). For `svymean`, the influence x−mean depends on the mean (:866). Because it is linear, storing per-PSU Σw·x and Σw gives a single pass. Post-stratification and raking also centre within post-strata (:346-375): keyed per post-stratum (raking is a fixed 10-iteration loop, :362). Factor columns get their levels from `model.matrix(~0+f)`, so the level set is global. Verified invariant under row permutation for a two-stage `apiclus2` design (estimates and vcov).
- `survey::svydesign` (pps="brewer") — ORDER=D (bug); CHUNK=K; state: as above; notes: `onestrat` multiplies `scale[!duplicated(cluster)]`, which is in first-appearance order (multistage.R:274), against `rowsum(x, cluster)`, which is sorted by cluster id (:276). When `scale` varies by PSU (Brewer PPS: per-unit fpc), the variance depends on row order. Test: 211891 vs 214730 for the same data permuted; the value is 227616 when rows are sorted by PSU id or when `ids=~1`.
- `survey::svydesign.default` — ORDER=S; CHUNK=K; state: design structures built globally (ids made nested via `interaction`, `as.fpc` checks per stratum, `table(ids, strata)` nesting check, a "one PSU" check); notes: the design object holds n-length vectors (cluster, strata, prob, fpc) aligned positionally with `variables`. A chunked rewrite must stream the design columns together with the analysis columns. `rescale` in `svyglm` uses `mean(1/prob)`, an A pre-pass (survey.R:1145).
- `survey::svyglm.survey.design` — ORDER=I; CHUNK=P; state: per IRLS pass X'WX and X'Wz; one final pass of per-(stratum, PSU) sums of estfun (= x·w·working residual) for `svy.varcoef` (survey.R:1240ff); notes: it is ordinary `glm()` with weights plus a K pass for the sandwich.
- `survey::svytotal.svyrep.design`/`svymean.svyrep.design` — ORDER=I; CHUNK=A; state: an R×p matrix of replicate totals Σ repw_r·pw·x (surveyrep.R:926, :1046); notes: A per replicate column, and the variance `svrVar` works only on the R replicate estimates (:733-751). `svyglm`/`svycoxph` on replicate designs refit per replicate: R+1 P-fits.
- `survey::svyquantile.survey.design`/`.svyrep.design`, `oldsvyquantile.*` — ORDER=I; CHUNK=H; state: a weighted ECDF of x (`qrule(xi, w, p)`, newsvyquantile.R:46); the Woodruff CI then calls `svymean` of I(x≤q̂), a K pass; notes: escape hatches are a weighted quantile sketch, or K when x has few distinct values.
- `survey::svytable.survey.design` — ORDER=I; CHUNK=K; state: `xtabs` of weights by cells (survey.R:879-920), optionally by stratum.
- `survey::svysmooth`, `svycdf`, `svykm`, `svyranktest`, `svycoxph` — ORDER=I; CHUNK=H; notes: local smoothing, ECDF, sorted event times and ranks. `svykm` degrades to K keyed by unique times.
- `survey::svydesign.character` (DBI-backed `DBIsvydesign`) — ORDER=I; CHUNK=M (columns only); state: only the design columns are loaded at creation (DBI.R:18-29), and each analysis call `getvars()` fetches just the formula's variables (dbiupdate.R:78-81); notes: **prior art for column-wise out-of-core**, not row chunking. Every query is `select ... from table` with no ORDER BY, and the design vectors and an R-side `subset` index (dbiupdate.R:84) are aligned positionally. This relies on the database returning rows in the same order every time.
- **verdict**: `svytotal`/`svymean`/`svyratio`/`svyby` are exact single-pass K computations (keyed by stratum×PSU, by stage path, and by domain for `svyby`). `svyglm` is P plus one K pass, and replicate-weight estimators are A. Existing prior art is the DBI design, which is column-lazy. The Brewer PPS variance bug above is real and order-dependent.

### ranger

- `ranger::ranger` — ORDER=R; CHUNK=H; state: none bounded (CART growth over all rows, with bootstrap or subsample in-bag counts per row); notes: with `seed=` the in-bag draws are indexed by row position (ranger.R:553-554, `inbag=` lists per-row counts), so permuting rows changes the forest. `respect.unordered.factors="order"` reorders levels by the mean response per level, a K pre-pass (ranger.R:438-487). Escape hatches: pre-binned histogram splits (LightGBM-style), or subagging with one tree per chunk.
- `ranger::predict.ranger`/`predict.ranger.forest` — ORDER=E; CHUNK=M; state: none; notes: chunkable over prediction rows. `type="quantiles"` uses terminal-node data stored in the forest, so it is still row-local.
- `ranger::importance_pvalues` — ORDER=R; CHUNK=H; notes: the Altmann method refits on permuted responses. The Janitza method uses the fitted importances only.
- **verdict**: only `predict` is chunkable. Training is H, and R under a seed.

### Rfast

- `Rfast::colmeans.data.frame`, `Rfast::colVars.data.frame` — ORDER=I; CHUNK=A; state: per-column n, Σx and Σx² (or Welford); notes: these are thin `.Call` wrappers (mean.R:12, Var.R:17). The rest of the matrix API is similar: `colsums` is A, while `colMedians`, `colMads`, `colRanks` and `Sort` are H.
- `Rfast::colanovas` — ORDER=I; CHUNK=K; state: per column, per group code, n_g and Σy_g, plus Σy and Σy²; notes: `k` is `colrange(x, cont=FALSE)`, the number of distinct codes (many_regression_models_correlations.R:395-405).
- **verdict**: `colanovas` (K) and the `col*` moments (A); everything is matrix-based.

### metafor

- `metafor::rma.mh`, `rma.peto` — ORDER=I; CHUNK=A; state: Mantel–Haenszel R=Σ a·d/N and S=Σ b·c/N, the RGB variance sums P, Q and R terms, CMH sums (rma.mh.r:528-565); notes: rows are studies. Breslow–Day needs the MH estimate first, giving 2 passes.
- `metafor::rma.uni` — ORDER=I; CHUNK=P; state: per tau² iteration, X'WX, X'Wy, y'Wy, Σw, tr(P) and tr(PP) via X'W²X and X'W³X; notes: DL, HE and HS are one A pass (rma.uni.r:1501-1511). REML and ML use Fisher scoring (:1815-1817), PM uses root finding, and each is P with A per iteration. The implementation builds k×k W and P matrices, so it is O(k²) memory. `test="permutation"`/`permutest` → R.
- `metafor::escalc` — ORDER=E; CHUNK=M (P for some options); state: none; notes: it is row-local except `to="if0all"`, which adds the continuity correction to all studies if any has a zero cell, a global A pre-pass (escalc.r:283-286). `vtype="AV"` uses sample-size-weighted averages over all studies, another A pre-pass (escalc.r:316-323, :1028, :1594).
- `metafor::aggregate.escalc`, `vcalc`, `rcalc` — ORDER=S; CHUNK=K; state: per-cluster blocks; notes: clusters are taken in `unique(cluster)` first-appearance order (aggregate.escalc.r:41). CAR uses the explicit `time` variable (:158-162).
- `metafor::rma.mv`, `rma.glmm` — ORDER=I; CHUNK=P; state: per optimizer step, block-diagonal sums keyed by random-effect cluster (rma.mv), or a GLMM via lme4/GLMMadaptive; notes: in practice H.
- `metafor::fsn` — ORDER=I; CHUNK=A; state: Σz (Rosenthal), and sums of yi and wi.
- `metafor::ranktest`, `trimfill`, `leave1out` — ORDER=I; CHUNK=H; notes: ranks, or k refits (leave1out could downdate A statistics).
- `metafor::tes`, `regtest` — ORDER=I; CHUNK=P; notes: an estimate pass, then a sum of per-study powers or an Egger fit.
- `metafor::to.long`, `to.table`, `to.wide`, `conv.*` — ORDER=E; CHUNK=M; notes: row reshaping or conversion. `to.wide` pairs rows within a study (K).
- `metafor::cumul.*` — ORDER=D (by design); notes: a cumulative meta-analysis in row or `order=` order.
- **verdict**: `rma.mh`/`rma.peto` and DL `rma.uni` are A. REML `rma.uni` is P with A per iteration. Practical value is low, since k (studies) is small.

### rrcov

- `rrcov::CovClassic`, `PcaClassic.*`, `T2.test.formula` (classical), `Wilks.test.*(method="c")`, `LdaClassic.formula`, `QdaClassic.formula` — ORDER=I; CHUNK=A (K by class for LDA/QDA/Wilks); state: n, Σx, Σxx' (per class); notes: CovClassic.R:9-33. The PCA scores are a later M pass.
- `rrcov::CovMcd`(robustbase)/`CovMve`/`CovSest`/`CovMest`/`CovMMest`/`CovSde`, `PcaHubert.default`, `Linda.formula`, `Wilks.test(method="mcd")` — ORDER=R; CHUNK=H; state: none bounded; notes: random elemental subsets or random directions are indexed by row. Wilks "mcd" also calibrates by simulation (Wilks.test.R:130, :222-226). Escape hatch: deterministic MCD or OGK on a sample, then an A pass for the reweighting step.
- `rrcov::CovOgk`, `CovMrcd`, `PcaGrid`/`PcaProj`/`PcaLocantore`, `LdaPP` — ORDER=I; CHUNK=H; notes: deterministic, but built on robust scales (MAD, tau), spatial medians and projection-pursuit grids.
- **verdict**: only the classical variants are A or K. All robust estimators are H, and R when subsample-based.

### MCMCpack

- `MCMCpack::MCMCregress` — ORDER=I; CHUNK=A (in principle); state: X'X, X'y, y'y; notes: Y and X are passed to C++ every iteration (MCMCregress.R:187-241). With the conjugate normal/IG prior, both Gibbs steps depend on the data only through these sufficient statistics, so one A pass plus MCMC on p×p state is exact. The current code uses full X per draw. `coef_start` fits an lm (A).
- `MCMCpack::MCMClogit`, `MCMCpoisson`, `MCMCnegbin`, `MCMCmnl` — ORDER=I; CHUNK=P; state: per Metropolis step, Σ row log-likelihoods; notes: mcmc+burnin passes (10⁴ to 10⁵), so this is not practical out-of-core.
- `MCMCpack::MCMCprobit`, `MCMCoprobit`, `MCMCtobit`, `MCMCquantreg`, `SSVSquantreg`, `MCMCfactanal`/`MCMCordfactanal`/`MCMCmixfactanal` — ORDER=I; CHUNK=P; state: per-row latent variables (z_i, factor scores), O(n) state; notes: data augmentation, so every pass must also read and write per-row state.
- `MCMCpack::MCMChregress`, `MCMChlogit`, `MCMChpoisson` — ORDER=I; CHUNK=P; state: per-group random effects, K keyed by group per sweep.
- `MCMCpack::MCMC*Change`, `HDPHMM*`, `HDPHSMMnegbin` — ORDER=D (by design); notes: change-point and HMM models over row order.
- **verdict**: only `MCMCregress` has an exact single-pass reduction. The other samplers are P with thousands of passes.

### multcomp

- `multcomp::glht` with `mcp()` (`mcp2matrix`), `modelparm.*` — ORDER=I; CHUNK=K; state: level counts `table(mf[[nm]])` for the contrast matrix, and covariate means for `covariate_average` (mcp.R:110, :364); notes: it materialises `model.matrix(model)` and `model.frame(model)` only for contrasts and assign (mcp.R:47-56). Otherwise it works on coef/vcov alone (helpers.R:105ff). It could use stored `xlevels` and counts.
- **verdict**: no real data pass; a K pass for level counts is enough.

### vcd

- `vcd::structable.formula`, `mosaic.formula`/`mosaic.default`, `assoc.formula`, `sieve.formula`, `tile.formula`, `doubledecker.formula`, `cotabplot.formula`, `agreementplot.formula`, `loddsratio.formula`/`lodds.formula` — ORDER=I; CHUNK=K; state: a contingency table via `table(mf)`/`xtabs` (structable.R:45-57, loddsratio.R:51-73); notes: the level sets come from factor levels, so declare them up front.
- `vcd::distplot`, `goodfit`, `assocstats` — ORDER=I; CHUNK=K; state: a frequency table (distplot.R:13).
- `vcd::cd_plot.formula` — ORDER=I; CHUNK=H; notes: `density()` with a data-driven bandwidth (cd_plot.R:51-63). Escape hatch: binned KDE on a fixed grid (A).
- `vcd::spine.formula` — ORDER=I; CHUNK=P; notes: a breaks pre-pass, then K counts.
- **verdict**: everything reduces to a K table pass. `structable.formula` and `mosaic.formula` are the obvious targets.

### reshape

- `reshape::cast`/`recast`/`reshape1` — ORDER=I (S when keys repeat and FUN is order-sensitive); CHUNK=K; state: per output cell, a mergeable aggregate (length/sum/mean); notes: aggregation is detected via `unique()` over keys (cast.r:184). `condense` uses a stable `sort_df`, then `tapply(value, index, fun)` (condense.r:22-26). Order-sensitive `fun.aggregate` (e.g. `function(x) x[1]`) → D. Non-decomposable FUN (median) → H per cell.
- `reshape::melt.data.frame`/`melt.cast_df` — ORDER=E; CHUNK=M; notes: output rows are grouped by variable block. The `variable` levels follow column order, not row order (melt.r:94).
- `reshape::sparseby` — ORDER=I; CHUNK=K; notes: sorts by keys (stable `order`) and applies FUN per group. Invariant only if FUN is.
- **verdict**: `cast` is K with decomposable FUN; `melt` is M.

### strucchange

- `strucchange::efp`, `Fstats`, `breakpoints.formula`, `mefp`/`monitor`, `recresid.*` — ORDER=D (by design); notes: CUSUM and MOSUM processes, recursive residuals and breakpoints are all over row order.
- `strucchange::gefp`/`sctest.default(order.by=)` — ORDER=D (trap on ties); CHUNK=H; notes: rows are sorted by `order(z)` (gefp.R:31-35), and ties keep input order, so sup-type functionals (`maxBB`, `supLM`) change under within-tie permutation. With a categorical `order.by` and `catL2BB`/`ordL2BB` functionals, only cumulative scores at category boundaries matter (zzz.R:240-249). That is ORDER=I and CHUNK=P: a model-fit pass, then K per-level sums of `estfun`.
- **verdict**: not a chunking target. `sctest(order.by=<factor>, functional=catL2BB)` is the only order-free path (per-level score sums).

### penalized

- `penalized::penalized` — ORDER=I; CHUNK=P; state: a pre-pass of column variances for standardisation (checkinput.R:264-266); then per Newton or gradient step X'r and X'WX restricted to the active set (core.R:25-43, :133-151); notes: when p > n, `.cvl` reparametrises into the n-dimensional row space via `.makeP` and `tcrossprod` (core.R:215-229), which is H. The Cox model needs risk sets (sorted times), also H.
- `penalized::cvl`, `optL1`, `optL2`, `profL1`, `profL2` — ORDER=R; CHUNK=P; notes: folds are `sample(n) %% fold + 1` (core.R:367), indexed by row. They are fixed only if `fold=` is given as a vector.
- **verdict**: `penalized` (L2, p ≤ n) is P with A per pass. CV is R.

### sommer

- `sommer::mmes`/`mmer` — ORDER=I; CHUNK=P (A in principle); state: with `henderson=TRUE` and iid residuals, the mixed-model-equation blocks X'X, X'Z, Z'Z, X'y, Z'y and y'y do not change across AI-REML iterations, so one pass suffices and iterations run on (p+q)² state; notes: relationship and kinship matrices (G, A) are supplied, not computed from rows. The direct formulation (`henderson=FALSE`, mmes.R:10, :688) and spatial or AR residual structures need n×n V, which is H.
- `sommer::GWAS` — ORDER=I; CHUNK=H; notes: per-marker tests using the fitted V⁻¹ (n×n).
- `sommer::predict.mmes`, `vpredict.mmes`, `wald_mmes` — ORDER=E or no data; notes: post-fit.
- **verdict**: the MME (henderson) path could be single-pass A for iid residuals; in practice sommer is in-memory.

### rstpm2

- `rstpm2::stpm2`/`gsm`/`pstpm2` — ORDER=I; CHUNK=P; state: a knot pre-pass at quantiles of log event time among uncensored rows (pm2-3.R:41), which is H and could use a sketch; initial values from `coxph` + `survfit` (pm2-3.R:940-960), which is H (sorted times); then optim over the sum of row log-likelihoods in C++ (`.Call("model_output")`, pm2-3.R:1206ff), with A per evaluation (likelihood + gradient); notes: `pstpm2` uses mgcv `s()` bases (data-dependent eigenbasis). Cluster and frailty terms are K keyed by cluster (`applyTapplySum`, pm2-3.R:402-408).
- `rstpm2::aft` — ORDER=I; CHUNK=P; notes: same structure.
- `rstpm2::predict` methods — ORDER=E; CHUNK=M.
- **verdict**: `stpm2` = quantile pre-pass + P with an A gradient per optimizer step; feasible, but needs a replacement for the coxph initialisation.

### semTools

- `semTools::mardiaSkew` — ORDER=I; CHUNK=P (2 passes); state: pass 1 mean and covariance, pass 2 third central moments (p³ tensor); notes: implemented as an O(n²) double loop over pairs of rows (dataDiagnosis.R:187-199). b1 = Σ S^{il}S^{jm}S^{kn} m_ijk m_lmn is exactly computable from the third-moment tensor. `mardiaKurtosis` is 2 passes A. `skew`/`kurtosis` are A (k-statistics from power sums).
- `semTools::htmt`, `efa.ekc` — ORDER=I; CHUNK=A (K for ordinal); state: a covariance or correlation matrix via `lavCor` (htmt.R:102), or polychoric bivariate tables per pair (K); notes: the result is a function of R only. It already accepts `sample.cov=` (prior art for passing sufficient statistics).
- `semTools::auxiliary`/`cfa.auxiliary`/`sem.auxiliary` etc., `fmi` — ORDER=I; CHUNK=K; state: lavaan FIML needs sufficient statistics per missingness pattern (means and cross-products keyed by pattern); notes: complete-data ML needs only the mean vector and covariance (A).
- `semTools::bsBootMiss`, `splitSample`, `parcelAllocation`, `PAVranking`, `poolMAlloc`, `quark` — ORDER=R; CHUNK=H; notes: bootstrap, random row splits, random item-to-parcel allocations (columns) with refits, and MI via `mice`.
- `semTools::monteCarloCI`, `AVE`, `compRelSEM` — no data pass (fitted model only).
- **verdict**: `mardiaSkew` (O(n²) → p³ two-pass) is the standout rewrite. `htmt` and `efa.ekc` are A.

### quanteda

- `quanteda::dfm` (tokens → dfm) — ORDER=S; CHUNK=K; state: per document a sparse row (E); the global feature index is the union of types; notes: types are numbered in first-appearance order (`unlist_character(unique=TRUE)` + `union`, tokens.R:648-651), so dfm column order follows row order. Chunk-wise dfms can be `rbind`ed with feature matching.
- `quanteda::corpus.data.frame`, `tokens`, `corpus_reshape` — ORDER=E; CHUNK=M; notes: one document per row. Duplicate docnames are made unique in row order (`make_docvars(unique=TRUE)`), which is S.
- `quanteda::dfm_trim` (min/max termfreq or docfreq), `dfm_tfidf`, `dfm_group` — ORDER=I; CHUNK=P/K; notes: a K pre-pass (term or doc frequency per feature), then an M filter or weight; `dfm_group` is K keyed by group.
- `quanteda::bootstrap_dfm`, `corpus_sample`, `dfm_sample` — ORDER=R.
- **verdict**: dfm construction is chunkable (E rows, K feature dictionary). Only the feature column order is presentation-dependent.

### vctrs

- `vctrs::vec_count` — ORDER=S (I with `sort="key"`); CHUNK=K; state: a key → count dictionary; notes: the default `sort="count"` breaks ties by first location (dictionary.R:57-65).
- `vctrs::vec_unique`, `vec_group_id`/`vec_group_loc`, `vec_duplicate_*` — ORDER=S; CHUNK=K; notes: first-appearance labels. `vec_duplicate_detect` is D-like (first occurrence kept).
- `vctrs::vec_order`/`vec_sort` — ORDER=I; CHUNK=H.
- `vctrs::vec_ptype2`/`vec_cast` (data.frame methods), `vec_ptype_common` — ORDER=I; CHUNK=A; state: a common prototype; notes: the type unification is a mergeable fold over chunks (schema only).
- **verdict**: infrastructure. Its dictionary primitives are the K building blocks.

### sjlabelled

- `sjlabelled::drop_labels`, `fill_labels`, `zap_unlabelled`, `as_factor`, `as_label(drop.levels=TRUE)` — ORDER=I; CHUNK=P (K pre-pass); state: the set of observed values per column; notes: `table(x)` (drop_labels.R:33), `unique(x)` (zap_labels.R:218), sorted `factor()` levels (as_factor.R:139). After the pre-pass the transform is M.
- `sjlabelled::set_na`, `zap_labels`, `zap_na_tags`, `remove_labels`, `as_numeric`, `as_character`, `unlabel`, `set_labels`/`set_label`/`add_labels`, getters — ORDER=E; CHUNK=M; notes: metadata or value recoding only.
- **verdict**: M, plus a distinct-value K pre-pass where labels must match observed values.

### prospectr

- `prospectr::standardNormalVariate`, `savitzkyGolay`, `gapDer`, `movav`, `detrend`, `continuumRemoval`, `baseline`, `binning`, `resample`/`resample2`, `spliceCorrection` — ORDER=E; CHUNK=M; state: none; notes: each spectrum (row) is transformed on its own (SNV uses `rowMeans`, standardNormalVariate.R:58). Order matters within a row (wavelength axis), not across rows.
- `prospectr::blockScale`, `blockNorm` — ORDER=I; CHUNK=P (2 passes); state: a global ΣX² or total variance, then an M rescale; notes: blockNorm.R:44-53. The bisection on the scale factor works on a scalar of the global sum, so one A pass is enough.
- `prospectr::kenStone`, `duplex`, `puchwein`, `shenkWest`, `honigs` — ORDER=I (D on ties); CHUNK=H; notes: PCA (A) then pairwise or Mahalanobis distances and max-min selection (kenstone.R:150ff). `which.max` ties resolve by row index.
- `prospectr::naes` — ORDER=R; CHUNK=P; notes: k-means with random starts.
- **verdict**: the preprocessing functions are all M. The sample-selection algorithms are H.

### metRology

- `metRology::mandel.kh.data.frame` — ORDER=I (S for group labels); CHUNK=K; state: per lab (group), n, Σx and Σx²; then h and k across lab means and SDs (mandel.r:157-185); notes: with `g` missing, rows are labs and the output follows row order (mandel.r:140-148). `method="robust"` uses `algA` (median/MAD start, mandel.r:175 → algAS.r), which is H over labs.
- `metRology::algA`/`algS`, `mpaule`, `REML` loc estimators — ORDER=I; CHUNK=H/P; notes: robust location starts from median and MAD (algAS.r:7-8).
- `metRology::uncert*`, `uncertMC` — no row data (uncertainty budgets, Monte Carlo).
- **verdict**: `mandel.kh` is K keyed by lab.

### rioja

- `rioja::WA.fit` (`WA`) — ORDER=I; CHUNK=P (2–3 passes); state: pass 1 per taxon Σy and Σy·x (WA.r:32-34); pass 2 per row x̂ (M) plus deshrinking-regression sums (5 scalars, :43-50), and, for `tolDW`, per taxon Σy(x−u)² and Hill's N2 (:61-65); pass 3 tolerance-weighted x̂ and its deshrinking sums (:74-86); notes: `mono=TRUE` uses a monotone smoother (H). `crossval`/bootstrap → R.
- `rioja::MAT`, `LWR` — ORDER=I; CHUNK=H; notes: nearest-neighbour analogues; chunkable over prediction rows only.
- `rioja::WAPLS`, `MLRC`, `IKFA` — ORDER=I; CHUNK=P; notes: iterative per-component or per-taxon fits.
- **verdict**: `WA` is an exact 2–3-pass A computation.

### qmap

- `qmap::fitQmapQUANT`, `fitQmapRQUANT`, `fitQmapSSPLIN`, `fitQmapPTF` (`.data.frame` methods per column) — ORDER=I; CHUNK=H; state: empirical quantiles of obs and mod, each separately (fitQmapQUANT.R:14-21, :42); notes: the wet-day threshold is derived from sorted values. Escape hatch: a quantile sketch on a `qstep` grid. obs and mod need not be row-paired. `nboot` → R.
- `qmap::fitQmapDIST` — ORDER=I; CHUNK=P; notes: Bernoulli-gamma etc. MLE, with A per optimizer step.
- `qmap::doQmap*` (`.data.frame` methods) — ORDER=E; CHUNK=M; notes: applies the fitted transfer function per value.
- **verdict**: fitting is H (sketchable). Applying (`doQmap`) is M.

### TraMineR

- `TraMineR::seqdef`, `seqformat` (STS ↔ SPS) — ORDER=E; CHUNK=P (alphabet pre-pass) then M; notes: rows are sequences, and order matters within a row only. The alphabet comes from `seqstatl` over all rows (seqdef.R:59), a K pre-pass. SPELL/TSE → STS groups rows by id and orders them by time, K keyed by id.
- `TraMineR::seqtab` — ORDER=I; CHUNK=K; state: weighted counts per distinct sequence; notes: `tapply` then `sort(decreasing=TRUE)` (seqtab.R:44-45). Ties stay in key order.
- `TraMineR::dissmfacw`, `disstree`, `seqtree` — ORDER=R; CHUNK=H; notes: work on a pairwise distance matrix and use permutation tests.
- **verdict**: `seqdef` is M after an alphabet pre-pass, `seqtab` is K, and the distance-based analyses are H.

### tsbox

- `tsbox::ts_dts.data.frame`, `ts_data.frame`, `ts_summary` — ORDER=D (by design); notes: time series. Rows are re-sorted by time, but summaries use start, end and frequency detection. Not a target.

### mvoutlier

- `mvoutlier::aq.plot`, `dd.plot`, `uni.plot`, `mvoutlier.CoDa`, `symbol.plot`, `color.plot` — ORDER=R; CHUNK=H; notes: built on `covMcd` (random subsets) and adjusted quantiles. Plots.
- **verdict**: none.

### Rmixmod

- `Rmixmod::mixmodCluster`/`mixmodLearn` (C++) — ORDER=R; CHUNK=P; state: per EM pass, per component Σt_ik, Σt_ik x and Σt_ik xx' (or modality counts for qualitative data); notes: random or smallEM initialisation.
- `Rmixmod::oldmixmodPredict` — ORDER=E; CHUNK=M.
- **verdict**: EM is P with fixed-size A per pass; prediction is M.

### picante

- `picante::sample2matrix` — ORDER=I; CHUNK=K; state: `tapply(abund, list(plot, id), sum)` (phylocom.R:11).
- `picante::match.phylo.data` — ORDER=E; CHUNK=M.
- `picante::multiPhylosignal`/`phylosignal` — ORDER=I; CHUNK=H; notes: rows are species (tips); tip-shuffle randomisations.
- **verdict**: `sample2matrix` is K.

### multgee

- `multgee::nomLORgee`, `ordLORgee` — ORDER=D (trap when `repeated` is missing), otherwise I; CHUNK=P; state: local odds ratios from marginal counts keyed by (time pair, category pair), then per GEE iteration cluster-level score and information contributions (K keyed by id); notes: without `repeated`, the occasion index is assigned by within-cluster row order (nomLORgee.R:151-154). Verified: `ordLORgee(arthritis)` coefficients change after a row permutation, but not when `repeated=time` is given. With `repeated`, rows are sorted by `order(id, repeated)` (:261).
- **verdict**: always pass `repeated=`. Then it is P with a K-by-cluster state.

### tweedie

- `tweedie::tweedie.profile`/`tweedie_profile` — ORDER=I; CHUNK=P; state: for each grid value of p, an IRLS `glm.fit` (A per pass), then `optimize` over φ of Σ log dtweedie (tweedie_profile.R:290-301, :348, :410); notes: nested P with many passes.

### sn

- `sn::selm` — ORDER=I; CHUNK=P; state: per `nlminb` step, the summed log-likelihood and gradient (A); notes: starting values from lm/moments (A). `selm.fit` (sn-funct.R:2008).
- `sn::predict.selm` — ORDER=E; CHUNK=M.

### raster

- `raster::rasterize` (`data.frame`/`matrix`/`SpatialPoints` → Raster) — ORDER=D (trap: default `fun='last'`); CHUNK=K; state: per cell, an aggregate (count/sum/min/max) on a fixed raster grid; notes: the default is `fun='last'` (rasterize.R:18; rasterizePoints.R:7, :46-63), so overlapping points keep the last row's value. `first` is also D. With `fun='sum'/'count'/'min'/'max'` it is I and K (bounded by the grid size, i.e. A).
- **verdict**: `rasterize(points, fun="sum"|"count")` is a clean chunk target; warn about the default.

### spatstat.geom

- `spatstat.geom::pixellate.ppp` (and `quadratcount`) — ORDER=I; CHUNK=A; state: counts or weighted sums on a fixed pixel grid (`nearest.raster.point`, pixellate.R:78-80); notes: the grid comes from W or `as.mask`, so it is fixed in advance.
- `spatstat.geom::as.im.data.frame`, `as.owin.data.frame` — ORDER=D (on duplicate coordinates) / I otherwise; CHUNK=P; state: pre-pass for sorted unique x and y (the grid; `fillseq` infers the step), then cell assignment; notes: `mm[iijj] <- zk` (as.im.R:321; window.R:452) keeps the last row for duplicated (x,y).
- `spatstat.geom::ppp`/`as.ppp.data.frame`, `cut.ppp`, `discretise`, `coords<-`, `marks<-`, `subset.ppp` — ORDER=E; CHUNK=M; notes: inside-window filtering per point. The window must be given (or bounding-box A pre-pass).
- `spatstat.geom::multiplicity.ppp`/`multiplicity.data.frame` — ORDER=I; CHUNK=K; state: counts keyed by location (+marks).
- `spatstat.geom::duplicated.ppp`, `uniquemap.ppp` — ORDER=D (first occurrence kept); CHUNK=K.
- `spatstat.geom::nncross.ppp`/`nnfun.ppp` — ORDER=I; CHUNK=H; notes: chunkable over X (query points) only when Y is held in full.
- `spatstat.geom::intensity.psp`, `summary.ppp` — ORDER=I; CHUNK=A (marks summary quantiles → H).
- **verdict**: `pixellate.ppp`/`quadratcount` (A on a fixed grid) and `multiplicity` (K).

### PerformanceAnalytics

- `PerformanceAnalytics::Return.cumulative`, `Return.annualized`, `StdDev`, `SharpeRatio`, `VaR(method="gaussian"/"modified")`, `skewness`/`kurtosis` — ORDER=I; CHUNK=A; state: Σ log(1+R) or ΠR (Return.cumulative.R:46), and power sums up to order 4; notes: despite the time-series input, these are order-free.
- `PerformanceAnalytics::VaR`/`ES(method="historical")` — ORDER=I; CHUNK=H; notes: empirical quantile.
- `PerformanceAnalytics::maxDrawdown`, `table.Drawdowns`, rolling `chart.*` — ORDER=D (by design).
- `PerformanceAnalytics::checkData` — plumbing.
- **verdict**: the moment-based risk metrics are A; drawdowns are D.

### neuralnet

- `neuralnet::neuralnet` — ORDER=I; CHUNK=P; state: per training step, the full-batch gradient Σ over rows (crossprod of neurons and deltas, fit_neuralnet.R:301-305) and the error sum; notes: rprop/backprop are full-batch, with up to `stepmax` (1e5) passes. Weight initialisation draws `rnorm` per weight, not per row (fit_neuralnet.R:155-162), so it is order-invariant under a seed. Stores per-row `net.result`.
- `neuralnet::compute`/`predict.nn` — ORDER=E; CHUNK=M.
- **verdict**: prediction is M; training is impractical out-of-core (P with ~10⁴ passes).

### RWeka

- `RWeka::predict.Weka_classifier` — ORDER=E; CHUNK=M.
- `RWeka::evaluate_Weka_classifier` — ORDER=R (with `numFolds`, seeded CV in Java); CHUNK=H; notes: without CV it is A or K over predictions (confusion matrix, error sums) on test rows.
- **verdict**: predict is M; learners are opaque Java (H).

### recommenderlab

- `recommenderlab::Recommender` (UBCF/IBCF/POPULAR) — ORDER=I; CHUNK=A/H; notes: POPULAR is column sums (A). IBCF item–item similarity is an items×items cross-product over users (A, with fixed but large state). UBCF predictions are chunkable over target users, given all training users (H). The only scanned candidate was a print method.

### robslopes

- `robslopes::robslope` (Theil–Sen, repeated median, Passing–Bablok) — ORDER=I; CHUNK=H; notes: median of pairwise slopes (O(n log n) exact C++). Escape hatch: slope sampling.

### predicts

- `predicts::partialResponse` — ORDER=I; CHUNK=P (could be A); state: a range pre-pass per variable (response.R:143), then for each of `nsteps` grid values the mean prediction over all rows (:149-156); notes: this is a partial-dependence computation. A single pass can carry nsteps×nvars running sums when `rng` is supplied.

### stochvol

- `stochvol::svlm` — ORDER=D (trap); CHUNK=P; notes: takes `formula`+`data` like `lm` (wrappers.R:1389-1395), but the latent log-volatility is AR(1) over row order (`svsample`), so the rows must be time-ordered.

### psychTools

- `psychTools::dfOrder` — ORDER=S; CHUNK=H; notes: sorts a data frame by columns (stable for ties).

### openxlsx

- `openxlsx::writeData`, `writeDataTable`, `write.xlsx` — ORDER=E; CHUNK=M; notes: rows are written in order. `writeData(startRow=)` lets chunks be appended to a sheet, but the workbook is kept in memory until `saveWorkbook`, so memory is not bounded. `writeDataTable` needs the final extent of its table range.

### xlsx

- `xlsx::addDataFrame`, `write.xlsx` — ORDER=E; CHUNK=M; notes: `addDataFrame(startRow=)` (addDataFrame.R:70-72) can append chunks to a Java workbook held in memory. `write.xlsx(append=TRUE)` adds a sheet, not rows.

### wCorr (no scan candidates)

- `wCorr::weightedCorr` — ORDER=I; CHUNK=A/K/P/H by method; notes: Pearson is A (weighted moments). Polychoric is K (a weighted x×y contingency table, then optimisation). Polyserial is P (thresholds from the y margin, then likelihood optimisation). Spearman is H (weighted ranks; `wrank.R`). It takes vectors, not a data frame.

### tm (no scan candidates)

- `tm::TermDocumentMatrix`/`DocumentTermMatrix` — ORDER=I (terms), E (documents); CHUNK=K; state: a term dictionary plus a per-document sparse row; notes: terms are `sort(unique(...))` (matrix.R:170), unlike quanteda. Global `bounds` filter on document frequency (matrix.R:60-67) needs a K pre-pass. `DataframeSource` and the `Source` reader API are a document-stream abstraction (prior art for streaming input).

### Other no-candidate packages (brief)

- `nonnest2::vuongtest` — ORDER=I; CHUNK=A; state: Σ(ℓ_A−ℓ_B) and Σ(ℓ_A−ℓ_B)² of per-row log-likelihood contributions (`llcont`, vuongtest.R:141); notes: needs both models fitted first (P).
- `splines2::bSpline`/`naturalSpline` etc. — ORDER=I; CHUNK=P; notes: default internal knots are at quantiles of x (man/bSpline.Rd:66), an H pre-pass that can be sketched. The basis is M given knots.
- `mixture::gpcm`, `movMF::movMF` — ORDER=R; CHUNK=P; notes: EM with per-component weighted moments (A per pass), random or k-means starts (gh_mixture.R:4, :143).
- `reformulas::mkReTrms` — ORDER=I; CHUNK=P; notes: grouping-factor levels (K pre-pass, `drop.unused.levels`, mkReTrms.R:67-81), then row-local Z construction (E).
- `sfheaders::sf_linestring`/`sf_polygon` — ORDER=D (by design); notes: row order defines vertex order within each id. `sf_point` is E.
- `roll`, `TTR` — ORDER=D (rolling or recursive windows); not targets.

### Skipped

Sim.DiffProc (summary and print of simulated SDE objects), TMB, TSP (`as.ETSP.data.frame` coercion), mlr3misc (column helpers), nanotime, rcdk ("formula" = chemical formula), reticulate (pandas conversion), rjd3toolkit (time series, D), seewave (`write.audacity`), waldo, TreeTools (tree edge matching). Of the no-candidate packages, the following were not examined beyond their titles because none consumes data frames row-wise: memoise, minerva, mniw, multiway, mvnfast, nabor, nFactors, ompr, openssl, oro.nifti, parallelDist, ParallelLogger, partitions, phylogram, pingr, plgp, pool, PowerTOST, promises, proxyC, qpdf, qs2, R.utils, rangen, RcppDist, RcppNumerical, rdist, reactR, redux, Rnanoflann, ROI, RSpectra, rstantools, rust, Rvcg, sass, scales, showtext, SkewHyperbolic, SNFtool, SqlRender, StanHeaders, systemfonts, tidyxl, tikzDevice, tinysnapshot, transport, TruncatedNormal, tsmethods, urltools, websocket.
