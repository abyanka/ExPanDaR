estimate_model <- function(df, dl) {
  dv <- dl$dvs
  idvs <- dl$idvs
  feffects <- dl$feffects
  clusters <- dl$clusters
  fe_str <- gsub("_","",paste(feffects, collapse = ", ")) # stargaze chokes on _
  cl_str <- gsub("_","",paste(clusters, collapse = ", ")) # stargaze chokes on _
  if ((feffects != "" & clusters != "") & (!is.factor(df[,dv]))) {
    f <- stats::as.formula(paste(dv, "~", paste(idvs, collapse = " + "), " | ",
                          paste(feffects, collapse = " + "), " | 0 | ", paste(clusters, collapse = " + ")))
  } else if (!is.factor(df[,dv]) & feffects != "") {
    f <- stats::as.formula(paste(dv, "~", paste(idvs, collapse = " + "), " | ",
                          paste(feffects, collapse = " + ")))
  } else if (!is.factor(df[,dv]) & clusters != "") {
    f <- stats::as.formula(paste(dv, "~", paste(idvs, collapse = " + "), " | 0 | 0 | ",
                          paste(clusters, collapse = " + ")))
  } else {
    f <- stats::as.formula(paste(dv, "~", paste(idvs, collapse = " + ")))
    if (is.factor(df[,dv]) & nlevels(df[,dv]) > 2) stop("multinomial logit is not implemented. Sorry.")
    if (is.factor(df[,dv]) & feffects != "") stop("fixed effects logit is not implemented. Sorry.")
  }
  if (is.factor(df[,dv])) {
    type_str = "logit"
    model <- glm(f, family = "binomial", df)
  } else {
    type_str = "OLS"
    model <- lfe::felm(f, data=df, psdef=FALSE)
  }
  list(model = model, type_str = type_str, fe_str = fe_str, cl_str = cl_str)
}


#' @title Prepares a Regression Table
#'
#' @description
#' Builds a regression table based on a set of user-specifed models or a single model and a partitioning variable.
#'
#' @param df Data frame containing the data to estimate the models on.
#' @param dvs A character vector containing the dependent variable(s).
#' @param idvs A character vector or a a list of character vectors containing the independent variables.
#' @param feffects A character vector or a a list of character vectors containing the fixed effects.
#' @param clusters A character vector or a a list of character vectors containing the cluster variables.
#' @param byvar A factorial variable to estimate the model on (only possible if only one model is being estimated).
#' @param format A character scalar that is passed on \link[stargazer]{stargazer} as \code{type} to determine the presentation
#'   format (e.g., "html", "text", or "latex").
#'
#' @return A list contining two items
#' \describe{
#'  \item{"models"}{A list containg the model results}
#'  \item{"table"}{The output of \link[stargazer]{stargazer} containing the table}
#' }
#'
#' @details
#' Depending on whether the dependent variable is numeric or a factor with two levels, the models are estimated
#'   using \code{\link[lfe]{felm}} or \link[stats]{glm} (with \code{family = binomial(link="logit")}).
#'   Fixed effects and clustered standard errors are only supported with continous dependent variables.
#'
#' @examples
#' df <- data.frame(year = as.factor(floor(stats::time(datasets::EuStockMarkets))),
#'                  datasets::EuStockMarkets)
#' dvs = list("DAX", "SMI", "CAC", "FTSE")
#' idvs = list(c("SMI", "CAC", "FTSE"),
#'             c("DAX", "CAC", "FTSE"),
#'             c("SMI", "DAX", "FTSE"),
#'             c("SMI", "CAC", "DAX"))
#' feffects = list("year", "year", "year", "year")
#' clusters = list("year", "year", "year", "year")
#' t <- prepare_regression_table(df, dvs, idvs, feffects, clusters)
#' t$table
#' t <- prepare_regression_table(df, "DAX", c("SMI", "CAC", "FTSE"), byvar="year")
#' print(t$table)
#' @export

prepare_regression_table <- function(df, dvs, idvs, feffects = rep("", length(dvs)),
                                     clusters = rep("", length(dvs)), byvar = "", format = "html") {
  if (byvar != "") if(!is.factor(df[,byvar])) stop("'byvar' needs to be a factor.")
  if ((length(dvs) > 1) & byvar != "") stop("you cannot subset multiple models in one table")
  datalist <- list()
  if (byvar != "") {
    datalist <- list(dvs = dvs,
                          idvs = idvs,
                          feffects = feffects,
                          clusters = clusters)
    mby <- lapply(levels(df[,byvar]), function(x) estimate_model(df[df[,byvar] == x,], datalist))
    models <- list()
    models[[1]] <- estimate_model(df, datalist)
    for (i in 2:(length(mby) + 1))
      models[[i]] <- mby[[i-1]]
  } else {
    for (i in 1:length(dvs))
      datalist[[i]] <- list(dvs = dvs[[i]],
                            idvs = idvs[[i]],
                            feffects = feffects[[i]],
                            clusters = clusters[[i]])
    models <- lapply(datalist, function (x) estimate_model(df, x))
  }
  fe_str <- "Fixed effects"
  cl_str <- "Std. errors clustered"
  m <- list()
  for (i in 1:length(models)) {
    if (models[[i]]$fe_str != "")  fe_str <- c(fe_str, models[[i]]$fe_str)
    else fe_str <- c(fe_str, "None")
    if (models[[i]]$cl_str != "")  cl_str <- c(cl_str, models[[i]]$cl_str)
    else cl_str <- c(cl_str, "No")
    m[[i]] <- models[[i]]$model
  }
  if (byvar != "") {
    labels <- gsub("_", "", c("Full Sample", levels(df[,byvar])))
    labels <- gsub("&", "+", labels)
    htmlout <- utils::capture.output(stargazer::stargazer(m,
                                                   type=format,
                                                   column.labels = labels,
                                                   omit.stat = c("f", "ser"),
                                                   add.lines=list(fe_str, cl_str),
                                                   dep.var.labels=dvs))
  } else htmlout <- utils::capture.output(stargazer::stargazer(m,
                                         type=format,
                                         omit.stat = c("f", "ser"),
                                         add.lines=list(fe_str, cl_str),
                                         dep.var.labels=unlist(dvs)))
  list(models = m, table = htmlout)
}