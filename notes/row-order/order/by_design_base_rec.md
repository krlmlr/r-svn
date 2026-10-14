# By-design row-order dependence: base R and the recommended packages

Scope: functions whose semantics treat data-frame rows as a sequence, as the complement of `catalog.md` (which records hidden dependence only).
Sources are the R-devel checkout (`src/library/<pkg>/R`) and the recommended-package sources in `scratchpad/rec/<pkg>/R`.
Every line marked "verified" was run in R 4.5.3 on a small data frame under a row permutation; the scripts are `order/tests_base/t01…t16*.R`, with `helpers.R`.
`classify()` reports I (identical), E (the result permutes with the rows) or D (anything else); plots compare 400×400 cairo PNGs pixel by pixel.

Classes, as in the catalog:
D = the result changes under row permutation;
E = row-aligned output that permutes with the input;
S = same content, but layout or labels follow row order;
I = invariant;
R = depends on the RNG stream.

"df:" says how a data frame reaches the function: a method, a coercion (`as.ts()` → `ts()` → `data.matrix()`, `as.matrix()`), a single column, or not at all.
A column means `df$x`; "1-col df" means `df["x"]`.

## Sequence semantics (time series)

Gateway: every `stats` time-series function calls `as.ts()`, which turns a data frame into `ts(data.matrix(df))` (ts.R:34, 127-131).
Row i becomes time `start + (i - 1)/frequency`, character and factor columns become integer codes, and a `Date` column becomes just another numeric series, never the index (verified, t13).
The universal fix is to sort by the time column (and the group), insert `NA` rows for missing times so spacing is regular, and set `start`/`frequency`, or to use `zoo::zoo(df[cols], order.by = df$time)`, which sorts by its index (verified order-free, t09).
Checks: t01, t02, t09, t13, t15.

- `stats::ts`, `stats::as.ts` — ORDER=D (values E, but the time index is the row position); why: row i is assigned time `start + (i-1)/frequency`, which every downstream ts function reads as sequence; df: method-free coercion `data.matrix(df)` (ts.R:34), char/factor/Date columns become codes silently (verified); fix: sort by time, fill gaps with NA rows, set `start`/`frequency`, or `zoo(order.by =)`.
- `stats::window` — ORDER=D; why: selects a time range, and a plain column gets `tsp = c(1, n, 1)` from `hasTsp()` (ts.R:116-120), so `window(df$x, 2, 5)` is `df$x[2:5]` (verified); df: `window(df, …)` errors "invalid time series parameters specified"; fix: subset on the time column.
- `stats::lag` — ORDER=D on `ts` objects, no-op on plain columns; why: shifts only the `tsp` attribute, so `lm(y ~ lag(y, -1), df)` regresses y on itself (coefficients 0, 1, verified); df: `lag(df)` errors; fix: `c(NA, head(y, -1))` after sorting, `embed()`, or `ts.intersect()` / `zoo::lag` on an indexed series.
- `base::diff` (`diff.default`) — ORDER=D; why: `x[i + lag] - x[i]` over consecutive rows; df: no data-frame method, the frame is treated as a list of columns: ≥ 2 columns error "non-numeric argument to binary operator", 1 column silently returns a 0-column frame (verified); `diff(as.matrix(df))` works; fix: sort first; per group `ave(x, g, FUN = function(v) c(NA, diff(v)))` on sorted rows.
- `stats::diffinv` — ORDER=D; why: cumulative inverse of `diff()` from initial values `xi`; df: errors "'x' is not a vector or matrix" (1-col too); column or matrix only; fix: sort first.
- `stats::embed` — ORDER=D; why: row i of the result is `x[i + k - 1], …, x[i]`, a lag matrix by position (embed.R:22-37); df: errors "'x' is not a vector or matrix"; `embed(as.matrix(df), k)` works (verified D); fix: sort first, one series per group.
- `stats::filter` — ORDER=D; why: convolution over a window of consecutive rows, or a recursive AR filter `y[i] = x[i] + f*y[i-1]`; df: accepted through `as.ts(x)` (filter.R:23), every column filtered, codes included (verified); fix: sort, filter per group with `ave()`.
- `stats::convolve(type = "filter")`, `stats::fft`, `stats::mvfft`, `stats::spec.taper` — ORDER=D; why: transforms indexed by position (frequency k pairs with element order); df: columns only, `mvfft(df)` errors "vector-valued (multivariate) series required", `mvfft(as.matrix(df))` works (verified); fix: sort, regular spacing.
- `stats::acf`, `stats::pacf`, `stats::ccf` — ORDER=D; why: correlation of `x[t]` with `x[t + k]`; lag-1 ACF went 0.814 → 0.134 under permutation (verified); df: accepted via `as.ts()` (acf.R:33), all columns form one multivariate series, including ids, dates and character codes (verified); `ccf` aligns two columns with `ts.intersect()` (acf.R:214); fix: sort, keep numeric series only, one call per group.
- `stats::ar` (`ar.yw`, `ar.ols`, `ar.burg`, `ar.mle`) — ORDER=D; why: AR(p) regression of each row on the p preceding rows; df: yw/ols/burg accept a df as a vector AR over all columns (ar.R:48), `ar.mle` errors for > 1 column (verified); fix: sort, select the series columns.
- `stats::arima` — ORDER=D; why: ARMA likelihood by a Kalman filter along rows; with `order = c(0, 0, 0)` and `xreg` it reduces to iid regression and is I (verified); df: `x` as column or 1-col df (`arima(df)` errors "only implemented for univariate time series"), `xreg = df[cols]` via `as.matrix(xreg)` (arima.R:154); fix: sort by time, explicit NA rows for gaps.
- `stats::arima0` — ORDER=D; why: exact ARMA likelihood along rows (verified `$coef`); df: column or 1-col df; fix: as for `arima`.
- `stats::predict.Arima`, `stats::predict.ar`, `stats::predict.HoltWinters`, `stats::KalmanForecast` — ORDER=D; why: forecasts continue from the last rows' state (verified for the first three); df: via the fit (`newxreg` may be a df); fix: make sure the last row is the latest time.
- `stats::StructTS`, `stats::tsSmooth` — ORDER=D; why: local-level/trend/BSM state-space model filtered along rows; df: column or 1-col df (multi-col errors); fix: sort, regular spacing.
- `stats::KalmanLike`, `stats::KalmanRun`, `stats::KalmanSmooth` — ORDER=D; why: Kalman recursions over `y` in row order (verified for Like and Run); df: `y` as a column plus a model list; fix: sort.
- `stats::HoltWinters` — ORDER=D; why: exponential-smoothing recursions; default starts `l.start = x[2]`, `b.start = x[2] - x[1]` (HoltWinters.R:59-63); df: via `as.ts()` (HoltWinters.R:40), column or 1-col df, seasonal models need `ts(…, frequency =)`; fix: sort, set frequency.
- `stats::decompose` — ORDER=D; why: centred moving average over `frequency` consecutive rows, plus means per cycle position; df: `decompose(df)` errors "time series has no or less than 2 periods" because `as.ts()` gives frequency 1, `decompose(ts(df["x"], frequency = 4))` works; fix: sort, complete the grid, set start and frequency.
- `stats::stl` — ORDER=D; why: loess smoothing of cycle subseries (all rows sharing a cycle position); df: only `ts(df$x, frequency =)`, a 1-col ts matrix errors "only univariate series are allowed" (verified); fix: as for `decompose`.
- `stats::spectrum`, `stats::spec.pgram` — ORDER=D; why: periodogram = squared FFT of the ordered series; df: accepted via `as.ts()` (spectrum.R:102), multivariate with coherency and phase; fix: sort, regular spacing.
- `stats::spec.ar` — ORDER=D; why: spectrum of a fitted AR model; df: errors even for 1 column ("must be a time series or an ar() fit"); column OK; fix: sort.
- `stats::cpgram` — ORDER=D; why: cumulative periodogram test for white noise; df: errors ("only implemented for univariate time series", or "'x' must be numeric" for 1 column); column OK; fix: sort.
- `stats::Box.test` — ORDER=D; why: Box–Pierce/Ljung–Box sum of squared autocorrelations at lags 1…k; df: column or 1-col df, more columns error; fix: sort; for model residuals keep the fit's row order.
- `stats::PP.test` — ORDER=D; why: Phillips–Perron unit-root regression of `x[t]` on `x[t-1]`; df: errors "'x' is not a vector or matrix" for any df; column OK; fix: sort.
- `stats::aggregate.ts` — ORDER=D; why: sums (or `FUN`s) blocks of `frequency/nfrequency` consecutive rows; df: via `ts(df, frequency =)`, whereas `aggregate(df, …)` dispatches to the order-free data-frame method; fix: sort, or aggregate by an explicit period column with `aggregate.data.frame`.
- `stats::ts.union`, `stats::ts.intersect` — ORDER=D; why: align series on their (position-derived) time; df: errors "no time series supplied"; `ts(df$x)` OK; fix: give each series a real start/frequency or merge on the time column.
- `stats::na.contiguous` — ORDER=D; why: keeps the longest stretch of consecutive non-NA rows (verified); df: errors "invalid time series parameters specified"; column or ts OK; fix: sort first.
- `stats::toeplitz` — ORDER=D; why: builds the symmetric matrix `x[|i - j| + 1]`, positional by definition; df: errors "'x' is not a vector", column OK; normally fed an autocovariance sequence rather than raw rows.
- `stats::monthplot.default` — ORDER=D; why: for a plain column `times = seq_along(x)` and `phase = (times - 1) %% 12 + 1` (monthplot.R:54-55), so row 1 is January; df: errors (list cannot be coerced to double); fix: pass `phase =` from a month column, or a `ts` with correct start.
- not data-frame consumers: `stats::tsdiag` (takes a fit; D through it, verified 5.4k px), `ARMAacf`, `ARMAtoMA`, `arima.sim`, `kernel`/`df.kernel`/`bandwidth.kernel`, `tsp`/`hasTsp`/`time`/`cycle`/`frequency`/`deltat`/`start`/`end` (ts attributes), `KalmanForecast` without data.

## Cumulative / running

Checks: t02, t03, t15.

- `base::cumsum`, `base::cumprod`, `base::cummax`, `base::cummin` (via `Math.data.frame`) — ORDER=D; why: running aggregate down each column, so `cumsum(df)` looks element-wise but is a sequence operation (verified); df: method `Math.data.frame` applies the generic per column (dataframe.R:1591-1596) and errors on any non-numeric column; fix: sort by time first; per group use `ave()` on sorted rows.
- `base::apply(df, 2, cumsum)` (and other running FUNs) — ORDER=D; why: same running aggregate per column after `as.matrix()` (verified); df: coercion, a character column makes the matrix character; fix: sort first.
- `stats::ave` with `FUN = cumsum`, `seq_along`, `cummax`, `function(v) c(NA, diff(v))` — ORDER=D; why: FUN receives each group's values in row order (catalog: `stats::ave`; verified cumsum and seq_along, while `FUN = mean` is E); df: columns; fix: `df <- df[order(df$g, df$t), ]` before calling.
- `base::unsplit` with a running FUN, `` base::`split<-` `` — ORDER=D; why: the i-th result of each group is scattered back to that group's i-th row, so `unsplit(lapply(split(x, g), cumsum), g)` is D, the plain round trip E (verified); df: columns or `split.data.frame`; fix: sort within groups first.
- `base::Reduce(f, x, accumulate = TRUE)` — ORDER=D; why: left fold over consecutive elements (verified); df: on a data frame it folds over columns, not rows; fix: sort first.
- `base::Position`, `base::Find` — ORDER=D; why: first (or with `right = TRUE` last) element satisfying a predicate (verified `id[Position(…)]` changes); df: columns, a data frame is iterated by column; fix: rank by an explicit column.
- `base::rle` — ORDER=D; why: runs of equal *consecutive* values (verified lengths change); df: a 1-col frame becomes one run whose value is the whole frame, more columns error "undefined columns selected" (verified); column OK; fix: sort by time within group.
- `stats::runmed`, `stats::smooth`, `stats::smoothEnds` — ORDER=D; why: running medians over k consecutive rows and Tukey 3RS3R-type resmoothing (verified); df: all error (list coercion, "attempt to smooth non-numeric values", "undefined columns selected"); column OK; fix: sort first.
- `stats::kernapply` — ORDER=D; why: kernel-weighted moving average of consecutive rows (verified); df: errors "'kernapply' is not available for object 'x'" (kernel.R:175-180), matrix or column OK; fix: sort first.
- `base::rowsum(reorder = FALSE)` — ORDER=S; why: groups listed in first-appearance order (catalog), with sums unchanged; df: method; fix: default `reorder = TRUE`.
- not data-frame consumers: `base::inverse.rle` (takes an rle object), `stats::diffinv` initial values `xi`.

## Positional access and first/last

Checks: t03, t04, t11.

- `utils::head`, `utils::tail` — ORDER=D; why: first or last n rows (negative n drops them); df: method (`head.array` via utils NAMESPACE); fix: sort first, or `df[order(-df$t)[seq_len(n)], ]`.
- `` base::`[.data.frame` `` with integer `i` (and `[<-`, `[[<-`) — ORDER=D; why: rows addressed by position; df: method; fix: logical `i` from a key column, or `match()` on a unique key.
- `` base::`[.data.frame` `` with character `i` (row names) — ORDER=I while row names travel with rows (`df[p, ]` keeps them, verified), D once they are automatic again: `merge()` output, `aggregate()`, `read.table()`, `rownames(x) <- NULL` renumber 1..n (verified: `df["3", ]` picked id 3 vs 5, merge row "1" id 1 vs 3); df: method; fix: keep an explicit key column.
- `base::seq_len(nrow(df))`, `base::seq_along`, automatic row names used as ids — ORDER=D; why: positions become identifiers (verified); df: `nrow()`; fix: derive ids from keys after sorting, e.g. `ave(t, g, FUN = rank)`.
- `base::which` — ORDER=E; why: returns positions, which relabel with the rows while the selected row set is invariant (verified); `which(cond)[1]` is D; df: on a column or `is.na(df)`; fix: none needed for set use.
- `base::which.max`, `base::which.min` — ORDER=D on ties (first extreme wins; verified id 2 vs 6 for a tied minimum), E without ties; df: column; fix: break ties explicitly, `order(-x, t)[1]`.
- `base::match` (lookup `df$v[match(k, df$key)]`) — ORDER=D when `table` has duplicates (first match wins, verified); df: column as `table`; fix: deduplicate the key by an explicit rule first.
- `base::duplicated`, `base::unique`, `base::anyDuplicated` (data-frame methods) — ORDER=D for which copy counts as first (`fromLast = TRUE` flips it) (catalog; verified `id[duplicated(x)]`); df: methods; fix: sort by a priority column before deduplicating.
- `base::make.unique`, `base::make.names(unique = TRUE)` — ORDER=D; why: the first occurrence keeps the bare name, later ones get `.1`, `.2` (verified); df: column; fix: sort first or build names from a key.
- `base::factor(x, levels = unique(x))`, `base::merge(sort = FALSE)`, `stats::reshape(direction = "wide")` column order, `stats::cutree` numbering, `nlme::varIdent` reference stratum — ORDER=S; why: first-appearance order (catalog); df: columns or methods; fix: explicit `levels =` or sorting.
- `base::rank(ties.method = "first" | "last")` — ORDER=D; why: tied values are ranked by position (verified), `"random"` is R, the default `"average"` is E; df: column; fix: break ties with a second key, `order(order(x, t))`.
- `base::order`, `base::sort_by.data.frame`, `base::sort(method = "radix")` — ORDER=S; why: stable sorts keep tied rows in input order (verified `sort_by(df, ~x)` ids differ); df: `sort_by` method, `order()` on columns, `order(df)` errors "cannot xtfrm data frames"; fix: add a tiebreak column (`order(x, id)`).
- `base::max.col(ties.method = "first" | "last")` — ORDER=E (row-local, verified); the default `"random"` is R (catalog); df: `as.matrix()`; fix: name `ties.method`.
- `stats::aggregate`, `base::tapply`, `base::by`, `stats::ave` with a positional FUN (`function(v) v[1]`, `head`, `tail`, `rev`, `paste(collapse =)`), and `df[!duplicated(df$g), ]` — ORDER=D; why: FUN sees each group's values in row order, so "first/last per group" follows row order (verified all four idioms); df: formula/data-frame methods; fix: sort within group by time, or pick `which.max(t)` per group.
- `utils::unstack` — ORDER=D; why: row i pairs the i-th occurrence of every group (catalog; verified); df: method; fix: reshape wide by an explicit pair id.
- `stats::reshape(direction = "long")` without `idvar` — ORDER=D; why: `ids = 1L:NROW(data)` become the id column (catalog; verified); df: data-frame input; fix: supply `idvar`.
- `utils::str`, `base::print.data.frame` (`max =` / `max.print` truncation) — ORDER=S; why: show the first values or rows; df: methods; fix: sort before previewing.
- `utils::read.table(nrows =, skip =)`, `utils::read.csv` — ORDER=D on file line order; why: a producer, rows enter in file order and get positional automatic row names; df: produces one; fix: sort after reading.
- not data-frame consumers: `utils::write.table` (E, output order = input order, catalog), `utils::type.convert` (I, catalog), `parallel::splitIndices`/`clusterSplit`/`pvec` (contiguous position blocks, results reassembled in input order, E; source only).

## Data frame treated as a sequence of columns

These are traps for code that expects row semantics: the generic sees the data frame as a list, so the sequence is the columns.
Checks: t03, t04, t15.

- `base::rev` — ORDER=E over rows; why: `rev.default` is `x[length(x):1L]` (rev.R:21), which reverses the *columns* of a data frame (verified); df: default method; fix: `df[rev(seq_len(nrow(df))), ]`.
- `base::sample` — ORDER=E over rows; why: `x[sample.int(length(x))]` (sample.R:26) permutes *columns* (verified); df: default; fix: `df[sample(nrow(df)), ]`.
- `base::is.unsorted` — ORDER=I over rows; why: for objects it calls `.gtn()`, i.e. `x[-1L] >= x[-n]` on the frame (sort.R:313-317), comparing adjacent *columns* elementwise: rows ascending with `a > b` give TRUE, descending rows FALSE (verified); df: no method; fix: `is.unsorted(df$t)` or `!identical(order(df$g, df$t), seq_len(nrow(df)))`.
- `base::diff`, `base::rle` — see above: 0-column frame or error, and one run holding the whole frame (verified).
- `base::sort`, `base::order`, `base::xtfrm` on a whole data frame — error "cannot xtfrm data frames" (dataframe.R:1694-1695); fix: `sort_by(df, ~ g + t)` (stable, S).
- `base::Reduce`, `base::Filter`, `base::Map`, `base::Find`, `base::Position` on a data frame — iterate over columns (verified for `Reduce`).

## Recycling down rows and positional pairing between objects

Checks: t03, t09, t11.

- `base::Ops.data.frame` (data frame op vector) — ORDER=D; why: a non-scalar vector is recycled down the rows, column-major (`rep_len(e2, prod(dim(e1)))`, dataframe.R:1639), so `df * c(10, 100)` alternates rows (catalog; verified); df: method; fix: use a column, `df$x * df$w`.
- `base::Ops.data.frame` (data frame op data frame) — ORDER=D; why: cells pair by position, row names are ignored and e1's are kept (verified `df - df[p, ]`); df: method; fix: `merge()` on a key, or `b[match(a$key, b$key), ]` first.
- `base::cbind.data.frame`, `base::data.frame(a, b)` — ORDER=D; why: positional pairing, and row names come from the first argument with non-automatic names, so `cbind(a, b[p, ])` labels rows with b's names while pairing a's values by position, silently (verified); df: method; fix: `merge(a, b, by = key)` or `by = 0`; `data.frame(a, b, check.rows = TRUE)` errors on mismatched names, but only when both carry explicit names (verified).
- `` base::`$<-.data.frame` ``, `` `[<-.data.frame` ``, `base::data.frame`, `base::cbind`, `base::transform` with a short vector — ORDER=D; why: a value whose length divides `nrow` is recycled down the rows (verified `df$h <- c("u", "v")` and three others); df: methods; fix: compute the value from a column.
- `base::split.data.frame` with a short `f` — ORDER=D; why: `split(seq_len(nrow(x)), f)` (split.R:41) recycles `f`, so `split(df, 1:k)` deals rows round-robin by position (verified); df: method; fix: `split(df, df$key %% k)` or `cut()` of a key.
- `base::mapply`, `base::Map`, `base::pmax`/`pmin`, `base::ifelse`, `base::rep_len`, `base::matrix(df$x, ncol = k)`, `base::array`, `` `dim<-` `` — ORDER=D; why: shorter arguments recycle and matrices fill by position (verified for six); df: columns; fix: build the second argument from a column.
- `base::sweep(df, 1, STATS)` — ORDER=D; why: `STATS` is aligned with rows by position (catalog; verified); df: via `as.matrix()`; fix: compute STATS from the same rows, or join by key.
- `stats::lm`, `stats::glm`, `stats::nls`, `stats::model.frame` with `subset = <integer>` or a short logical, `stats::update(fit, subset = -1)` — ORDER=D; why: `subset` is evaluated and used as a row index (models.R:565), integers are positions and a short logical recycles (`subset = c(TRUE, FALSE)` takes every other row) (verified); df: `data =`; fix: a logical subset built from a column, e.g. `subset = t <= 20` (verified I).
- `stats::pairwise.t.test(paired = TRUE)`, `stats::pairwise.wilcox.test(paired = TRUE)`, `stats::t.test(x[g == "a"], x[g == "b"], paired = TRUE)` — ORDER=D; why: the i-th observation of each group is paired by position (catalog for pairwise; verified the manual form); `t.test(y ~ g, paired = TRUE)` and the `wilcox.test` formula now error "cannot use 'paired' in formula method", steering users to `Pair(x, y) ~ 1` on a wide frame, which is I (verified); df: vectors/columns; fix: reshape wide by pair id, then `Pair()`.
- Graphical parameter vectors shorter than the data (`col`, `pch`, `lty`, `cex`) — ORDER=D; why: recycled by row position (catalog conventions; `lattice::parallelplot` default colours, catalog); fix: map aesthetics from a column.
- not data-frame consumers: none beyond the above.

## Implicit index axis (x missing means x = row number)

Checks: t05, t09.

- `stats::lowess(y)`, `stats::smooth.spline(y)`, `stats::isoreg(y)`, `stats::approx(y)`/`approxfun`, `stats::spline(y)`/`splinefun` — ORDER=D; why: `xy.coords(x, NULL)` substitutes `x = seq_along(y)` (xyz.coords.R:66; lowess.R:22, smspline.R:57, approx.R:27, isoreg.R:23), so the fit runs over row index (verified all five; with `x` supplied they sort and are I); df: columns; fix: pass the time column as `x`.
- `graphics::plot(df$y)`, `plot(y ~ 1)`, `matplot(df)`, a 1-column `xy.coords` input — ORDER=D; why: index plot, x = row number (catalog; `plot(df$y)` verified 1.8k px); df: columns; fix: plot against the time column.
- `stats::plot.lm(which = 4)` — ORDER=D; why: Cook's distance is drawn against observation number, `plot(cook, type = "h")` (plot.lm.R:229-235) (verified 4.1k px; `which = 5` 0 px); df: through the fit; fix: sort by a meaningful key before fitting, or plot `cooks.distance(fit)` against a column.
- `stats::monthplot.default` — see time-series section (`times = seq_along(x)`).
- not data-frame consumers: none.

## Plot geometry follows row order

Only items missing from the catalog are listed.
Already covered there: `type = "l"/"b"/"o"/"c"` in `plot`/`plot.formula`/`lines.formula`, `matplot` index x, lattice `xyplot` types "l", "b", "o", "s", `cloud(type = "l")`, `parallelplot` colour recycling, `plot(y ~ 1)`, `barplot.formula` with `cbind()` LHS, `stars` layout, `dotchart`, `levelplot(region.type = "contour")`, `smoothScatter` ties, `chull` indices.
Checks: t02, t05, t06.

- `graphics::plot.data.frame(type = "l")` (2 columns), `graphics::lines(df[c("x", "y")])`, `graphics::plot.default(type = "s" | "S")` — ORDER=D; why: consecutive rows are joined, and a step joins each row to the next (verified 11.8k, 11.8k and 7.4k px; types "p" and "h" 0 px); df: `plot.data.frame` → `plot(x[[1]], x[[2]], type)`, `lines` via `xy.coords`; fix: sort by x (or time) first.
- `graphics::polygon`, `graphics::polypath`, `graphics::xspline` — ORDER=D; why: vertices or spline control points are taken in row order (verified 26k and 8k px); df: columns; fix: order vertices explicitly (e.g. by angle around the centroid).
- `graphics::barplot.default` (vector, or `as.matrix(df)` stacked) — ORDER=S; why: bars and stacked segments appear in row order (verified 24k and 21k px); df: columns or `as.matrix()`; `barplot(df)` errors; fix: sort, or the formula method, which goes through `xtabs()` level order (catalog, I).
- `graphics::pie` — ORDER=S; why: slices are laid out counter-clockwise in row order (verified 21k px); df: column; fix: sort.
- `graphics::image(as.matrix(df))`, `stats::heatmap(…, Rowv = NA)` — ORDER=D; why: matrix row i is drawn at position i (verified 67k and 91k px); the default `heatmap()` reorders rows by dendrogram and was I (0 px); df: `as.matrix()`; `image`/`contour`/`persp`/`filled.contour` with explicit x/y reject unsorted vectors ("increasing 'x' and 'y' values expected", verified); fix: sort rows by a key or let the dendrogram order them.
- `stats::plot.ts`, `stats::ts.plot`, `stats::lag.plot`, `stats::cpgram`, `stats::plot.acf`, `stats::plot.stl`, `stats::plot.decomposed.ts`, `stats::plot.HoltWinters`, `stats::plot.spec`, `stats::monthplot`, `stats::tsdiag` — ORDER=D; why: the time axis is the row position and lines join consecutive rows (verified 1.8k–14.8k px each); df: `plot.ts(df)`, `ts.plot(df)`, `lag.plot(df)` accept a df via `as.ts()`, the rest need a column or a fit; fix: sort and set start/frequency.
- `lattice::xyplot.ts` — ORDER=D; why: `xyplot(ts(df))` draws each column with `type = "l"` against position-derived time (xyplot.ts.R:48; verified 7.7k px); df: via `ts(df)`; fix: sort first, or `xyplot(y ~ t, df[order(df$t), ], type = "l")`.
- `lattice::panel.polygon`, `lattice::panel.lines` in custom panels — ORDER=D; why: draw vertices in the order the panel receives rows (verified 12k px); df: formula `data =`; fix: sort inside the panel (`o <- order(x)`).
- `nlme::plot.groupedData` (`plot.nfnGroupedData`) with `outer =` or `inner =` — ORDER=D; why: `panel.superpose(…, type = "l")` (groupedData.R:418) joins each subject's points in row order (verified 8.5k px); the default panel averages y per x and sorts (groupedData.R:372-379), I (0 px); df: a `groupedData`; fix: sort by group, then covariate.
- Contrast (verified I, 0 px): lattice `barchart`/`dotplot` with a character label (sorted factor levels), `interaction.plot` (cells via `tapply`), `plot(ecdf(x))`, `xyplot(type = "smooth")`, default `heatmap()`. `biplot(prcomp(df))` differed only through prcomp's arbitrary signs (hidden, catalog).
- not data-frame consumers: `graphics::persp`, `contour`, `filled.contour` (matrix + sorted grid vectors), `grDevices::as.raster` (no data-frame method; matrix rows are pixel rows).

## Serial correlation / grouped sequences (recommended packages)

Checks: t07, t08, t16.

- `nlme::corAR1`, `corARMA`, `corCAR1`, `corSymm`, `corNatural`, `corExp`, `corGaus`, `corLin`, `corRatio`, `corSpher` without a covariate (`form = ~ 1 | g`) in `gls`, `lme`, `gnls`, `nlme` — ORDER=D; why: the time is `seq_along` within group (corStruct.R:206-208), or `1:nrow(data)` without groups, so within-group and global permutations change logLik (catalog; re-verified on `Ovary` for corAR1, corARMA, corCAR1, corExp, lme + corAR1); df: `data =`; fix: `form = ~ time | g` with an explicit covariate, which was I for corAR1/corARMA (integer visit index) and corCAR1/corExp (continuous `Time`) (verified).
- `nlme::corAR1(form = ~ t | g)` with an integer covariate — ORDER=I for the fit, S for the class; why: when within-group diffs of `t` in row order are not all 1, it silently becomes `corARMA(1, 0)` (corStruct.R:963-969), which indexes by `t`; sorted rows fit "corAR1", permuted rows "corARMA" with identical logLik and phi (verified); a non-integer `t` errors with a message naming "corARMA"; fix: none needed, but expect either class.
- `nlme::corCompSymm` — ORDER=I; why: exchangeable within group (verified); listed as the order-free control.
- `nlme::ACF.gls` — ORDER=D; why: the help page says `form = ~ t | g` gives a time covariate, but the code reads only `getGroupsFormula(form)` (gls.R:368) and lags by within-group position (gls.R:405-409), so `t` is ignored (verified D with `form = ~ tidx | Mare`); df: through the fit; fix: sort by (g, t) and insert NA rows for missing times before fitting.
- `nlme::ACF.lme` — ORDER=D; why: no `form` at all, lags are positions within the innermost group (lme.R:837-849) (catalog; verified); df: through the fit; fix: as for `ACF.gls`.
- `nlme::Variogram` (`.gls`, `.lme`, `.default`) — ORDER=D with the default `form = ~ 1` (distance = position within group), I with `form = ~ Time | g` (verified both); df: through the fit; fix: give the covariate.
- `nlme::groupedData` — ORDER=E; why: rows stay in input order, the grouping factor is re-levelled by max response, which is I (catalog; verified); df: constructor; fix: none.
- `MASS::glmmPQL(correlation = corAR1())` — ORDER=D without a covariate (catalog); fix: `corAR1(form = ~ t | g)`.
- `mgcv::bam(rho =, AR.start =)` — ORDER=D; why: AR1 whitening pairs each row with the previous one, and `AR.start` rows restart the chain (bam.r:478-492); global and within-series permutations change the fit, reordering whole series blocks does not (verified); df: `data =`, `AR.start` is a logical column; fix: sort by (series, time), then `AR.start = !duplicated(series)`.
- `mgcv::bam.update` with `rho != 0` — ORDER=D; why: carries the last whitened row into the next batch (catalog); fix: append batches in time order.
- `mgcv::gamm(correlation = corAR1(form = ~ t | g))` — ORDER=I with the covariate (verified), D without it (catalog); fix: name the covariate.
- `boot::tsboot` — ORDER=D; why: resamples blocks of consecutive rows (`sim = "fixed"`/`"geom"`) or rebuilds series from a model; df: accepted, it does `as.matrix()` and restores the class, so the statistic receives data frames (bootfuns.q:3245-3248; verified); fix: sort by time, one series per call.
- `MASS::lm.gls` — ORDER=D; why: `W` is an n×n matrix indexed by row position, factored by `eigen(W)` (lm.gls.R:31-34) (catalog; verified); df: `data =`; fix: build `W` from the time column after sorting, or permute `W` with the rows.
- `survival::tmerge` (`tdc`, `cumtdc`, `event`, `cumevent`) — ORDER=I without tied times; why: cumulative covariates look sequential but data2 is sorted by `order(match(id, baseid), etime)` (tmerge.R:297), so permuting data1 or data2 left the sorted output identical (verified); tied (id, time) is D (catalog); df: data frames; fix: none, or break ties.
- `survival::survSplit`, `survival::aeqSurv` — ORDER=E (verified); `survival::cluster(id)` robust variance in `coxph` — I (verified); `survival::survfit` multi-state with `id`, `survival::survcheck` — I, they sort by id and time (verified).
- `survival::survcondense` (D, a bug with unsorted input) and `survival::neardate` (D on tied dates) — catalog.
- not data-frame consumers: `nlme::corMatrix`, `nlme::Initialize` (take corStruct objects).

## Sorts internally: sequence-looking but order-free

Checks: t08, t10.

- `splines::interpSpline`, `splines::periodicSpline`, `splines::backSpline`, `stats::splinefun(method = "hyman" | "monoH.FC")`, `stats::ksmooth`, `stats::ecdf`, `stats::sortedXyData`, `stats::NLSstClosestX`, `base::cut` — ORDER=I (verified); why: they sort x (and pool ties) before using neighbour structure; df: columns.
- `stats::approx`, `stats::spline`, `stats::isoreg`, `stats::lowess`, `stats::smooth.spline` with `x` supplied — ORDER=I (verified for isoreg and lowess; catalog for the rest); D only when `x` is missing (index axis above).
- `survival::tmerge`, `cumtdc`, `cumevent`, `survfit(id =)`, `survcheck` — ORDER=I (verified); why: sort by id and time internally.
- `nlme::Variogram(form = ~ t | g)` and covariate-based `cor*` classes — ORDER=I (verified).
- `stats::stepfun`, `base::findInterval` — reject unsorted input ("'x' must be ordered increasingly", "'vec' must be sorted non-decreasingly"), so they cannot be silently order-dependent (verified).
- `zoo::zoo(…, order.by =)` (CRAN, the fix used above) — ORDER=I up to row names; why: sorts by its index, and `acf()`/`lag()` on it matched under permutation (verified).

## Online / sequential algorithms

Checks: t14.

- `stats::kmeans(algorithm = "MacQueen")` — ORDER=D per pass; why: centres move after each row, in row order (verified after one iteration; the converged result matched on well-separated data); Hartigan–Wong and Lloyd with fixed centres were I here; df: `as.matrix()`; fix: Lloyd, or several random starts (catalog for ties and random starts).
- `class::SOM`, `class::lvq1`/`lvq2`/`lvq3`/`olvq1`, `cluster::clara` — ORDER=R; why: online updates on randomly drawn row positions (catalog).

## Packages with no by-design sequence consumers

`methods`, `tools`, `compiler`, `stats4` (`mle` is I), `parallel` (E; see positional section), `grDevices` (only `xy.coords`, catalog), `KernSmooth`, `spatial`, `rpart`, `nnet`, `foreign`, `Matrix`, `codetools`, `class`/`cluster` beyond the R entries above.
Their hidden dependences (ties, random folds, first-appearance levels) are in `catalog.md`.
