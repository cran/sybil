#  sysBiolAlg_lmomaClass.R
#  FBA and friends with R.
#
#  Copyright (C) 2010-2012 Gabriel Gelius-Dietrich, Dpt. for Bioinformatics,
#  Institute for Informatics, Heinrich-Heine-University, Duesseldorf, Germany.
#  All right reserved.
#  Email: geliudie@uni-duesseldorf.de
#
#  This file is part of sybil.
#
#  Sybil is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  Sybil is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with sybil.  If not, see <http://www.gnu.org/licenses/>.


#------------------------------------------------------------------------------#
#                 definition of the class sysBiolAlg_lmoma                     #
#------------------------------------------------------------------------------#

setClass(Class = "sysBiolAlg_lmoma",
         contains = "sysBiolAlg"
)


#------------------------------------------------------------------------------#
#                            default constructor                               #
#------------------------------------------------------------------------------#

# contructor for class sysBiolAlg_lmoma
setMethod(f = "initialize",
          signature = "sysBiolAlg_lmoma",
          definition = function(.Object,
                                model,
                                wtflux,
                                COBRAflag = FALSE,
                                wtobj = NULL,
                                wtobjLB = TRUE,
                                scaling = NULL, ...) {

              if ( ! missing(model) ) {

                  if (missing(wtflux)) {
                      tmp    <- sybil:::.generateWT(model, ...)
                      wtflux <- tmp$fluxes[tmp$fldind]
                      wtobj  <- tmp$obj
                  }
                  
                  stopifnot(is(model, "modelorg"),
                            is(COBRAflag, "logical"),
                            is(wtobjLB, "logical"),
                            is(wtflux, "numeric"))
                  
                  stopifnot(length(wtflux) == react_num(model))

                  #  the problem: minimize
                  #
                  #            |      |      |                ]
                  #        Swt |  0   |  0   |  = 0           ] left out if not COBRA
                  #            |      |      |                ]
                  #       -------------------------
                  #            |      |      |
                  #         0  | Sdel |  0   |  = 0
                  #            |      |      |
                  #       -------------------------
                  #            |      |      |
                  #         v1 - v2   |delta-| >= 0
                  #         v2 - v1   |delta+| >= 0
                  #            |      |      |
                  #       -------------------------
                  #       c_wt |  0   |  0   | >= c^T * v_wt  ] left out if not COBRA
                  #            |      |      |
                  #  lb   v_wt |del_lb|  0   |
                  #  ub   v_wt |del_ub|10000 |
                  #            |      |      |
                  #            |      |      |
                  #  obj    0  |  0   |  1   |


                  # ---------------------------------------------
                  # problem dimensions
                  # ---------------------------------------------

                  nc     <- react_num(model)
                  nr     <- met_num(model)

                  nCols  <- 4*nc
                  nRows  <- ifelse(isTRUE(COBRAflag),
                                   2*nr + 2*nc + 1,
                                   nr + 2*nc)

                  absMAX <- SYBIL_SETTINGS("MAXIMUM")


                  # ---------------------------------------------
                  # constraint matrix
                  # ---------------------------------------------

                  # the initial matrix dimensions
                  LHS <- Matrix::Matrix(0, 
                                        nrow = nr + 2*nc,
                                        ncol = nCols,
                                        sparse = TRUE)

                  # rows for the wild type strain
                  LHS[1:nr,(nc+1):(2*nc)] <- S(model)

                  # location of the wild type strain
                  fi <- c((nc+1):(2*nc))

                  # rows for the delta match matrix
                  diag(LHS[(nr+1)   :(nr+2*nc),1       :(2*nc)]) <- -1
                  diag(LHS[(nr+1)   :(nr+2*nc),(2*nc+1):(4*nc)]) <-  1
                  diag(LHS[(nr+1)   :(nr+nc)  ,(nc+1)  :(2*nc)]) <-  1
                  diag(LHS[(nr+nc+1):(nr+2*nc),1       :nc    ]) <-  1


                  # contraint matrix for linearMOMA, COBRA version
                  if (isTRUE(COBRAflag)) {
          
                      # rows for the wild type strain
                      LHSwt <- Matrix::Matrix(0,
                                              nrow = nr,
                                              ncol = nCols,
                                              sparse = TRUE)
                      LHSwt[1:nr,1:nc] <- S(model)
          
                      # fix the value of the objective function
                      crow <- Matrix::Matrix(c(obj_coef(model), rep(0, 3*nc)),
                                             nrow = 1,
                                             ncol = nCols,
                                             sparse = TRUE)
          
                      # the final contraint matrix
                      LHS <- rBind(LHSwt, LHS, crow)
          
                      alg <- "lmoma_cobra"
                  }
                  else {
                      alg <- "lmoma"
                  }


                  # ---------------------------------------------
                  # lower and upper bounds
                  # ---------------------------------------------

                  if (isTRUE(COBRAflag)) {
                      # Here we calculate wild type and deletion strain
                      # simultaineously, so we need upper and lower bounds
                      # for both, the wild type and the deletion strain.
                      # All the delta's are positive.
                      lower <- c(lowbnd(model),
                                 lowbnd(model),
                                 rep(0, 2*nc))
                      upper <- c(uppbnd(model),
                                 uppbnd(model),
                                 rep(absMAX, 2*nc))
          
          
                      rlower <- c(rep(0, nRows-1), wtobj)
                      rupper <- c(rep(0, 2*nr), rep(absMAX, 2*nc), wtobj)
                      #rupper <- rlower
                      #rupper <- c(rep(0, 2*nr), rep(0, 2*nc), 0)
                  }
                  else {
                      # Here, we keep the wild type flux distribution fixed.
                      lower  <- c(wtflux, lowbnd(model), rep(0, 2*nc))
                      upper  <- c(wtflux, uppbnd(model), rep(absMAX, 2*nc))
                      rlower <- c(rep(0, nRows))
                      rupper <- c(rep(0, nr), rep(absMAX, 2*nc))
                  }

                  # ---------------------------------------------
                  # constraint type
                  # ---------------------------------------------

                  if (isTRUE(COBRAflag)) {
                      rtype <- c(rep("E", 2*nr), rep("L", 2*nc))
                      if (isTRUE(wtobjLB)) {
                          rtype <- append(rtype, "L")
                      }
                      else {
                          rtype <- append(rtype, "U")
                      }
                  }
                  else {
                      rtype  <- c(rep("E", nr), rep("L", 2*nc))
                  }


                  # ---------------------------------------------
                  # objective function
                  # ---------------------------------------------

                  cobj <- c(rep(0, 2*nc), rep(1, 2*nc))


                  # ---------------------------------------------
                  # build problem object
                  # ---------------------------------------------

                  .Object <- callNextMethod(.Object,
                                            alg        = alg,
                                            pType      = "lp",
                                            scaling    = scaling,
                                            fi         = fi,
                                            nCols      = nCols,
                                            nRows      = nRows,
                                            mat        = LHS,
                                            ub         = upper,
                                            lb         = lower,
                                            obj        = cobj,
                                            rlb        = rlower,
                                            rub        = rupper,
                                            rtype      = rtype,
                                            lpdir      = "min",
                                            ctype      = NULL,
                                            ...)
#
#                  # ---------------------------------------------
#                  # build problem object
#                  # ---------------------------------------------
#
#                  lp <- optObj(solver = solver, method = method)
#                  lp <- initProb(lp, nrows = nRows, ncols = nCols)
#
#                  # ---------------------------------------------
#                  # set control parameters
#                  # ---------------------------------------------
#
#                  if (!any(is.na(solverParm))) {
#                      setSolverParm(lp, solverParm)
#                  }
#    
#
#                  loadLPprob(lp,
#                             nCols = nCols,
#                             nRows = nRows,
#                             mat   = LHS,
#                             ub    = upper,
#                             lb    = lower,
#                             obj   = cobj,
#                             rlb   = rlower,
#                             rub   = rupper,
#                             rtype = rtype,
#                             lpdir = "min"
#                  )
#                  
#                  if (!is.null(scaling)) {
#                      scaleProb(lp, scaling)
#                  }
#
#                  .Object@problem   <- lp
#                  .Object@algorithm <- alg
#                  .Object@nr        <- as.integer(nRows)
#                  .Object@nc        <- as.integer(nCols)
#                  .Object@fldind    <- as.integer(fi)
#                  validObject(.Object)
                  
              }
              return(.Object)
          }
)


#------------------------------------------------------------------------------#