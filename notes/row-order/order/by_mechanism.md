# Row-order dependence in R data-frame consumers, by mechanism

This page classifies every order-sensitive finding in `catalog.md` by the mechanism that makes the result depend on row order.
Scope is base R, the recommended packages, and CRAN packages at dependency depth 1–3, as in the catalog.
Obvious time-series code is mostly absent from the catalog by design, so mechanism 1 is a list of traps plus a few by-design entries, not a census.

## How entries were selected

- The catalog has 1,223 one-line findings; 403 of them carry at least one order-sensitive mechanism and yield 440 entries here (10 sibling lines, such as `gbm::gbm.more`, are folded into the bullet of the function they mirror).
- Included: every line whose ORDER field contains `D`, `R` or `S` anywhere, including mixed classes such as `D (ties only) / I`, except six where the order-sensitive part never reaches the result (`zoo::rollapply` sorts first, `quantreg::rq(method = "pfn")` and `robustbase::nlrob` draw parameters or paths, `poLCA` draws per class, `simulateUsedAvail` simulates from parameters, `plot.factor` only dispatches).
- Also included: `I`/`E` lines whose notes describe an order trap (first appearance, ties, positions, last row, row-indexed RNG options), found by keyword search and screened by hand.
- Excluded: traps that are chunk-dependent but not order-dependent (`format.data.frame`, `as.matrix`, `type.convert`, `predict.bam(discrete = TRUE)`), tie handling verified invariant (`isoreg`, `lowess`, `supsmu`, `laeken::gini`), and seeds that index parameters rather than rows (`nnet` starts, `poLCA`, `VGAM`, `neuralnet`, `nlrob`, `gnm`).
- One catalog line can yield several entries when it combines mechanisms (for example `stats::kmeans` is both sequential and RNG-indexed); each entry is one bullet, and a bullet may group sibling methods.
- Evidence markers: "verified" means the catalog reports a permutation (or chunking) experiment; "from source" means the claim rests on reading the code.

## Taxonomy and counts

Entries per mechanism, with the number verified by permutation and the split by package group (440 entries, 117 verified).

- **1. Row position as time or sequence**: 52 entries, 14 verified; 22 by design.
  - By group: base/utils 1, stats 1, graphics/lattice 7, recommended 7, CRAN 1 11, CRAN 2 13, CRAN 3 12.
- **2. Row position as identity: pairing, occurrence, id, cluster**: 17 entries, 6 verified.
  - By group: base/utils 3, stats 2, graphics/lattice 1, CRAN 1 7, CRAN 2 2, CRAN 3 2.
- **3. Positional alignment of side inputs**: 15 entries, 2 verified.
  - By group: base/utils 3, graphics/lattice 1, recommended 1, CRAN 1 1, CRAN 2 4, CRAN 3 5.
- **4. First or last occurrence wins**: 30 entries, 7 verified; 1 by design.
  - By group: base/utils 1, stats 3, graphics/lattice 3, recommended 2, CRAN 1 7, CRAN 2 9, CRAN 3 5.
- **5. Positional subsets, splits and prefixes**: 15 entries, 3 verified; 2 by design.
  - By group: base/utils 1, CRAN 1 5, CRAN 2 6, CRAN 3 3.
- **6. Tie-breaking by encounter order**: 44 entries, 16 verified.
  - By group: base/utils 1, stats 3, graphics/lattice 5, recommended 9, CRAN 1 5, CRAN 2 10, CRAN 3 11.
- **7. Sequential algorithms: online, greedy, cumulative**: 12 entries, 3 verified; 2 by design.
  - By group: stats 1, recommended 2, CRAN 1 2, CRAN 2 3, CRAN 3 4.
- **8. Random draws indexed by row position**: 159 entries, 24 verified.
  - By group: base/utils 1, stats 1, graphics/lattice 3, recommended 26, CRAN 1 37, CRAN 2 45, CRAN 3 46.
- **9. Accumulation order and algebraic non-uniqueness**: 10 entries, 8 verified.
  - By group: base/utils 1, stats 3, recommended 5, CRAN 2 1.
- **10. Input order handed to user code**: 14 entries, 3 verified.
  - By group: base/utils 3, stats 2, CRAN 1 1, CRAN 2 6, CRAN 3 2.
- **11. Presentation only**: 63 entries, 22 verified.
  - By group: base/utils 5, stats 3, graphics/lattice 9, recommended 9, CRAN 1 11, CRAN 2 17, CRAN 3 9.
- **12. Bugs: two orderings or indices mixed up**: 9 entries, 9 verified.
  - By group: graphics/lattice 1, recommended 2, CRAN 1 1, CRAN 2 2, CRAN 3 3.

## Counts by package group

Entries per package group, split by mechanism number.

- **base/utils**: 20 entries from 18 catalog lines, 11 verified.
  - By mechanism: 1: 1, 2: 3, 3: 3, 4: 1, 5: 1, 6: 1, 8: 1, 9: 1, 10: 3, 11: 5.
- **stats**: 19 entries from 15 catalog lines, 18 verified.
  - By mechanism: 1: 1, 2: 2, 4: 3, 6: 3, 7: 1, 8: 1, 9: 3, 10: 2, 11: 3.
- **graphics/lattice**: 30 entries from 28 catalog lines, 22 verified.
  - By mechanism: 1: 7, 2: 1, 3: 1, 4: 3, 6: 5, 8: 3, 11: 9, 12: 1.
- **recommended**: 63 entries from 58 catalog lines, 40 verified.
  - By mechanism: 1: 7, 3: 1, 4: 2, 6: 9, 7: 2, 8: 26, 9: 5, 11: 9, 12: 2.
- **CRAN depth 1**: 88 entries from 78 catalog lines, 6 verified.
  - By mechanism: 1: 11, 2: 7, 3: 1, 4: 7, 5: 5, 6: 5, 7: 2, 8: 37, 10: 1, 11: 11, 12: 1.
- **CRAN depth 2**: 118 entries from 108 catalog lines, 14 verified.
  - By mechanism: 1: 13, 2: 2, 3: 4, 4: 9, 5: 6, 6: 10, 7: 3, 8: 45, 9: 1, 10: 6, 11: 17, 12: 2.
- **CRAN depth 3**: 102 entries from 98 catalog lines, 6 verified.
  - By mechanism: 1: 12, 2: 2, 3: 5, 4: 5, 5: 3, 6: 11, 7: 4, 8: 46, 10: 2, 11: 9, 12: 3.

## Changes to the draft taxonomy

- Draft class 1 is split into position as time or sequence (1) and position as identity (2), because the fixes differ: a time covariate versus an id or pairing key.
- New class 3, positional alignment of side inputs: the frame is handled correctly, but a parallel vector, matrix or query result is matched to it by position.
- New class 10, input order handed to user code: `tapply`, `by`, `aggregate`, `ave`, `dcast`, `plyr` and `data.table` `j` are order-free only for order-free callbacks, which the draft had no place for.
- Draft class 3 now also covers prefixes that fix a global decision: schema or factor coding from the first rows or first chunk (`duckdb_read_csv`, `yyjsonr`, `biglm`).
- Draft class 7 is broadened to algebraic non-uniqueness (QR/SVD signs in `lm$effects`, `prcomp`, `qda`, `mca`), which is not a floating-point effect.
- Draft class 9 is widened from first-appearance-versus-sorted mix-ups to index bugs in general (`ff::csum` adds `l[[1]]` for `l[[i]]`).
- Placements of draft examples: `JM` and `psych::alpha` stay in 4 (a representative row); `stats::SSfol` goes to 1 (the last row as the last time); `unstack` and paired tests go to 2; `max.col` ties go to 8; stable sorts go to 6.
- Class 8 is sub-divided by what the draws are for, since its 159 entries otherwise hide the few that are traps (`max.col`, `rpart` xval, `bam` bases, `vcovBS` cluster order).

## Ten entries worth knowing about

- `base::rowsum` on integer columns (9): a running C `int` turns into a sticky `NA` only for some orders of the same values; `sum()` and `colSums()` are safe (verified).
- `stats::pairwise.t.test(paired = TRUE)`, `pairwise.wilcox.test` (2): pairs the k-th row of each group by position and offers no block argument (verified).
- `gee::gee` (2): clusters are runs of contiguous `id`, so a shuffled frame turned 60 subjects into 296 clusters and changed robust SEs (verified).
- `sandwich::vcovPL`/`vcovHAC`, `lmtest::dwtest`, `gmm::gmm` (1): defaults use row order as time, so `gmm()` IV coefficients on cross-sectional data move under permutation (verified).
- `nlme::varIdent` (11): the reference stratum is whichever comes first in the data, so the reported variance ratio and sigma change while logLik does not (verified).
- `survey::svydesign(pps = "brewer")` (12): first-appearance PSU scale factors multiply PSU totals sorted by id, so the variance depends on row order (verified).
- `sampling::strata` (12): `size` is matched to strata in first-appearance order, so reversing the rows swaps the sample sizes between strata (verified).
- `bain::t_test.formula` (12): group n and variance follow first appearance while means follow `levels()`, changing the Bayes factor from 3.87 to 7.49 (verified).
- `psych::alpha` (4): constant items borrow their value from row 1, so an NA in row 1 shifts every total score (verified).
- `mgcv::bam` (8): above `chunk.size` rows the default basis is built on a seeded positional subsample, so permuted data give fitted values up to 6.4e-2 apart (verified).

## 1. Row position as time or sequence

The function needs an ordering (time, depth, iteration, vertex sequence) and, when no covariate supplies one, silently uses the row index: `seq_along()`, `1:n`, `diff()` of adjacent rows.
Lags, serial correlation, cumulative sums, HAC kernels and drawn paths then change under any permutation, although the call looks like an ordinary cross-sectional fit.

52 entries, 14 verified.

- `base::Math.data.frame` (`cumsum`, `cumprod`, `cummax`, `cummin`) — The cumulative members of the Math group run down each column in row order, though they look element-wise (verified; `dataframe.R:1596`).
- `stats::SSfol` (`initial`) — Uses `resp[n]` and `input[n]` as the last time point, assuming rows sorted by time (verified; `zzModels.R:259-261`).
- `graphics::plot.formula`, `graphics::plot.data.frame` (`y ~ 1`, one non-numeric column, `type = "l"`) — Falls back to an index plot with x = row number, or connects points in row order (verified; `plot.R:224`, `xyz.coords.R:95-99`).
- `graphics::matplot`, `graphics::matlines`, `graphics::matpoints` (missing x or `type = "l"`) — One-argument `matplot(df)` uses `x <- seq_len(NROW(y))`, so the row index is the x axis (verified; `matplot.R:47-52`).
- `grDevices::xy.coords` (1-column frame or bare vector) — Yields `x = seq_along(y)`, so the row index becomes the x coordinate (from source; `xyz.coords.R:61-67, 95-99`).
- `lattice::xyplot`, `lattice::panel.xyplot` (`type = "l"`, `"b"`, `"o"`) — Draws lines in row order (verified; `xyplot.R:149-151`).
- `lattice::cloud` (`type = "l"`) — Joins rows in data order (verified; `cloud.R:245`).
- `MASS::glmmPQL` (`corAR1()` without covariate) — Within-group row order defines time, so fixed effects change 0.4% under permutation (verified).
- `nlme::lme`, `nlme::gls`, `nlme::gnls`, `nlme::nlme` (`corAR1`, `corARMA`, `corSymm`, `corCAR1`, spatial `cor*` without covariate) — Without a covariate the time is `seq_along` within group (or `dist(1:nrow)`); logLik −568.12 → −612.51 under within-group permutation (verified; `corStruct.R:206-208, 1895, 1907`).
- `nlme::Variogram` (`.lme`, `.gls`, `.default`, default `form = ~1`) — The default distance is the position within the group (`tapply(rep(1, n), grps, cumsum)`) (from source; `lme.R:2644`).
- `mgcv::bam(rho != 0)`, `mgcv::bam.update` (AR1) — The AR1 error model uses row order as time (from source).
- `mgcv::gamm` (`correlation = corAR1(form = ~1|g)`) — Inherits nlme's covariate-free serial correlation: within-group position is time; logLik changed, `~t|g` did not (verified).
- `gss::ssanova9(cov = list("arma", ...))` — ARMA errors are indexed by row position (from source; `R/ssanova9.R:33-35`).
- `fastmatrix::cov.MSSD` — The mean square successive difference uses consecutive rows of a plain data frame (from source; `man/cov.MSSD.Rd:21`).
- `airGR::SeriesAggreg.data.frame` — Grid start and end come from the first and last rows and the time step from the first two rows; assumes date-sorted input (from source; `R/SeriesAggreg.data.frame.R:96-100`).
- `zoo::as.zoo.data.frame(x)` (no `order.by`) — `zoo(as.matrix(x))` uses row positions as the index (from source; `as.zoo.R:21-24`).
- `zoo::na.locf.data.frame` — Carries values forward in raw data-frame row order with no index (from source; `na.locf.R:53-57`).
- `zoo::zooreg` — The regular index is generated from position (start + (i − 1)/frequency) (from source).
- `nlstools::test.nlsResiduals` — The runs test counts sign runs of residuals in row order (from source; `nlsResiduals.R:146-153`).
- `collapse::flag`, `collapse::fdiff`, `collapse::fgrowth`, `collapse::fcumsum` (no `t`/`o`) — Without a time or order variable they use row order within groups (from source; `fcumsum.R:69`).
- `dlnm::crossbasis` (upstream of `smooth.construct.cb.smooth.spec`) — With a vector `x`, lags are built with `Lag(..., group)` in row order (from source; `crossbasis.R:14, 64`).
- `lmtest::dwtest` (no `order.by`) — `sum(diff(res)^2)` takes successive residuals in row order: a regression diagnostic that silently uses row order (verified; `dwtest.R:49-53`).
- `sandwich::vcovPL` (`meatPL`) without `order.by` — The time index is the row's position within its cluster via `make.unique(as.character(cluster))` (verified; `vcovPL.R:69-74`).
- `sandwich::vcovPC` (`meatPC`) without `order.by` — Same position-within-cluster time index as `vcovPL` (from source; `vcovPC.R:66-71`).
- `sandwich::vcovHAC`, `sandwich::NeweyWest`, `sandwich::kernHAC`, `sandwich::meatHAC`, `sandwich::bwAndrews`, `sandwich::bwNeweyWest` — Default order is `1:n`, so `vcovHAC(lm_fit)` on cross-sectional data uses row order as time (verified; `vcovHAC.R:41-53`).
- `gmm::gmm` (default `vcov = "HAC"`) — Kernel autocovariances across adjacent rows make cross-sectional IV estimates order-dependent (coefficients move 9e-3); `"MDS"` is invariant (verified; `R/gmm.R:14, 577-585`).
- `gmm::evalGmm`, `gmm::bwWilhelm` — Default `vcov = "HAC"` and HAC bandwidths use row order as time (from source; `R/gmm.R:50-51`).
- `aqp::checkHzDepthLogic` — Flags `sort(top) != top` and `bottom[-n] != top[-1]`, so row order within a profile is semantic (from source; `R/checkHzDepthLogic.R:191, 205`).
- `multgee::nomLORgee`, `multgee::ordLORgee` (no `repeated`) — The occasion index is assigned by within-cluster row order; coefficients change under permutation (verified; `nomLORgee.R:151-154`).
- `stochvol::svlm` — Takes `formula` + `data` like `lm`, but the latent log-volatility is AR(1) over row order (from source; `wrappers.R:1389-1395`).

By design, listed in the catalog for completeness (22):

- `graphics::plot.xy` (`type = "l"`, `"b"`, `"o"`, `"c"`) — Lines connect points in row order throughout base graphics, so row order is the path (from source; `plot.R:353-368`).
- `graphics::lines.formula` — Connects points in row order (from source; `plot.R:266`).
- `boot::tsboot` — Block or model resampling of a time series; row order is time by design (from source).
- `nlme::ACF.lme`, `nlme::ACF.gls` — Lag products are computed by within-group position (by design) (from source; `lme.R:837-849`).
- `data.table::shift`, `data.table::frollmean`, `data.table::frollapply` — Lags and rolling windows count rows, so row order is time (from source).
- `coda::mcmc` and its `as.data.frame`, `xyplot`, `acfplot`, `cumuplot` methods — Rows are iterations; `start`/`end`/`thin`, traces, autocorrelation and diagnostics are positional by design (from source).
- `pastecs::regul`, `pastecs::turnpoints`, `pastecs::vario`, `pastecs::disto`, `pastecs::escouf` — Space and time series tools; row order is the series (by design) (from source).
- `matrixStats::colCumsums` and friends — Cumulative sums run down the rows by design (from source).
- `collapse::psmat`, `collapse::psacf`, `collapse::pspacf` — Panel-series reshaping and autocorrelation by position within (id, time) (from source).
- `datawizard::smoothness.data.frame` — Lag-1 autocorrelation or differences in row order (from source).
- `gsignal::buffer` — Signal framing; row order is the signal (by design) (from source).
- `lmtest::bgtest`, `lmtest::harvtest`, `lmtest::grangertest` (formula methods) — Lagged residuals, recursive residuals by rank-one updates in row order, and `lag()` on series (from source; `bgtest.R:36`, `harvtest.R:21-40`, `grangertest.R:39-51`).
- `quantreg::dynrq` — Lags via zoo; time-series quantile regression by design (from source).
- `udpipe::keywords_rake`, `udpipe::keywords_collocation`, `udpipe::txt_sentiment`, `udpipe::paste.data.frame`, `udpipe::cooccurrence` (skipgram) — Token rows are a sequence within documents: n-grams, negator windows and adjacency (from source).
- `pomp::pomp` — Rows are observation times; particle filters scan sequentially (by design) (from source).
- `bsts::bsts`, `bsts::AddDynamicRegression` — Kalman filtering in row order unless `timestamps` are supplied (by design) (from source).
- `MCMCpack::MCMC*Change`, `MCMCpack::HDPHMM*`, `MCMCpack::HDPHSMMnegbin` — Change-point and HMM models over row order (by design) (from source).
- `strucchange::efp`, `strucchange::Fstats`, `strucchange::breakpoints`, `strucchange::recresid` — CUSUM/MOSUM processes, recursive residuals and breakpoints run over row order (by design) (from source).
- `tsbox::ts_dts`, `tsbox::ts_data.frame`, `tsbox::ts_summary` — Time-series tools (by design) (from source).
- `PerformanceAnalytics::maxDrawdown`, `PerformanceAnalytics::table.Drawdowns`, rolling `chart.*` — Drawdowns are path-dependent over row order (by design) (from source).
- `sfheaders::sf_linestring`, `sfheaders::sf_polygon` — Row order defines vertex order within each id (by design) (from source).
- `roll`, `TTR` — Rolling and recursive windows (by design) (from source).

**How to make it order-free:** Pass the ordering explicitly (`order.by =`, `corAR1(form = ~ time | g)`, `repeated =`, `t =`/`o =`, `form = ~ time`), or sort by an explicit time key right before the call; in cross-sectional code treat any default that falls back to `1:n` as a bug.

## 2. Row position as identity: pairing, occurrence, id, cluster

Here position does not stand for time but for which unit a row belongs to: the k-th row of group A is paired with the k-th row of group B, a run of contiguous ids is one cluster, or a generated id is the row number.
Permuting rows re-pairs observations, splits or merges clusters, or renames subjects, so values change even though every row is still present.

17 entries, 6 verified.

- `base::split<-`, `base::unsplit` — Scatter values back by within-group position, so values are re-attached to rows by encounter order (from source).
- `` base::`[.data.frame` `` (integer or character `i`) — Integer or row-name `i` addresses rows by position; duplicated selected row names are `make.unique()`d in encounter order (from source; `dataframe.R:732`).
- `utils::unstack` — Row i of the result pairs the i-th occurrence of every group, so within-group order defines the pairing (verified; `frametools.R:65`).
- `stats::pairwise.t.test`, `stats::pairwise.wilcox.test` (`paired = TRUE`) — Pairs the k-th observation of group i with the k-th of group j by position; no block argument exists (verified; `pairwise.R:52-53`).
- `stats::reshape(direction = "long")` without `idvar` — `ids = 1:NROW(data)` become the id column, so ids are row positions (verified; `reshape.R:22, 60`).
- `lattice::levelplot(region.type = "contour")` — Builds `matrix(z, length(cx))` straight from data order, assuming rows arrive in grid order (verified; `levelplot.R:268`).
- `data.table::rleid`, `.I`, `.GRP` — Run ids, row numbers and group numbers are defined by input position (from source).
- `effsize::cohen.d.formula(paired = TRUE)` without `Subject(id)` — Pairs observations by position within group (the source warns) (from source; `R/CohenD.R:117, 350-352`).
- `gee::gee` — Clusters are runs of contiguous equal `id`, and AR-M, M-dependent and unstructured correlations use position within them; a shuffle made 60 ids into 296 clusters (verified; `man/gee.Rd:123-127`, `R/ugee.R:204`).
- `zoo::read.zoo(split = Inf)` — Duplicate timestamps are numbered by occurrence (`ave(ix, ix, FUN = seq_along)`), and the number picks the series a value lands in (verified; `read.zoo.R:115-116`).
- `lsr::cohensD(method = "paired")` (formula) — Pairs by within-group row position (the source warns) (from source; `cohensD.R:160`).
- `r2rtf::rtf_body`, `r2rtf::rtf_page` (`page_by`, `group_by`, `nrow`) — Groups must arrive as sorted runs (`stop("Data is not sorted by ...")`), and pages are positional slices (from source; `rtf_body.R:190`).
- `tinytable::group_tt(i = )` — Row groups are given as row positions (from source).
- `mstate::msprep`, `mstate::expand.covs` (no `id`) — The subject id is the row position `1:n` (from source; `msprep.R:160-162`).
- `splitstackshape::getanID`, `splitstackshape::merged.stack`, `splitstackshape::Reshape` — Duplicated ids get a secondary index `sequence(.N)` in row order (from source; `getanID.R:40`).
- `dfidx::dfidx` (missing index) — The first index is created positionally as `rep(1:nchid, each = nalts)`, and a missing second index comes from within-group row order (from source; `R/dfidx.R:137-141, 168-172, 396-400`).
- `bain::t_test.formula(paired = TRUE)` — Pairs rows by within-group position (from source; `R/t_test_wrapper.R:140`).

**How to make it order-free:** Supply the identity as data (`Subject(id)`, `Pair(x, y)`, `idvar =`, `id =`, an explicit block or occasion column), and define clusters by key value rather than by contiguity.

## 3. Positional alignment of side inputs

A vector, matrix or second table that travels next to the data frame (sweep `STATS`, a GLS weight matrix, per-subject weights, phylogeny tips, survey design vectors, recycled operands) is matched to rows by position rather than by key.
Permuting the data frame without permuting the side input in lockstep silently attaches the wrong values to rows.

15 entries, 2 verified.

- `base::sweep` (`MARGIN = 1`) — `STATS` is aligned with the rows by position, so it must be permuted in lockstep with the data (from source).
- `base::Ops.data.frame` — A short vector operand is recycled down the rows, so `df * c(10, 100)` scales alternate rows (verified; `dataframe.R:1639`).
- `base::cbind.data.frame`, `base::data.frame` — Shorter arguments are recycled positionally down the rows (from source).
- `lattice::parallelplot`, `lattice::panel.parallel` — Without `groups` the 7 default colours are recycled over rows by position; with `groups` z-order is row order (verified; `parallel.R:44, 61`).
- `MASS::lm.gls` — The n×n `W` is indexed by row position and must be permuted together with the rows (from source; `lm.gls.R:33-39`).
- `sp::SpatialPointsDataFrame`, `sp::SpatialMultiPointsDataFrame` (`match.ID = FALSE`) — Coordinates and attribute rows are zipped by position (from source; `SpatialPointsDataFrame-methods.R:13-24`).
- `GLMMadaptive::mixed_model` (`weights`) — Ids are coded by first appearance, and the per-subject `weights` vector is matched positionally to that order (from source; `mixed_model.R:104, 109`).
- `ape::compar.gee`, `ape::binaryPGLMM`, `ape::correlogram.formula`, `ape::compar.lynch` — If row names do not match all tips they are ignored with a warning and rows are matched to tips by position (from source; `compar.gee.R:26-37`).
- `ape::corBrownian`, `ape::corPagel` and other `corPhyl` (`Initialize.corPhyl`) without `form` — "species will be taken as ordered in the data frame" (from source; `PGLS.R:55-57`).
- `ape::yule.cov` — Data rows are indexed positionally by node number (`X[phy$edge[, 1], ]`) (from source; `yule.R:41-43`).
- `ade4::supcol.*` — Supplementary rows must be aligned by position with the original rows (from source).
- `ade4::mld` — Orthobasis vectors index rows by position (a series or phylogeny) (from source).
- `CDM::modelfit.cor`, `CDM::modelfit.cor2` — `posterior` must be row-aligned with `data` (from source).
- `survey::svydesign.default` — Cluster, strata, prob and fpc vectors are aligned positionally with `variables` (from source).
- `survey::svydesign.character` (`DBIsvydesign`) — Queries carry no `ORDER BY`, so design vectors align with columns only if the database returns rows in the same order every time (from source; `dbiupdate.R:84`).

**How to make it order-free:** Match side inputs by key (row names, ids, `match.ID = TRUE`, named vectors, a `form = ~ species` covariate, `ORDER BY` in database queries), and refuse to fall back to position when keys are missing.

## 4. First or last occurrence wins

When several rows share a key (a duplicated cell, a repeated (id, time), the rows of one subject), the function keeps one of them, and encounter order decides which: `duplicated()`, `match()`, `m[i] <- z`, `tail(x, 1)` or row 1.
The kept value differs under permutation exactly when the duplicates disagree, which is the case the user did not anticipate.

30 entries, 7 verified.

- `base::duplicated.data.frame`, `base::anyDuplicated.data.frame` — Which copy is flagged as the duplicate, and the returned index, is decided by encounter order (`fromLast` flips it) (from source; `duplicated.R:40`).
- `stats::approx`, `stats::approxfun`, `stats::spline`, `stats::splinefun` (`ties = "ordered"`) — Skips sorting and tie collapsing; with tied x the value kept depends on row order (verified; `approx.R:50-61`).
- `stats::aggregate` (numeric `by`) — Values sharing `as.character()` (`0.1+0.2`, `0.3`) form one group whose printed key is the first row's value (verified; `aggregate.R:103`).
- `stats::reshape(direction = "wide")` (duplicates) — A duplicated (id, time) takes the first match; a varying "constant" variable takes the id's first row (verified; `reshape.R:167, 177`).
- `grDevices::chull` (repeated vertices) — Which duplicate of a repeated vertex is reported depends on encounter order (from source).
- `lattice::levelplot`, `lattice::contourplot` (duplicated cells) — `m[...] <- z` and per-row rectangles let the last row of a duplicated (x, y) cell win (verified; `levelplot.R:314-315`).
- `lattice::wireframe` (incomplete grid) — Fills `tmp[idx] <- z`, so the last duplicate of a cell wins (from source; `cloud.R:1092`).
- `survival::tmerge` — Stable sort by (id, time) lets the last of two tied `tdc()` values win; the first call takes the first `data2` row per id (verified; `tmerge.R:212, 297`).
- `survival::neardate` — With tied (id, date) in `data2` the stable `order(hash2)` returns the earliest-positioned row (from source; `neardate.R:67-71`).
- `data.table::[.data.table` (GForce `first`, `last`, `head`, `tail`, `[`, `shift` by group) — Positional reducers pick rows by within-group encounter order (verified).
- `data.table::merge.data.table`, `X[i, on=]` (`mult = "first"/"last"`, `roll=`) — Over duplicate keys in the lookup table the chosen row is picked by position (from source; `R/merge.R:96`).
- `data.table::duplicated.data.table`, `data.table::unique.data.table(by = <subset>)` — Which non-key values survive depends on which row came first; `fromLast` flips it (from source; `R/duplicated.R:26-44`).
- `insight::get_datagrid.data.frame` — `factors = "reference"` takes `unique(x)[1]` of character/logical columns, the first-appearing value (from source; `R/get_datagrid.R:1619, 1635`).
- `JM::survfitJM.jointModel`, `JM::predict.jointModel`, `JM::rocJM` — `last.time` is the time on each id's last row (`tapply(time, id, tail, n = 1)`), not the maximum; baseline covariates also come from it (from source; `R/survfitJM.jointModel.R:48, 73`, `R/predict.jointModel.R:104`, `R/rocJM.R:98`).
- `SSBtools::Match`, `SSBtools::any_duplicated_rows` — `Match` returns first-match positions among duplicated rows (from source).
- `collapse::ffirst`, `collapse::flast` — First and last are taken in row order (from source).
- `collapse::pivot(how = "wider")`, `"recast"` — Default `FUN = "last"` keeps the last duplicate of an id × name cell in first-appearance order (from source; `pivot.R:146, 303`).
- `datawizard::data_unique`, `datawizard::data_duplicated` — `keep = "first"`/`"last"` are positional, and `"best"` (fewest NAs) falls back to the first (from source; `data_unique.R:77-87`).
- `gamlss::getPEF`, `gamlss::getQuantile` (`how = "last"`) — Other covariates are fixed at the last observation `tail(x, 1)` (from source; `getPEF.R:58-70`).
- `gdata::update.data.frame` — With duplicate keys in `new` the last assignment wins; unmatched rows are appended in input order (from source; `update.data.frame.R:11-17`).
- `psych::alpha` — For zero-variance items it adds `x[1, bad]` to every total, so an NA in row 1 drops the constant (mean 2.355 vs 3.105) (verified; `alpha.R:62, 121`).
- `psych::describeFast` — The type check reads row 1 only (`is.numeric(x[1, i])`) (from source; `describe.R:69-72`).
- `lqmm::lqmm` — Group weights are taken from each group's first row (`model.weights(dataMix)[!duplicated(grp)]`) (from source; `lqmm.R:403`).
- `spatstat.univar::uniquemap.data.frame`, `spatstat.sparse::representativeRows` — Each row maps to the index of its first duplicate (from source).
- `gaston::SNP.duplicated` — Returns indices of later duplicates; which copy counts as the duplicate depends on order (from source; `R/snp_duplicated.r`).
- `vctrs::vec_duplicate_*` — The first occurrence is the one kept (from source).
- `raster::rasterize` (default `fun = "last"`) — Overlapping points keep the last row's value; `"first"` is also positional (from source; `rasterize.R:18`, `rasterizePoints.R:46-63`).
- `spatstat.geom::as.im.data.frame`, `spatstat.geom::as.owin.data.frame` — `mm[iijj] <- zk` keeps the last row for duplicated (x, y) (from source; `as.im.R:321`, `window.R:452`).
- `spatstat.geom::duplicated.ppp`, `spatstat.geom::uniquemap.ppp` — The first occurrence is kept (from source).

By design, listed in the catalog for completeness (1):

- `data.table::first`, `data.table::last`, `head.data.table`, `tail.data.table` — Positional by design; the trap is their use inside grouped `j`, where they look like ordinary aggregates (from source).

**How to make it order-free:** Resolve duplicates with an explicit symmetric rule (sum, mean, min, max, or an error on conflict) or by an explicit order column (`max(time)` rather than the last row), and give `first`/`last` an ordering argument.

## 5. Positional subsets, splits and prefixes

A deterministic subset is defined by position: the first `train.fraction` of rows, a central fraction, a split point, consecutive or interleaved folds, an every-k-th subsample, or the first n rows that fix a schema or a factor coding.
No random numbers are involved, so a fixed seed does not help: after a permutation the subset simply holds different observations.

15 entries, 3 verified.

- `gbm::gbm`, `gbm::gbm.more` (`train.fraction < 1`) — Trains on the first `floor(train.fraction * n)` rows and validates on the rest (from source; `R/gbm.R:126, 375`).
- `aplpack::compute.bagplot`, `aplpack::bagplot` (n > 300) — Takes the systematic positional subsample `round(seq(1, n, by = n/approx.limit))` (from source; `R/bagplot.R:251-258`).
- `pls::cvsegments` (`"consecutive"`, `"interleaved"`) — Segments are blocks or strides of row positions (from source; `cvsegments.R:143-160`).
- `yyjsonr::read_ndjson_file` (companion reader) — Column types come from the first `nprobe = 100` records, so the leading rows fix the schema (from source; `ndjson.R:40`).
- `RODBC::sqlSave(append = TRUE)` — Column types are chosen from the first chunk written (from source; `sql.R:156-159`).
- `biglm::bigglm` (`.function`, `.data.frame`), `biglm::biglm` + `update.biglm` — p, `assign` and the factor coding come from the first chunk (positional slices `data[start:cursor, ]`); later chunks with other levels are silently mis-coded (verified; `bigglm.R:6-19, 52-58`, `update.biglm.R:10`).
- `ff::cmean`, `ff::cmedian`, `ff::cquantile`, `ff::csummary` — Combine per-chunk results of positional `bbatch()` slices: an unweighted mean of chunk means, a median of chunk medians (from source; `CFUN.R:52-58, 145-150`).
- `duckdb::duckdb_read_csv` — Infers the schema from the first `nrow.check = 500` rows of each file (from source; `csv.R:76-85`).
- `lmtest::raintest` (default `order.by = NULL`) — The "central fraction" is `quantile(1:n, ...)` on row positions (verified; `raintest.R:22-28`).
- `lmtest::gqtest`, `lmtest::hmctest` (no `order.by`) — Split the sample at a row position (`X[1:point1, ]`) (verified for `gqtest`; `gqtest.R:45-46`, `hmctest.R:38`).
- `h2o::h2o.glm(fold_assignment = "Modulo")` — Folds assigned by row position modulo `nfolds` (from source; `R/glm.R:215`).
- `chemometrics::lassoCV` and siblings (`segment.type = "consecutive"`, `"interleaved"`) — Folds are blocks or strides of row positions, order-dependent without any RNG (from source; `R/lmCV.R:25`, `R/mvr_dcv.R:69`, `R/pcaCV.R:17`).
- `cvTools::cvFolds` (`type = "consecutive"`, `"interleaved"`) — Positional folds without randomness (from source; `R/cvFolds.R:61`).

By design, listed in the catalog for completeness (2):

- `utils::head`, `utils::tail`, `utils::str.data.frame` — Positional by design: first or last n rows (from source).
- `berryFunctions::headtail`, `berryFunctions::insertRows` — Positional by definition (from source).

**How to make it order-free:** Define the subset by an explicit key or order statistic (`order.by =`, a fold-id column, a hash of a row key), and infer schemas from the whole input or declare them (`colClasses`, `levels =`, `xlev`).

## 6. Tie-breaking by encounter order

The algorithm is order-free on distinct values, but ties in sort keys, distances, densities, counts or costs are resolved by the first candidate under a strict comparison or a stable sort.
With tied data (rounded values, integer distances, factor modes) the chosen merge, rank, mode, window or medoid, and everything downstream, follows row order.

44 entries, 16 verified.

- `base::order`, `base::sort_by.data.frame` — Stable sort: tied keys keep their input order (from source).
- `stats::hclust` — The NN-chain loop takes the first minimal pair with strict `.LT.`, so tied dissimilarities merge in row-index order (verified; `src/hclust.f:93-98`).
- `stats::cutree` (tied heights) — With tied merge heights the k-cut itself changes with the `hclust` tie order (verified).
- `stats::qqnorm`, `stats::qqplot` — `qnorm(ppoints(n))[order(order(y))]` assigns tied y values their theoretical quantiles by position (verified; `qqnorm.R:34`).
- `graphics::smoothScatter` — The `nrpoints` outlier dots come from `order(dens)`, so density ties at the cut-off are broken by row order (verified; `smoothScatter.R:83`).
- `lattice::xyplot` (`type = "s"`, `"S"`) — Step lines sort by x, but tied x keep row order (verified; `xyplot.R:167, 182`).
- `lattice::xyplot(aspect = "xy")`, `lattice::banking` — `dy` comes from x-sorted diffs with ties broken by row order, so the banked aspect ratio changes (8–10 values over 20 permutations) (verified; `xyplot.R:30-48`, `common.R:415-428`).
- `lattice::cloud` (points) — Points are drawn in depth order; exact depth ties fall back to row order (verified; `cloud.R:207-209`).
- `lattice::panel.smoothScatter` — `order(idens)[1:nrpoints]` breaks density ties by row order (from source; `panel.smoothscatter.R:103`).
- `MASS::isoMDS`, `MASS::Shepard` — `order(dis)` ranks tied dissimilarities by position, changing the isotonic blocks (stress 0.1%, configuration 12%) (verified; `isoMDS.R:53`).
- `class::knn` (training order) — The fuzzy tie fence compares with the current k-th distance, so near-tie membership within 1e-4 can depend on training order (from source; `class.c:124`).
- `KernSmooth::dpill` — Stable `sort.list` then rank trimming and equal-count blocks: tied x at a boundary land in blocks by input order (verified; `all.R:495-502`, `blkest.f:27`).
- `survival::residuals.coxph` (Schoenfeld) — Residual rows at tied event times follow input order (from source).
- `survival::summary.aareg` (`slope`) — Cumulates event rows in input order within tied event times, so `slope` changes while coef/se/p do not (verified; `summary.aareg.R:41`).
- `cluster::pam` — Among equal-cost swap candidates the medoid is chosen by row index (`ammax <= beter[i]`), so medoid ids change with duplicated rows (verified; `pam.c:270`).
- `cluster::agnes` — Same tie behaviour as `hclust`: on tied integer data heights and the k = 4 cut changed (verified).
- `cluster::medoids` — Ties among candidate medoids are resolved by index (from source).
- `mgcv::k.check` (1-D k-index) — `diff(rsd[order(x)])` takes tied x in input order (from source; `plots.r:217`).
- `data.table::setorder`, `data.table::setorderv`, `data.table::sort_by.data.table` — Stable sort: tied keys keep input order (from source).
- `insight::get_datagrid.data.frame` (`.mode_value()`) — Ties for the mode are broken by first appearance (from source; `R/get_datagrid.R:1645-1650`).
- `zoo::zoo`, `zoo::read.zoo`, `zoo::as.zoo.data.frame(order.by = )` — The constructor sorts by index (so input order is irrelevant), but tied index values keep input order (from source; `zoo.R:5`).
- `mclust::Mclust`, `mclust::mclustBIC`, `mclust::densityMclust`, `mclust::MclustDA` — The agglomerative `hc()` initialisation merges tied values in position order, giving a different local optimum after permutation (verified; `mclust.R:660`).
- `RANN::nn2` — Equidistant neighbours are ordered by kd-tree layout, which depends on input order (from source).
- `collapse::collap`, `collapse::collapv` — The default `catFUN = fmode` inherits its first-occurrence tie rule (from source).
- `collapse::fmode` (default `ties = "first"`) — Returns the first value in row order reaching the maximum count: 2 on `c(1,3,2,2,4,4,1,7)`, 4 reversed (verified; `man/fmode.Rd:75`).
- `datawizard::demean`, `datawizard::degroup` (`center = "mode"`) — `distribution_mode()` breaks ties by first appearance though its message claims the smallest value: `c(3,3,1,1)` gives 3 (verified; `descriptives.R:32-47`).
- `lmtest::raintest`, `lmtest::gqtest`, `lmtest::hmctest`, `lmtest::dwtest`, `lmtest::bgtest` (with `order.by`) — Sorting by `order.by` breaks ties by input position (from source).
- `memisc::sort.data.frame` — Stable sort: ties keep input order (from source).
- `plyr::arrange` — Stable `order()`: ties keep input order (from source).
- `udpipe::cooccurrence.data.frame` — Counts are invariant; `setorder(result, -cooc)` leaves tied pairs in input order (from source; `nlp_cooccurrence.R:176`).
- `statnet.common::sort.data.frame`, `statnet.common::order.data.frame` — Stable `order()`: ties keep input order (from source).
- `wdm::wdm`, `wdm::indep_test` (`method = "xi"`) — Chatterjee's xi breaks x ties by "a fixed, reproducible ordering" unless `seeds` is given (compiled code not inspected) (from source; `man/wdm.Rd:31`).
- `xts::as.xts.data.frame` — The time index sorts rows, but ties keep input order (from source).
- `marginaleffects::datagrid` (default `"mean_or_mode"`, `newdata = "mean"`) — `get_mode()` takes `unique(x)[which.max(tabulate(...))]`: a 16/16 tie gives `"x"` on the data, `"y"` reversed (verified; `R/mean_or_mode.R:4-11`).
- `margins::cplot` — The mode tie-break lives in package prediction, the same code as marginaleffects (likely the same trap, not verified) (from source).
- `MatchIt::matchit(method = "nearest")` (propensity score) — "any ties are broken based on the order in which the data appear" (from source; `R/matchit2nearest.R:190`).
- `dfidx::mean.dfidx` — Character modes use `factor(x, levels = unique(x))` then `which.max(table(x))`, so ties go to first appearance (from source; `R/methods.R:309-310`).
- `gplots::bandplot.formula` — `order(x)` then running mean and sd over windows of `n * width` points; tied x keep input order (from source; `R/bandplot.R:39-43`).
- `gaston::LD.clump` — Greedy clumping in `order(p)`, so SNPs with tied p-values are processed in input order (from source; `R/ld_clump.r:15`).
- `BMisc::sort_panel` — Orders rows by id and time; ties keep input order (from source).
- `strucchange::gefp`, `strucchange::sctest(order.by = )` — `order(z)` keeps ties in input order, so `maxBB` and `supLM` change under within-tie permutation (from source; `gefp.R:31-35`).
- `vctrs::vec_count` (default `sort = "count"`) — Count ties are broken by first location (from source; `dictionary.R:57-65`).
- `prospectr::kenStone`, `prospectr::duplex`, `prospectr::puchwein`, `prospectr::shenkWest`, `prospectr::honigs` — Max-min selection with `which.max`, whose ties resolve by row index (from source; `kenstone.R:150`).
- `psychTools::dfOrder` — Stable sort: ties keep input order (from source).

**How to make it order-free:** Break ties by a total order on the values themselves (sort by the full key, then by a unique row key), or use symmetric tie handling (`ties = "min"`, mid-ranks, pooling tied blocks).

## 7. Sequential algorithms: online, greedy, cumulative

State is updated after every row and later rows see the updated state: online k-means and SOM updates, greedy matching without replacement, cumulative meta-analysis, species accumulation, Kaczmarz sweeps.
The visiting sequence is part of the algorithm, so another order reaches another (often local) solution even from identical starting values.

12 entries, 3 verified.

- `stats::kmeans` (Hartigan–Wong, MacQueen) — Points are visited in row order with immediate centre updates; only 12% (HW) and 30% (MacQueen) of permutations reproduced the centres (verified; `kmns.f`, `kmeans.c`).
- `class::lvq1`, `class::lvq2`, `class::lvq3`, `class::olvq1` — Codebook vectors are updated after every presented row, so the visiting sequence shapes the result (verified; `lvq.R:56`).
- `class::SOM` — Online neighbourhood updates per presented row (from source; `class.c:401-417`).
- `som::som`, `som::som.train` — Online SOM training visits samples in data order (compiled SOM_PAK port, inferred) (from source; `som.R:62-89`).
- `e1071::matchControls` — Greedy nearest-control matching without replacement in case order, so earlier cases claim controls first (from source; `matchControls.R:49-60`).
- `e1071::ica` — Online SGD over rows in input order for `epochs` passes (from source; `ica.R:34-41`).
- `vegan::specaccum(method = "collector")` — Accumulates species in the row order of sites, a curve that looks order-free but is not (verified; `specaccum.R:23-27`).
- `MatchIt::matchit(method = "nearest")` — Greedy matching in `m.order`, whose default is `"data"` for non-propensity distances: earlier units claim controls first (from source; `R/matchit2nearest.R:525-527`).
- `MatchIt::matchit(method = "cem", k2k = TRUE)` — k2k pruning uses the default `m.order = "data"` (from source; `R/matchit2cem.R:495`).
- `lfe::getfe(method = "kaczmarz")` — Kaczmarz sweeps rows sequentially: the iterate path depends on order, the converged solution only up to tolerance (from source).

By design, listed in the catalog for completeness (2):

- `rmeta::cummeta`, `rmeta::cummeta.summaries` — Cumulative meta-analysis over `subset = 1:i` in row order, by design (from source; `meta.R:25-72`).
- `metafor::cumul.*` — Cumulative meta-analysis in row (or `order=`) order, by design (from source).

**How to make it order-free:** Use the batch variant (Lloyd k-means, batch SOM, optimal instead of greedy matching), or make the visiting order an explicit argument (`m.order`, a sort key, or a shuffle seeded from row keys).

## 8. Random draws indexed by row position

Random numbers are consumed per row or used as row indices (`sample.int(n)`, fold labels, bootstrap indices, jitter, random tie-breaks), so draw k always lands on whatever row sits at position k.
The result is invariant in distribution, but with a fixed seed it changes under permutation, which breaks the reproducibility of seeded analyses and of reordered or chunked rewrites.

159 entries, 24 verified.

### 8a. Resampling and subsampling: bootstrap, bagging, forests, subsamples

45 entries.

- `boot::boot` — `ordinary.array` draws `sample.int(n, n*R, replace = TRUE)` over positions; even the sorted `t` differs after permutation (verified; `bootfuns.q:784-803`).
- `boot::censboot` (`sim = "ordinary"`, `"model"`, `"cond"`) — Draws per row; `sim = "weird"` draws per unique failure time and is invariant (verified).
- `eha::coxreg`, `eha::coxreg2` (`max.survs` below risk-set size, `boot > 0`) — Risk-set sampling and bootstrap draw by row; Efron/Breslow/ML fits are invariant because `risksets()` sorts (from source; `R/coxreg.R:197`, `R/risksets.R:10-11`).
- `eha::toBinary` (`max.survs`) — Risk-set sampling draws by row (from source).
- `gbm::gbm` (`bag.fraction`, `cv.folds`) — Bagging subsample and CV folds drawn by row position (from source).
- `investr::calibrate`, `investr::invest` (bootstrap intervals) — Bootstrap resamples rows by position (from source).
- `ada::ada` — Bagging subsamples by position (from source; `R/ada.machine.R:19-22`).
- `randomForest::randomForest` — Bootstrap samples and feature draws index rows by position (from source).
- `randomForest::rfImpute` — Each iteration grows a random forest (from source; `rfImpute.R:41`).
- `segmented::segmented.lm`, `segmented::segmented.glm`, `segmented::segreg`, `segmented::stepreg`, `segmented::segmented.lme` — Default `n.boot = 10` bootstrap restarts draw `sample(n, size.boot, replace = TRUE)` (from source; `seg.lm.fit.boot.r:135`).
- `nlstools::nlsBoot`, `nlstools::nlsBootPredict` — Resamples residuals by position (`sample(scale(resid1))`) (from source; `nlsBoot.R:14`).
- `yaImpute::yai` (`bootstrap = TRUE`, `method = "randomForest"`/`"ica"`) — Resamples reference rows with `sample(refs, replace = TRUE)` or grows random forests (from source; `yai.R:252`).
- `Matching::MatchBalance` — KS bootstrap `sample(1:obs, obs, replace = TRUE)` (from source; `GenBalance.R:202`).
- `laeken::bootVar` — Bootstrap resamples rows by position (from source).
- `kyotil::iorw` — Default `nboot = 10000` bootstrap resamples rows (from source).
- `stabs::stabsel.data.frame` — `B` complementary-pair subsamples drawn by row (from source; `stabsel.R:13`).
- `datawizard::describe_distribution` (`ci =`) — Bootstrap confidence intervals resample rows (from source).
- `datawizard::skewness`, `datawizard::kurtosis` (`iterations =`) — Bootstrap SE via `boot::boot` (from source).
- `lavaan::lavaan` and co. (`se = "bootstrap"`, `test = "bollen.stine"`) — Resampling indexed by row position (from source).
- `gamlss::bp(bootstrap = TRUE)` — Resamples residuals (from source).
- `arules::confint.rules(method = "bootstrap")` — Resamples transactions (from source).
- `isotree::isolation.forest` — Each tree grows on a random row subsample (from source; `isoforest.R:46`).
- `sandwich::vcovBS` (`.lm`, `.glm`, `.default`) — Bootstrap draws are indexed by cluster in first-appearance order (`factor(cluster, levels = unique(cluster))`) (verified; `vcovBS.lm.R:103`).
- `psych::alpha(n.iter > 1)` — Bootstrap resamples rows (from source; `alpha.R:215`).
- `psych::fa(n.iter > 1)` — Resamples rows (from source; `fa.R:75-80`).
- `pROC::ci.auc`, `pROC::ci`, `pROC::roc.test`, `pROC::ci.se`, `pROC::ci.sp`, `pROC::ci.thresholds`, `pROC::ci.coords` (bootstrap, `"venkatraman"`) — Bootstrap and permutation resample rows; DeLong is invariant (from source).
- `xgboost` (`subsample < 1`, `colsample_*`) — Row subsampling per tree (from source).
- `ResourceSelection::rsf`, `ResourceSelection::rspf` (`B > 0`) — Bootstrap resamples rows through a positional index into per-row log-likelihoods (from source; `rsf.fit.R:6-16`).
- `quantregForest::quantregForest` — Bootstrap samples per tree (from source).
- `marginaleffects::inferences` (`"boot"`, `"rsample"`, `"fwb"`, `"conformal_*"`) — Resample rows or split them at random (from source; `R/inferences_boot.R:20`).
- `margins::margins(vce = "bootstrap")` — `sample(seq_len(nrow(data)), nrow(data), TRUE)` per replicate (from source; `R/get_effect_variances.R:142`).
- `bayestestR::weighted_posteriors.data.frame` — `sample(nrow(temp_params), size = ...)` per model (from source; `R/weighted_posteriors.R:289`).
- `h2o::h2o.shap_summary_plot` — Subsamples rows (from source).
- `icenReg::ic_sp(bs_samples > 0)` — Bootstrap resamples rows (from source; `R/internal_utilities.R:23`).
- `CDM::IRT.repDesign(jktype = "BOOT")` — Bootstrap replicate weights (from source).
- `lfe::felm(Nboot = )` — Bootstrap resamples rows (from source; `R/felm.R:1325`).
- `grf::lm_forest`, `grf::multi_arm_causal_forest` and other grf forests — Subsampling with honesty splits and a random seed (from source; `R/lm_forest.R:126-138`).
- `aorsf::orsf` — Bootstrap or subsample per tree (from source).
- `fwb::vcovFWB`, `fwb::fwb` — Default `wtype = "exp"` draws `rexp(n * R)` filled by row; `"poisson"` likewise per row (from source; `R/fwb.R:465-481`).
- `Amelia::amelia` — Each imputation starts from a bootstrap with `runif(nrow(x))` indices (from source; `R/emb.r:80`).
- `dagitty::localTests(R = )` — Bootstraps rows (from source).
- `laGP::blhs` — Bootstrapped block Latin hypercube subsample (from source).
- `ranger::ranger` — With `seed=` the in-bag draws are indexed by row position (from source; `ranger.R:553-554`).
- `semTools::bsBootMiss`, `semTools::splitSample`, `semTools::parcelAllocation`, `semTools::PAVranking`, `semTools::poolMAlloc`, `semTools::quark` — Bootstrap, random row splits and MI (from source).
- `quanteda::bootstrap_dfm`, `quanteda::corpus_sample`, `quanteda::dfm_sample` — Random resampling of documents by position (from source).

### 8b. Cross-validation folds and random splits

21 entries.

- `boot::cv.glm` — `sample0(rep(1:K, f), n)` assigns folds by position; LOOCV (`K = n`) is invariant (verified; `bootfuns.q:845`).
- `rpart::rpart` (default `xval = 10`) — `sample(rep(1:xval, length.out = nobs))` assigns folds by row position; the tree is invariant, `xerror`/`xstd` are not (verified; `rpart.R:119`).
- `rpart::xpred.rpart` — Same positional `sample()` fold assignment (verified; `xpred.rpart.R:70`).
- `grpreg::cv.grpreg` — Random fold assignment by position (from source).
- `pls::mvr(validation = "CV")`, `pls::crossval`, `pls::cvsegments` (`"random"`) — `sample(1:N)` assigns segments by position (from source; `cvsegments.R:140`).
- `lars::cv.lars` — Folds from `sample(1:n)` (from source; `cv.folds.R:4`).
- `ncvreg::cv.ncvreg` — Random fold assignment by position (from source).
- `gamlss::gamlssCV`, `gamlss::CV` — Fold ids `sample(K.fold, N, replace = TRUE)` indexed by row position (from source; `gamlssVGD_23_12_21.R:442`).
- `e1071::svm` (`cross =`, `probability = TRUE`) — libsvm-internal resampling (from source).
- `e1071::tune`, `e1071::tune.nnet`, `e1071::tune.rpart` — `perm.ind <- sample(n)` assigns folds by row position (from source; `tune.R:71`).
- `MuMIn::arm.glm`, `MuMIn::stackingWeights` — Random splits of rows (from source).
- `glmnet::cv.glmnet` — `foldid = sample(rep(seq(nfolds), length = N))` is positional (from source; `R/cv.glmnet.R:257`).
- `h2o::h2o.glm` (`nfolds`, `"AUTO"`/`"Random"`) — Random fold assignment (from source).
- `earth::earth(nfold = )` — Random cross-validation folds (from source).
- `chemometrics::lassoCV`, `chemometrics::ridgeCV`, `chemometrics::lmCV`, `chemometrics::mvr_dcv`, `chemometrics::pcaCV` — `cvsegments(type = "random")` folds by position (from source; `R/ridgeCV.R:34`).
- `abc::cv4abc` — Random choice of validation simulations (from source).
- `cvTools::cvFit`, `cvTools::cvTuning`, `cvTools::cvFolds` — `cvFolds` uses `sample(n)` (from source; `R/cvFolds.R:79`).
- `animation::cv.nfeaturesLDA` — Random CV folds (from source).
- `penalized::cvl`, `penalized::optL1`, `penalized::optL2`, `penalized::profL1`, `penalized::profL2` — Folds `sample(n) %% fold + 1` are indexed by row (from source; `core.R:367`).
- `rioja::WA.fit` (cross-validation, bootstrap) — Random folds and resamples (from source).
- `RWeka::evaluate_Weka_classifier(numFolds = )` — Seeded CV in Java assigns folds by position (from source).

### 8c. Random starts, random subsets and random basis selection

35 entries.

- `stats::kmeans` (random starts) — `centers = k` draws `x[sample.int(m, k), ]`; `nstart >= 2` samples from `unique(x)` in first-appearance order (verified; `kmeans.R:99, 101-105`).
- `MASS::lda`, `MASS::qda` (`method = "mve"`) — Inherits the random row subsets of `cov.rob` (from source).
- `MASS::rlm(method = "MM")` — Starts from `lqs(method = "S")`, which draws random subsets by row index (verified).
- `MASS::lqs`, `MASS::lmsreg`, `MASS::ltsreg` — Random p-subsets of row indices when `choose(n, p) >= 5000`; exhaustive (invariant) below that (verified; `lqs.R:107, 117`).
- `MASS::cov.rob`, `MASS::cov.mve`, `MASS::cov.mcd` — Random row subsets drawn in C (verified; `lqs.R:218-264`).
- `class::batchSOM` — Default `init` samples rows by position, and `knn1` breaks near-ties at random (verified; `SOM.R:24`, `class.c:47`).
- `class::lvqinit`, `class::multiedit`, `class::condense`, `class::reduce.nn` — Combine `knn`/`knn.cv` with `sample()` over row positions (from source; `lvq.R:41`, `multiedit.R:30`).
- `cluster::pam` (`medoids = "random"`, `nstart`) — Random initial medoids are drawn by row index (verified; `pam.q:5-6`).
- `cluster::clara` — Random subsamples drawn by row position; the partition changed under permutation with a fixed seed (verified).
- `mgcv::bam` (default `discrete = FALSE`, `nrow > chunk.size`) — Bases are set up on a seeded positional subsample `sample(1:n, chunk.size)`, so knots, eigenbases and constraints change (fitted values up to 6.4e-2) (verified; `bam.r:393-395`).
- `mgcv::summary.gam` (objects lacking `R`) — Falls back to a seeded positional row subsample of the model frame (from source; `mgcv.r:3987-3999`).
- `gss::ssanova`, `gss::gssanova`, `gss::gssanova1`, `gss::ssanova9` — Default `id.basis <- sample(nobs, nbasis, prob = wt)` picks basis rows by position; invariant when `id.basis` is given (from source; `R/ssanova.R:22`).
- `gss::ssden`, `gss::ssden1`, `gss::sscden`, `gss::sscden1`, `gss::ssllrm` — Basis rows sampled by position (from source; `R/ssden.R:25`).
- `gss::sscox`, `gss::sshzd`, `gss::sshzd1`, `gss::sshzd2d`, `gss::sshzd2d1` — Basis sampled among event rows by position (from source; `R/sscox.R:54`).
- `EMCluster::emcluster` (`init.EM`) — Random starts (`em.EM`, `Rnd.EM`) draw rows by position; invariant given `emobj` (from source; `R/fcn_init_EM.r:52-64`).
- `dr::dr.weights` — Random sampling of rows (`nsamples`) (from source).
- `AlgDesign::optFederov`, `AlgDesign::optMonteCarlo` — `nRepeats` random starts index candidate rows (from source; `R/FederovOpt.R:9`).
- `mda::mda` — Starting subclasses come from per-class `kmeans` with random centres and restarts (from source; `mda.start.R`).
- `mclust::Mclust` (n > 2000) — Initialisation draws a random row subset (from source; `mclust.R:596`).
- `SSBtools::Extend0rnd1` — Random extra rows via `sample()` (from source; `Extend0rnd1.R:74`).
- `som::som(init = "sample")` — Initial codes drawn as random rows (from source; `som.R:10`).
- `flexmix::flexmix` — Initial posteriors assign a random cluster per observation, and SEM/random classification steps sample per row (from source; `flexmix.R:263, 278, 420`).
- `kohonen::supersom` — Initial codebook is `sample(1:nobjects, ncodes)`; online mode presents rows in random order (from source; `supersom.R:100`).
- `robustbase::lmrob` — S-estimator candidates are random row subsamples (`nResample = 500`) (from source; `lmrob.MM.R:61-80`).
- `robustbase::covMcd` (FAST-MCD) — Random row subsets; `nsamp = "deterministic"` is invariant (from source; `covMcd.R:195-204`).
- `robustbase::ltsReg` — FAST-LTS random row subsets (from source).
- `robustbase::glmrob` (`weights.on.x = "robCov"`, `"covMcd"`) — Inherits the random subsets of the robust covariance (from source).
- `Rtsne::Rtsne.data.frame` — Random initial embedding indexed by row (from source).
- `h2o::h2o.kmeans` — Random or PlusPlus initialisation with a seed (from source).
- `betareg::betamix` — flexmix EM with random initial clustering per row (from source).
- `rrcov::CovMcd`, `rrcov::CovMve`, `rrcov::CovSest`, `rrcov::CovMest`, `rrcov::CovMMest`, `rrcov::CovSde`, `rrcov::PcaHubert`, `rrcov::Linda`, `rrcov::Wilks.test(method = "mcd")` — Random elemental subsets or directions are indexed by row (from source; `Wilks.test.R:130, 222-226`).
- `prospectr::naes` — k-means with random starts (from source).
- `mvoutlier::aq.plot`, `mvoutlier::dd.plot`, `mvoutlier::uni.plot` and siblings — Built on `covMcd` random subsets (from source).
- `Rmixmod::mixmodCluster`, `Rmixmod::mixmodLearn` — Random or smallEM initialisation (from source).
- `mixture::gpcm`, `movMF::movMF` — Random or k-means starts (from source; `gh_mixture.R:4, 143`).

### 8d. Monte Carlo permutation and randomisation tests

23 entries.

- `mgcv::k.check`, `mgcv::gam.check`, `mgcv::qq.gam` — Unseeded positional subsample for n > 5000 and residual shuffles; p-values moved 0.1725 → 0.1525 under permutation (verified; `plots.r:195, 220, 248`).
- `bnlearn::ci.test` (`mc-*`, `smc-*`, `sp-*`) — Monte Carlo permutation tests permute row positions (from source; `R/globals.R:13-16`).
- `lmPerm::lmp`, `lmPerm::aovp` — Falls back to Monte Carlo permutations drawn in C when N > `maxExact` (from source; `permtst.R:45-48`).
- `qtl::scanone` (`method = "imp"`, `n.perm > 0`) — Imputations and permutations are drawn per individual (row) (from source; `scanone.R:570-620`).
- `lmodel2::lmodel2` (`nperm > 0`) — Permutation tests permute row positions (from source).
- `ape::lmorigin` — `nperm = 999` row permutations (from source; `lmorigin.R:81`).
- `Boruta::Boruta` — Random forests with shadow features from row permutations (from source).
- `agricolae::resampling.model` — `sample(yy)` permutes responses by position (from source; `resampling.model.R:19`).
- `clinfun::permlogrank` — `nperm = 5000` permutations of row positions (from source).
- `vegan::envfit`, `vegan::factorfit` — Permutation p-values reshuffle rows (from source).
- `vegan::adonis2`, `vegan::adonis`, `vegan::anosim`, `vegan::mrpp`, `vegan::bioenv`, `vegan::capscale`, `vegan::dbrda` — Permutation p-values permute row positions (from source).
- `vegan::anova.cca`, `vegan::simulate.capscale` — Row permutations of residuals (from source; `anova.cca.R:11`, `permutest.cca.R:167`).
- `vegan::adipart`, `vegan::multipart`, `vegan::hiersimu` — Null-model simulations (from source).
- `mstate::MarkovTest` — B bootstrap/permutation replicates (from source).
- `zCompositions::perLog` — Permutation tests (from source).
- `twosamples::ks_test`, `twosamples::cvm_test`, `twosamples::ad_test`, `twosamples::wass_test`, `twosamples::dts_test`, `twosamples::kuiper_test` — Permutation p-values permute pooled positions (from source).
- `h2o::h2o.permutation_importance` — `n_samples = 10000` subsample plus permutations (from source; `R/permutation_varimp.R:31-34`).
- `geoR::variog.mc.env`, `geoR::sample.geodata` — `data[sample(1:n.data)]` permutations (from source; `R/variogram.R:952-953`).
- `caper::fusco.test`, `caper::phylo.d` — Randomisation tests (from source).
- `labdsv::indval` — The permutation test reshuffles cluster labels by position; indicator values are invariant (from source; `R/indval.R:29`).
- `ranger::importance_pvalues` (Altmann) — Refits on permuted responses (from source).
- `metafor::rma.uni(test = "permutation")`, `metafor::permutest` — Permutation tests (from source).
- `TraMineR::dissmfacw`, `TraMineR::disstree`, `TraMineR::seqtree` — Permutation tests (from source).

### 8e. Random tie-breaking

12 entries.

- `base::max.col` (default `ties.method = "random"`) — Draws `unif_rand()` per tied row in row order, so the same seed gives different winners after permutation (verified; `src/appl/maxcol.c:75`).
- `MASS::lda(CV = TRUE)`, `MASS::qda(CV = TRUE)` — Global `min(dist)` normalisation underflows an outlier's posterior to `NaN`, and its class then comes from `max.col` random ties (verified; `lda.R:185`, `qda.R:161`).
- `MASS::predict.lda`, `MASS::predict.qda`, `MASS::predict.polr(type = "class")` — Class labels use `max.col`, whose random tie-breaking is drawn per row in row order (from source; `lda.R:288`, `qda.R:294`).
- `nnet::predict.nnet`, `nnet::predict.multinom` (`type = "class"`) — `max.col` ties are broken at random per row (from source; `nnet.R:228`, `multinom.R:195`).
- `class::knn`, `class::knn1` — Vote ties draw `unif_rand()` in test-row order (verified; `class.c:197`).
- `class::knn.cv` — Leave-one-out vote ties draw random numbers in row order; one tied row changed under permutation (verified).
- `class::lvqtest` — It is `knn1()` with random vote ties drawn per test row (from source).
- `randomForest::predict.randomForest` — Classification vote ties are broken at random per row (from source; `predict.randomForest.Rd:75`).
- `Matching::Match(ties = FALSE)` — Ties are broken at random (from source).
- `e1071::matchControls` (ties) — Distance ties are broken by `sample()` (from source; `matchControls.R:49-60`).
- `circular::watson.wheeler.test.formula` — Circular ranks use `rank(x, ties.method = "random")`, so tied values get RNG draws by position (from source; `watson.wheeler.test.R:112`).
- `copula::empCopula`, `copula::pobs` (`ties.method = "random"`) — Random tie-breaking of ranks by position (from source).

### 8f. Per-row draws: jitter, simulation, MCMC, sampling designs, random visiting order

23 entries.

- `graphics::stripchart` (`method = "jitter"`) — Draws `runif()` per row in row order (verified; `stripchart.R:87`).
- `lattice::densityplot` (default `plot.points = "jitter"`) — Draws `jitter(rep(0, n))` per row (verified; `densityplot.R:155-156`).
- `lattice::dotplot`, `lattice::stripplot` (`jitter.data = TRUE`) — `jitter()` per row (verified; `bwplot.R:462-467`).
- `class::lvq1`, `class::lvq2`, `class::lvq3`, `class::olvq1` — `sample(n, niter, TRUE)` draws row positions, then online updates follow in draw order (verified; `lvq.R:56, 83, 111, 140`).
- `class::SOM` — Picks random rows `i = (int)(n * UNIF)` and updates online; the same seed visits different data after permutation (from source; `class.c:396`).
- `cluster::clusGap` — Reference data drawn with `runif()` plus the clustering function's own randomness (verified; `clusGap.R:63`).
- `nlme::simulate.lme` — `set.seed(seed)` and draws are indexed by row and group, then refits (from source; `simulate.R:153`).
- `JM::survfitJM.jointModel` (`simulate = TRUE`) — Monte Carlo per subject (from source; `R/survfitJM.jointModel.R:175, 193`).
- `dbarts::bart2`, `dbarts::dbarts`, `dbarts::rbart_vi`, `dbarts::xbart` — MCMC over trees and random CV folds in `xbart` (from source).
- `statmod::qresiduals` — Randomised quantile residuals draw `runif(length(y))` per row (from source; `qres.R:34`).
- `vegan::specaccum(method = "random")` — Random site orderings drawn by position (from source).
- `zCompositions::lrDA` — Data augmentation MCMC (from source).
- `lqmm::lqm.counts` — Jittering draws per row (from source).
- `sampling::strata` — Within-stratum `srswor()` uses `sample.int` over positions (from source).
- `sampling::cluster` — Clusters are sorted levels; only the draws are positional (from source; `cluster.r:56`).
- `splitstackshape::stratified` — Within-stratum sampling by position (from source).
- `randomizr::declare_ra` — Random assignment is indexed by unit position within blocks or clusters (from source).
- `missMethods::impute_sRHD`, `missMethods::delete_MCAR` — Draws per row (from source).
- `geoR::jitterDupCoords` — Random jitter of duplicated coordinates (from source).
- `betareg::simulate.betareg`, `mclogit::simulate.mclogit`, `mclogit::simulate.mblogit` — One draw per fitted row (from source).
- `icenReg::ic_bayes` — MCMC with one log-likelihood pass per proposal (from source).
- `MCMCglmm::MCMCglmm` — Gibbs sampling draws per-row latent variables for non-Gaussian families (from source).
- `coneproj::shapereg(test = TRUE)` — Simulates `rnorm(n)` per row (from source).

**How to make it order-free:** Derive the randomness from a row key (a counter-based RNG or a hash of a stable id), or pass the random structure in explicitly (`foldid =`, `id.basis =`, `centers =` as a matrix, `xval =` as a vector, `inbag =`, `medoids =`).

## 9. Accumulation order and algebraic non-uniqueness

The mathematical result is order-free but the computed one is not: integer partial sums overflow depending on their order, floating-point noise creates or breaks ties, a non-convex optimiser amplifies rounding, and QR or SVD factors are unique only up to sign.
Headline estimates usually agree, while secondary components such as `$effects`, loading signs, tie counts or concordance differ.

10 entries, 8 verified.

- `base::rowsum` (integer columns) — Integer partial sums overflow to a sticky `NA` depending on summation order; a permutation of `c(.Machine$integer.max, 1L, -1L)` avoids it (verified; `src/main/unique.c:2035`).
- `stats::lm` (`$effects`, `$qr`) — Householder QR depends on row order: `$effects` and `qr.R()` row signs change; coefficients and tests do not (verified).
- `stats::aov` with `Error()` — Stratum sums of squares are invariant, but per-stratum `qty`/effects rows depend on the QR's row order (from source; `aov.R:106-125`).
- `stats::prcomp` — SVD has no sign convention; `rotation` and score signs flip under permutation, `sdev` invariant (verified; `prcomp.R:40`).
- `MASS::qda` — Per-group `qr()` is unique only up to row signs of R, so `scaling` column signs flip; posteriors are invariant (verified; `qda.R:135-141`).
- `MASS::mca` — Singular vector signs flip under permutation (verified).
- `nnet::nnet` — Non-convex BFGS amplifies floating-point summation order: permuted rows move weights by 47% with the same seed (verified).
- `survival::coxph` (`$concordance`) — Always runs `concordancefit()` on the fitted lp, whose floating-point ties shift under permutation (`tied.x` 121 vs 120); coefficients invariant (verified; `coxph.R:661-667`).
- `survival::royston` — Ties of the linear predictor are found by exact `duplicated(eta)`, so floating-point noise changes the tie count (153 vs 154) and R.D (verified; `royston.R:39`).
- `xgboost::xgb.ExtMemDMatrix`, `xgboost::xgb.QuantileDMatrix.from_iterator` — The quantile-sketch merge order of batches can shift histogram bin edges slightly (from source).

**How to make it order-free:** Accumulate in double or a wider integer, fix sign conventions (positive diagonal of R, `fix_sign = TRUE`), detect ties with a tolerance, and sort rows canonically when bitwise reproducibility matters.

## 10. Input order handed to user code

The function is order-free itself, but it passes each group's rows, or whole columns, to a user-supplied `FUN`, `j` or expression in input order.
Any positional user code (`x[1]`, `head()`, `cumsum()`, `seq_along()`, `shift()`, `paste()`) therefore makes the result order-dependent without a warning.

14 entries, 3 verified.

- `base::tapply` — `FUN` receives each group's values in input order, so `tapply(x, g, "[", 1)` changes under permutation (verified).
- `base::by.data.frame` — `FUN` sees each group's sub-frame in input order with its original row names (from source; `by.R:50`).
- `base::subset.data.frame`, `base::transform.data.frame`, `base::within.data.frame` — User expressions see whole columns in input order, so `x[1]`, `cumsum(x)` or a lag inside them is positional (from source; `frametools.R:25`).
- `stats::aggregate.data.frame`, `stats::aggregate.formula` — `FUN` gets each group's values in input order (`split(e, grp)`), so `function(v) v[1]` changes (verified; `aggregate.R:108`).
- `stats::ave` — `FUN = cumsum` or `seq_along` numbers rows within a group in input order (verified).
- `data.table::dcast.data.table` — `fun.aggregate` receives each cell's values in input order, so `function(x) x[1]` is positional (from source; `R/fcast.R:193`).
- `collapse::BY`, `collapse::rsplit` — An arbitrary `FUN` receives each group's rows in input order; `rsplit` keeps within-group row order (from source).
- `memisc::Within.data.frame` — Expressions see whole columns in input order (from source).
- `maditr::let`, `maditr::let_if`, `maditr::let_all`, `maditr::take`/`query` with positional `j` — `j` expressions using `shift()`, `first()`, `last()` or `.I` see rows in input order (from source).
- `maditr::dcast`, `maditr::to_wide` — `fun.aggregate` sees each cell's values in input order (from source).
- `plyr::ddply`, `plyr::daply`, `plyr::dlply`, `plyr::d_ply`, `plyr::summarise` — Within each group `.fun` sees rows in input order (from source).
- `plyr::mutate` — Expressions using `cumsum(x)` or other positional functions see columns in input order (from source).
- `reshape::cast`, `reshape::recast` — `condense` stably sorts, then `tapply(value, index, fun)`, so an order-sensitive `fun.aggregate` sees repeated keys in input order (from source; `condense.r:22-26`).
- `reshape::sparseby` — Stable sort by keys, then `FUN` per group in input order; invariant only if `FUN` is (from source).

**How to make it order-free:** Keep the callback order-free, or sort within groups by an explicit key before applying it (`setorder()` then `by =`, `arrange()` then `summarise()`).

## 11. Presentation only

The set of results is invariant, but output row order, group order, factor levels, labels, row names, returned row indices or plot z-order follow first appearance in the input.
It turns into a value change downstream as soon as something keys on position: a reference category, `levels[1]`, a `cbind()` with another output, or merging chunk results by code instead of by label.

63 entries, 22 verified.

- `base::rowsum(reorder = FALSE)` — Groups come out in first-appearance order (verified; `rowsum.R:29`).
- `base::split.data.frame` — Group names are sorted levels, but rows within each group and their row names follow input order (verified; `split.R:27`).
- `base::merge.data.frame` — With `sort = FALSE` keys are numbered by first appearance in `x`; within a key an unstable Shell sort scrambles rows (verified; `merge.R:111-112`, `src/main/util.c:667`).
- `base::unique.data.frame` — Same distinct rows, but their order and kept row names are those of first occurrences (verified; `duplicated.R:136`).
- `base::rbind.data.frame` — Factor levels of the result are the first-appearance union across arguments; new character values add levels in appearance order (verified; `dataframe.R:1354`).
- `stats::cutree` — Cluster numbers follow first appearance in observation order (same partition, different labels) (verified).
- `stats::reshape(direction = "wide")` — Columns follow `unique(timevar)` and rows follow `!duplicated(idvar)`, i.e. first appearance (verified; `reshape.R:140, 167`).
- `stats::complete.cases`, `stats::na.omit.data.frame`, `stats::na.exclude.data.frame` — The `"na.action"` attribute stores positional row indices, which change under permutation although the kept rows do not (verified; `nafns.R:85-86`).
- `graphics::boxplot` (`.default`, `.formula`, `.matrix`) — Statistics are invariant, but `out` and `group` list outliers in input row order (verified; `calc.R:41`).
- `graphics::barplot.formula` (`cbind()` LHS) — Bars are the columns of `t(mf[[1]])`, i.e. drawn in row order rather than level order (verified; `barplot.R:249-251`).
- `graphics::plot.formula`, `graphics::plot.data.frame`, `graphics::pairs`, `graphics::coplot`, `graphics::points.formula`, `graphics::text.formula`, `graphics::symbols`, `lattice::splom` — Marks are invariant; only overplotting z-order (and text overlap) follows row order (verified for `coplot`, `splom`; `plot.R:284-295`).
- `graphics::stripchart` (`method = "overplot"`) — Overplotting z-order follows row order; `"stack"` is invariant (from source; `stripchart.R:88-93`).
- `graphics::dotchart` — One line per input element at y = its position; with `groups` rows are stably sorted, keeping row order within a group (verified; `dotchart.R:81-94`).
- `graphics::stars` — Default `locations` lay glyphs out on a grid by row index (verified; `stars.R:56`).
- `grDevices::chull` — Returns row indices of hull vertices, which change under permutation; the vertex set is invariant (verified).
- `grDevices::boxplot.stats` — `out` keeps the outliers in input order (from source; `calc.R:41`).
- `lattice::barchart`, `lattice::panel.barchart` — Duplicated categories are overplotted, and stacked segments of duplicates stack in row order (verified; `bwplot.R:185-201`).
- `survival::finegray` — Values invariant after sorting; output grouped by stratum, then input order (verified).
- `survival::survcheck` — Reported problem rows are given as positions (from source).
- `survival::survobrien` — Presentation only: row layout follows input; a downstream `coxph` fit is invariant (from source).
- `cluster::mona` — The (variable, step) multiset is invariant; only the banner order follows input (verified).
- `nlme::varIdent` (and stratified `varPower`/`varExp`/`varConstPower`) — The reference stratum (ratio 1) is the first in data order, so reported ratios and sigma change; logLik and β do not (verified; `varFunc.R:364`).
- `nlme::lmList` — Coefficients invariant; the `origOrder` attribute is first-appearance order (verified; `lmList.R:95`).
- `nlme::collapse.groupedData` — Collapsed groups are ordered by `unique()` (from source; `groupedData.R:305`).
- `nlme::predict.lme` and siblings (`asList = TRUE`) — The list splits groups in first-appearance order (from source).
- `mgcv::uniquecombs(ordered = FALSE)` — Unique rows come out in first-appearance order; `ordered = TRUE` sorts (verified; `smooth.r:200-210`).
- `data.table::[.data.table` (`by=`) — Groups are re-ordered to first appearance; `keyby=` sorts them (verified; `R/data.table.R:1603-1609`).
- `data.table::merge.data.table` — Output is keyed but ties keep input order (from source; `R/merge.R:109`).
- `data.table::groupingsets`, `data.table::rollup`, `data.table::cube` — Each grouping set is evaluated with `by=`, so groups appear in first-appearance order (from source; `R/groupingsets.R:158-162`).
- `data.table::split.data.table` — The default `sorted = FALSE` keeps first-appearance group order (from source; `R/data.table.R:2547, 2571`).
- `insight::get_datagrid.data.frame` (character columns) — Levels follow `unique()` order (from source).
- `eha::toBinary` — Output layout follows input order (from source).
- `aod::splitbin` — Generated `idbin` labels follow input order (from source).
- `functionals::fmapg` — `split()` by group then apply, so within-group order and output follow the input (from source; `R/fmapg.R:28-33`).
- `lsr::longToWide` — Output columns ordered by first appearance of `within` (from source).
- `locpol::locpol` — The stored model frame and residuals are in sorted-x order, with ties in input order (from source; `locpol.R:759-760`).
- `proxy::dist`, `proxy::simil` — Output labels follow input order (equivariant) (from source).
- `ff::read.table.ffdf`, `ff::read.csv.ffdf` — Levels are sorted within the first chunk, then new levels are appended in order of appearance, so codes depend on chunk size and row order (from source; `ffcsv.R:172, 186`).
- `collapse::GRP`, `collapse::fgroup_by`, Fast Statistical Functions (`sort = FALSE`) — Groups follow first appearance; the default `sort = TRUE` is invariant (verified; `GRP.R:96, 403`).
- `collapse::funique` — The default `sort = FALSE` keeps first-appearance order (from source; `GRP.R:805, 818`).
- `datawizard::data_to_wide` — New columns are ordered by `unique(names_from)`, i.e. first appearance (from source; `data_to_wide.R:352`).
- `datawizard::data_merge` — Output row order follows the inputs (from source).
- `datawizard::data_rotate` — Transpose: output columns are input rows (from source).
- `ape::as.phylo.formula` — Tip order follows the data (from source).
- `gdata::mapLevels(sort = FALSE)` — Level map in first-appearance order (from source).
- `circlize::chordDiagramFromDataFrame` — Sector order defaults to first appearance and links are drawn in row order (from source).
- `geos::geos_inner_join` — Output row order follows the inputs (from source; `geos-join.R:50-58`).
- `data.tree::as.Node.data.frame` — Child order follows rows (from source).
- `memisc::contract.data.frame` (default `sort = FALSE`) — Cells listed in first-appearance order via `match(x, unique(x))` (from source; `contract.R:1-9`).
- `memisc::Reshape`, `memisc::to.data.frame` — Output order follows input order and `id` values (from source).
- `maditr::take`, `maditr::query`, `maditr::take_if`, `maditr::rollup`, `maditr::cube`, `maditr::groupingsets` (`by`) — Wrap `DT[i, j, by]`, so groups come in first-appearance order; `keyby` sorts (from source; `let.R:405-460`).
- `plyr::ddply` and siblings (more than 2^31 combinations) — Group ids switch to `match(char_id, unique(char_id))`, i.e. first appearance (from source; `id.r:44-46`).
- `udpipe::document_term_frequencies`, `udpipe::document_term_matrix` — Documents are levelled by `unique()`, so DTM rows follow first appearance (from source; `nlp_flow.R:285`).
- `statnet.common::compress_rows.data.frame` — Distinct rows and counts are invariant; the returned `ordering` attribute is positional (from source; `misc.utilities.R:221-229`).
- `marginaleffects::predictions(variables = "x")` (fewer than 6 values) — Counterfactual values are `unique()` in first-appearance order, so output rows follow input (from source; `R/sanitize_variables.R:162-164`).
- `caper::comparative.data` — Rows are reordered to tree order via `match()`; residue is presentation only (from source; `R/comparative.data.R:52-57`).
- `BMisc::make_balanced_panel`, `BMisc::set_balanced_panel` — `dt[, if (.N == nt) .SD, by = idname]` returns rows grouped by first appearance of the id (from source; `R/BMisc.R:32-33`).
- `BMisc::get_principal_components` — Presentation only: `dcast` + `prcomp()` output follows input layout (from source; `R/BMisc.R:1807-1814`).
- `metafor::aggregate.escalc`, `metafor::vcalc`, `metafor::rcalc` — Clusters are taken in `unique(cluster)` first-appearance order (from source; `aggregate.escalc.r:41`).
- `quanteda::dfm` — Types are numbered by first appearance, so dfm column order follows row order (from source; `tokens.R:648-651`).
- `quanteda::corpus.data.frame` — Duplicate docnames are made unique in row order (from source).
- `vctrs::vec_unique`, `vctrs::vec_group_id`, `vctrs::vec_group_loc` — Labels and output follow first appearance (from source).
- `metRology::mandel.kh.data.frame` (no `g`) — Rows are labs and the output follows row order (from source; `mandel.r:140-148`).

**How to make it order-free:** Use the sorted variant (`keyby =`, `sort = TRUE`, `reorder = TRUE`, `ordered = TRUE`, levels from `sort(unique())` or declared `levels =`), or sort the output by key before using it.

## 12. Bugs: two orderings or indices mixed up

Two vectors that must be aligned are built in different orders, one by first appearance (`unique()`, `!duplicated()`) and the other sorted (`levels()`, `rowsum()`, `order()`), or an index is simply wrong.
On sorted input the orders coincide and the bug is invisible; on unsorted input the values themselves, not just their presentation, are wrong.

9 entries, 9 verified.

- `graphics::spineplot` (Date, POSIXct, difftime x) — Axis labels index the unsorted `xorig` with a mask computed on sorted breaks; shuffled input gives wrong labels or an error (verified; `spineplot.R:149`).
- `MASS::loglm` (repeated cells with offset) — The `.Within.` factor reorders `fac` and `rsp` by `order(rev(fac))`, but the offset is taken unsorted, so offsets land on wrong rows (deviance +30%) (verified; `loglm.R:94-109`).
- `survival::survcondense` — Sorts by (id, stop) but two branches index `Y` in data order instead of through `index`, so unsorted input keeps the wrong start time (verified; `survcondense.R:61, 63`).
- `lsr::pairedSamplesTTest` (long form) — Wide columns follow first appearance of `within`, but labels come from `levels()`; listing the second level first flips the sign of t (verified; `longToWide.R:64`, `pairedSamplesTTest.R:363, 421`).
- `ff::csum`, `ff::cmean` (`na.rm = TRUE`) — Add `l[[1]]` instead of `l[[i]]`, so the first chunk is counted repeatedly: `csum(c(1,NA), c(2,3), na.rm = TRUE)` gives `2 NA` (verified; `CFUN.R:238, 254, 288, 311`).
- `sampling::strata` — `size` is matched to strata in first-appearance order of `unique(data[, stratanames])`, so reversing rows swaps sizes (a = 2, b = 8 becomes 8, 2) (verified; `strata.r:50`).
- `bain::t_test.formula` — `n` and `v` follow `unique()` first-appearance order while estimates follow `levels(g)`: BF.c 3.87 vs 7.49 after permutation (verified; `R/t_test_wrapper.R:145-148, 154-156`).
- `speedglm::updateWithMoreData`, `speedglm::update.speedlm(add = TRUE)` — Merged level set is unsorted, yet chunk X'X and X'y are added positionally; a chunk lacking a middle level permutes dummies (`fb` 0.315 vs 0.995) (verified; `speedlm.R:312, 343-379`).
- `survey::svydesign(pps = "brewer")` — `scale[!duplicated(cluster)]` (first appearance) multiplies `rowsum(x, cluster)` (sorted), so the variance changes (211891 vs 214730) (verified; `multistage.R:274, 276`).

**How to make it order-free:** Fix the code to index both sides by the same key; until then, sort the input by that key (stratum, PSU, id, factor level) before calling.
