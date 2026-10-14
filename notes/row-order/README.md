# Row order and chunk-wise consumption of data frames in R

Research notes on which data-frame consumers in base R, the recommended packages, and CRAN packages of dependency depth 1–3
ignore row order, which could consume their input in chunks, and which depend on row order and why.

- `chunkable-report.md`: synthesis of which functions are order-invariant and how a chunk-wise rewrite would work.
- `catalog.md`: 1,223 per-function findings with source citations, one line each, classified by `rubric.md`.
- `order-report.md`: synthesis of which functions depend on row order, grouped by six reasons.
- `order/by_mechanism.md`: the order-sensitive catalog entries sorted into 12 mechanisms.
- `order/by_design_base_rec.md` and `order/by_design_cran.md`: functions that treat rows as a sequence by design.

Depth 0 is base plus recommended; a depth-k CRAN package's hard dependencies all have depth below k.
CRAN coverage is the 1,038 depth-1–3 packages with the most reverse dependencies, out of about 9,400.
Claims marked "verified" were checked by running the function on a data frame and on a row-permuted copy with a fixed seed.
The verification scripts mentioned in the notes as living in a scratchpad were not committed.
