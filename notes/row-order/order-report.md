# Row-order dependence in R data-frame consumers

Question: which functions in base R, the recommended packages, and CRAN packages of dependency depth 1–3
depend on the order of the rows of a data frame, and why?

This synthesis draws on three detailed files, all in `order/`:

- `by_mechanism.md`: 440 entries from the earlier catalog, sorted into 12 mechanisms (117 checked by permuting rows).
- `by_design_base_rec.md`: about 100 functions in base R and the recommended packages that treat rows as a sequence by design.
- `by_design_cran.md`: about 140 such functions in CRAN depth-1–3 packages, about 85% checked by permutation.

"Checked" means the function was run on a small data frame and on a row-permuted copy with a fixed seed, and the results compared.
Coverage limits are the same as before:
1,038 of about 9,400 depth-1–3 CRAN packages, ranked by reverse dependencies, and only functions that accept data frames.

## Answer in brief

A function depends on row order for one of six reasons.

1. **The rows are a sequence by design.**
   Time series, lags, differences, rolling windows, cumulative sums, carry-forward fills, run ids, Kalman filters,
   serial-correlation tests and HAC variances, MCMC diagnostics, and plots that join points with lines.
   This is legitimate, but the function trusts row order as time instead of reading a time column.
2. **Position is silently used as information the user never supplied.**
   Position stands in for time, for identity, or for alignment with a side input;
   first or last occurrence wins; positional subsets; ties broken by encounter order; online algorithms;
   user callbacks that see each group in input order.
   These are the dangerous ones, because the function looks order-free.
3. **Random draws are indexed by row position.**
   Bootstrap, cross-validation folds, random starts, subsamples, permutation tests, random tie-breaking.
   The result is invariant in distribution but changes under permutation with a fixed seed.
4. **Numerical artefacts of accumulation order.**
   Floating-point sums differ in the last bits, integer overflow can depend on order, and QR/SVD signs are not unique.
5. **Presentation only.**
   The set of results is unchanged, but output order, labels, levels, or the reference category follow first appearance.
6. **Bugs that mix up two orderings.**
   One part of the code uses first-appearance order and another sorted order, so values end up under the wrong labels.

The fix is almost always the same: make the order an explicit input.
Sort by a key, pass a time covariate (`order.by =`, `form = ~ t | g`, `t =`, `keyby =`, an index for `zoo`/`xts`),
name ids and pairs explicitly, break ties by a sorted key, and derive random numbers from a row key rather than a row position.

## 1. Rows as a sequence by design

- base and stats:
  - `ts()`/`as.ts()` on a data frame call `data.matrix()`.
    As a result, `acf()`, `ar()`, `filter()`, `spectrum()` and `HoltWinters()` analyse *every* column, ids, dates and codes included,
    with row position as time (verified).
  - `diff()`, `embed()`, `filter()`, `acf()`/`pacf()`/`ccf()`, `ar()`, `arima()`, `StructTS()`, `KalmanLike()`, `HoltWinters()`,
    `decompose()`, `stl()`, `spectrum()`, `Box.test()`, `PP.test()`, `aggregate.ts()`, `na.contiguous()`, `runmed()`, `smooth()`,
    `kernapply()`, `rle()`.
  - `cumsum()`/`cumprod()`/`cummax()`/`cummin()` reach data frames through `Math.data.frame`, so `cumsum(df)` looks element-wise but is not.
  - `ave(x, g, FUN = cumsum)` and `ave(x, g, FUN = seq_along)` number or accumulate rows within groups in input order.
  - `lag()` on a plain column is a no-op, so `lm(y ~ lag(y, -1))` regresses `y` on itself (coefficients 0 and 1, verified).
  - Index plots and line geometry: `plot(df$y)`, `plot(y ~ 1)`, `matplot(df)`, `type = "l"`/`"s"`, `polygon()`, `image(as.matrix(df))`,
    `plot.lm(which = 4)` (Cook's distance against observation number).
    `lowess(y)`, `smooth.spline(y)`, `isoreg(y)` and `approx(y)` without `x` use `x = seq_along(y)`.
- Recommended packages:
  - `nlme` serial and spatial correlation classes (`corAR1`, `corARMA`, `corCAR1`, `corSymm`, `corExp`, …) without a covariate
    use position within group as time (logLik −568.1 vs −612.5 after shuffling within groups).
    `glmmPQL()` and `gamm()` inherit this.
  - `nlme::ACF.gls()` ignores the time covariate its help page documents for `form = ~ t | g`
    and lags by position within group (gls.R:368, verified).
    `ACF.lme()` has no `form` at all.
  - `mgcv::bam(rho =, AR.start =)`, `bam.update()` with `rho != 0`, `boot::tsboot()`,
    `MASS::lm.gls()` (an n × n weight matrix indexed by position).
- CRAN depth 1–3:
  - Lags, leads and differences, rolling windows: `data.table::shift()`/`froll*()`,
    `collapse::flag()`/`fdiff()`/`fgrowth()` (without `t =`),
    `zoo::rollapply()` on unindexed data, `TTR`, `RcppRoll`, `roll`, `caTools`, `tsModel`, `dlnm`.
  - Fills and cumulative operations: `data.table::nafill()`, `zoo::na.locf()`/`na.approx()`, `vctrs::vec_fill_missing()`,
    `metafor::cumul()` without `order =`.
  - Run and sequence ids: `data.table::rleid()`/`rowid()`, `vctrs::vec_identify_runs()`, `splitstackshape::getanID()`, `evd::clusters()`.
  - Time-series models and tests: `KFAS`, `dlm`, `strucchange`, `urca::ca.jo()` (takes a data frame directly),
    MCMC diagnostics in `coda` and `LaplacesDemon`.
  - Serial-correlation-robust inference: `lmtest::dwtest()`/`bgtest()`/`gqtest()`/`harvtest()`/`raintest()`/`hmctest()`,
    `sandwich::vcovHAC()`/`NeweyWest()`/`kernHAC()`/`vcovPL()`, each without `order.by =`.
    `gmm::gmm()` defaults to HAC weighting, so IV coefficients on cross-sectional data move under permutation (verified).
  - Also: signal processing, track and polygon geometry, positional train/test splits, systematic sampling, `udpipe` token streams,
    `lubridate::int_diff()`, `psych::mssd()`, `pracma` integrals.

Order-free despite appearances: `zoo`/`xts` objects built with an index sort on construction,
and so do `TTR` and `PerformanceAnalytics` on data frames with date row names, `tsbox`, `spacetime::STIDF`,
`survival::tmerge()` (except tied id/time pairs), multi-state `survfit(id =)`, `data.table` with `keyby =`,
`collapse` with `t =`/`o =`, the `lmtest`/`sandwich`/`strucchange` functions with `order.by =`,
and `nlme::corAR1(form = ~ t | g)`, which keeps the fit order-free by silently switching to `corARMA(1, 0)` when rows are unsorted.

## 2. Position silently used as information

### Position as time

Listed above under `nlme`, `sandwich`, `lmtest`, `gmm` and `stats::SSfol()` (its starting values read the last row as the last time).
These look like ordinary cross-sectional functions, which is what makes them traps.

### Position as identity (17 entries)

- `gee::gee()` forms clusters from runs of contiguous equal `id`:
  shuffling turned 60 subjects into 296 clusters and changed the robust SEs (verified).
- `pairwise.t.test()`/`pairwise.wilcox.test()` with `paired = TRUE`, `effsize::cohen.d(paired = TRUE)` and
  `lsr::pairedSamplesTTest()` (long form) pair the k-th row of each group.
- `reshape(direction = "long")` without `idvar` uses row numbers as ids; `unstack()` pairs the i-th occurrence of every group.
- `multgee` without `repeated =` numbers occasions by position; `mstate::msprep()` and `dfidx` derive ids from position.

### Side inputs aligned by position (15 entries)

- `cbind(a, b)` and `data.frame(a, b)` pair rows by position and keep `b`'s row names without warning,
  even when `b` was permuted (verified).
- `Ops.data.frame` recycles a vector down the rows (`df * c(10, 100)` alternates), and `df1 - df2` pairs cells by position,
  ignoring row names.
- `sweep(df, 1, STATS)`, recycled graphical parameters (`col`, `pch`), `split(df, 1:k)` (round-robin), `lm(subset = <integer>)`.
- `GLMMadaptive` and `lqmm` take per-subject weights from first-appearing rows;
  `sampling::strata()` matches `size` to strata by first appearance.

### First or last occurrence wins (30 entries)

- `duplicated()`, `unique()`, `match()` with duplicate keys, `which.max()`/`which.min()` on ties, `make.unique()`, `Position()`/`Find()`.
- `levelplot()`/`contourplot()`/`wireframe()` keep the last row for duplicated cells; `raster::rasterize()` defaults to `fun = "last"`;
  `spatstat.geom::as.im.data.frame()` keeps the last duplicate.
- `survival::tmerge()` resolves tied `tdc()` values to the last row; `JM` dynamic predictions read each subject's last row,
  not its latest time;
  `psych::alpha()` reads a constant item's value from row 1, so an NA there shifts every total (verified).

### Positional subsets and prefixes (15 entries)

- `head()`/`tail()`, `gbm(train.fraction =)` (trains on the first rows), consecutive or interleaved CV folds (`chemometrics`, `cvTools`,
  `h2o` with `fold_assignment = "Modulo"`), `aplpack::bagplot()` positional subsample above 300 rows.
- Global decisions from the first chunk or first rows: schema inference in readers, `biglm`'s model coding from the first chunk.

### Ties broken by encounter order (44 entries)

- Modes: `collapse::fmode(ties = "first")`, the default categorical summary in `collap()`;
  `datawizard::distribution_mode()`, which documents the smallest tied value but returns the first;
  `marginaleffects::datagrid()` (16/16 tie gives "x" or "y" depending on order, verified).
- Clustering and scaling: `hclust()` (except single linkage), `cluster::agnes()`/`pam()`, `MASS::isoMDS()`,
  `mclust::Mclust()` (ties in its hierarchical start).
- Sorting and ranking: stable `order()`/`sort_by()`, `rank(ties.method = "first")`, `KernSmooth::dpill()`,
  `MatchIt` nearest-neighbour matching without a propensity score.

### Sequential and online algorithms (12 entries)

`kmeans()` Hartigan–Wong (default) and MacQueen update centres row by row,
so only 12% and 30% of 40 permutations agreed even from fixed centres (Lloyd: 100%).
Also `class::SOM()`, `som`, `vegan::specaccum(method = "collector")`, `rmeta::cummeta()`, `metafor::cumul()`.

### User code receives rows in input order (14 entries)

`tapply()`, `by()`, `aggregate()`, `ave()`, `split()`/`lapply()`, `data.table`'s `j`, `dcast(fun.aggregate =)`,
`plyr` and `collapse` callbacks are order-free
only for order-free callbacks: `function(v) v[1]`, `head()`, `paste(collapse =)` or `cumsum()` make them order-dependent.

## 3. Random draws indexed by row position (159 entries)

This is the largest group, and mostly by design: the results are correct in distribution.
It matters for reproducibility, because a fixed seed no longer reproduces a result after the data are re-sorted or re-read in another order.

- Resampling: `boot()`, `cv.glm()`, `randomForest`, `ranger`, `gbm` bagging, `lqs()`/`cov.rob()`, `robustbase` subsamples.
- Folds and splits: `rpart(xval =)` (same tree, different `xerror`), `cv.glmnet()`, `cvTools`.
- Starts and subsets: `kmeans()` starts, `cluster::clara()` (whose default generator ignores `set.seed()`), `clusGap()`,
  and `mgcv::bam()` with `discrete = FALSE` above `chunk.size` rows,
  which builds its smooth bases on a positional subsample (fitted values differ by up to 0.064).
- Random tie-breaking: `max.col()` (default), `class::knn()` votes, `circular::watson.wheeler()`.
- Not row-indexed despite using random numbers, and therefore order-free with a fixed seed:
  `chisq.test(simulate.p.value = TRUE)`, `fisher.test(simulate.p.value = TRUE)`, `ks.test()` simulation (they draw from the margins),
  `nnet` start weights, `poLCA`.

## 4. Numerical artefacts (10 entries)

- `rowsum()` on integer columns: a running C `int` becomes a sticky `NA` when a partial sum overflows,
  so `c(INT_MAX, 1L, -1L)` gives `NA` and `c(INT_MAX, -1L, 1L)` gives `INT_MAX` (re-checked); `sum()` and `colSums()` are safe.
- Floating-point summation order: every "invariant" fit agrees only to `all.equal()`, not bitwise.
  `survival::concordance()` detects ties by exact equality,
  and identical rows can get linear predictors one ulp apart depending on their position.
- Sign non-uniqueness: `lm()$effects` signs, `prcomp()` rotation signs, `qda()` scaling, `MASS::mca()`; magnitudes are invariant.
- `nnet()` is chaotic: a 1e-15 perturbation changed the weights by 23%.

## 5. Presentation only (63 entries)

Output order, labels or the reference follow first appearance; the values are unchanged.

- `rbind()` builds factor levels in first-appearance order, `factor(x, levels = unique(x))`, `merge(sort = FALSE)`,
  `rowsum(reorder = FALSE)`,
  `reshape(direction = "wide")` column order, `cutree()` cluster numbers, `split()` within-group row order.
- `data.table` `by =` (use `keyby =`), `unique()` output order, `collapse` grouping order, `uniquecombs(ordered = FALSE)`.
- `nlme::varIdent()` takes the first-appearing stratum as the reference,
  so the reported sigma and variance ratios change while logLik does not.
- Plot z-order (last drawn on top), `barplot()`/`pie()` order, `boxplot()`'s `out` order.

## 6. Bugs that mix up two orderings or indices

All reproduced; most are outside base R.

- `bain::t_test.formula()`: group n and variance follow first appearance, means follow factor levels; Bayes factor 3.87 vs 7.49.
- `survey::svydesign(pps = "brewer")`: first-appearance PSU scale factors multiply PSU totals sorted by id; variance depends on row order.
- `sampling::strata()`: `size` matched to strata by first appearance; reversing the rows swaps the sample sizes.
- `survival::survcondense()`: keeps the wrong start time on unsorted input (re-checked).
- `MASS::loglm()` on a data frame with repeated cells and an offset attaches offsets to the wrong rows.
- `eha::join.spells()` sorts the spells but passes covariates and ids in the original order, scrambling them on unsorted input.
- `sandwich::vcovPC()` ignores `order.by` except to check balance; rows must already be sorted by cluster.
- `bsts(timestamps =)` treats a permuted but complete daily series as regular and ignores the stamps.
- `graphics::spineplot()` with a Date x takes axis labels by position and errors on unsorted input.
- Not order bugs, found on the way: `geosphere::perimeter()` returns the sum of the absolute coordinates instead of the perimeter
  (re-checked: 4 for a 1° square), and `ff::csum()`/`cmean()` with `na.rm = TRUE` add the first chunk repeatedly.

## A data frame treated as a sequence of columns

Several base generics iterate over a data frame as a list of columns, which surprises when rows were meant:
`rev(df)` reverses and `sample(df)` permutes the columns;
`is.unsorted(df)` compares adjacent columns;
`diff(df)` errors with two or more columns and returns a 0-column frame with one;
`rle(df)` treats a one-column frame as a single run;
`Reduce()`, `Filter()`, `Map()`, `Find()` and `Position()` iterate over columns.
None of these depends on row order, but each fails to do the row-wise operation a user may expect.
