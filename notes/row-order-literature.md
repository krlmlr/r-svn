# Ignoring row order: literature, projects, and R packages

This note surveys the prior art for computations whose result depends only on the multiset of rows.
Such computations are invariant to row permutation, so data can be shuffled, partitioned, streamed in chunks,
processed in parallel, or pushed down to a database without changing the answer.
It builds on an earlier catalogue of about 1,200 data-frame-consuming functions in base R, the recommended packages,
and CRAN packages of dependency depth 1–3.
That catalogue classified each function by order class
(invariant, row-local, first-appearance presentation, invariant in distribution, order-dependent)
and by chunk class (stateless map, mergeable fixed-size state, keyed state, several passes, holistic).

**How citations were checked.**
Each item was checked by web search against an index or publisher record
(DBLP, ACM, vldb.org, PMLR, JMLR, Numdam, Project Euclid, journal pages),
or by reading primary source text: R help pages and NEWS files of installed packages, CRAN tarballs, and framework source code on GitHub.
Full texts of many papers could not be fetched from this environment,
so a quoted wording sometimes rests on a search snippet or a secondary source; this is said where it applies.
Items marked **unverified** could not be confirmed and should be checked before they are cited.

## 1. Database theory and practice

### The relational model

- Codd, E. F. (1970). "A Relational Model of Data for Large Shared Data Banks." *Communications of the ACM* 13(6), 377–387. <https://doi.org/10.1145/362384.362685>
  - Section 1.2.1, "Ordering Dependence", is the first of three dependencies Codd wants applications freed from.
    His example is a file stored in part-number order, where programs break when the storage order changes.
  - Section 1.3 lists the properties of a relation drawn as a table,
    including that the ordering of rows is immaterial and that all rows are distinct.
    This is the founding statement that queries must not depend on row order.
  - Title, venue, and year were verified; the DOI and pages come from the standard record.
- Codd, E. F. (1990). *The Relational Model for Database Management: Version 2.* Addison-Wesley.
  The book exists; its exact wording on ordering is **unverified**.

### Bags versus sets

SQL tables are bags: they keep the "order does not matter" property of relations but allow duplicate rows.

- Albert, J. (1991). "Algebraic Properties of Bag Data Types." *VLDB '91*, 211–219. <https://www.vldb.org/conf/1991/P211.PDF>
  - Gives an algebra of bag operations as a basis for defining bag semantics and optimising queries over them.
- Chaudhuri, S. & Vardi, M. Y. (1993). "Optimization of Real Conjunctive Queries." *PODS '93*, 59–70. <https://doi.org/10.1145/153850.153856>
  - Shows that containment and equivalence results proven under set semantics do not carry over to bag semantics.
    Multiplicity matters to the answer; position never does.
- Grumbach, S. & Milo, T. (1993). "Towards Tractable Algebras for Bags." *PODS '93*, 49–58. <https://doi.org/10.1145/153850.153855>
  (journal version: *JCSS* 52(3), 570–588, 1996).
  - Analyses how duplicates affect the expressive power and complexity of a nested algebra for bags.

For R, the multiset-of-rows view is exactly bag semantics: a data frame with a duplicated row is a different input, a reordered one is not.

### SQL: no row order without ORDER BY

- PostgreSQL documentation, §7.5 "Sorting Rows (ORDER BY)". <https://www.postgresql.org/docs/current/queries-order.html>
  - Without `ORDER BY`, rows are returned in an unspecified order that depends on scan and join plans and on the order on disk.
- Microsoft, "ORDER BY Clause (Transact-SQL)". <https://learn.microsoft.com/en-us/sql/t-sql/queries/select-order-by-clause-transact-sql>
  - `ORDER BY` in a view, inline function, derived table, or subquery does not guarantee ordered output unless the outer query also orders.
- SQLite, `PRAGMA reverse_unordered_selects`. <https://www.sqlite.org/pragma.html#pragma_reverse_unordered_selects>
  - A debugging switch that reverses the output of unordered `SELECT`s,
    so applications that accidentally depend on the stable-but-unspecified order are exposed.
    It is the database world's own row-order-invariance test.
- PostgreSQL tutorial §3.5, "Window Functions". <https://www.postgresql.org/docs/current/tutorial-window.html>
  - The order in which window functions process rows is set by `ORDER BY` inside `OVER`, independently of output order.
    `row_number()`, `lag()`, and running sums are deterministic only with that explicit order.

### Query optimisation relies on order being free

- Selinger, P. G., Astrahan, M. M., Chamberlin, D. D., Lorie, R. A. & Price, T. G. (1979).
  "Access Path Selection in a Relational Database Management System." *SIGMOD '79*, 23–34.
  <https://courses.cs.washington.edu/courses/cse444/25wi/papers/selinger79.pdf>
  - Introduces "interesting orders": an order is kept only where `ORDER BY`, `GROUP BY`,
    or a merge join can use it, and is otherwise a free choice of the optimiser.
- Graefe, G. (1990). "Encapsulation of Parallelism in the Volcano Query Processing System." *SIGMOD '90*. <https://doi.org/10.1145/93597.98720>
  - The exchange operator repartitions rows across processes and interleaves their output nondeterministically,
    which is correct only because order carries no meaning.
- Graefe, G. (1993). "Query Evaluation Techniques for Large Databases." *ACM Computing Surveys* 25(2), 73–170. <https://pages.cs.wisc.edu/~yxy/cs764-f20/papers/p73-graefe.pdf>
  - Describes the duality of sort-based and hash-based algorithms;
    hash aggregation and hash joins are valid substitutes only because output order is not part of the contract.
- Simmen, D., Shekita, E. & Malkemus, T. (1996). "Fundamental Techniques for Order Optimization." *SIGMOD '96*, 57–67. <https://doi.org/10.1145/233269.233320>
  - Uses keys, predicates, and functional dependencies to push sorts down or prove them unnecessary (implemented in DB2).
- Neumann, T. & Moerkotte, G. (2004). "A Combined Framework for Grouping and Order Optimization." *VLDB 2004*, 960–971. <https://www.vldb.org/conf/2004/RS24P3.PDF>
  (preceded by "An Efficient Framework for Order Optimization", *ICDE 2004*, 461–472).
  - Distinguishes a *grouping*, where equal keys need only be adjacent, from a full *ordering*.
    This is the formal counterpart of R's "first-appearance presentation" class: a weaker property than sorted, stronger than unordered.

### Order-preserving and order-agnostic operators

- W3C (2017). *XQuery 3.1: An XML Query Language.* Recommendation. <https://www.w3.org/TR/xquery-31/>
  - Has an explicit ordering mode (`ordered` / `unordered`), plus `unordered { }` and `fn:unordered()`,
    so that a query can opt out of document order and let the engine optimise.
    It is the clearest language-level precedent for declaring that order does not matter for one sub-expression.

### Dataframe systems

- Petersohn, D. et al. (2020).
  "Towards Scalable Dataframe Systems." *PVLDB* 13(11), 2033–2046. <https://doi.org/10.14778/3407790.3407807> (arXiv:2001.00888)
  - Defines a dataframe algebra in which rows are *ordered* and labelled,
    and names ordering as a feature that distinguishes dataframes from relations.
    It discusses what that costs for scaling, with Modin as the implementation.
  - The page range is from the standard record and was not checked against the PDF.
- Petersohn, D. (2021). *Dataframe Systems: Theory, Architecture, and Implementation.* PhD thesis, UC Berkeley, UCB/EECS-2021-193.
  <https://www2.eecs.berkeley.edu/Pubs/TechRpts/2021/EECS-2021-193.html>
- pandas, "Intro to data structures". <https://pandas.pydata.org/docs/user_guide/dsintro.html>
  - Binary operations between Series align on index labels rather than position, so pandas stores rows in order but matches them by key.
- Polars, `DataFrame.group_by(maintain_order=)` and `DataFrame.unique(maintain_order=)`.
  <https://docs.pola.rs/api/python/dev/reference/dataframe/api/polars.DataFrame.group_by.html>
  - Group order is not kept by default; `maintain_order=True` is documented as slower and as blocking the streaming engine.
  - "Announcing Polars 2.0" (<https://pola.rs/posts/announcing-polars-2/>) reportedly makes the streaming engine the default and drops order guarantees for joins and group-bys unless requested.
    This was seen only in search summaries and is **unverified**.
- Apache Arrow Acero (C++ streaming engine). <https://arrow.apache.org/docs/developers/cpp/acero.html>
  - In the headers `exec_plan.h` and `options.h`, a source's ordering defaults to `Ordering::Unordered`.
    `Ordering::Implicit` marks a meaningful order not represented by any column, which filter and project nodes preserve.
- DuckDB, "Order Preservation". <https://duckdb.org/docs/current/sql/dialect/order_preservation>
  - Single-table `FROM`, `WHERE`, `SELECT`, `LIMIT`, and `UNION ALL` preserve order;
    `JOIN`, `UNION`, `GROUP BY`, and aggregation do not, and `ORDER BY` may be unstable.
  - The setting `preserve_insertion_order` (default `true`) can be turned off.
    This reduces memory use for larger-than-memory imports and exports.
    The page suggests `row_number() OVER ()` to turn the original order into an explicit column.
- Apache Spark, `pyspark.sql.functions.collect_list`.
  <https://spark.apache.org/docs/3.5.0/api/python/reference/pyspark.sql/api/pyspark.sql.functions.collect_list.html>
  - Documented as non-deterministic
    "because the order of collected results depends on the order of the rows which may be non-deterministic after a shuffle".

### Relevance for R

R's `data.frame` belongs to the dataframe tradition that Petersohn et al. formalise:
rows are positional, and many functions return results in input or first-appearance order.
The database line from Codd to DuckDB shows what an explicit contract buys.
When an operation is defined as invariant to permutation up to an explicit sort, an engine is free to hash, partition,
and stream it, and users opt back into order with `ORDER BY`, `maintain_order`, or `preserve_insertion_order`.
Base R mixes order-preserving and order-defining behaviour without a stated contract.
`merge(sort = FALSE)` is documented as giving "an unspecified order", while `aggregate()` and `split()` sort by factor levels.
This matters most where R code is translated to SQL or Acero,
because an order-dependent R expression can silently change meaning in translation.

## 2. Distributed and streaming computation

### MapReduce and the classification of aggregates

- Dean, J. & Ghemawat, S. (2004). "MapReduce: Simplified Data Processing on Large Clusters." *OSDI '04*, 137–150.
  <https://www.usenix.org/legacy/events/osdi04/tech/full_papers/dean/dean.pdf>
  - Section 4.3 introduces the *combiner*, which partially merges map output on each machine before the shuffle.
    It may be used when the reduce function is commutative and associative,
    because the framework decides how often and in what grouping it runs.
    The "commutative and associative" wording is confirmed only through secondary sources.
- Apache Hadoop, "MapReduce Tutorial". <https://hadoop.apache.org/docs/stable/hadoop-mapreduce-client/hadoop-mapreduce-client-core/MapReduceTutorial.html>
  - The combiner is optional local aggregation, may also run during spills, and in WordCount is the reducer itself.
- Gray, J., Chaudhuri, S., Bosworth, A., Layman, A., Reichart, D., Venkatrao, M., Pellow, F. & Pirahesh, H. (1997).
  "Data Cube: A Relational Aggregation Operator Generalizing Group-By, Cross-Tab, and Sub-Totals."
  *Data Mining and Knowledge Discovery* 1(1), 29–53.
  <https://doi.org/10.1023/A:1009726021843> (arXiv:cs/0701155)
  - Classifies aggregates as *distributive* (`COUNT`, `SUM`, `MIN`, `MAX`: partials over disjoint partitions combine directly),
    *algebraic* (`AVG`, standard deviation: a fixed-size tuple of distributive values),
    and *holistic* (median, mode, rank: no constant-size partial state).
    This taxonomy is exactly the earlier catalogue's split between mergeable fixed-size state and holistic computation.

### Mergeable summaries and monoids

- Agarwal, P. K., Cormode, G., Huang, Z., Phillips, J. M., Wei, Z. & Yi, K. (2012). "Mergeable Summaries." *PODS 2012*.
  <https://doi.org/10.1145/2213556.2213562>; extended in *ACM TODS* 38(4), article 26, 2013, <https://doi.org/10.1145/2500128>.
  - A summary is mergeable if two summaries can be combined into a summary of the union with the same error and size guarantees,
    under any merge tree.
    Misra–Gries and SpaceSaving heavy hitters are mergeable, and the paper gives a fully mergeable randomised quantile summary.
- Yu, Y., Gunda, P. K. & Isard, M. (2009).
  "Distributed Aggregation for Data-Parallel Computing: Interfaces and Implementations." *SOSP 2009.*
  <https://www.microsoft.com/en-us/research/publication/distributed-aggregation-for-data-parallel-computing-interfaces-and-implementations/>
  - Defines a function H as *decomposable* if H = C ∘ I with commutative I and C,
    and *associative-decomposable* if C is also associative, which is what arbitrary aggregation trees require.
    DryadLINQ exposes this as an annotation on user functions — a declared reducer protocol.
- Lin, J. (2013). "Monoidify! Monoids as a Design Principle for Efficient MapReduce Algorithms." arXiv:1304.7544. <https://arxiv.org/abs/1304.7544>
  - Recasts "use a combiner" as "make the intermediate value a monoid",
    with the mean as the example: a mean cannot be combined, a (sum, count) pair can.
- Boykin, O., Ritchie, S., O'Connell, I. & Lin, J. (2014).
  "Summingbird: A Framework for Integrating Batch and Online MapReduce Computations." *PVLDB* 7(13), 1441–1451.
  <https://doi.org/10.14778/2733004.2733016>
  - Restricting aggregations to commutative semigroups and monoids lets one program run as a Hadoop batch job or a Storm stream,
    with partial results merged.
- Twitter Algebird. <https://github.com/twitter/algebird>
  - A Scala library of semigroups and monoids (moments, HyperLogLog, Count-Min, and others)
    for building aggregation systems on Scalding and Storm.
- Apache Spark, `RDD` API. <https://spark.apache.org/docs/latest/api/scala/org/apache/spark/rdd/RDD.html>
  - `reduce` requires "a commutative and associative binary operator";
    `fold` warns that non-commutative functions may give results differing from a sequential fold;
    `aggregate` takes a per-partition `seqOp` and a merging `combOp`;
    `treeAggregate` is "semantically identical" but merges in a multi-level tree.
- Apache Beam, `Combine` / `CombineFn`. <https://beam.apache.org/documentation/programming-guide/>
  - The Javadoc requires combining functions to be associative, because values are combined "in an arbitrary tree structure",
    and commutative, because "any order of the input values is ignored".
- Apache Flink, `AggregateFunction`. <https://nightlies.apache.org/flink/flink-docs-stable/>
  - Supports distributive aggregation through an accumulator with `merge()`; the Javadoc does not state the algebraic laws explicitly.

### Floating point: invariant in exact arithmetic is not invariant in practice

- Demmel, J. & Nguyen, H. D. (2013). "Fast Reproducible Floating-Point Summation." *ARITH 21*, 163–172. <https://doi.org/10.1109/ARITH.2013.9>
  - Non-associative floating-point addition plus dynamic scheduling makes even parallel sums irreproducible;
    the paper gives an order-independent summation,
    later developed into ReproBLAS (<https://www2.eecs.berkeley.edu/Pubs/TechRpts/2016/EECS-2016-121.html>).
- Chen, Y.-F. et al. (2017). "An Executable Sequential Specification for Spark Aggregation." *NETYS 2017.* <https://arxiv.org/abs/1702.02439>
  - Shows Spark aggregations returning different answers on the same input because partials merge in different orders.
    The full author list is **unverified**.

### Online and streaming algorithms

- Welford, B. P. (1962). "Note on a Method for Calculating Corrected Sums of Squares and Products." *Technometrics* 4(3), 419–420. <https://doi.org/10.2307/1266577>
  - A one-pass, numerically stable sequential update of mean and sum of squares.
- Chan, T. F., Golub, G. H. & LeVeque, R. J. (1979).
  "Updating Formulae and a Pairwise Algorithm for Computing Sample Variances." Stanford report STAN-CS-79-773.
  - Gives the formula for merging (n, mean, M2) from two subsamples, which turns the variance into a monoid and permits tree reduction.
- Chan, T. F., Golub, G. H. & LeVeque, R. J. (1983).
  "Algorithms for Computing the Sample Variance: Analysis and Recommendations." *The American Statistician* 37(3), 242–247.
  <https://doi.org/10.1080/00031305.1983.10483115>
  - Error analysis showing pairwise merging has better error growth than sequential updating.
- Pébay, P. (2008).
  "Formulas for Robust, One-Pass Parallel Computation of Covariances and Arbitrary-Order Statistical Moments." Sandia report SAND2008-6212.
  <https://www.osti.gov/biblio/1028931>
  - Merge and update formulas for central moments of any order and for covariances.
- Greenwald, M. & Khanna, S. (2001). "Space-Efficient Online Computation of Quantile Summaries." *SIGMOD 2001.* <https://doi.org/10.1145/375663.375670>
  - Deterministic ε-approximate quantiles in O((1/ε) log(εN)) space; Agarwal et al. classify it as only one-way mergeable.
- Dunning, T. & Ertl, O. (2019). "Computing Extremely Accurate Quantiles Using t-Digests." arXiv:1902.04023. <https://arxiv.org/abs/1902.04023>
  - Relative-error quantiles, accurate in the tails and mergeable.
- Karnin, Z., Lang, K. & Liberty, E. (2016). "Optimal Quantile Approximation in Streams." arXiv:1603.05346. <https://arxiv.org/abs/1603.05346>
  - The KLL sketch: optimal space through randomised compactors, mergeable.
    Publication at FOCS 2016 is **unverified** here.
- Flajolet, P., Fusy, É., Gandouet, O. & Meunier, F. (2007).
  "HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm." *AofA 2007*, DMTCS Proceedings AH, 127–146.
  <https://doi.org/10.46298/dmtcs.3545>
  - Registers are updated and merged with element-wise max, so the sketch is exactly invariant to order and partitioning.
- Cormode, G. & Muthukrishnan, S. (2005).
  "An Improved Data Stream Summary: The Count-Min Sketch and its Applications." *Journal of Algorithms* 55(1), 58–75.
  <https://doi.org/10.1016/j.jalgor.2003.12.001>
  - A linear sketch merged by addition, hence exactly order-invariant.
- A distinction worth keeping: the GK summary, t-digest, and KLL keep their error guarantees under any order,
  but their contents and estimates depend on insertion and merge order (inferred from the algorithms, not stated in these sources).
  HyperLogLog and Count-Min are exactly invariant.

### Coordination theory

- Shapiro, M., Preguiça, N., Baquero, C. & Zawirski, M. (2011). "Conflict-Free Replicated Data Types." *SSS 2011*, LNCS 6976, 386–400. <https://hal.inria.fr/inria-00609399>
  - State-based CRDTs merge by a semilattice join (commutative, associative, idempotent), so replicas converge whatever the delivery order.
- Ameloot, T. J., Neven, F. & Van den Bussche, J. (2013). "Relational Transducers for Declarative Networking." *JACM* 60(2), article 15. <https://arxiv.org/abs/1012.2858>
  - Proves the CALM conjecture: exactly the monotone queries have coordination-free distributed implementations.
- Hellerstein, J. M. & Alvaro, P. (2020). "Keeping CALM: When Distributed Consistency Is Easy." *Communications of the ACM* 63(9), 72–81.
  <https://cacm.acm.org/magazines/2020/9/246941-keeping-calm/fulltext>
  - Monotone programs give the same result whatever order messages arrive in; aggregation thresholds and negation need coordination.

### Relevance for R

Every framework above makes the same demand: an aggregation can be partitioned, streamed,
or parallelised only if it is written as a fixed-size state with an associative, commutative merge.
R has the mathematics in many places (biglm's QR, `KernSmooth` binning, `princomp(covmat=)`),
but no shared protocol in which a function declares an `init`/`update`/`merge`/`finalize` quadruple.
The literature also separates "invariant in exact arithmetic" from "bitwise invariant".
Base `sum()` and `mean()` on doubles are reproducible only for a fixed order,
so any chunked or parallel version via `parallel`, `future`, arrow, duckdb, or sparklyr can change low-order bits.
Order-invariance tests must therefore compare with a tolerance,
except for exactly invariant summaries such as integer counts, max, HyperLogLog, and Count-Min.

## 3. Statistics

### Exchangeability

- de Finetti, B. (1937). "La prévision : ses lois logiques, ses sources subjectives." *Annales de l'Institut Henri Poincaré* 7(1), 1–68.
  <https://www.numdam.org/item/AIHP_1937__7_1_1_0>
  (English translation: "Foresight: its logical laws, its subjective sources",
  in Kyburg & Smokler (eds.), *Studies in Subjective Probability*, Wiley, 1964).
  - Defines exchangeability — a joint law unchanged by finite permutations —
    and shows that an infinite exchangeable binary sequence is a mixture of iid sequences.
    "Row order carries no information" is therefore a modelling assumption with a precise meaning.
  - The 1931 Italian paper is **unverified**.
- Hewitt, E. & Savage, L. J. (1955). "Symmetric Measures on Cartesian Products." *Transactions of the AMS* 80, 470–501. <https://doi.org/10.1090/S0002-9947-1955-0076206-8>
  - Extends de Finetti's theorem to general spaces and proves the 0–1 law for permutation-invariant events.
- Aldous, D. J. (1985).
  "Exchangeability and Related Topics." In *École d'Été de Probabilités de Saint-Flour XIII —
  1983*, Lecture Notes in Mathematics 1117, Springer.
  <https://doi.org/10.1007/BFb0099421>
  - The standard survey of exchangeable sequences, arrays, and partitions, and thus of which symmetries justify treating data as a bag.

### Sufficiency as the formal reason a fit can ignore order

- Fisher, R. A. (1922).
  "On the Mathematical Foundations of Theoretical Statistics." *Philosophical Transactions of the Royal Society A* 222, 309–368.
  <https://doi.org/10.1098/rsta.1922.0009>
  - Introduces sufficiency.
- Neyman, J. (1935).
  "Su un teorema concernente le cosiddette statistiche sufficienti." *Giornale dell'Istituto Italiano degli Attuari* 6, 320–334.
  - The factorisation criterion f(x; θ) = g(T(x); θ) h(x); confirmed only through one bibliography (<https://encyclopediaofmath.org/wiki/Factorization_theorem>).
- Halmos, P. R. & Savage, L. J. (1949).
  "Application of the Radon–Nikodym Theorem to the Theory of Sufficient Statistics." *Annals of Mathematical Statistics* 20(2), 225–241.
  <https://doi.org/10.1214/aoms/1177730032>
  - The general measure-theoretic factorisation theorem.
- Under iid sampling the likelihood is a product over rows and hence symmetric in them,
  so the order statistics (equivalently the empirical distribution) are sufficient.
  Any likelihood-based inference is therefore a function of the multiset of rows.
  When a fixed-dimensional sufficient statistic exists (X'X and X'y for the linear model;
  counts for a contingency table), the computation also becomes mergeable.
  This is the bridge from section 2's monoids to statistical models: `lavaan` with a sample covariance, `factanal(covmat=)`,
  and `stats::free1way()` on a table are all fits from a sufficient statistic.

### Divide-and-conquer and online updating

- Lin, N. & Xi, R. (2011). "Aggregated Estimating Equation Estimation." *Statistics and Its Interface* 4(1), 73–83. <https://doi.org/10.4310/SII.2011.v4.n1.a8>
  - Compresses each block into low-dimensional statistics and combines them;
    the result is asymptotically equivalent to the full-data estimating-equation estimator.
- Chen, X. & Xie, M. (2014). "A Split-and-Conquer Approach for Analysis of Extraordinarily Large Data." *Statistica Sinica* 24, 1655–1684.
  <https://www3.stat.sinica.edu.tw/statistica/j24n4/J24N49/J24N49.html>
  - Fits penalised GLMs on subsets and combines them, with asymptotic equivalence to the full fit.
- Zhang, Y., Duchi, J. C. & Wainwright, M. J. (2013). "Communication-Efficient Algorithms for Statistical Optimization." *JMLR* 14, 3321–3363. <https://jmlr.org/papers/v14/zhang13b.html>
  - Averaging per-machine M-estimators attains the centralised rate when the number of machines is at most about √N.
- Kleiner, A., Talwalkar, A., Sarkar, P. & Jordan, M. I. (2014). "A Scalable Bootstrap for Massive Data." *JRSS B* 76(4), 795–816. <https://doi.org/10.1111/rssb.12050>
  - The Bag of Little Bootstraps assesses estimator quality on random subsets and averages;
    it relies on rows being exchangeable so that any random partition works.
- Jordan, M. I., Lee, J. D. & Yang, Y. (2019). "Communication-Efficient Distributed Statistical Inference." *JASA* 114(526), 668–681.
  <https://doi.org/10.1080/01621459.2018.1429274>
  - A surrogate likelihood that improves on naive averaging and supports inference.
- Schifano, E. D., Wu, J., Wang, C., Yan, J. & Chen, M.-H. (2016).
  "Online Updating of Statistical Inference in the Big Data Setting." *Technometrics* 58(3), 393–403.
  <https://doi.org/10.1080/00401706.2016.1142900>
  - Cumulative updating for linear models and estimating equations as blocks arrive;
    for the linear model the result does not depend on block order.
- Wang, C., Chen, M.-H., Schifano, E., Wu, J. & Yan, J. (2016).
  "Statistical Methods and Computing for Big Data." *Statistics and Its Interface* 9(4), 399–414.
  <https://doi.org/10.4310/SII.2016.v9.n4.a1>
  - A review of subsampling, divide-and-conquer, and online updating that includes R packages; the page range is unconfirmed.
- Scott, S. L., Blocker, A. W., Bonassi, F. V., Chipman, H. A., George, E. I. & McCulloch, R. E. (2016).
  "Bayes and Big Data: The Consensus Monte Carlo Algorithm."
  *International Journal of Management Science and Engineering Management* 11(2), 78–88. <https://doi.org/10.1080/17509653.2016.1142191>
  - Runs MCMC per shard and combines draws by weighted averaging;
    exact for Gaussian posteriors because the posterior factorises over shards.

### Updating regression

- Gentleman, W. M. (1973).
  "Least Squares Computations by Givens Transformations without Square Roots."
  *Journal of the Institute of Mathematics and its Applications* 12, 329–336.
  - Row-at-a-time square-root-free Givens rotations; confirmed through reference lists only, DOI **unverified**.
- Gentleman, W. M. (1974).
  "Algorithm AS 75: Basic Procedures for Large, Sparse or Weighted Linear Least Squares Problems." *Applied Statistics* 23(3), 448–454.
  Code: <http://lib.stat.cmu.edu/apstat/75>
- Miller, A. J. (1992). "Algorithm AS 274: Least Squares Routines to Supplement Those of Gentleman." *Applied Statistics* 41(2), 458–478. <https://doi.org/10.2307/2347583>
  - Adds rows to a QR factorisation one at a time without forming X'X; the final R is unique up to row signs whatever the arrival order.
    This is the algorithm inside `biglm`.
- Lumley, T. *biglm: Bounded Memory Linear and Generalized Linear Models.* CRAN, version 0.9-3. <https://CRAN.R-project.org/package=biglm>
  - The `bigglm()` data-function contract says:
    "The chunks need not be the same size or in the same order when the data are reread, but the same data must be provided in total."
  - `?biglm` warns that the formula "must not contain any data-dependent terms, as these will not be consistent when updated."
    The warning is documented but not enforced,
    which is how the earlier session found silent errors with differing factor levels and `poly()`.

### Stochastic gradient methods: order matters, shuffling is the remedy

- Bottou, L. (2009). "Curiously Fast Convergence of Some Stochastic Gradient Descent Algorithms." Open-problem note, SLDS 2009.
  <https://leon.bottou.org/papers/bottou-slds-open-problem-2009>
  - Reshuffling once per epoch converges near t⁻², sampling with replacement near t⁻¹.
- Recht, B. & Ré, C. (2012).
  "Toward a Noncommutative Arithmetic-Geometric Mean Inequality: Conjectures, Case-Studies, and Consequences." *COLT 2012*, PMLR 23.
  <https://proceedings.mlr.press/v23/recht12.html>
  - Conjectures the matrix inequality that would explain why without-replacement sampling wins; Lai & Lim (ICML 2020, PMLR 119, <https://proceedings.mlr.press/v119/lai20a.html>) disproved it in general.
- HaoChen, J. Z. & Sra, S. (2019). "Random Shuffling Beats SGD after Finite Epochs." *ICML 2019*, PMLR 97, 2624–2633. <https://proceedings.mlr.press/v97/haochen19a.html>
- Gürbüzbalaban, M., Ozdaglar, A. & Parrilo, P. A. (2021).
  "Why Random Reshuffling Beats Stochastic Gradient Descent." *Mathematical Programming* 186, 49–84.
  <https://doi.org/10.1007/s10107-019-01440-w>
- Mishchenko, K., Khaled, A. & Richtárik, P. (2020). "Random Reshuffling: Simple Analysis with Vast Improvements." *NeurIPS 2020.*
  <https://proceedings.neurips.cc/paper_files/paper/2020/file/c8cc6e90ccbff44c9cee23611711cdc4-Paper.pdf>
- Together these say that a one-pass iterative estimator is a function of the row *sequence*,
  and that data stored sorted (by time, by group, by response) can slow or bias it.
  Random permutation restores exchangeability in expectation, which is the "invariant only in distribution" class.

### Permutation tests

- Pitman, E. J. G. (1937). "Significance Tests Which May Be Applied to Samples from Any Populations." *Supplement to the JRSS* 4(1), 119–130. <https://doi.org/10.2307/2984124>
- Good, P. I. (2005). *Permutation, Parametric, and Bootstrap Tests of Hypotheses*, 3rd ed. Springer. <https://doi.org/10.1007/b138696>
- Both rest on exchangeability of labels under the null, the same symmetry that licenses ignoring row order of the data themselves.

### Relevance for R

Sufficiency guarantees that `lm()` and `glm()` estimates are invariant to row order, up to rounding in the QR and pivoting.
`biglm`, `speedglm::shglm()`, `fastglm::fastglm_streaming()`, and `mgcv::bam()` are R instances of "sufficient statistic as running state",
and `lavaan`, `dagitty`, `princomp(covmat=)`, and `factanal(covmat=)` accept the statistic directly.
The literature also shows where R's chunked fitters fall short of their theory:
the merge is valid only if the model frame is chunk-invariant (same factor levels, same spline knots, same `poly()` basis),
which needs a pre-pass that none of them provides as an API.
Divide-and-conquer methods assume exchangeable partitions, so splitting sorted data by position violates them; randomise before splitting.
Some functions iterate in row order: Hartigan–Wong `kmeans()`, `gee` contiguous clusters, and nlme `corAR1()` without a time covariate.
They are the statistical analogue of unshuffled SGD.

## 4. Machine learning

### Permutation-invariant set functions

- Zaheer, M., Kottur, S., Ravanbakhsh, S., Póczos, B., Salakhutdinov, R. & Smola, A. J. (2017). "Deep Sets." *NeurIPS 30*, 3391–3401. <https://papers.nips.cc/paper/6931-deep-sets>
  - Shows that permutation-invariant set functions have the form ρ(Σ φ(x)), a learned sum-decomposition.
    This is the neural analogue of a sufficient statistic accumulated by summation, and therefore of a mergeable reducer.
- Qi, C. R., Su, H., Mo, K. & Guibas, L. J. (2017).
  "PointNet: Deep Learning on Point Sets for 3D Classification and Segmentation." *CVPR 2017*, 652–660.
  <https://doi.org/10.1109/CVPR.2017.16>
  - Uses max-pooling as the symmetric function over unordered points.
- Lee, J., Lee, Y., Kim, J., Kosiorek, A. R., Choi, S. & Teh, Y. W. (2019).
  "Set Transformer: A Framework for Attention-based Permutation-Invariant Neural Networks." *ICML 2019*, PMLR 97, 3744–3753.
  <https://proceedings.mlr.press/v97/lee19d.html>
  - Attention-based pooling that models interactions between elements while remaining permutation-invariant.
- Wagstaff, E., Fuchs, F. B., Engelcke, M., Posner, I. & Osborne, M. A. (2019).
  "On the Limitations of Representing Functions on Sets." *ICML 2019*, PMLR 97, 6487–6494.
  <https://proceedings.mlr.press/v97/wagstaff19a.html>
  - Continuous sum-decompositions need a latent dimension at least the maximum set size,
    so an order-free summary is not automatically a small one — the ML counterpart of holistic aggregates.
- Bloem-Reddy, B. & Teh, Y. W. (2020). "Probabilistic Symmetries and Invariant Neural Networks." *JMLR* 21(90), 1–61. <https://jmlr.org/papers/v21/19-322.html>
  - Connects invariant and equivariant networks to de Finetti-type representations, tying this thread to section 3.
    Row-local functions in the earlier catalogue are the *equivariant* case in this vocabulary.

### Data-loader shuffling

- PyTorch, `torch.utils.data.DataLoader`. <https://docs.pytorch.org/docs/stable/data.html>
  - `shuffle` reshuffles every epoch but defaults to `False`, so the default is the stored order.
- TensorFlow, `tf.data.Dataset.shuffle(buffer_size, ...)`. <https://www.tensorflow.org/api_docs/python/tf/data/Dataset#shuffle>
  - Samples from a buffer of the next `buffer_size` elements;
    "for perfect shuffling, set the buffer size equal to the full size of the dataset."
    The quote was verified on the related `shuffle_and_repeat` page.
- Hugging Face Datasets, `IterableDataset.shuffle`. <https://huggingface.co/docs/datasets/en/about_mapstyle_vs_iterable>
  - An explicitly approximate shuffle combining a buffer with shuffled shard order, and documented as insufficient on its own.
- LightGBM, `deterministic` parameter. <https://lightgbm.readthedocs.io/en/v4.4.0/Parameters.html>
  - Gives stable results only "when using the same data and the same parameters", which includes the same row order.
- Row-order sensitivity of XGBoost `hist` with several threads,
  and ranger's seed reproducibility depending on `num.threads`, are reported only in third-party sources:
  **unverified** in the official documentation.

### Relevance for R

Tree ensembles and boosting in R (ranger, xgboost, lightgbm) are permutation-invariant in principle,
but "invariant only in distribution" in practice:
bootstrap and column-sampling draws are indexed by row position, so shuffling with a fixed seed changes the fitted model.
Tests for such functions should compare distributions or predictive performance, not bitwise output.
For mini-batch learners (torch, keras), the shuffling literature argues for reshuffling each epoch.
Chunked readers that cannot shuffle globally, such as arrow or duckdb scans, give only buffer-like shuffles,
so order effects persist when data are stored sorted.

## 5. R community and packages

Each package is labelled by its stance:
**ignores** order (order is not part of the result), **preserves** it (order is part of the contract),
or **documents the cost** of preserving it.
Statements below were read from installed help pages, NEWS files, vignettes, or package sources unless marked otherwise.

### Base R

- `merge()` (`?merge`): rows are sorted on the key columns by default, "but for `sort = FALSE` are in an unspecified order" —
  **ignores** order when asked to.
- `order()` (`?order`): stable except for `method = "quick"`;
  `sort()` other than `method = "radix"` depends on the locale's collation — **preserves**, with a locale hazard.
- *Writing R Extensions*: `R CMD check` runs tests with collation set to the C locale "to minimize differences between platforms".
  This is the only check-level measure related to ordering;
  the CRAN Repository Policy says nothing about order or locale dependence of results.

### tidyverse

- dplyr (<https://dplyr.tidyverse.org>) — **preserves**.
  - `group_by()` "internally orders the groups in ascending order",
    in the C locale since 1.1.0 for "substantial performance improvements" and "reproducibility across R sessions" (NEWS 1.1.0).
  - `.by` results "maintain the ordering of the existing data", unlike `group_by()`.
  - `distinct()` keeps the first row of each combination; `arrange()` ignores grouping unless `.by_group = TRUE`.
  - `all_equal()` defaulted to `ignore_row_order = TRUE`.
    It was deprecated in 1.1.0 "because it makes it too easy to ignore important differences".
    This is a data point against blanket order-insensitive comparison.
  - The tidyverse blog post on dplyr 1.1.0 (<https://tidyverse.org/blog/2023/02/dplyr-1-1-0-pick-reframe-arrange/>) exists; its wording was not read.
- dbplyr — **ignores** order, and forces it to be explicit.
  - `?arrange.tbl_lazy`: "ORDER BY clauses can not generally appear in subqueries";
    the internal warning reads "ORDER BY is ignored in subqueries without LIMIT … use `window_order()` instead?".
  - A windowed expression without order warns that it "does not have explicit order",
    and asks to "use `arrange()`, `window_order()`, or `.order` to make deterministic" (reproduced with `simulate_postgres()`).
  - `window_order()` and `window_frame()` set the `ORDER BY` and frame of generated window functions.
- vctrs — **preserves**: `vec_unique()` returns values in order of first appearance.
- tidyr — **preserves**: `pivot_wider(names_sort = FALSE)` orders new columns by first appearance.
- tibble — rejects row names as an implicit index:
  "it is best to avoid row names, because they are basically a character column with different semantics than every other column";
  `rowid_to_column()` makes position an explicit column.

### Database and columnar back ends

- duckplyr (`vignette("limits")`, `?config`) — **documents the cost**.
  - "DuckDB does not guarantee order stability for the output.
    For performance reasons, duckplyr does not enable output order stability by default."
  - `DUCKPLYR_OUTPUT_ORDER` restores it, "but the plans are more complicated, and DuckDB needs to do more work."
  - `?config`: preserving order "leads to more complicated execution plans with less potential for optimization, and thus may be slower."
- duckdb — **documents the cost** through `preserve_insertion_order` (section 1).
- arrow (r/NEWS.md) — **ignores** order.
  - Since 6.0.0, "Row order of data from a Dataset query is no longer deterministic.
    If you need a stable sort order, you should explicitly `arrange()` the query result";
    `head()` without `arrange()` gives "a random slice of data".
  - `options(arrow.summarise.sort = TRUE)` restores dplyr-like sorted summaries.
  - Since 24.0.0, `write_dataset(preserve_order = FALSE)` makes within-partition order opt-in.
- sparklyr — **ignores** order unless made explicit.
  - `sdf_with_unique_id()` gives monotonically increasing but not sequential ids that "can differ across new computations" unless persisted;
    `sdf_with_sequential_id()` uses `zipWithIndex` and is independent of partitioning.

### In-memory speed packages

- data.table (`?setkey`, `?data.table`, secondary-indices vignette) — **preserves**, and **documents the cost**.
  - `setkey()` "physically reorders the data in RAM"; `setindex()` stores an ordering so that "the original row order is preserved".
  - The vignette notes that "reordering a data.table can be expensive".
  - `by=` preserves first-appearance order of groups; `keyby=` sorts them.
  - `unique()` and `duplicated()` keep the first occurrence unless `fromLast = TRUE`.
- collapse (`?GRP`) —
  **documents the cost**: `sort = FALSE` groups in order of first appearance,
  which "often provides a performance gain if the data was not sorted beforehand"; `method = "hash"` does no sorting.
- matrixStats and Rfast — fast column and row summaries; no statement on row order was found.
  Their column summaries are invariant by construction, but neither offers a merge API for chunked use.

### Chunked and out-of-memory packages

- biglm — **ignores** order by contract (section 3), the clearest precedent in R.
- iotools (`?chunk.apply`) —
  **documents the cost**: with `CH.SEQUENTIAL = FALSE` "the chunks may be processed in any order to gain better performance";
  results are combined by `CH.MERGE` (default `rbind`).
- disk.frame (archived from CRAN; GitHub README) — two-stage group-by gives the same results as on a data frame,
  but "functions that depend on the order of a column can only be obtained using estimated methods",
  and median, quantile, and IQR are listed as estimates.
  This is the holistic class, documented as such.
- chunked (README) — useful for selecting, mutating, and filtering, but "less helpful in group-ing and summarize-ation".
  It makes no statement on order.
- LaF — block-wise file access; no statement on order.
- bigmemory and biganalytics — file-backed matrices; no statement on order was found.
- ffbase — archived from CRAN.
- tdigest — provides `td_merge()`; merge-order invariance is not stated.
- data.sketches — describes its sketches as "compact, mergeable summaries built in a single pass".
- onlinePCA and onlineCOV — online updating of PCA and covariance; no statement on order was found.
- RcppRoll — rolling windows, order-dependent by definition.

### Community discussion

Verifiable primary sources are mostly release notes and vignettes:
dplyr 1.1.0 NEWS on the C-locale switch, arrow 6.0.0 NEWS, the duckplyr limits vignette,
DuckDB's order-preservation page, the data.table secondary-indices vignette, and the biglm documentation.
No R-devel or R-help thread, R Journal article, or useR! talk dedicated to row-order invariance could be verified.

### Relevance for R

The ecosystem splits three ways.
In-memory tools (dplyr `.by`, data.table `by`, vctrs, tidyr, collapse `sort = FALSE`) treat first-appearance order as part of the contract.
Out-of-memory and database back ends (dbplyr, arrow, DuckDB, Spark)
declare order undefined and require `arrange()` or an explicit row-number column.
Several packages state the cost of guaranteeing order as a trade-off, most explicitly duckplyr,
which is the strongest argument for knowing which functions do not need it.
`biglm` is the only package found that makes chunk order irrelevant by contract,
and its own documentation states the data-dependent-terms limitation that the earlier session observed in practice.

## 6. Reproducibility and testing

### Metamorphic testing

- Chen, T. Y., Cheung, S. C. & Yiu, S. M. (1998).
  "Metamorphic Testing: A New Approach for Generating Next Test Cases." Technical report HKUST-CS98-01; reposted as arXiv:2002.12543.
  <https://arxiv.org/abs/2002.12543>
  - Proposes checking relations between outputs of related inputs when no oracle exists.
    "Permuting the rows leaves the result unchanged" is such a relation.
- Murphy, C., Kaiser, G., Hu, L. & Wu, L. (2008). "Properties of Machine Learning Applications for Use in Metamorphic Testing." *SEKE 2008.*
  - Catalogues additive, multiplicative, *permutative*, invertive, inclusive, and exclusive relations;
    partly verified through secondary sources.
- Xie, X., Ho, J. W. K., Murphy, C., Kaiser, G., Xu, B. & Chen, T. Y. (2011).
  "Testing and Validating Machine Learning Classifiers by Metamorphic Testing." *Journal of Systems and Software* 84(4), 544–558.
  <https://doi.org/10.1016/j.jss.2010.11.920>
  - Applies metamorphic relations to kNN and naive Bayes in Weka, including permutation of attributes and of class labels.
    Whether it includes permutation of training instances is **unverified**.
- Segura, S., Fraser, G., Sanchez, A. B. & Ruiz-Cortés, A. (2016).
  "A Survey on Metamorphic Testing." *IEEE Transactions on Software Engineering* 42(9), 805–824.
  <https://doi.org/10.1109/TSE.2016.2532875>
- Dwarakanath, A. et al. (2018).
  "Identifying Implementation Bugs in Machine Learning Based Image Classifiers Using Metamorphic Testing." *ISSTA 2018.*
  <https://doi.org/10.1145/3213846.3213858> (arXiv:1808.05353)
  - Reports catching 71% of injected implementation bugs; whether a permutation relation is among those used is **unverified**.
- SQLite's `reverse_unordered_selects` (section 1) is a production example of the same idea built into an engine.

### Property-based testing in R

- hedgehog (CRAN) — "a property-based testing package in the spirit of 'QuickCheck'" with integrated shrinking and testthat integration.
  `gen.sample(x)` produces a random permutation and shrinks "towards the original list order",
  which makes it a ready generator for row permutations.
- quickcheck (CRAN) —
  property-based testing "inspired by 'hedgehog'", integrated with testthat,
  with generators `any_data_frame()`, `any_tibble()`, and `any_data.table()`.
- testthat — no permutation helper,
  but `expect_setequal()` and `expect_mapequal()` give order-insensitive comparisons for outputs whose order is not part of the contract.

### Policy

Neither the CRAN Repository Policy nor *Writing R Extensions* asks that results be independent of row order.
The only related measure is that `R CMD check` runs tests in the C collation locale.

### Relevance for R

Row-permutation invariance is a textbook permutative metamorphic relation, and R already has the parts to test it:
hedgehog's shrinking permutation generator, quickcheck's data-frame generators, and testthat's set expectations.
The relation has to match the order class: invariant functions should give equal results up to tolerance;
row-local functions should give results permuted the same way; first-appearance functions should agree after sorting by key;
distribution-invariant functions need a distributional comparison.
dplyr's deprecation of `all_equal(ignore_row_order = TRUE)` warns that a blanket order-insensitive comparison hides real differences,
so the relation should be chosen per function rather than applied globally.
No R package or CRAN check that systematically tests functions for row-order dependence was found.

## Gaps: what R lacks

- **A mergeable-reducer protocol for grouped aggregation.**
  Spark, Beam, Flink, DryadLINQ,
  and Algebird all let a user declare an aggregate as `init` / `update` / `merge` / `finalize` with associative, commutative `merge`.
  R has no such generic, so `aggregate()`, `tapply()`, dplyr `summarise()`,
  and `data.table` `j` expressions are opaque functions of a whole group, and back ends cannot split them.
  A small S3 protocol (for example `reducer(init, update, merge, finalize)`,
  with implementations for moments, X'X, counts, HyperLogLog, and quantile sketches)
  would let `iotools::chunk.apply()`, `parallel`, duckplyr fallbacks, and arrow scans aggregate any registered statistic in any order.
- **A model-frame pre-pass API for chunked fitting.**
  `biglm`'s documentation forbids data-dependent terms but does not enforce it, and `speedglm` and `fastglm` share the problem.
  What is missing is a first pass that collects factor levels, `poly()` coefficients, spline knots,
  and `scale()` centres from all chunks (itself a mergeable reduction),
  freezes them into the `terms` object (as `predvars` already does for prediction), and then makes the second pass chunk-invariant.
  Base R has the pieces in `model.frame()` and `makepredictcall()`;
  nothing ties them into a streaming contract, and no fitter detects inconsistent chunks.
- **Declared order classes.**
  R documentation rarely says whether a function's result is order-invariant, row-local, first-appearance, invariant in distribution,
  or order-dependent.
  A machine-readable tag, analogous to Spark's notes on non-deterministic functions or XQuery's ordering mode,
  would let back ends such as dbplyr and duckplyr decide what can be reordered and warn when it cannot.
- **Explicit order arguments for hidden order dependence.**
  `gee` cluster formation, nlme `corAR1()` without a time covariate, `kmeans()` Hartigan–Wong, `sandwich::vcovPL()` without `order.by`,
  and `gmm()` HAC defaults all use row position as an implicit time or grouping variable.
  The dbplyr pattern — warn when an order-dependent operation has no explicit order — could be applied to them.
- **Row-order-invariance tests.**
  No package or check permutes rows and compares results.
  A testthat helper such as `expect_row_order_invariant(f, data, class = ...)`,
  built on hedgehog permutations and the relations of section 6,
  plus an optional `R CMD check` mode in the spirit of SQLite's `reverse_unordered_selects`,
  would surface the order dependences catalogued earlier.
- **Reproducible floating-point reductions.**
  Chunked or parallel sums in R differ in low-order bits from serial ones.
  An opt-in reproducible summation (Demmel–Nguyen style) for `sum()`, `colSums()`,
  and crossproducts would make "invariant" mean bitwise invariant where that matters, for example in tests and audits.
- **Mergeable sketches in base or recommended packages.**
  Exact quantiles, ranks, and distinct counts are holistic.
  CRAN has `tdigest` and `data.sketches`, but `quantile()`, `median()`,
  and `ecdf()` offer no approximate, mergeable mode, and `tdigest` does not document merge-order behaviour.
