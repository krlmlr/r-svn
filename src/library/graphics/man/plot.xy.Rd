% File src/library/graphics/man/plot.xy.Rd
% Part of the R package, https://www.R-project.org
% Copyright 1995-2007 R Core Team
% Distributed under GPL 2 or later

\name{plot.xy}
\alias{plot.xy}
\title{Basic Internal Plot Function}
\description{
  This is \emph{the} internal function that does the basic plotting of
  points and lines.  Usually, one should rather use the higher level
  functions instead and refer to their help pages for explanation of the
  arguments.
}
\usage{
plot.xy(xy, type, pch = par("pch"), lty = par("lty"),
        col = par("col"), bg = NA,
        cex = 1, lwd = par("lwd"), \dots)
}
\arguments{
  \item{xy}{A four-element list as results from
    \code{\link{xy.coords}}.}
  \item{type}{1 character code: see \code{\link{plot.default}}.
    \code{NULL} is accepted as a synonym for \code{"p"}.}
  \item{pch}{character or integer code for kind of points, see
    \code{\link{points.default}}.}
  \item{lty}{line type code, see \code{\link{lines}}.}
  \item{col}{color code or name, see \code{\link{colors}},
    \code{\link{palette}}.  Here \code{NULL} means colour 0.}
  \item{bg}{background (fill) color for the open plot symbols 21:25:
    see \code{\link{points.default}}.}
  \item{cex}{character expansion.}
  \item{lwd}{line width, also used for (non-filled) plot symbols, see
    \code{\link{lines}} and \code{\link{points}}.}
  \item{\dots}{further \link{graphical parameters} such as \code{xpd},
    \code{lend}, \code{ljoin} and \code{lmitre}.}
}
\details{
  The arguments \code{pch}, \code{col}, \code{bg}, \code{cex},
  \code{lwd} may be vectors and may be recycled, depending on
  \code{type}: see \code{\link{points}} and \code{\link{lines}} for
  specifics.  In particular note that \code{lwd} is treated as a vector
  for points and as a single (first) value for lines.

  \code{cex} is a numeric factor in addition to \code{par("cex")} which
  affects symbols and characters as drawn by \code{type} \code{"p"},
  \code{"o"}, \code{"b"} and \code{"c"}.
}
\seealso{
  \code{\link{plot}},
  \code{\link{plot.default}},
  \code{\link{points}},
  \code{\link{lines}}.
}
\examples{
points.default # to see how it calls "plot.xy(xy.coords(x, y), ...)"
}
\keyword{aplot}
