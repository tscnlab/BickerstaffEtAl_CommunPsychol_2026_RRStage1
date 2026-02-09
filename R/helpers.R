# helpers.R

# function to save in a directory even if it does not exist
save_rds_safe <- function(object, path, overwrite = TRUE) {
  
  path <- normalizePath(path, mustWork = FALSE)
  dir <- dirname(path)
  
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  if (file.exists(path) && !overwrite) {
    stop("File already exists and overwrite = FALSE:\n", path)
  }
  
  saveRDS(object, path)
  invisible(path)
}