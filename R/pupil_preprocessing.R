# pupil_preprocessing.R

library(here)
library(zoo)
library(tidyverse)
library(glue)
library(signal)

source(here("R", "plot_settings.R"))

metadata <- read_csv(here("data", "preprocessing_demos", "metadata.csv"))

# Variables
target_sampling_rate_def        <- 60       # 60 Hz
confidence_percentile_def       <- 0.6      # Percentile for filtering out data based on confidence values
absolute_conf_thres_def         <- 0.71     # Maximum threshold
fd_sd_threshold_def             <- 0.5      # SD threshold for masking first derivative
fd_sd_winsize_def               <- 5        # Window size for masking first derivative
sg_smoothing_window_def         <- 61       # At 60 Hz, 61 is around 1000 ms
baseline_thres_percentile_def   <- 0.9      # Percentile above which to select data as the baseline

# ---------------------------------

# Code from PyPlr (Martin et al., 2021) to mask first derivative, converted into R code with ChatGPT
# Derivative calculates the difference at sample n between sample n and sample n-1
# Computes a rolling standard deviation of the derivative 
# and flags points where the change is, say, >0.5× the local sd
# This allows to detect sustained, unusual jumps
mask_pupil_first_derivative <- function(samples,
                                        threshold = fd_sd_threshold_def,
                                        mask_cols = c("pupil_size"),
                                        winsize = fd_sd_winsize_def) {
  # Deep‐copy input
  samps <- samples
  
  for (col in mask_cols) {
    if (! col %in% names(samps)) next
    
    d <- c(NA, diff(samps[[col]]))
    # rolling mean and sd
    roll_m <- rollapply(d, width = winsize, FUN = mean, na.rm = TRUE,
                        fill = NA, align = "center")
    roll_s <- rollapply(d, width = winsize, FUN = sd,   na.rm = TRUE,
                        fill = NA, align = "center") * threshold
    
    # flag where |d - local_mean| > local_sd
    bad <- abs(d - roll_m) > roll_s
    samps[[col]][which(bad)] <- NA
    
    samps[[col]][which(!is.na(samps[[col]]) & samps[[col]] == 0)] <- NA
  }
  
  return(samps)
}

# This allows to detect gaps in the pupil data
detect_gaps <- function(data, ts_col = "timestamps", threshold_ms = 200) {
  data %>%
    # 1. Normalize timestamps to plain numeric ms
    mutate(ts_ms = as.numeric(.data[[ts_col]]) * 1000) %>%
    # 2. Ensure data are sorted & add a row index
    arrange(ts_ms) %>%
    mutate(idx = row_number()) %>%
    # 3. Compute dt vs. the previous sample
    mutate(dt = ts_ms - lag(ts_ms)) %>%
    # 4. Flag gaps > threshold
    dplyr::filter(dt > threshold_ms)
}

preprocess_pupil <- function(data,
                             pid,
                             eye_id,
                             target_sampling_rate = target_sampling_rate_def,
                             confidence_percentile = confidence_percentile_def,
                             absolute_conf_thres = absolute_conf_thres_def,
                             fd_sd_threshold = fd_sd_threshold_def,
                             fd_sd_winsize = fd_sd_winsize_def,
                             sg_smoothing_window = sg_smoothing_window_def,
                             baseline_thres_percentile = baseline_thres_percentile_def,
                             mode = "2d") {
  sprintf("Processing pupillary data for participant %s, eye %s", pid, eye_id)
  
  # Mask first derivative
  data_masked_1 <- mask_pupil_first_derivative(data,
                                               threshold = fd_sd_threshold, # +-n*SD is threshold for masking
                                               mask_cols = c("pupil_size"),
                                               winsize = fd_sd_winsize) # calculates rolling SD over 5 samples, excludes is sample is out of SD range
  
  # Mask confidence
  ## Keep only what is in the top {confidence_percentile} % of the confidence values
  confidence_threshold <- quantile(data_masked_1$confidence, confidence_percentile, na.rm = TRUE)
  ## Maximum threshold should be absolute threshold, not higher
  ## Allows to recover datasets with low confidence values
  if (confidence_threshold > absolute_conf_thres) {
    confidence_threshold <- absolute_conf_thres
  }
  print(glue("Removing data with confidence < {confidence_threshold}"))
  data_masked_2 <- data_masked_1 %>%
    mutate(pupil_size = if_else(confidence < confidence_threshold, NA_real_, pupil_size))
  
  # Mask physiologically impossible values
  if (mode == "3d") {
    # 0 to 10 mm
    data_masked_3 <- data_masked_2 %>%
      mutate(pupil_size = if_else(pupil_size < 0 | pupil_size > 10, NA_real_, pupil_size))
  } else {
    # only positive values
    data_masked_3 <- data_masked_2 %>%
      mutate(pupil_size = if_else(pupil_size < 0, NA_real_, pupil_size))
  }
  
  # Compute some data quality analysis metrics
  
  # Number of gaps > 200 ms
  gaps <- detect_gaps(data)
  if (nrow(gaps) == 0) {
    print("No gaps >200 ms in the data")
  } else {
    message(sprintf("%s gaps >200 ms in the data", nrow(gaps)))
  }
  
  # Percentage of data left (% of NA compared to non NA)
  na_percentage <- sum(1-is.na(data_masked_3$pupil_size)) / length(data_masked_3$pupil_size) * 100
  message(sprintf("%.2f percent of data left after preprocessing", na_percentage))
  
  # Resampling
  new_timestamps <- seq(from = min(data_masked_3$timestamps),
                        to = max(data_masked_3$timestamps),
                        by = 1 / target_sampling_rate)
  # Interpolation
  resampled_pupil_size <- approx(x = data_masked_3$timestamps,
                                 y = data_masked_3$pupil_size,
                                 xout = new_timestamps,
                                 rule = 2)$y # rule = 2 means extrapolate outside the range
  
  # Smoothing using SG filtering
  smoothed_pupil_size <- sgolayfilt(resampled_pupil_size, p = 3, n = sg_smoothing_window)
  
  # Combine into a new dataframe
  data_raw <- data.frame(
    timestamps = data$timestamps,
    pupil_size_raw = data$pupil_size,
    pupil_size_masked_1 = data_masked_1$pupil_size,
    pupil_size_masked_2 = data_masked_2$pupil_size,
    pupil_size_masked_3 = data_masked_3$pupil_size
  )
  # need to separate because not the same timestamps as raw data
  data_processed <- data.frame(
    timestamps = new_timestamps,
    pupil_size_resampled = resampled_pupil_size,
    pupil_size_smoothed = smoothed_pupil_size
  )
  
  # Baseline correction
  # Look at the highest 10% pupil size values across the entire experiment,
  # Take the median of this subset as the baseline
  # This can be done, because the measurement are almost never above the actual pupil size
  # But often noisy and then measured to be below what they actually are
  # Calculate the n-th percentile (i.e., cutoff for top n %)
  cutoff <- quantile(data_processed$pupil_size_smoothed, baseline_thres_percentile, na.rm = TRUE)
  # Extract rows where the value is greater than or equal to the 90th percentile
  top_values <- if_else(data_processed$pupil_size_smoothed < cutoff, NA_real_, data_processed$pupil_size_smoothed)
  baseline <- median(top_values, na.rm = TRUE)
  # Apply baseline correction
  data_processed <- data_processed %>%
    mutate(pupil_size_bc = pupil_size_smoothed / baseline * 100)
  
  # parameters passed on to the function
  params <- list(
    target_sampling_rate = target_sampling_rate,
    confidence_percentile = confidence_percentile,
    absolute_conf_thres = absolute_conf_thres,
    fd_sd_threshold = fd_sd_threshold,
    fd_sd_winsize = fd_sd_winsize,
    sg_smoothing_window = sg_smoothing_window,
    baseline_thres_percentile = baseline_thres_percentile
  )
  
  # Return the processed data, and information about it
  return(list(
    data_raw = data_raw,
    data_processed = data_processed,
    na_percentage = na_percentage,
    gaps = nrow(gaps),
    confidence_threshold = confidence_threshold,
    baseline = baseline,
    pid = pid,
    params = params
  ))
}

plot_pupil <- function(
    data,
    which = "raw"
) {
  
  pid <- data$pid
  
  # Plotting variables
  y_max <- 100
  y_label <- "Pupil size (pixels)"
  show_baseline <- FALSE
  show_median <- FALSE
  
  if (which == "raw") {
    plot_df <- dplyr::transmute(data$data_raw, timestamp = timestamps, value = pupil_size_raw)
    title <- "*Raw data*"
  } else if (which == "masked_1") {
    plot_df <- dplyr::transmute(data$data_raw, timestamp = timestamps, value = pupil_size_masked_1)
    title <- glue("**1.** Masking: first derivative, threshold = ±{data$params$fd_sd_threshold}*SD, {data$params$fd_sd_winsize}-sample windows")
  } else if (which == "masked_2") {
    plot_df <- dplyr::transmute(data$data_raw, timestamp = timestamps, value = pupil_size_masked_2)
    title <- glue("**2.** Masking: confidence threshold = {round(data$confidence_threshold, 2)}, negative values")
  } else if (which == "resampled") {
    plot_df <- dplyr::transmute(data$data_processed, timestamp = timestamps, value = pupil_size_resampled)
    title <- glue("**3.** Resampling to {data$params$target_sampling_rate} Hz")
  } else if (which == "smoothed") {
    plot_df <- dplyr::transmute(data$data_processed, timestamp = timestamps, value = pupil_size_smoothed)
    title <- glue("**4.** Smoothing: {data$params$sg_smoothing_window}-sample Savitzky-Golay, p=3")
  } else if (which == "baseline_corrected") {
    plot_df <- dplyr::transmute(data$data_processed, timestamp = timestamps, value = pupil_size_bc)
    title <- glue("**5.** Baseline correction: median of top {(1-data$params$baseline_thres_percentile)*100}% of all values")
    # Override some variables specifically for baseline-corrected data
    show_baseline <- TRUE
    y_max = 120
    y_label <- "% of baseline pupil size"
  } else {
    stop("'which' argument is wrong")
  }
  
  # filter metadata for our example participant
  metadata_participant <- metadata %>% 
    dplyr::filter(participant_id == pid)
  
  med_y <- if (show_median) {
    median(dplyr::pull(data, value), na.rm = TRUE)
  } else {
    NULL
  }
  
  p <- ggplot(
    plot_df,
    aes(x = timestamp, y = value)
  ) +
    geom_line(linewidth = 0.3) +
    geom_vline(
      data = metadata_participant,
      aes(
        xintercept = as.numeric(lights_on_ts),
        colour = factor(melanopic_edi)
      ),
      linewidth = 0.6,
      alpha = 0.7
    ) +
    coord_cartesian(ylim = c(0, y_max)) +
    scale_colour_manual(
      name = "Melanopic EDI (lux)",
      values = colorRampPalette(c("yellow", "darkred"))(
        length(unique(metadata_participant$melanopic_edi))
      )
    ) +
    labs(
      title = title,
      x = "Time (HH:MM)",
      y = y_label
    ) +
    theme_minimal() +
    plot_formatting +
    theme(plot.title = ggtext::element_markdown())
  
  p <- p +
    { if (show_median) geom_hline(yintercept = med_y, colour="red", linewidth=0.6, linetype="dashed") } +
    { if (show_baseline) geom_hline(yintercept = 100, colour="red", linewidth=0.6, linetype="dashed") }
  
  p
}