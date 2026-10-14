# Order-free, chunkable data-frame consumers in R

Question: which functions in base R, the recommended packages, and CRAN packages of dependency depth 1–3
accept data frames, do not care about row order,
and could be rewritten to consume the data chunk by chunk (read a chunk, update a state, discard the chunk, finish)?

The per-function catalog with source citations is in `catalog.md` (1,223 entries; classes defined in `rubric.md`).
This report is the synthesis.

## Legend

Every function got two codes.

- **ORDER** — what happens when the rows are permuted:
  - `I` invariant: the result is a function of the multiset of rows (up to floating-point summation order).
  - `E` row-local: each output row depends only on its own input row plus fixed parameters.
  - `S` same set of results, but output order or labels follow first appearance.
  - `R` invariant only in distribution: random draws are indexed by row position, so a fixed seed gives a different answer.
  - `D` order-dependent: row position carries meaning.
- **CHUNK** — what a chunk-wise rewrite needs:
  - `M` map: stateless per chunk.
  - `A` one pass, fixed-size mergeable state (counts, sums, moments, X'X, incremental QR, min/max, fixed-grid bins).
  - `K` one pass, keyed mergeable state that grows with the number of distinct keys (groups, cells, unique values, event times).
  - `P` several passes, each `M`/`A`/`K` (IRLS, Newton, EM, Lloyd; or a pre-pass that fixes levels, ranges, knots).
  - `H` holistic: order-free, but needs all rows at once (exact quantiles, ranks, distances, neighbours, tree growing).

Across all 1,223 entries the most common combinations are `I`/`P` (203), `E`/`M` (177), `I`/`K` (141), `I`/`H` (132) and `I`/`A` (112).
Counting each entry's first-listed order class, 55% are `I`, 21% `E`, 6% `S`, 9% `R` and 9% `D`.
The subagents were asked to report `D` only for functions that look order-free,
so most of the `D` entries are traps rather than time-series code.

## Base R and recommended packages

### Row maps (`E`/`M`)

These are chunkable today, given parameters fixed in advance.

- `predict()` with `newdata` for `lm`, `glm`, `nls`, `loess`, `lda`/`qda`, `polr`, `multinom`, `nnet`, `rpart`, `coxph`, `lme`, `gls`,
  `gam` (mgcv already blocks it via `block.size`).
  The exception is `predict.bam()` on a `discrete = TRUE` fit, which re-discretises `newdata` against the batch's own range.
- `model.frame()`, `model.matrix()`, `Matrix::sparse.model.matrix()` —
  row-local *only* with declared levels (`xlev`) and frozen `predvars`.
- `subset()`, `transform()`, `within()`, `[.data.frame` with a logical index — row-local only if the user expression is.
- `complete.cases()`, `na.omit()`, `is.na()`, `Ops`/`Math` group generics (except the cumulative members of `Math`).
- `write.table(append = TRUE, col.names = FALSE)` — byte-identical to an unchunked write (verified).
  `write.csv()` is not: it ignores `append` and repeats the header on a connection.
- `foreign::write.arff()`, `write.foreign()`; `write.dta()` and `write.dbf()` need a width/range pre-pass.
- `survival::survSplit()`, `nlme` variance functions given parameters, `mahalanobis()` given centre and covariance.

### One pass, fixed-size state (`I`/`A`)

- The whole linear-model family: `lm()`, `lm.fit()`, `lm.wfit()`, `aov()` (no `Error()`), `lsfit()`, `manova()`,
  and everything derived from the fit: `summary`, `anova`, `vcov`, `confint`, `add1`/`drop1`/`step` (one scope-wide cross-product).
  State: Givens/TSQR factor or X'WX, X'Wy, y'Wy.
- `cov()`, `cor()` (Pearson), `cov.wt()`, `var()`, `sd()`, `weighted.mean()`, `colSums()`/`colMeans()`,
  `Summary.data.frame` (`sum`, `range`, …), `crossprod()`.
- `prcomp()`, `princomp()`, `factanal()`, `cancor()` (scores are a second `M` pass).
  `princomp(covmat =)` and `factanal(covmat =)` are already chunk-capable;
  feed `princomp` a `cov.wt(..., method = "ML")` list to reproduce `sdev`.
- `t.test()`, `var.test()`, `prop.test()`, `binom.test()`, `poisson.test()`, `prop.trend.test()`.
- `MASS::lm.ridge()`, `boot::corr()`, `nnet::nnetHess()`, `Matrix::crossprod()` of a sparse model matrix,
  `grDevices::chull()` (hull of union = hull of hulls), `extendrange()`, `nclass.Sturges()`.
- Binned smoothers with a fixed grid: `KernSmooth` linear binning is exactly additive (verified),
  and `locpoly(binned = TRUE)` and `bkfe(binned = TRUE)` already accept pre-binned counts, but `linbin`/`rlbin` are not exported.

### One pass, keyed state (`I`/`K`)

- Tables and everything that only reads a table:
  `table()`, `xtabs()`, `ftable()`, then `chisq.test()`, `fisher.test()`, `mantelhaen.test()`, `mcnemar.test()`,
  `MASS::loglm()`/`corresp()` on tables, `mosaicplot()`, `assocplot()`, `fourfoldplot()`.
  Simulated p-values in `chisq.test()`/`fisher.test()` draw from the margins only, so they are `I`, not `R` (verified).
  Merging chunk tables needs a level-aligning merge:
  adding two `xtabs` results with `+` silently puts counts under the wrong level (verified).
- Grouped reductions with a decomposable `FUN`: `rowsum()`, `tapply()`, `by()`, `aggregate()`, `ave()` (two passes),
  `split()` as the partition step.
  R cannot infer decomposability from a closure, so a chunked API needs `FUN` as a (map, combine, finalize) triple.
- Rank tests over (distinct value × group) frequency tables:
  `wilcox.test()`, `kruskal.test()`, `ansari.test()`, `mood.test()`, two-sample `ks.test()`, `fligner.test()`, Spearman `cor()`,
  and all nine `quantile()` types.
  This is exact, and it turns `H` into `K` whenever the number of distinct values is bounded;
  `mood.test()` already works this way under ties.
  Also `bartlett.test()`, `oneway.test()`, `friedman.test()`, `TukeyHSD()`, `ecdf()`, `unique.data.frame()`.
- Keyed by unique `x`: `isoreg()`, `approx(ties = mean)`, `sortedXyData()` and the self-start models, `smooth.spline()` after a pre-pass,
  `xyTable()`/`sunflowerplot()`.
- Keyed by group: `MASS::lda()`/`qda()` (count, sum and cross-product per class),
  `nlme::lme()` with `pdMat`-only random effects (it already reduces each group to an R factor of `[Z X y]` before optimising;
  `MEdecomp`, lme.R:306-310),
  `nlme::lmList()`, `nlme::gsummary()`, `survival::clogit()`.
- Keyed by unique event time: `survival::survfit()` Kaplan–Meier/Aalen–Johansen, `survdiff()`, `aareg()`, `pyears()`, `coxph.detail()`.
- `stats::free1way()` (R-devel only) is already chunk-capable:
  it reduces every input to an `xtabs()` and works on that alone (verified equal on summed chunk tables).

### Several passes (`I`/`P`)

- Pre-pass then map — the global-information functions:
  `factor()`, `droplevels()`, `interaction()`, `cut(breaks = <n>)`, `data.matrix()` on character columns,
  `scale()` (moments, then apply), `poly()`, `splines::ns()`/`bs()` (knots at quantiles, so `H` unless knots are given),
  `utils::type.convert()` (a 4-bit "can still be logical/integer/double/complex" mask per column, ANDed across chunks),
  `hist()` (n and range, then counts on fixed breaks), `density()` with numeric `bw` (range, then additive binning), `MASS::kde2d()`,
  `KernSmooth::bkde()`/`bkde2D()`.
- Iterative fitters, one `A` pass per iteration:
  `glm()` and its `anova`/`step`/`profile`/`confint`, `nls()`, `kmeans(algorithm = "Lloyd")`,
  `MASS::glm.nb()`, `polr()`, `fitdistr()`, `boxcox()`, `cov.trob()`, `rlm(scale.est = "Huber")`,
  `nnet::multinom()` (`summ = 2/3` already compresses rows to unique patterns), `nnet()`,
  `survival::survreg()`, `class::batchSOM()`, `spatial::surf.ls()`, `MASS::ucv()`/`bcv()` (exact in 2 passes,
  and O(n + nb²) instead of the current O(n²)).
- Iterative fitters with keyed state per iteration:
  `survival::coxph()` (per unique time S0, S1, S2, then reverse cumulative sums; `coxfit6_iter` already accumulates exactly this),
  `nlme::gls()` with `varFunc`, `nlme::nlme()`/`gnls()`, `mgcv::gam()` (PIRLS after a basis pre-pass).
- Already chunk-capable: `mgcv::bam(chunk.size =)`, `mgcv::bam.update()` (exact appending for Gaussian additive models),
  `mgcv::predict.gam(block.size =)`.
  The best mgcv target is `bam(discrete = TRUE)`: its discretisation and each PIRLS step need bounded state,
  and only the in-memory model frame and n-length index vectors keep it from being fully out-of-core.

### Holistic (`I`/`H`)

These are order-free but need all rows: `quantile()`, `median()`, `mad()`, `IQR()`, `fivenum()`, `boxplot.stats()`,
the quartiles in `summary.data.frame()`,
Kendall's tau, `density()` and `smooth.spline()` with default bandwidth/tolerance (they call `IQR`), `shapiro.test()`,
`loess()`, `lowess()`, `supsmu()`, `ppr()`, `dist()`, `hclust()`, `cmdscale()`, everything in `cluster` except `mona()`,
`rpart()` tree growing, `MASS::rlm()` (MAD scale), `isoMDS()`, `sammon()`, `spatial::surf.gls()`, `variogram()`, `order()`/`sort_by()`.
The escape hatches are value-count tables when distinct values are few (exact),
quantile sketches (approximate; boxplot can then be drawn with the existing `bxp()` and `panel.bwplot(stats =)` hooks),
and chunking over prediction rows only.

### Graphics

Two senses of "chunkable" apply.
The *computed summary* (axis limits, bin counts, box statistics) is mostly order-free and needs one range pass plus one binning pass;
`hist()`, lattice `histogram()`, `smoothScatter()` (3 passes), `chull()` and `xyTable()` merge exactly.
The *drawing* can be done chunk by chunk after a range pre-pass (`plot.new(); plot.window(); points()` per chunk,
or lattice `trellis.focus()` + `panel.points()`),
but overplotting order follows input order (`S`), and `type = "l"` connects rows in input order (`D`).

## CRAN packages at depth 1–3

### Already chunk-capable (prior art)

- Fitters: `biglm::biglm()`/`update()` (incremental Givens QR) and `bigglm(data = function(reset))` (one pass per IRLS iteration);
  `speedglm::shglm(datafun =)` and `updateWithMoreData()`; `fastglm::fastglm_streaming()`; `xgboost` `xgb.DataIter`/`xgb.ExtMemDMatrix`;
  `leaps::regsubsets()` (with a `biglm` method); `irlba` (any matrix class with `%*%`).
- Sufficient-statistics front ends: `lavaan` (`sample.cov`, `sample.mean`, `NACOV`), `dagitty::localTests(sample.cov =)`, `emmeans::qdrg()`.
- Approximate or subsampling designs: `quantreg::rq(method = "pfn")`, `robustbase` random-subset partitioning,
  `h2o` (distributed GLM, approximate quantiles).
- Readers, writers, engines: `data.table::fread(skip =, nrows =)` and `fwrite(append = TRUE)`, `nanoparquet::append_parquet()`,
  `nanoarrow`, `duckdb`, `fst::read_fst(from, to)`, `hdf5r`, `ff::chunk()`, `iterators::iread.table()`/`idiv()`,
  `RODBC::sqlSave(append = TRUE)`, `terra::global()`/`zonal()`.
- Domain-specific: `survey::svydesign(dbtype =, dbname =)` (loads only needed columns, not row chunks),
  `eha::toTpch()` → `tpchreg()` (compress, then fit), `CDM::din()` (response-pattern counts), `scam::predict.scam(block.size =)`, `wk`,
  `udpipe(parallel.chunksize =)`, `reclin2` (pattern tables merged by summing).

### Best new targets

- Depth 1:
  - `data.table` grouped aggregation with decomposable GForce functions (`sum`, `mean`, `var`, `.N`),
    `dcast()` with a decomposable `fun.aggregate`, `uniqueN()` (`K`).
  - `hexbin` (fixed-grid counts, `A`), `naivebayes` (per-class counts and sums, `K`;
    the fitted object stores the whole training set, which a streaming version must drop).
  - `pls::plsr()`/`pcr()` with kernelpls/simpls/svdpc (all from X'X and X'Y, `A`), `lars`, `SparseM::slm()`, `moments`, `ppcor`, `lmodel2`.
  - `psychotools::raschmodel()` (item totals and raw-score counts are sufficient, `K`), `ca::mjca()` (Burt matrix),
    `bnlearn::ci.test()`/`bn.fit()`.
  - `VGAM::vglm()`, `mclust::me()`/`em()`, `pscl::zeroinfl()`/`hurdle()`,
    `gss::ssanova()` (two passes with a reservoir-sampled basis) (`P`).
- Depth 2:
  - `collapse` `fsum`/`fmean`/`fvar`/`qsu`/`collap()` (`K` with a global group dictionary).
  - `sandwich::vcovHC()` (2 passes) and `vcovCL()` (keyed by cluster); `lmtest::bptest()`, `resettest()`,
    `coxtest()`/`jtest()`/`encomptest()` (Gram matrices).
  - `psych::polychoric()`/`tetrachoric()` (tables), `fa()`/`principal()`/`corr.test()` (cross-products), `ICC(lmer = FALSE)`.
  - `vegan::rda()`/`cca()`/`varpart()` (Gram of [Y, X, Z]); `pROC::roc()`/DeLong (counts per distinct score, `K`).
  - `ordinal::clm()`, `e1071::naiveBayes()`, `poLCA` (response-pattern counts), `gnm` with `eliminate`,
    `lavaan` statistics computed per group and per missingness pattern (`K`).
- Depth 3:
  - `glmnet()` gaussian in covariance mode (the default when nvars < 500):
    Gram plus moments in one pass gives the whole lambda path exactly (`A`).
    `cv.glmnet()` becomes one pass keyed by fold once fold ids are hashed from a row key.
  - `survey::svytotal()`/`svymean()`/`svyratio()`/`svyby()` (`K` keyed by stratum × PSU; confirmed invariant on `apiclus2`);
    `svyglm()` is `P`; replicate weights are `A`.
  - `lfe::felm()` (alternating projections with `K` state per fixed-effect level — the model case of "multi-pass, keyed").
  - `gam::gam()` with `s()` (backfitting with state keyed by unique x), `ade4::dudi.pca()`/`dudi.coa()`/`dudi.acm()` (Gram, then scores).
  - `marginaleffects::avg_predictions()`/`avg_slopes()` (one keyed pass, delta-method SEs included,
    since the p+1 perturbed coefficient vectors are known in advance).
  - `eRm::RM()`/`PCM()`, `icenReg::ic_np()`, `ks::kde()` (already bins), `semTools::mardiaSkew()` (O(n²) loop that needs only two passes),
    `MCMCpack::MCMCregress()` (X'X, X'y, y'y).

## Traps: functions that look order-free but are not

Each of these was confirmed by permuting rows with a fixed seed, except where marked "from source".

- Base R:
  - `rowsum()` on integer columns: a partial sum that overflows becomes a sticky `NA` (unique.c:2035, :2109),
    so `c(INT_MAX, 1L, -1L)` gives `NA` but `c(INT_MAX, -1L, 1L)` gives `INT_MAX` (re-checked).
  - `max.col()` breaks ties at random per row (default), `unstack()` pairs the i-th occurrence of each group,
    `cumsum()` and friends hide inside `Math.data.frame`.
  - `merge()` emits rows within a key in an unstable Shell-sort order, and with several `by` columns sorts on pasted strings (10 < 2 < 9).
  - `rbind()` builds factor levels in first-appearance order, so the order in which chunks are combined changes the levels.
  - `as.matrix()`, `format()` and `apply(df, 1, …)` on mixed-type frames pick number formats from the whole column,
    so a chunk formats differently.
- stats:
  - `kmeans()`: random starts index rows (`R`),
    and the default Hartigan–Wong and MacQueen depend on row order even from fixed centres (only 12% and 30% of 40 permutations agreed);
    only Lloyd is order-free.
  - `hclust()` with tied distances (except single linkage), `cutree()` labels, `SSfol` starting values (uses the last row),
    `approx(ties = "ordered")`.
  - `pairwise.t.test()`/`pairwise.wilcox.test()` with `paired = TRUE` pair by position;
    `reshape(direction = "wide")` takes columns in first-appearance order.
  - `aggregate()` merges numeric keys that print the same (`0.1 + 0.2` and `0.3`) under the first row's label.
- Recommended packages:
  - `nlme` `corAR1()`/`corARMA()`/`corSymm()`/spatial classes without `form = ~ time | g` use position within group as time
    (logLik −568.1 vs −612.5); `glmmPQL()` and `gamm()` inherit this.
  - `nlme::varIdent()` takes the first-appearing stratum as reference (`S`).
  - `mgcv::bam()` with `discrete = FALSE` and n > `chunk.size` builds the basis on a subsample chosen by row position (`R`).
  - `rpart()` assigns cross-validation folds by position (`R`); `cluster::clara()` ignores `set.seed()` and samples by position;
    `pam()`/`agnes()` break ties by index.
  - `MASS::loglm()` on a data frame with repeated cells and an offset attaches offsets to the wrong rows (deviance changed by 30%).
  - `survival::survcondense()` keeps the wrong start time on unsorted input (re-checked: 10 instead of 0);
    `tmerge()` resolves tied `tdc()` values by input order;
    `concordance()` ties can differ by one ulp of the linear predictor depending on row position.
  - `spineplot()` with a Date x errors on unsorted input; `levelplot(region.type = "contour")` assumes grid order;
    `contourplot()`/`levelplot()`/`wireframe()` keep the last row for duplicated cells.
- CRAN:
  - `gee`: clusters are runs of contiguous equal `id`; shuffling turned 60 subjects into 296 clusters.
  - `multgee` without `repeated=` numbers occasions by position;
    `GLMMadaptive` and `lqmm` take per-subject weights from first-appearing rows.
  - `lmtest::raintest()`, `gqtest()`, `hmctest()` split by position unless `order.by` is given;
    `sandwich::vcovPL()`/`vcovPC()` use position within cluster as time, and `vcovHAC()` defaults to `1:n`.
  - `gmm::gmm()` with the default `vcov = "HAC"` uses autocovariances between adjacent rows, even for cross-sectional data.
  - `collapse::collap()`'s default `catFUN` is `fmode(ties = "first")`;
    `datawizard::distribution_mode()` documents the smallest tied value but returns the first;
    `marginaleffects::datagrid()` breaks mode ties by first appearance.
  - `psych::alpha()` reads a zero-variance item's value from row 1; `vegan::specaccum(method = "collector")`;
    `sampling::strata()` matches `size` to strata by first appearance.
  - `lsr::pairedSamplesTTest()` (long form) flips the sign of t; `effsize::cohen.d(paired = TRUE)` pairs by position;
    `mclust::Mclust()` depends on order through ties in its hierarchical start.
  - `JM` dynamic predictions take each subject's last row, not its latest time; `gbm(train.fraction =)` trains on the first rows;
    `dfidx` builds indices from position (from source).
  - `raster::rasterize()` defaults to `fun = "last"`; `spatstat.geom::as.im.data.frame()` keeps the last duplicate (from source).
  - `data.table` `by=` returns groups in first-appearance order (`S`; use `keyby=`), and `unique()`/`duplicated()` keep the first row.

## What every chunked rewrite needs: global information

Almost every exact rewrite above fails for the same few reasons, so a shared infrastructure would fix them all at once.

- **Factor levels.**
  `lm()` and `glm()` force `drop.unused.levels = TRUE`, and `model.matrix()` turns character columns into factors per call,
  so a chunk that lacks a level gets fewer columns and a different baseline.
  The pre-pass is `stats::.getXlevels()` (a `K` union), passed back as `xlev`.
- **Data-dependent bases.**
  `poly()`, `scale()`, `ns()`/`bs()`, mgcv smooth constructors, `cut(breaks = n)`,
  histogram breaks and density ranges must be frozen by a pre-pass (`makepredictcall()` already captures them once computed).
  Whole-column expressions in formulas or `subset()` (`I(x - mean(x))`, `x > mean(x)`) silently become chunk-local.
- **Types and formats.**
  `type.convert()` per chunk is lossy (`"007"` becomes `7L` in a chunk where the global column is character),
  and mixed-type `as.matrix()`/`format()` picks column-wide formats.
- **The combine step.**
  `rbind()` builds factor levels in first-appearance order, and adding contingency tables with `+` misaligns levels;
  merges must align by label.
- **Random numbers.**
  Folds, starts and subsamples drawn by row position make results `R`;
  hashing fold ids or seeds from a row key makes them order-free and chunkable.

These traps are not hypothetical; existing chunked fitters fall into them.
`biglm` builds its model frame from each chunk without carrying levels or `predvars` forward.
Re-checked here: fitting `y ~ poly(x, 2)` in two chunks gives a coefficient of 5.52 instead of 7.81,
and chunks with level sets {a, b} and {a, c} silently code "c" as "b".
`speedglm::updateWithMoreData()` adds X'X positionally after merging level sets without sorting;
when a later chunk lacks a middle level and drops it, `fb` comes out as 0.315 instead of 0.995 (re-checked).
`shglm()` in the same package aligns by column name and is correct.

## Bugs found along the way

These are outside the question, but each one is reproducible.

- Re-checked in this session:
  - `stats::quade.test()` (this R-devel checkout):
    `b <- nlevels(blocks)` is computed before blocks with missing values are dropped (quade.test.R:46-49),
    so `B` and the degrees of freedom are wrong when any block has an NA.
  - `class::SOM()`: the neighbour-update loop sits inside the winner search and reuses its counter `cd`,
    so only code 1 can ever be the winner.
  - `MASS::lqs(method = "S")` stores the refined coefficients as `$coefficents` (lqs.R:164), so `coef()` returns the unrefined ones.
  - `biglm::bigglm(sandwich = TRUE)`: an inner `for (i in 1:p)` overwrites the IRLS counter (bigglm.R:36, 74),
    so the fit stops early and reports non-convergence when p ≥ `maxit`.
  - `survival::survcondense()`, `speedglm::updateWithMoreData()`, `biglm` with `poly()` and differing level sets (see above).
  - `KernSmooth`'s internal `linbin()` drops a point exactly at the upper grid end.
- Reported and reproduced by the subagents, not re-checked here:
  `bain::t_test.formula()` stores group n and variance in first-appearance order but means by level (BF.c 3.87 vs 7.49);
  `survey` Brewer PPS variance depends on row order (multistage.R:274-276);
  `MASS` `VR_den_bin` writes out of bounds when `nb < 101` (valgrind);
  `nnet::multinom(summ = 1)` merges distinct non-integer covariate rows;
  `lda(CV = TRUE)` gives all-`NaN` posteriors for outlying rows;
  `ff` `csum`/`cmean` with `na.rm = TRUE` add `l[[1]]` instead of `l[[i]]`;
  `datawizard::winsorize()` fails to clip the upper tail with NAs;
  `biglm` counts n before `na.omit` and `predict(se.fit = TRUE)` crashes;
  loading `circular` makes `var(df)` return per-column variances.

## Method and coverage

- **Depth.**
  Base and recommended packages are depth 0.
  A depth-k CRAN package's Depends/Imports/LinkingTo all have depth < k, at least one has depth k − 1.
  On today's CRAN that gives 4,637 packages at depth 1, 2,694 at depth 2 and 2,091 at depth 3.
- **Selection.**
  Download statistics were not reachable from this environment, so packages were ranked by reverse-dependency count (Depends, Imports,
  LinkingTo, Suggests).
  In scope: every depth-1–3 package with at least 10 reverse dependencies,
  plus statistical or data-frame packages (by title and description) with at least 5 — 1,038 packages (500, 305 and 233 by depth).
  The remaining ~8,400 depth-1–3 packages were not examined.
- **Static scan.**
  The R sources were parsed for exported functions and registered S3 methods
  that take a data-like argument together with `model.frame`/`terms`/`as.data.frame` use,
  are `*.data.frame`/`*.formula` methods, or coerce an `x` argument from a data frame.
  That gave 2,977 candidates in 424 packages; S4 methods and compiled code are invisible to it,
  so the subagents also skimmed packages with no candidates.
- **Classification.**
  13 subagents classified functions against a shared rubric from the source code (R sources of this R-devel checkout,
  CRAN tarballs for recommended and CRAN packages),
  and checked non-obvious claims by permuting rows with a fixed seed and comparing with `all.equal()` on R 4.5.3.
  Claims about compiled code in CRAN packages were reasoned from the R wrappers and documentation and are marked as such in the catalog.
