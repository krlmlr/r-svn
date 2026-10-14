# CRAN depth 1–3: data-frame consumers that depend on row order by design

Scope: functions in the 1,038 CRAN packages of dependency depth 1–3 (`selected.tsv`)
that treat rows as a sequence on purpose and that a data frame reaches,
either directly, through `data =` and a formula, as a column, or after an internal coercion.
This complements `catalog.md`, which recorded only *hidden* order dependence.

Method: the R sources in `src/<pkg>/R` were grepped for sequence primitives
(`shift`, `lag`, `diff`, `cum*`, `rle`/`rleid`, `embed`, rolling and fill functions, `acf`, `ts`/`zoo`/`xts`, `.I`/`.GRP`, `order.by`),
and exported names were scanned for sequence vocabulary (roll, run, lag, cum, locf, diff, first/last, drawdown, cusum, ewma, accum, runs).
"verified" means a script in `order/tests_cran/` compares the result on a data frame with the result on the same rows permuted
(`df[p, ]`, fixed permutation or seed, row-aligned outputs mapped back),
run with R 4.5.3 and CRAN binaries whose versions match the scanned sources.
The scripts print `ORDER-FREE` or `CHANGES under permutation` per check; `helper.R` holds the shared fixture.
"from source" cites `src/<pkg>/R/<file>:<line>`.

Every entry below is ORDER=D unless the line says otherwise.
Depth is the package's CRAN dependency depth from `selected.tsv`.
Base R and recommended packages (depth 0, e.g. `stats::filter`, `stats::acf`, `nlme::corAR1`, `survival::tmerge`) are out of scope here.

## Lags, leads and differences

- `data.table::shift` (types lag/lead/shift/cyclic) — ORDER=D; depth=1; why: returns the value n rows earlier or later; a data frame or list is shifted column by column, and `by=` shifts within groups in row order; df: `shift(df)`, `DT[, l := shift(x), by = g]`; fix: sort first (`setorder(DT, g, t)` or `DT[order(t), ..., by = g]`, verified order-free); evidence: verified (t_datatable.R), shift.R:1
- `collapse::flag` / `L`, `collapse::fdiff` / `D`, `collapse::fgrowth` / `G` (default, matrix, data.frame, grouped_df, pdata.frame methods) — ORDER=D; depth=2; why: lag, difference and growth rate by row position within groups `g` when no time variable is given; df: `flag(df, n, g)`, `L(df, by = ~id, t = ~t)`; fix: pass `t =` (time ids, verified order-free); evidence: verified (t_collapse.R)
- `zoo::as.zoo.data.frame` (and `zoo(df)` without `order.by`) followed by `lag`/`diff` — ORDER=D; depth=1; why: the index defaults to 1..n, so lags and differences follow row position; df: `as.zoo(df)`; fix: `read.zoo(df)` or `zoo(df[cols], order.by = df$date)`, which sort (verified); evidence: verified (t_zoo_xts.R), as.zoo.R:21
- `timeSeries::lag` (timeSeries method) — ORDER=D; depth=2; why: `timeSeries(df, charvec)` keeps rows in input order, unsorted, and `lag()` shifts by position; df: `timeSeries(df[cols], charvec = df$date)`; fix: `sort(x)` first (verified); `returns()` already sorts; evidence: verified (t_timeseries.R), fin-returns.R:103
- `tsModel::Lag` — ORDER=D; depth=1; why: lagged copies by position, restarting per `group` (used for distributed-lag exposures in epidemiological time series); df: `Lag(df$x, k, group = df$id)`; fix: inherent, sort by group and time; evidence: verified (t_misc3.R)
- `dlnm::crossbasis` — ORDER=D; depth=2; why: builds the exposure-by-lag basis from x at row lags 0..L; `group` only restarts the series, so rows must be consecutive equally spaced times; df: `crossbasis(df$x, lag = L, ...)` then `glm(..., data = df)`; fix: inherent; evidence: verified (t_misc3.R)
- `lubridate::int_diff` — ORDER=D; depth=3; why: intervals between consecutive elements of a date-time vector; df: `int_diff(df$time)`; fix: sort the times first; evidence: verified (t_misc1.R)
- `psych::mssd`, `psych::rmssd` — ORDER=D; depth=2; why: mean square successive difference (von Neumann) per column at `lag`, optionally within `group`, so rows must be time-ordered within subject; df: `mssd(df, group = df$id)`; fix: inherent, sort by group and time; evidence: verified (t_misc1.R)
- `psych::autoR` — ORDER=D; depth=2; why: lag-1 autocorrelation per column, optionally within `group`; df: `autoR(df, group = )`; fix: inherent; evidence: verified (t_misc1.R)
- `datawizard::smoothness` (data.frame method) — ORDER=D; depth=2; why: per column, lag-`lag` autocorrelation (`method = "cor"`) or mean absolute successive difference (`"diff"`); df: `smoothness(df)`; fix: inherent; evidence: verified (t_misc5.R)
- `matrixStats::colDiffs`, `rowDiffs`, `diff2` — ORDER=D; depth=1; why: successive differences down each column; df: a data frame is rejected (error), so only via `as.matrix(df)`; fix: inherent; evidence: verified (t_misc3.R)
- `TTR::ROC`, `TTR::momentum` — ORDER=D; depth=3; why: rate of change x[t]/x[t−n] and difference x[t]−x[t−n]; df: column, or a data frame whose integer row names make `try.xts()` fall back to `as.matrix()`; fix: date row names or an xts input (sorted); evidence: verified ROC (t_zoo_xts.R)
- `udpipe::txt_next`, `txt_previous`, `txt_nextgram` — ORDER=D; depth=2; why: token n positions ahead or behind, or the n-gram starting at each row of a token column; df: a column of the one-row-per-token annotation frame; fix: sort by doc_id, sentence_id, token_id; evidence: verified txt_next (t_misc3.R), utils.R:232,401

## Rolling / running windows

- `data.table::frollmean`, `frollsum`, `frollmax`, `frollmin`, `frollprod`, `frollmedian`, `frollvar`, `frollsd`, `frollapply` — ORDER=D; depth=1; why: windows of n consecutive rows (right, left or centre aligned); a data frame or list rolls every column; `by=` rolls within groups in row order; df: `frollmean(df[cols], n)`, `DT[, m := frollmean(x, n), by = g]`; fix: sort first; time-based windows via `frolladapt(index, n)` plus `adaptive = TRUE`, which refuses an unsorted index; evidence: verified frollmean/frollapply/frolladapt (t_datatable.R), froll.R:115,153
- `zoo::rollapply` (default method, used for data frames), `rollmean`, `rollsum`, `rollmax`, `rollmedian` — ORDER=D; depth=1; why: windows over positions 1..n of a vector or each column of a data frame; df: `rollapply(df[cols], width, FUN)`; fix: build a zoo with `order.by`/`read.zoo` first (windows then follow time, still by observation count); evidence: verified (t_zoo_xts.R), rollapply.R:38, rollmean.R:54
- `TTR::SMA`, `EMA`, `WMA`, `DEMA`, `RSI`, `MACD`, `BBands`, `ATR`, `ADX`, `stoch`, `CCI`, `runSum`, `runMean`, `runSD`, `runMax`, `runPercentRank` — ORDER=D; depth=3; why: technical indicators over preceding rows; EMA- and Wilder-type recursions make every value depend on all earlier rows; df: column, or a data frame (HLC for `ATR`) via `try.xts(x, error = as.matrix)`, which keeps row order when row names are not dates; fix: date row names or xts (sorted; output comes back in time order); evidence: verified SMA/EMA/RSI/ATR/runSD (t_zoo_xts.R), MovingAverages.R:174
- `RcppRoll::roll_mean`, `roll_sum`, `roll_sd`, `roll_var`, `roll_median`, `roll_max`, `roll_min`, `roll_prod` (and l/r variants) — ORDER=D; depth=1; why: fixed-width windows down each column; df: a data frame is rejected (error), so `as.matrix(df)` or a column; fix: inherent; evidence: verified (t_misc3.R)
- `roll::roll_mean`, `roll_sd`, `roll_cor`, `roll_cov`, `roll_scale`, `roll_lm` — ORDER=D; depth=3; why: rolling (optionally exponentially weighted) statistics and regressions over the last `width` rows; df: a data frame is rejected (error), so matrix or columns; fix: inherent; evidence: verified roll_lm (t_misc3.R)
- `caTools::runmean`, `runmin`, `runmax`, `runquantile`, `runmad`, `runsd` — ORDER=D; depth=2; why: moving-window statistics down a vector or each matrix column; df: column or `as.matrix(df)`; fix: inherent; evidence: verified runmean (t_misc2.R)
- `gtools::running` — ORDER=D; depth=1; why: applies `fun` to successive windows of `width` consecutive elements; df: column; fix: inherent; evidence: verified (t_misc2.R)
- `tsModel::runMean` — ORDER=D; depth=1; why: mean over lags 0..k by position (moving-average exposure); df: column; fix: inherent; evidence: verified (t_misc3.R)
- `timeSeries::rollMean`, `rollMin`, `rollMax`, `rollStats` — ORDER=D; depth=2; why: windows by position over the stored rows, which the constructor does not sort; df: `timeSeries(df, charvec)`; fix: `sort(x)` first; evidence: verified rollMean (t_timeseries.R)
- `pracma::movavg` — ORDER=D; depth=1; why: simple, triangular, weighted, modified, exponential and running moving averages along the vector; df: column; fix: inherent; evidence: verified (t_misc2.R), movavg.R:6
- `pracma::hampel` — ORDER=D; depth=1; why: a point is an outlier relative to the median and MAD of its k neighbours on each side; df: column; fix: inherent; evidence: verified with a spike (t_misc2.R), hampel.R:6

## Cumulative operations and carry-forward fills

- `data.table::nafill`, `setnafill` (`type = "locf"`/`"nocb"`) — ORDER=D; depth=1; why: fills NA with the previous or next non-missing value in row order, column by column for a data frame; df: `nafill(df, "locf")`, `setnafill(DT, "locf", cols = )`; fix: sort first, group with `DT[order(t), x := nafill(x, "locf"), by = g]`; evidence: verified (t_datatable.R), shift.R:29,34
- `data.table` `cumsum`/`cumprod`/`cummax` inside `DT[, ..., by = g]` — ORDER=D; depth=1; why: running totals within each group in row order; df: any data.table; fix: `DT[order(t), ..., by = g]`; evidence: verified (t_datatable.R)
- `collapse::fcumsum` — ORDER=D; depth=2; why: cumulative sums within groups `g` in row order; df: `fcumsum(df, g)`; fix: `o =` ordering vector (verified order-free); evidence: verified (t_collapse.R)
- `collapse::na_locf`, `na_focb` — ORDER=D; depth=2; why: last observation carried forward / first observation carried back by position; df: vectors or data-frame columns; fix: sort first; evidence: verified (t_collapse.R)
- `zoo::na.locf` (default and data.frame methods) — ORDER=D; depth=1; why: carries the last non-NA value down each column of a data frame; df: `na.locf(df)`; fix: sort first; evidence: verified (t_zoo_xts.R), na.locf.R:29,53
- `zoo::na.approx`, `na.spline` (default methods) — ORDER=D; depth=1; why: interpolate NAs against `x = index(object)`, which is 1..n for a vector or data frame; df: column or data frame; fix: `x = df$time` (verified order-free); evidence: verified (t_zoo_xts.R), na.approx.R:49
- `vctrs::vec_fill_missing` — ORDER=D; depth=3; why: fills missing rows of a data frame (whole-row missingness) "down", "up" or both, the primitive behind tidyverse fill operations; df: data frames natively; fix: sort first; evidence: verified (t_misc1.R)
- `matrixStats::colCumsums`, `colCumprods`, `colCummaxs`, `colCummins` (and row variants) — ORDER=D; depth=1; why: cumulative operations down each column; df: a data frame errors, so `as.matrix(df)`; fix: inherent; evidence: verified (t_misc3.R)
- `Rfast::colCumSums`, `colCumProds`, `colCumMaxs`, `colCumMins` — ORDER=D; depth=3; why: column-wise cumulative operations; df: `as.matrix(df)`; fix: inherent; evidence: verified colCumSums (t_misc3.R)
- `metafor::cumul` (rma.uni, rma.mh, rma.peto methods) — ORDER=D; depth=3; why: cumulative meta-analysis refits after adding one study at a time in row order; df: `cumul(rma(yi, vi, data = df))`; fix: `order =` with a unique key (tied years keep row order, verified); evidence: verified (t_misc2.R), cumul.rma.uni.r:1
- `rmeta::cummeta` — ORDER=D; depth=1; why: cumulative Mantel–Haenszel or DerSimonian–Laird summaries over studies in row order; df: `cummeta(..., data = df)`; fix: inherent, sort rows first; evidence: verified (t_misc2.R)
- `vegan::specaccum(method = "collector")` — ORDER=D; depth=2; why: species accumulation curve adding sites in row order of the community data frame; df: sites × species data frame; fix: `method = "exact"` (verified order-free) or `"random"`; evidence: verified (t_misc1.R)
- `PerformanceAnalytics::maxDrawdown`, `Drawdowns`, `findDrawdowns`, `table.Drawdowns`, `CalmarRatio`, `Return.portfolio`, `chart.CumReturns` — ORDER=D for a numeric vector, order-free for a data frame; depth=3; why: compounding wealth paths and peak-to-trough runs; `checkData()` only accepts data frames with date row names and converts them to sorted xts; df: `maxDrawdown(df)` (sorted) vs `maxDrawdown(df$r)` (positional); fix: pass the data frame with dates, not a column; evidence: verified (t_zoo_xts.R), checkData.R:45, maxDrawdown.R:44

## Run-length and sequence ids

- `data.table::rleid`, `rleidv` — ORDER=D; depth=1; why: id that increments whenever the value (or any of `cols`) differs from the previous row; df: `rleidv(df, cols)`; fix: sort first; evidence: verified (t_datatable.R), data.table.R:3164,3168
- `data.table::rowid`, `rowidv` — ORDER=D; depth=1; why: occurrence counter 1, 2, 3 within each group in row order; df: `rowidv(df, cols)`; fix: sort by group and time first; evidence: verified (t_datatable.R), data.table.R:3139,3143
- `data.table` `.GRP` and `.I` in grouped `j` — ORDER=D with `by=`; depth=1; why: `.GRP` numbers groups by first appearance under `by=`, and `.I[1]` is the first row of each group; fix: `keyby=` numbers groups in sorted order (verified); evidence: verified (t_datatable.R)
- `collapse::groupid` — ORDER=D; depth=2; why: run id of consecutive equal values, like `rleid`; df: column or list; fix: `o =` or sort first; evidence: verified (t_collapse.R)
- `collapse::seqid` — ORDER=D; depth=2; why: id of runs of consecutive integers, such as unbroken time spells in a panel; df: column; fix: `o =` ordering argument; evidence: verified (t_collapse.R)
- `vctrs::vec_identify_runs`, `vec_run_sizes`, `vec_group_rle` — ORDER=D; depth=3; why: run ids and run lengths of consecutive equal rows of a data frame (all columns compared); df: data frames natively; fix: sort first; evidence: verified (t_misc1.R)
- `splitstackshape::getanID` — ORDER=D; depth=2; why: adds `.id`, the occurrence counter within `id.vars` in row order, to make duplicated ids unique; df: data frame or data.table; fix: sort first; evidence: verified (t_misc2.R)
- `PhysicalActivity::wearingMarking` (via `marking`) — ORDER=D; depth=1; why: non-wear time is a run of ≥ `frame` consecutive zero-count rows (with an allowance), located by row position, not by timestamp; df: accelerometer data frame with timestamp and counts; fix: sort by timestamp, with one row per minute; evidence: verified (t_physact.R), marking.R
- `evd::clusters`, `evd::exi`, `evd::fpot(cmax = TRUE)` — ORDER=D; depth=1; why: runs declustering joins exceedances fewer than `r` positions apart into one cluster, which drives the extremal index and cluster-maxima fits; df: column; fix: inherent (`fpot` with the default `cmax = FALSE` is order-free, verified); evidence: verified (t_misc7.R), stocproc.R:119

## First/last and positional selection

- `data.table::first`, `last` (and `head`/`tail` in grouped `j`, optimised by GForce) — ORDER=D; depth=1; why: first or last row of a data frame, or first or last element per group; df: `first(df)`, `DT[, first(x), keyby = g]`; fix: sort first; evidence: verified (t_datatable.R), last.R:5,46
- `data.table` joins with `mult = "first"`/`"last"`, and rolling joins (`roll =`) into a lookup table with duplicated keys — ORDER=D; depth=1; why: among equal keys the row is chosen by position; with unique keys the lookup is sorted on `on =` and order-free (verified); df: `X[i, on = , roll = TRUE]`; fix: deduplicate the lookup table or add a tiebreak key; evidence: verified (t_datatable.R)
- `data.table::frank(ties.method = "first")`, `dcast(fun.aggregate = function(v) v[1])` — ORDER=D; depth=1; why: ties ranked by position, cell value taken from the first row; df: column / data.table; fix: another `ties.method`, an order-free aggregate; evidence: verified (t_datatable.R)
- `collapse::ffirst`, `flast` (default, matrix, data.frame, grouped_df) — ORDER=D; depth=2; why: first or last (non-NA by default) value per group; df: `ffirst(df, g)`; fix: `roworder(df, t)` first (verified); evidence: verified (t_collapse.R)
- `collapse::fslice` — ORDER=D with `how = "first"`/`"last"`; depth=2; why: keeps the first or last n rows per group; with `how = "min"`/`"max"` and `order.by` the rows are chosen by value but returned in first-appearance group order (S); df: `fslice(df, "id", n = 1)`; fix: `how = "min"`/`"max"` plus `order.by`; evidence: verified (t_collapse.R)
- `collapse::fmode` — ORDER=D on ties; depth=2; why: the default `ties = "first"` returns the first-appearing of several modes; df: column or data frame; fix: `ties = "min"` or `"max"`; evidence: verified (t_collapse.R)
- `gdata::first`, `last` — ORDER=D; depth=2; why: thin wrappers around `head()`/`tail()`, so the first or last n rows of a data frame; df: direct; fix: sort first; evidence: from source (first.R:1-2)

## Time-series models and tests on row sequence

- `KFAS::SSModel` (then `fitSSM`, `KFS`, `logLik`) — ORDER=D; depth=1; why: rows of `data` are consecutive time points of a state-space model; the Kalman filter and smoother run down the rows; df: `SSModel(y ~ SSMtrend(...), data = df)`; fix: inherent, sort by time; evidence: verified log-likelihood (t_misc4.R)
- `dlm::dlmFilter`, `dlmSmooth`, `dlmLL`, `dlmMLE` — ORDER=D; depth=1; why: Kalman recursions over observations in row order; df: column or `as.matrix(df)`; fix: inherent; evidence: verified dlmLL (t_misc6.R)
- `bsts::bsts` — ORDER=D; depth=3; why: Bayesian structural time series with rows as time points; `timestamps =` does not rescue unsorted gap-free rows (see "Bugs"); df: `bsts(y ~ x, ss, data = df)`; fix: sort rows by time; evidence: verified (t_bsts.R, t_bsts2.R)
- `stochvol::svlm`, `svsample` — ORDER=D; depth=3; why: errors follow an AR(1) log-variance (stochastic volatility) process over the rows; df: `svlm(y ~ x, data = df)` or a column; fix: inherent; evidence: from source (wrappers.R:209,1372)
- `urca::ca.jo`, `ca.po` — ORDER=D; depth=1; why: Johansen and Phillips–Ouliaris cointegration tests take the columns of a data frame as series and its rows as time; df: `ca.jo(df)` directly; fix: inherent; evidence: verified (t_econ.R), ca-jo.R:4, ca-po.R:4
- `urca::ur.df`, `ur.pp`, `ur.kpss`, `ur.ers`, `ur.za`, `ur.sp` — ORDER=D; depth=1; why: unit-root and stationarity tests on lags and differences of the series; df: column; fix: inherent; evidence: verified ur.df (t_econ.R), others from source (ur-pp.R:4, ur-kpss.R:4, ur-ers.R:4, ur-za.R:4)
- `strucchange::efp`, `Fstats`, `breakpoints`, `recresid`, `sctest.formula` (incl. `type = "Chow"`), `mefp`/`monitor` — ORDER=D; depth=3; why: CUSUM/MOSUM fluctuation processes, sup-F over candidate breaks and segment partitions all treat row order as time; df: `efp(y ~ x, data = df)`; fix: sort data; only `gefp(..., order.by = )` sorts internally (verified); evidence: verified (t_econ.R), efp.R:1, Fstats.R:1, breakpoints.R:20
- `lmtest::grangertest` — ORDER=D; depth=2; why: Granger causality regresses on lagged values built with `lag()` by row; df: `grangertest(y ~ x, order = k, data = df)`; fix: inherent, sort by time; evidence: verified (t_econ.R), grangertest.R:7
- `changepoint::cpt.mean`, `cpt.var`, `cpt.meanvar` — ORDER=D; depth=2; why: change points along the series; df: column only, since a data frame errors ("Only numeric data allowed") and each *row* of a matrix is a separate series (row order then free, verified); fix: inherent; evidence: verified (t_misc4.R)
- `ecp::e.divisive`, `e.agglo` — ORDER=D; depth=2; why: nonparametric multiple change-point analysis of a T × d matrix whose rows are time-ordered; df: `as.matrix(df)`; fix: inherent; evidence: verified e.divisive (t_misc4.R)
- `Kendall::MannKendall`, `SeasonalMannKendall` — ORDER=D; depth=1; why: Kendall's tau between the series and its position (monotone trend test); df: column; fix: inherent (use `Kendall(x, time)` for an explicit time); evidence: verified MannKendall (t_misc2.R)
- `lawstat::runs.test` — ORDER=D; depth=3; why: Wald–Wolfowitz test on runs above and below the median in sequence; df: column; fix: inherent; evidence: verified (t_misc2.R)
- `randtoolbox::gap.test`, `serial.test`, `poker.test`, `order.test` — ORDER=D; depth=2; why: tests of i.i.d. uniform sequences count gaps, serial pairs and hands in order (`freq.test` is order-free); df: column; fix: inherent; evidence: verified gap.test (t_misc5.R)
- `pastecs::turnpoints`, `trend.test`, `AutoD2`, `CrossD2`, `decaverage`, `tsd` — ORDER=D; depth=1; why: turning points, trend tests, multivariate autocorrelation and decompositions of regular series; df: column or `as.ts(df)` for `AutoD2`; fix: inherent; evidence: verified turnpoints/trend.test/AutoD2 (t_misc5.R)
- `astsa::acf2`, `sarima`, `lag1.plot` — ORDER=D; depth=1; why: sample ACF/PACF and seasonal ARIMA fits of the series; df: column; fix: inherent; evidence: verified acf2 (t_misc5.R)
- `seasonal::seas` — ORDER=D; depth=2; why: X-13ARIMA-SEATS seasonal adjustment; the input must be a `ts`, so a column reaches it as `ts(df$y, start, frequency)`; fix: inherent; evidence: from source (seas.R:28,217)
- `airGR::CreateInputsModel` with `RunModel_GR4J` and the other GR/CemaNeige models — ORDER=D; depth=1; why: rainfall–runoff simulation steps through rows as consecutive time steps; `DatesR` is checked only for duplicates, and the time step is read from the last two rows; df: `CreateInputsModel(FUN, DatesR = df$DatesR, Precip = df$P, PotEvap = df$E)`; fix: sort by date; evidence: verified (t_airgr.R: other rows permuted silently change Qsim, the last two permuted error), Utils.R:37-39, CreateInputsModel.R:30-32
- `oce::ctdTrim`, `ctdFindProfiles`, `despike` — ORDER=D; depth=2; why: CTD processing finds the downcast and the profiles from the pressure sequence in scan (row) order, and `despike` uses running medians; df: `as.ctd(df)`, column; fix: inherent (`ctdDecimate`, binning by pressure, is order-free, verified); evidence: verified (t_oce.R)
- `qcc::qcc` (run rules; `type = "xbar.one"` limits), `qcc::cusum`, `qcc::ewma` — ORDER=D; depth=1; why: Shewhart run rules flag consecutive points on one side, individuals limits use moving ranges, CUSUM and EWMA accumulate over samples in row order (`type = "xbar"` limits are order-free, verified); df: `qcc.groups(df$v, df$sample)` or a samples × replicates data frame; fix: inherent; evidence: verified (t_misc2.R)

## MCMC output (rows are iterations)

- `coda::effectiveSize`, `geweke.diag`, `heidel.diag`, `raftery.diag`, `autocorr`, `autocorr.diag`, `batchSE`, `spectrum0.ar`, `gelman.diag`, `summary.mcmc` (time-series SE) — ORDER=D; depth=1; why: spectral density at zero, early versus late segments, two-state Markov transitions and batch means all use iteration order; df: `mcmc(df)`, `as.mcmc(df)`, and `effectiveSize(df)` directly; fix: inherent (means, quantiles and `HPDinterval` are order-free, verified); evidence: verified (t_mcmc.R; `raftery.diag` with 5,000 draws)
- `LaplacesDemon::ESS`, `MCSE`, `IAT`, `Geweke.Diagnostic`, `burnin`, `BMK.Diagnostic`, `is.stationary` — ORDER=D; depth=1; why: effective sample size, Monte Carlo SE, integrated autocorrelation time and stationarity checks over iterations; df: `ESS(df)` directly, others via column or `as.matrix(df)`; fix: inherent; evidence: verified ESS/MCSE/IAT/Geweke.Diagnostic/burnin (t_mcmc.R)
- `mcmc::initseq`, `olbm` — ORDER=D; depth=1; why: Geyer initial-sequence and overlapping-batch-means variance estimates; df: column or `as.matrix(df)`; fix: inherent; evidence: verified (t_mcmc.R)

## Serial-correlation-robust inference (HAC, DW)

- `sandwich::NeweyWest`, `vcovHAC`, `kernHAC`, `meatHAC`, `weightsAndrews`, `weightsLumley`, `bwAndrews`, `bwNeweyWest` — ORDER=D; depth=2; why: kernel-weighted cross-products of estimating functions at row lags 1..L, with the bandwidth from an AR(1) fit to them; df: any model fitted with `data = df`; fix: `order.by = ~t` (verified order-free); evidence: verified (t_econ.R), vcovHAC.R:9,129,242,417
- `sandwich::lrvar` — ORDER=D; depth=2; why: long-run (HAC) variance of the mean of a series; df: column; fix: inherent, no `order.by`; evidence: verified (t_econ.R), lrvar.R:1
- `sandwich::vcovPL`, `meatPL` — ORDER=D; depth=2; why: panel Newey–West (Driscoll–Kraay type) lags taken in row order within clusters; df: model fitted with `data = df`; fix: `order.by = ~t` (verified order-free); evidence: verified (t_econ.R), vcovPL.R:18
- `sandwich::vcovPC`, `meatPC` (balanced panels) — ORDER=D; depth=2; why: residuals are split by cluster in row order and X is combined with `kronecker(sigma, I_t)`, so rows must be sorted cluster-major with a common time order; `order.by` only tests balance; df: model fitted with `data = df`; fix: `df[order(df$id, df$t), ]` before fitting (`order.by` does not help, verified); evidence: verified (t_econ.R, t_vcovpc.R), vcovPC.R:90-106
- `lmtest::dwtest`, `bgtest`, `harvtest` — ORDER=D; depth=2; why: Durbin–Watson, Breusch–Godfrey and Harvey–Collier statistics use lagged or recursive residuals in row order; df: `dwtest(y ~ x, data = df)`; fix: `order.by = ~t` (verified); evidence: verified (t_econ.R), dwtest.R:1, bgtest.R:1, harvtest.R:1
- `lmtest::gqtest`, `hmctest`, `raintest` — ORDER=D; depth=2; why: split or trim the sample by row position (Goldfeld–Quandt break point, Harrison–McCabe, Rainbow central fraction); df: `gqtest(y ~ x, data = df)`; fix: `order.by = ~z`, sorting by the suspected variance driver; evidence: verified (t_econ.R), gqtest.R:1-36, raintest.R:1
- `gmm::gmm` (default `vcov = "HAC"`) — ORDER=D; depth=3; why: the default optimal weighting matrix and covariance use a Quadratic-Spectral HAC with Andrews bandwidth and AR(1) prewhitening over row order, so even cross-sectional two-step IV coefficients change; df: `gmm(y ~ x, ~ z1 + z2, data = df)`; fix: `vcov = "iid"` or `"MDS"` for cross-sections (both verified order-free); evidence: verified coefficients and vcov (t_econ.R), gmm.R:14-16

## Signal processing and spectra

- `signal::filter`, `filtfilt`, `sgolayfilt`, `fftfilt`, `decimate`, `resample`, `medfilt1` — ORDER=D; depth=1; why: digital filters and resampling along the sample axis; df: column; fix: inherent; evidence: verified filter/sgolayfilt (t_misc4.R)
- `gsignal::filter`, `filtfilt`, `sgolayfilt`, `medfilt1`, `detrend`, `pwelch` — ORDER=D; depth=2; why: filters and spectra along rows; a data frame is accepted and filtered column by column (rows are samples); df: `filtfilt(butter(2, .3), df)`; fix: inherent; evidence: verified filtfilt (data frame in, data frame out) and medfilt1 (t_misc4.R)
- `seewave::env`, `zcr`, `meanspec`, `spec`, `spectro`, `ffilter`, `timer` and the other functions reading input through `inputw()` — ORDER=D; depth=3; why: a data frame is taken as a wave (column `channel`, rows are samples), so envelopes, zero-crossing rates and spectra follow row order (`rms` is order-free); df: `env(df, f = 8000)`; fix: inherent; evidence: verified env/zcr/meanspec (t_misc5.R), seewave.r:8713
- `wavelets::dwt`, `modwt`, `mra` — ORDER=D; depth=1; why: wavelet transforms along the time axis; documented to accept data frames (dwt.R:4) but a data frame errors ("'list' object cannot be coerced"), so a column or matrix; fix: inherent; evidence: verified (t_misc4.R)
- `waveslim::dwt`, `modwt`, `mra` — ORDER=D; depth=2; why: wavelet decompositions of the series; df: column; fix: inherent; evidence: verified modwt (t_misc5.R)
- `dtw::dtw` — ORDER=D; depth=2; why: dynamic time warping aligns two sequences whose rows are time points (multivariate data frames accepted); df: `dtw(df_a, df_b)`; fix: inherent; evidence: verified (t_misc4.R)
- `pracma::findpeaks` — ORDER=D; depth=1; why: peaks are runs of `nups` increases followed by `ndowns` decreases along the vector; df: column; fix: inherent; evidence: from source (findpeaks.R:1)

## Geometry along the row sequence (tracks, polygons, integrals)

- `geodist::geodist(x, sequential = TRUE)` — ORDER=D; depth=1; why: distances between consecutive rows of a lon/lat data frame, i.e. track legs (the full matrix is equivariant, verified); df: direct; fix: sort by time; evidence: verified (t_misc2.R)
- `geosphere::distGeo`, `distHaversine` and siblings with `p2` missing, `bearing`, `lengthLine` — ORDER=D; depth=2; why: distances and bearings between consecutive rows, and line length along them; df: lon/lat data frame or matrix; fix: sort by time; evidence: verified distGeo/bearing/lengthLine (t_misc2.R, t_misc7.R), distGeo.R:6-8
- `geosphere::areaPolygon`, `pracma::polyarea`, `sp::Polygon`, `spatstat.geom::owin(poly = )` — ORDER=D; depth=2/1/1/3; why: vertex rows in order define the ring; reordering (other than cyclic shift or reversal) changes the area, and `owin` errors on a ring it reads as clockwise; df: vertex data frame or its columns; fix: keep the digitising order; evidence: verified (t_misc2.R, t_misc6.R)
- `pracma::trapz`, `cumtrapz`, `caTools::trapz` — ORDER=D; depth=1/1/2; why: trapezoid rule over consecutive (x, y) pairs, so an unsorted x (e.g. a concentration–time curve) gives a wrong AUC; df: `trapz(df$t, df$conc)`; fix: sort by x; evidence: verified (t_misc2.R), trapz.R:6

## Positional splits, folds and sampling designs

- `gbm::gbm(train.fraction < 1)` — ORDER=D; depth=1; why: the first `train.fraction * nrow(data)` rows train the model and the rest form the validation set behind `valid.error` and `gbm.perf(method = "test")`; df: `gbm(y ~ ., data = df)`; fix: shuffle rows or use `cv.folds`; evidence: verified (t_misc7.R), gbm.R:126,375
- `RSNNS::splitForTrainingAndTest` — ORDER=D; depth=2; why: the last `ratio` of rows becomes the test set; df: `splitForTrainingAndTest(df[x], df$y)`; fix: shuffle first; evidence: from source (reg_class.R:50-58)
- `splitTools::create_timefolds` — ORDER=D; depth=1; why: rolling-origin time-series folds defined by position; df: column; fix: sort by time (intended); evidence: verified (t_misc7.R)
- `cvTools::cvFolds(type = "consecutive"/"interleaved")`, `cvFit(foldType = )` — ORDER=D; depth=3; why: folds are blocks or every K-th row by position (default `"random"` is RNG-based); df: `cvFit(lm, formula, data = df)`; fix: `"random"` with a seed; evidence: verified consecutive (t_misc7.R), cvFolds.R:60
- `pls::plsr`/`pcr`/`mvr(validation = "CV", segment.type = "consecutive"/"interleaved")`, `cvsegments` — ORDER=D; depth=1; why: CV segments by position (default `"random"`); df: `plsr(y ~ ., data = df, validation = "CV")`; fix: `"random"` with a seed; evidence: verified consecutive (t_misc7.R), cvsegments.R:98
- `MatchIt::matchit(method = "nearest")` with `m.order = "data"` — ORDER=D; depth=3; why: greedy matching takes treated units in row order, and `"data"` is the default when no propensity score is used (e.g. `distance = "mahalanobis"`); df: `matchit(tr ~ x, data = df)`; fix: `m.order = "closest"` (verified order-free) or a propensity score (default `"largest"`, verified order-free); evidence: verified (t_misc7.R), matchit2nearest.R:524-528
- `sampling::UPsystematic`, `strata(method = "systematic")`, `UPpivotal` — ORDER=D; depth=2; why: systematic sampling walks cumulative inclusion probabilities in frame order from one random start, and the pivotal method settles units pairwise in order; df: `UPsystematic(df$pik)`; fix: sort the frame deliberately (implicit stratification) or `UPrandomsystematic`; evidence: verified UPsystematic/UPpivotal (t_misc7.R)
- `permute::how(within = Within(type = "series"/"grid"))` used by `vegan::adonis2`, `anova.cca`, `mantel`, `permutest` — ORDER=D; depth=1 (vegan 2); why: restricted permutations are cyclic shifts of the rows as given, for time series and transects; df: `adonis2(comm ~ x, data = env, permutations = how(...))`; fix: sort rows by time or position; evidence: verified shuffleSet and adonis2 (t_misc1.R)

## Sequences within groups (counting process, panel, token streams)

- Grouped variants listed above restart the sequence per group but still follow row order within it: `data.table` `by =`, `collapse` `g =`, `tsModel::Lag(group = )`, `dlnm::crossbasis(group = )`, `psych::mssd(group = )`, `sandwich::vcovPL(cluster = )`.
- `udpipe::cooccurrence.character` (`skipgram`), `keywords_collocation`, `keywords_rake`, `keywords_phrases`, `txt_recode_ngram`, `txt_sentiment`, `paste.data.frame`, `as_conllu` — ORDER=D; depth=2; why: rows are tokens, so neighbours, collocations, contiguous candidate phrases (`rleid`), negators and amplifiers within `n_before` tokens, and pasted text follow row order within each document; df: the `udpipe()` annotation data frame; fix: sort by doc_id, paragraph_id, sentence_id, token_id; `cooccurrence(df, group =, term =)` and `document_term_frequencies` are order-free (verified); evidence: verified all but `as_conllu` (t_misc3.R, t_udpipe2.R), nlp_rake.R:65, udpipe_train.R:259
- `JM::jointModel` — ORDER=D; depth=1; why: subjects in the survival fit are matched to the `lme` groups by position, not by id, so both data frames must list subjects in the same order; df: `lme(..., data = long)`, `coxph(..., data = surv)`; fix: sort both by id; evidence: from source (jointModel.R:112-132; man/jointModel.Rd:216-219)
- `spacetime::STFDF` — ORDER=D; depth=3; why: full space–time grid whose data rows map to (space, time) by position, space varying fastest; `ST()` errors when times are unsorted; df: `STFDF(sp, time, data = df)`; fix: sort by time, then space as in `sp`; evidence: from source (STFDF-methods.R:5, ST-methods.R:9)
- `eha::join.spells` — ORDER=D (bug); depth=1; why: meant to merge adjacent spells per id after sorting, but sorts only enter/exit/event; df: spell data frame; fix: sort by id, enter, exit first; evidence: verified (t_eha.R), join.spells.R:45-61

## Bugs and partial sequence checks found

- `eha::join.spells` (depth 1) sorts `dat` by (id, enter, exit) but passes the covariates and the id codes to Fortran in the original row order (join.spells.R:45-61).
  On unsorted input the output is scrambled: in t_eha.R two subjects' spells come back labelled with the wrong ids and covariates.
- `bsts::bsts(timestamps = )` (depth 3) classes timestamps as "trivial" when `NoDuplicates()` and `NoGaps()` hold, and `NoGaps()` sorts before checking (format.timestamps.R:111-127, 145), so a permuted but complete daily series is treated as regular and the stamps are ignored.
  In t_bsts2.R the posterior state path then tracks y in permuted row order (r = 0.72) instead of time order (r = −0.36).
- `geosphere::perimeter` (depth 2), matrix and data.frame methods, computes the geodesic legs and then returns `sum(abs(x))` of the coordinates (perimeter.R:66-68): 4 for a 1° square whose perimeter is about 443.8 km.
  It is order-free only because of this bug.
- `sandwich::vcovPC` (depth 2) ignores `order.by` except to test balance (vcovPC.R:90-106); rows must be sorted cluster-major (t_vcovpc.R).
- `wavelets::dwt` (depth 1) documents data-frame input (dwt.R:4-5) but fails on it.
- Partial or full sequence checks that turn silent order dependence into an error:
  `pomp::pomp(data = df, times = "t")` errors unless times are non-decreasing (t_misc4.R);
  `data.table::frolladapt` errors on an unsorted index (t_datatable.R);
  `spacetime::ST()` errors on unsorted times (ST-methods.R:9);
  `airGR::CreateInputsModel` only errors when the last two dates are not one time step apart (t_airgr.R).

## Order-free despite appearances

- `zoo::zoo(x, order.by = )`, `zoo::read.zoo(df)` — ORDER=I/E; depth=1; why: the index is sorted on construction, so `lag`, `diff`, `na.approx` and `rollapply` then follow time (windows count observations, gaps are not filled); evidence: verified (t_zoo_xts.R)
- `xts::xts(df, order.by = )`, `xts::as.xts(df)` with date row names — ORDER=I/E; depth=2; why: the constructor sorts by index (xts.R:181-188; data.frame.R:30), so `lag`, `diff`, `period.apply`, `endpoints`, `to.period` and `first/last(x, "1 month")` use time; evidence: verified (t_zoo_xts.R)
- `TTR` indicators on a data frame with date row names — ORDER=E up to presentation (S); depth=3; why: `try.xts()` succeeds and sorts; the output data frame comes back in time order, not input order; evidence: verified SMA (t_zoo_xts.R)
- `PerformanceAnalytics` on data frames (`maxDrawdown`, `Return.cumulative`, `Return.annualized`, `Return.calculate`, `table.Autocorrelation`, `apply.rolling`) — ORDER=I; depth=3; why: `checkData()` requires date row names and converts to sorted xts (integer row names error); a bare numeric vector stays positional; evidence: verified (t_zoo_xts.R)
- `timeSeries::returns` — ORDER=E; depth=2; why: sorts the series before differencing (fin-returns.R:103), unlike `lag` and `rollMean`; evidence: verified (t_timeseries.R)
- `tsbox::ts_lag`, `ts_diff`, `ts_pc`, `ts_ts` on long data frames — ORDER=I/E; depth=3; why: series are keyed by the time column and regularised; evidence: verified (t_zoo_xts.R)
- `data.table` with `keyby =`, `setorder()`/`order()` in `i`, and rolling joins on unique keys — ORDER=I/E; depth=1; why: grouping and joins sort on the key; evidence: verified (t_datatable.R)
- `collapse` with `t =` (`flag`, `fdiff`, `fgrowth`, `psacf`), `o =` (`fcumsum`, `seqid`), and value-based `fnth`, `fbetween`, `varying`, `timeid` — ORDER=I/E; depth=2; evidence: verified (t_collapse.R)
- `lmtest::dwtest`/`bgtest`/`gqtest`/`harvtest`/`raintest`/`hmctest`, `sandwich::vcovHAC`/`NeweyWest`/`kernHAC`/`vcovPL`, `strucchange::gefp` with `order.by =` — ORDER=I; depth=2/2/3; why: the data are sorted by `order.by` before lagging; evidence: verified dwtest, NeweyWest, vcovPL, gefp (t_econ.R)
- `metafor::cumul(order = )` with a unique key, and `metafor::rma.mv(struct = "AR")` — ORDER=I; depth=3; why: `cumul` sorts by `order`; the AR(1) structure is defined over the sorted levels of the inner variable (numeric, factor or character), not row order; evidence: verified (t_misc2.R, t_metafor_ar.R)
- `MatchIt::matchit(method = "nearest")` with a propensity score (default `m.order = "largest"`) — ORDER=I up to ties; depth=3; evidence: verified (t_misc7.R)
- `BMisc::get_lagYi`, `get_first_difference` — ORDER=E; depth=3; why: sort by (id, time), lag within id, scatter back (BMisc.R:1493-1519); evidence: from source
- `Amelia::amelia(ts = , cs = , lags = , leads = )` — ORDER=E apart from RNG; depth=3; why: lags and leads are built after ordering by cross-section and time (prep.r:244-281); evidence: from source
- `deSolve::ode(events = list(data = df))` and `forcings` — ORDER=I apart from ties; depth=1; why: event rows are sorted by time with a warning (checkevents.R:139-143) and forcings by x (forcings.R:96-101); several events at the same time still apply in row order; evidence: from source
- `spacetime::STIDF`, `stConstruct` (long format) — ORDER=I/E; depth=3; why: rows are reordered by time on construction (STIDF-methods.R:20-28); evidence: from source
- `aqp::depths<-` (SoilProfileCollection) — ORDER=I/E; depth=3; why: horizons are sorted by profile id and top depth; evidence: verified (t_misc6.R)
- `validate::is_linear_sequence`, `in_linear_sequence` — ORDER=I; depth=2; why: default `sort = TRUE` (genericrules.R:70,112); evidence: from source
- `quanteda::corpus(df)` with `tokens`, `tokens_ngrams`, `kwic`, `fcm(context = "window")` — ORDER=S; depth=3; why: rows are documents and token order lives inside each text, so permuting rows only reorders docnames; `fcm(tri = TRUE)` stores each pair in the triangle set by first-appearance feature order; evidence: verified (t_misc6.R)
- `TraMineR::seqdef(df)` with `seqdist`, `seqtrate` — ORDER=I/E over rows; depth=3; why: each row is one sequence across columns; the column order is the sequence; evidence: verified (t_misc5.R)
- `prospectr::savitzkyGolay`, `gapDer`, `movav`, `detrend`, `continuumRemoval`, and `baseline::baseline` — ORDER=E over rows; depth=3/2; why: spectra in rows, wavelengths in columns; evidence: verified savitzkyGolay rows free, columns not (t_misc5.R)
- `changepoint::cpt.*` on a matrix — ORDER=E over rows; depth=2; why: each row is a separate series; evidence: verified (t_misc4.R)
- `udpipe::cooccurrence(df, group = , term = )`, `document_term_frequencies` — ORDER=I; depth=2; why: co-occurrence within the same document, and counts; evidence: verified (t_misc3.R)
- `oce::ctdDecimate`, `evd::fpot(cmax = FALSE)`, `qcc::qcc(type = "xbar")` limits, `vegan::specaccum(method = "exact")` — ORDER=I; why: binning by pressure, all exceedances, within-sample ranges, expected richness over all site orders; evidence: verified (t_oce.R, t_misc7.R, t_misc2.R, t_misc1.R)
- `mstate::msprep` — ORDER=E; depth=2; why: wide data with one row per subject, expanded per subject; `data.table::shift` appears only in plot helpers; evidence: from source (msprep.R)
- Not fixes, despite looking like one: `bsts(timestamps = )`, `sandwich::vcovPC(order.by = )` (see "Bugs").
